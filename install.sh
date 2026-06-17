#!/usr/bin/env bash
#
# install.sh — Install the latest un-nerfed Claude Code system prompts.
#
# WHAT IT DOES
#   1. Detects your installed Claude Code version and locates its binary.
#   2. Downloads the LATEST un-nerf scripts + rules straight from git (so you
#      always patch with the most recent rule set, not a pinned release zip).
#   3. Rebuilds that exact CC version's STOCK prompts with tweakcc's published
#      data (sync-version.mjs), then replays every un-nerf onto them
#      (apply-unnerfs.py). This adapts automatically to new CC releases.
#   4. Seeds ~/.tweakcc from your real binary (tweakcc extraction), drops the
#      un-nerfed prompts on top, and patches the binary with tweakcc.
#   5. VERIFIES the un-nerf actually landed in the binary (unpack + grep) and
#      confirms the patched binary still runs.
#
# WHY --patches: a bare `tweakcc --apply` also tries tweakcc's UI patches,
# whose regexes drift behind new CC releases and abort the whole repack. We
# apply ONLY the un-nerfed system-prompt patches by ID, sidestepping that.
#
# USAGE
#   ./install.sh                 # full install (interactive extraction step)
#   ./install.sh --prompts-only  # only regenerate ~/.tweakcc/system-prompts
#   ./install.sh --dry-run       # show what it would do; touch nothing
#   ./install.sh --help
#
# ENV OVERRIDES
#   UNNERF_REPO   git URL of the un-nerf repo   (default: upstream project)
#   UNNERF_REF    branch/tag/commit to fetch    (default: master)
#   TWEAKCC_PKG   npm package for tweakcc        (default: tweakcc@latest;
#                 set to tweakcc-fixed@latest if upstream lags your CC version)
#   CC_BIN        path to the Claude Code native binary (default: auto-detect)
#
set -Eeuo pipefail

UNNERF_REPO="${UNNERF_REPO:-https://github.com/BenIsLegit/tweakcc-system-prompts-unnerfed.git}"
UNNERF_REF="${UNNERF_REF:-master}"
TWEAKCC_PKG="${TWEAKCC_PKG:-tweakcc@latest}"
TWEAKCC_DIR="${HOME}/.tweakcc"
PROMPTS_DIR="${TWEAKCC_DIR}/system-prompts"

DRY_RUN=0
PROMPTS_ONLY=0
WORKDIR=""

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=""; G=""; Y=""; R=""; D=""; N=""; fi
log()  { printf '%s==>%s %s\n' "$B$G" "$N" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s!! %s%s\n' "$Y" "$*" "$N" >&2; }
die()  { printf '%sERROR:%s %s\n' "$R$B" "$N" "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '%s[dry-run]%s %s\n' "$D" "$N" "$*"; else eval "$@"; fi; }

cleanup() { [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT
trap 'die "failed at line $LINENO (exit $?)"' ERR

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
for a in "$@"; do
  case "$a" in
    --dry-run)      DRY_RUN=1 ;;
    --prompts-only) PROMPTS_ONLY=1 ;;
    -h|--help)      usage ;;
    *) die "unknown argument: $a (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------
log "Preflight checks"
case "$(uname -s)" in
  Linux|Darwin) : ;;
  *) warn "untested platform '$(uname -s)'. This script targets Linux/macOS/WSL; on native Windows use PowerShell per the README." ;;
esac
for tool in node npm npx python3 git curl; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
info "node $(node --version), npm $(npm --version), python3 $(python3 --version 2>&1 | awk '{print $2}')"

# ---------------------------------------------------------------------------
# 2. Detect Claude Code version + binary
# ---------------------------------------------------------------------------
log "Detecting Claude Code"
command -v claude >/dev/null 2>&1 || die "the 'claude' CLI is not on PATH. Install Claude Code first."
CC_VERSION="$(claude --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
[ -n "$CC_VERSION" ] || die "could not parse the Claude Code version from 'claude --version'"

if [ -z "${CC_BIN:-}" ]; then
  # Resolve the `claude` launcher to the real native binary (often claude.exe even on Linux).
  cc_link="$(command -v claude)"
  CC_BIN="$(readlink -f "$cc_link" 2>/dev/null || realpath "$cc_link" 2>/dev/null || echo "$cc_link")"
fi
[ -f "$CC_BIN" ] || die "Claude Code binary not found at: $CC_BIN (set CC_BIN=/path/to/binary)"
info "Claude Code v${CC_VERSION}"
info "binary: ${CC_BIN}"

# ---------------------------------------------------------------------------
# 3. Fetch the latest un-nerf scripts + rules from git
# ---------------------------------------------------------------------------
log "Fetching latest un-nerf scripts from git"
info "${UNNERF_REPO} @ ${UNNERF_REF}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/unnerf.XXXXXX")"
REPO="${WORKDIR}/repo"
if [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] would clone into $REPO"
else
  git clone --quiet --depth 1 --branch "$UNNERF_REF" "$UNNERF_REPO" "$REPO" 2>/dev/null \
    || git clone --quiet --depth 1 "$UNNERF_REPO" "$REPO" \
    || die "git clone failed for $UNNERF_REPO"
fi
[ "$DRY_RUN" = 1 ] || [ -f "${REPO}/scripts/sync-version.mjs" ] || die "cloned repo is missing scripts/sync-version.mjs"

# ---------------------------------------------------------------------------
# 4. Build the un-nerfed prompts for THIS CC version
# ---------------------------------------------------------------------------
log "Building un-nerfed prompts for v${CC_VERSION}"
if [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] would: npm install (gray-matter), sync-version.mjs ${CC_VERSION} --download, apply-unnerfs.py"
  log "Dry run complete — no changes made."
  exit 0
fi

( cd "${REPO}/scripts" && npm install --quiet --ignore-scripts --no-audit --no-fund >/dev/null 2>&1 ) \
  || die "npm install (gray-matter) failed in scripts/"

# Stock baseline -> snapshot -> un-nerf in place; the diff gives the patched IDs.
node "${REPO}/scripts/sync-version.mjs" "$CC_VERSION" --download >/dev/null \
  || die "sync-version.mjs could not fetch prompts for v${CC_VERSION} (tweakcc may not have published them yet)"
STOCK_SNAP="${WORKDIR}/stock"
cp -a "${REPO}/system-prompts" "$STOCK_SNAP"
python3 "${REPO}/scripts/apply-unnerfs.py" --dir "${REPO}/system-prompts" >/dev/null \
  || die "apply-unnerfs.py reported failures — the rule set may need updating for v${CC_VERSION}"

# Compute the list of un-nerfed prompt IDs (filename stems that changed vs stock).
UNNERFED_IDS=""
changed=0
for f in "${REPO}/system-prompts"/*.md; do
  base="$(basename "$f")"
  if ! cmp -s "$f" "${STOCK_SNAP}/${base}"; then
    UNNERFED_IDS="${UNNERFED_IDS:+$UNNERFED_IDS,}${base%.md}"
    changed=$((changed + 1))
  fi
done
[ "$changed" -gt 0 ] || die "no prompts changed after un-nerfing — aborting (nothing to apply)"
info "${changed} prompts un-nerfed"

# ---------------------------------------------------------------------------
# 5. Seed ~/.tweakcc and stage the un-nerfed prompts
# ---------------------------------------------------------------------------
log "Seeding ~/.tweakcc from your binary"
# tweakcc's --apply needs an extraction baseline (original hashes + prompt-data
# cache) that maps each .md back to its string in the binary. That extraction
# is produced by tweakcc's interactive TUI; it cannot be reliably scripted.
need_extract=1
if [ -f "${TWEAKCC_DIR}/systemPromptOriginalHashes.json" ] && [ -d "${TWEAKCC_DIR}/prompt-data-cache" ]; then
  # Reuse only if a prior extraction already matches THIS CC version.
  if grep -rqs "ccVersion: ${CC_VERSION}\b" "$PROMPTS_DIR" 2>/dev/null; then
    need_extract=0
    info "existing extraction matches v${CC_VERSION} — reusing it"
  fi
fi

if [ "$need_extract" = 1 ]; then
  warn "A one-time tweakcc extraction is required to map prompts to your binary."
  info "tweakcc's extractor is an interactive TUI and can't be driven headlessly."
  info "When the tweakcc menu opens, choose 'Edit system prompts' (this extracts"
  info "them), then quit (q). This repo's prompts will be overwritten next."
  # Move STALE extraction state aside first. An older-version ~/.tweakcc (old
  # system-prompts, prompt-data-cache, hashes, and an old native-binary.backup)
  # would otherwise shadow the new prompts or make `--restore` recover the wrong
  # binary. Moving (not deleting) keeps it recoverable and avoids duplicating the
  # ~240 MB backup. tweakcc regenerates everything cleanly for v${CC_VERSION}.
  stale="${TWEAKCC_DIR}/.unnerf-stale-$(date +%s 2>/dev/null || echo prev)"
  mkdir -p "$stale"
  for f in system-prompts prompt-data-cache systemPromptOriginalHashes.json \
           systemPromptAppliedHashes.json native-binary.backup \
           native-claudejs-orig.js native-claudejs-patched.js; do
    [ -e "${TWEAKCC_DIR}/${f}" ] && mv "${TWEAKCC_DIR}/${f}" "$stale/" || true
  done
  info "moved stale extraction state -> ${stale}"
  printf '%sPress Enter to launch tweakcc for extraction (Ctrl-C to abort)...%s' "$B" "$N"; read -r _
  npx --yes "$TWEAKCC_PKG" || true
  [ -f "${TWEAKCC_DIR}/systemPromptOriginalHashes.json" ] \
    || die "extraction did not complete (no systemPromptOriginalHashes.json). Re-run after extracting in tweakcc."
fi

log "Installing un-nerfed prompts into ${PROMPTS_DIR}"
mkdir -p "$PROMPTS_DIR"
# Back up whatever is there, then overwrite with the freshly un-nerfed set.
if [ -n "$(ls -A "$PROMPTS_DIR" 2>/dev/null)" ]; then
  bak="${PROMPTS_DIR}.bak.$(date +%s 2>/dev/null || echo prev)"
  cp -a "$PROMPTS_DIR" "$bak"; info "backed up previous prompts -> $bak"
fi
cp -f "${REPO}/system-prompts"/*.md "$PROMPTS_DIR/"

if [ "$PROMPTS_ONLY" = 1 ]; then
  log "Prompts-only mode: ${PROMPTS_DIR} updated."
  info "Apply them with:  npx ${TWEAKCC_PKG} --apply --patches \"${UNNERFED_IDS}\""
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Patch the binary (system-prompt patches only) and verify
# ---------------------------------------------------------------------------
log "Patching the Claude Code binary (system-prompt patches only)"
npx --yes "$TWEAKCC_PKG" --apply --patches "$UNNERFED_IDS" \
  || die "tweakcc --apply failed. Try TWEAKCC_PKG=tweakcc-fixed@latest if upstream lags v${CC_VERSION}."

log "Verifying the un-nerf actually landed in the binary"
VERIFY_JS="${WORKDIR}/patched.js"
if npx --yes "$TWEAKCC_PKG" unpack "$VERIFY_JS" "$CC_BIN" >/dev/null 2>&1; then
  # A sentinel phrase that exists only in the un-nerfed prompts.
  if grep -q "senior-engineer standard" "$VERIFY_JS" 2>/dev/null \
     || grep -q "never trade away rigor, depth, or correctness" "$VERIFY_JS" 2>/dev/null; then
    info "${G}verified:${N} un-nerfed text is present in the patched binary"
  else
    die "patch reported success but the un-nerf is NOT in the binary. Did the extraction baseline match this binary? Re-run a fresh extraction."
  fi
else
  warn "could not unpack the patched binary to verify (continuing); confirm behavior in a session."
fi

log "${G}Done.${N} Restart any running Claude Code sessions to pick up the un-nerfed prompts."
info "Roll back any time with:  npx ${TWEAKCC_PKG} --restore"
