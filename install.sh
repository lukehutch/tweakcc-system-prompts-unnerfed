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
#   4. Stages the un-nerfed prompts into ~/.tweakcc and patches the binary with
#      a `tweakcc --apply` (which downloads its own prompt data and self-creates
#      a backup — no interactive extraction). By default tweakcc is BUILT FROM
#      upstream main (it tracks new CC releases fastest); set TWEAKCC_VERSION to
#      use a released tweakcc via npx instead.
#   5. VERIFIES the un-nerf actually landed in the binary (unpack + grep) and
#      confirms the patched binary still runs.
#
# COMPATIBILITY: applying system-prompt edits to the binary needs a tweakcc whose
# binary-patch logic matches your CC version. tweakcc's npm releases can lag a
# brand-new CC build (which may need a fresh prompt-locator/repack fix), so this
# script BUILDS tweakcc from upstream main by default — main carries those fixes
# soonest (e.g. the Latin-1 \xHH locator fix, PR #808). If even main can't fully
# patch your CC version yet, a bare `--apply` may abort or only partially match;
# this script does NOT pretend otherwise — it verifies the un-nerf actually landed
# and fails loudly (leaving your binary clean) when it can't. Set
# TWEAKCC_VERSION=latest to use the released tweakcc via npx instead of building.
#
# USAGE
#   ./install.sh                 # full install (non-interactive)
#   ./install.sh --prompts-only  # only regenerate ~/.tweakcc/system-prompts
#   ./install.sh --dry-run       # show what it would do; touch nothing
#   ./install.sh --help
#
# ENV OVERRIDES
#   UNNERF_REPO     git URL of the un-nerf repo (default: upstream project)
#   UNNERF_REF      branch/tag/commit to fetch  (default: master)
#   TWEAKCC_GIT     git URL of tweakcc to BUILD FROM SOURCE
#                   (default: https://github.com/Piebald-AI/tweakcc.git — upstream)
#   TWEAKCC_REF     branch/tag/commit of tweakcc to build
#                   (default: main — tracks new CC releases fastest)
#   TWEAKCC_VERSION if set (e.g. 'latest' or '4.1.1'), use the RELEASED tweakcc
#                   via npx instead of building from git. Lighter, but can lag a
#                   brand-new CC release (see README/BACKGROUND).
#   CC_BIN          path to the Claude Code native binary (default: auto-detect)
#
set -Eeuo pipefail

UNNERF_REPO="${UNNERF_REPO:-https://github.com/BenIsLegit/tweakcc-system-prompts-unnerfed.git}"
UNNERF_REF="${UNNERF_REF:-master}"
TWEAKCC_GIT="${TWEAKCC_GIT:-https://github.com/Piebald-AI/tweakcc.git}"  # tweakcc source to BUILD FROM (default: upstream)
TWEAKCC_REF="${TWEAKCC_REF:-main}"             # branch/tag/commit to build (default: main; tracks new CC releases fastest)
TWEAKCC_VERSION="${TWEAKCC_VERSION:-}"         # set (e.g. 'latest') to use a RELEASED tweakcc via npx instead of building from git
TWEAKCC=""   # set by setup_tweakcc ("node <dist>/index.mjs", or "npx tweakcc@<ver>")
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

# Pick the tweakcc to use and set $TWEAKCC to a runnable command. Default: BUILD
# from upstream tweakcc main — main tracks new Claude Code releases faster than
# npm releases do (a brand-new CC build often needs a prompt-locator/repack fix
# that lands on main before the next tweakcc release is cut). Opt out by setting
# TWEAKCC_VERSION (e.g. 'latest') to use a released tweakcc via npx instead.
setup_tweakcc() {
  if [ -n "$TWEAKCC_VERSION" ]; then
    log "Using the released tweakcc (npx tweakcc@${TWEAKCC_VERSION})"
    local resolved
    resolved="$(npm view "tweakcc@${TWEAKCC_VERSION}" version 2>/dev/null | tail -1)"
    [ -n "$resolved" ] || die "could not resolve 'tweakcc@${TWEAKCC_VERSION}' from npm — check your network, or unset TWEAKCC_VERSION to build from git."
    TWEAKCC="npx --yes tweakcc@${resolved}"
    # Warm the npx cache once (and fail early if it can't run) so the later
    # --apply / unpack calls are fast and don't re-hit the registry.
    $TWEAKCC --version >/dev/null 2>&1 \
      || die "'npx tweakcc@${resolved}' could not run — check your network/npm, or unset TWEAKCC_VERSION to build from git."
    info "tweakcc ${resolved} (released via npx)"
    return
  fi
  build_tweakcc
}

# Build tweakcc from git — the default path. Clones TWEAKCC_GIT @ TWEAKCC_REF
# (default: upstream main) and builds it, so the binary patcher matches the
# newest CC release that main supports.
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
APPLY_LOG="${WORKDIR}/apply-unnerfs.log"
if ! python3 "${REPO}/scripts/apply-unnerfs.py" --dir "${REPO}/system-prompts" >"$APPLY_LOG" 2>&1; then
  # Surface WHAT failed — the [FAIL]/[MISSING] blocks and the summary — instead of
  # swallowing them. WORKDIR is removed on exit, so print the detail inline.
  warn "apply-unnerfs.py reported failures for v${CC_VERSION} (rules: ${UNNERF_REPO} @ ${UNNERF_REF}):"
  grep -B1 -A2 -E '\[FAIL|\[MISSING|\[ERROR' "$APPLY_LOG" | sed 's/^/      /' >&2 || true
  grep -E 'Rules (applied|skipped|FAILED)|Missing files' "$APPLY_LOG" | sed 's/^/      /' >&2 || true
  die "apply-unnerfs.py reported failures (details above). MISSING = a rule targets a prompt that no longer exists in v${CC_VERSION} (Anthropic renamed/removed it); FAIL = a rule's stock text drifted. Retire/retarget those rules in the un-nerf repo, or point UNNERF_REPO/UNNERF_REF at a rule set that matches v${CC_VERSION}."
fi

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
# 5. Set up tweakcc (built from upstream main by default), then stage the un-nerfed prompts
# ---------------------------------------------------------------------------
setup_tweakcc

log "Staging un-nerfed prompts into ~/.tweakcc (no interactive extraction needed)"
# tweakcc's --apply downloads the prompt data for your CC version itself
# (downloadStringsFile), so there is NO interactive TUI extraction step: it
# patches each prompt whose .md in ~/.tweakcc/system-prompts differs from stock,
# and creates its own native-binary.backup. We move any older-version ~/.tweakcc
# state aside first — stale system-prompts / prompt-data-cache / hashes and an
# old native-binary.backup could otherwise shadow the new prompts or make
# `--restore` recover the wrong binary. Moving (not deleting) keeps it recoverable.
if [ -d "${PROMPTS_DIR}" ] || [ -f "${TWEAKCC_DIR}/native-binary.backup" ]; then
  stale="${TWEAKCC_DIR}/.unnerf-stale-$(date +%s 2>/dev/null || echo prev)"
  mkdir -p "$stale"
  for f in system-prompts prompt-data-cache systemPromptOriginalHashes.json \
           systemPromptAppliedHashes.json native-binary.backup \
           native-claudejs-orig.js native-claudejs-patched.js; do
    [ -e "${TWEAKCC_DIR}/${f}" ] && mv "${TWEAKCC_DIR}/${f}" "$stale/" || true
  done
  info "moved stale tweakcc state -> ${stale}"
fi
mkdir -p "$PROMPTS_DIR"
cp -f "${REPO}/system-prompts"/*.md "$PROMPTS_DIR/"

# Check: confirm the un-nerfed prompts are staged (each expected id differs from
# stock).
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
  info "Apply them by running this script without --prompts-only, or run"
  info "'npx tweakcc@latest --apply' yourself, then verify."
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Patch the binary (bare --apply) and verify the un-nerf actually landed
# ---------------------------------------------------------------------------
log "Patching the Claude Code binary"
# A bare `--apply` is what actually applies system-prompt .md edits (it patches
# every prompt whose .md differs from the extracted original). `--apply
# --patches <prompt-ids>` does NOT apply system-prompt edits. A bare --apply also
# runs tweakcc's other binary patches; if your tweakcc is older than your CC
# build one of them ('patches-applied-indication') can fail (older tweakcc then
# aborted the whole repack — fixed in 4.1.1). Either way the result depends on
# your tweakcc version matching your CC version, so the verify step below, not
# tweakcc's exit code, is the source of truth.
if ! $TWEAKCC --apply 2>"${WORKDIR}/apply.err"; then
  sed 's/^/      /' "${WORKDIR}/apply.err" >&2 2>/dev/null || true
  die "tweakcc --apply aborted on CC v${CC_VERSION} — your tweakcc may lag this CC release. Check the error above; rebuild from a newer TWEAKCC_REF (you're on '${TWEAKCC_REF}', default 'main') or pin a released TWEAKCC_VERSION. Your binary is unchanged."
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
           "thorough, clear, and rich with explanation"; do
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
