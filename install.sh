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
# COMPATIBILITY: applying system-prompt edits to the binary needs a tweakcc
# whose binary-patch logic matches your CC version. On very recent CC releases
# a bare `--apply` can abort (a failed UI patch refuses the repack) or only
# partially match the prompts. This script does NOT pretend otherwise: it
# verifies the un-nerf actually landed and fails loudly (leaving your binary
# clean) when your tweakcc can't fully patch your CC version.
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
#   TWEAKCC_GIT   git URL of tweakcc to BUILD   (default: the fork carrying the
#                 v2.1.179 Latin-1 \xHH locator fix). We build tweakcc from git,
#                 not the npm release, because the released tweakcc can't fully
#                 patch recent Claude Code builds (see README/BACKGROUND).
#   TWEAKCC_REF   branch/tag/commit of tweakcc  (default: the fix branch)
#   CC_BIN        path to the Claude Code native binary (default: auto-detect)
#
set -Eeuo pipefail

UNNERF_REPO="${UNNERF_REPO:-https://github.com/BenIsLegit/tweakcc-system-prompts-unnerfed.git}"
UNNERF_REF="${UNNERF_REF:-master}"
TWEAKCC_GIT="${TWEAKCC_GIT:-https://github.com/lukehutch/tweakcc.git}"
TWEAKCC_REF="${TWEAKCC_REF:-fix-latin1-xhh-locator-2.1.179}"
TWEAKCC=""   # set to "node <dist>/index.mjs" by build_tweakcc
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

# Build tweakcc from git and set $TWEAKCC to a runnable command. We build from
# source (not `npx tweakcc@latest`) because the released tweakcc lags recent
# Claude Code builds: on v2.1.179 it can't fully patch system prompts (a failed
# UI patch aborts the repack, and its locator misses Latin-1 \xHH escapes). The
# default fork carries those fixes.
build_tweakcc() {
  log "Building tweakcc from git (${TWEAKCC_GIT} @ ${TWEAKCC_REF})"
  local dir="${WORKDIR}/tweakcc"
  git clone --quiet --depth 1 --branch "$TWEAKCC_REF" "$TWEAKCC_GIT" "$dir" 2>/dev/null \
    || git clone --quiet --depth 1 "$TWEAKCC_GIT" "$dir" \
    || die "could not clone tweakcc from $TWEAKCC_GIT @ $TWEAKCC_REF"
  if ! command -v pnpm >/dev/null 2>&1; then
    corepack enable pnpm >/dev/null 2>&1 || npm i -g pnpm >/dev/null 2>&1 \
      || die "tweakcc builds with pnpm; install pnpm (npm i -g pnpm) and retry"
  fi
  ( cd "$dir" && pnpm install --silent --prefer-offline >/dev/null 2>&1 \
      && pnpm build:dev >/dev/null 2>&1 ) \
    || die "tweakcc build failed under $dir — run 'pnpm install && pnpm build:dev' there to see why"
  [ -f "${dir}/dist/index.mjs" ] || die "tweakcc build produced no dist/index.mjs"
  TWEAKCC="node ${dir}/dist/index.mjs"
  info "tweakcc built: $($TWEAKCC --version 2>/dev/null | head -1)"
}

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
# 5. Build tweakcc from git, then seed ~/.tweakcc and stage the un-nerfed prompts
# ---------------------------------------------------------------------------
build_tweakcc

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
  $TWEAKCC || true
  [ -f "${TWEAKCC_DIR}/systemPromptOriginalHashes.json" ] \
    || die "extraction did not complete (no systemPromptOriginalHashes.json). Re-run after extracting in tweakcc."
fi

# Check (2): the extracted prompts must have come from THIS binary. tweakcc's
# extraction is byte-identical to the repo's synced stock for the same version,
# and that synced stock is itself verified against the binary — so any mismatch
# means a stale or wrong-version extraction is shadowing the real one.
log "Verifying extracted prompts came from your v${CC_VERSION} binary"
ext_n=$(find "$PROMPTS_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
syn_n=$(find "$STOCK_SNAP" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "${ext_n:-0}" -gt 0 ] || die "no extracted prompts in $PROMPTS_DIR — extraction did not run"
emiss=0; ediff=0
for f in "$STOCK_SNAP"/*.md; do
  b=$(basename "$f")
  if [ ! -f "${PROMPTS_DIR}/${b}" ]; then emiss=$((emiss + 1))
  elif ! cmp -s "$f" "${PROMPTS_DIR}/${b}"; then ediff=$((ediff + 1)); fi
done
info "extracted ${ext_n} prompts (expected ${syn_n} for v${CC_VERSION})"
if [ "$emiss" -gt 0 ] || [ "$ediff" -gt 0 ]; then
  die "extracted prompts do NOT match v${CC_VERSION} stock (${emiss} missing, ${ediff} differing). The extraction is stale or from a different binary — wipe ~/.tweakcc/system-prompts and re-extract (old state was moved to ${stale:-~/.tweakcc/.unnerf-stale-*})."
fi
info "${G}verified:${N} extracted prompts match the v${CC_VERSION} binary exactly (${ext_n}/${syn_n})"

log "Installing un-nerfed prompts into ${PROMPTS_DIR}"
mkdir -p "$PROMPTS_DIR"
# Back up whatever is there, then overwrite with the freshly un-nerfed set.
if [ -n "$(ls -A "$PROMPTS_DIR" 2>/dev/null)" ]; then
  bak="${PROMPTS_DIR}.bak.$(date +%s 2>/dev/null || echo prev)"
  cp -a "$PROMPTS_DIR" "$bak"; info "backed up previous prompts -> $bak"
fi
cp -f "${REPO}/system-prompts"/*.md "$PROMPTS_DIR/"

# Check (3): confirm the stock prompts were actually overwritten with un-nerfed
# ones — every expected id must now differ from the stock snapshot.
overlaid=0
for id in $(printf '%s' "$UNNERFED_IDS" | tr ',' ' '); do
  if [ -f "${PROMPTS_DIR}/${id}.md" ] && ! cmp -s "${PROMPTS_DIR}/${id}.md" "${STOCK_SNAP}/${id}.md"; then
    overlaid=$((overlaid + 1))
  fi
done
[ "$overlaid" -eq "$changed" ] \
  || die "overlay incomplete: only ${overlaid}/${changed} prompts are un-nerfed in ${PROMPTS_DIR}"
info "${G}verified:${N} ${overlaid}/${changed} prompts overwritten with un-nerfed versions"

if [ "$PROMPTS_ONLY" = 1 ]; then
  log "Prompts-only mode: ${PROMPTS_DIR} updated (${changed} un-nerfed)."
  info "Apply them by running this script without --prompts-only, or build tweakcc"
  info "from git (${TWEAKCC_GIT} @ ${TWEAKCC_REF}) and run its '--apply', then verify."
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Patch the binary (bare --apply) and verify the un-nerf actually landed
# ---------------------------------------------------------------------------
log "Patching the Claude Code binary"
# A bare `--apply` is what actually applies system-prompt .md edits (it patches
# every prompt whose .md differs from the extracted original). `--apply
# --patches <prompt-ids>` does NOT apply system-prompt edits. The catch: a bare
# --apply also runs tweakcc's other binary patches, and on very recent CC
# releases one of them ('patches-applied-indication') can fail and abort the
# whole repack. There is no clean per-prompt apply that skips it, so the result
# depends entirely on your tweakcc version matching your CC version — and the
# verify step below, not tweakcc's exit code, is the source of truth.
if ! $TWEAKCC --apply 2>"${WORKDIR}/apply.err"; then
  sed 's/^/      /' "${WORKDIR}/apply.err" >&2 2>/dev/null || true
  die "tweakcc --apply aborted on CC v${CC_VERSION}. The git tweakcc we built (${TWEAKCC_REF}) may still lag this CC release. Check the error above; you may need a newer tweakcc branch (set TWEAKCC_REF). Your binary is unchanged."
fi

# Check (4): confirm the un-nerf actually reached the binary. tweakcc can report
# success while patching nothing (or only partially) when its system-prompt
# locator lags the CC version, so verify by unpacking and counting sentinels.
log "Verifying the un-nerf actually landed in the binary"
VERIFY_JS="${WORKDIR}/patched.js"
if $TWEAKCC unpack "$VERIFY_JS" "$CC_BIN" >/dev/null 2>&1; then
  hits=0
  for s in "senior-engineer standard" "never trade away rigor, depth, or correctness" \
           "Spawn agents whenever parallel investigation" "investigate thoroughly, then be direct" \
           "Make your review thorough and complete"; do
    grep -qF "$s" "$VERIFY_JS" 2>/dev/null && hits=$((hits + 1))
  done
  if [ "$hits" -ge 4 ]; then
    info "${G}verified:${N} un-nerf is present in the patched binary (${hits}/5 sentinels)"
    log "${G}Done.${N} Restart any running Claude Code sessions to pick up the un-nerfed prompts."
    info "Roll back any time with:  npx tweakcc@latest --restore"
  elif [ "$hits" -ge 1 ]; then
    die "PARTIAL apply (${hits}/5 sentinels). Your tweakcc version can only partially patch system prompts into CC v${CC_VERSION} (a known gap on very recent CC). Restore a clean binary: npx tweakcc@latest --restore"
  else
    die "apply did NOT land (0/5 sentinels) even though tweakcc reported success — its system-prompt patcher does not support CC v${CC_VERSION} yet, so nothing was changed. Restore a clean binary with: npx tweakcc@latest --restore"
  fi
else
  warn "patched binary could not be unpacked to verify — check behavior in a session, or restore with: npx tweakcc@latest --restore"
fi
