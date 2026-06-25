#!/usr/bin/env bash
#
# install.sh — Install the latest un-nerfed Claude Code system prompts.
#
# WHAT IT DOES
#   1. Detects your Claude Code, locates its binary, and pins CC to the exact
#      version the rules support — min(tweakcc's newest published prompts, this
#      repo's ccVersion) — by uninstalling any existing install(s) and installing
#      that version, then disabling CC's auto-updater (DISABLE_AUTOUPDATER) so the
#      pin/patch aren't reverted on the next launch. CC_PIN=0 skips all of this.
#   2. Fetches the un-nerf scripts + rules from the repo this script was run from
#      (so a clone installs its own rules), or the upstream project if install.sh
#      isn't inside a git checkout. Override with UNNERF_REPO / UNNERF_REF.
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
#   UNNERF_REPO     git URL or local path of the un-nerf repo
#                   (default: the repo install.sh was run from; else upstream)
#   UNNERF_REF      branch/tag/commit to fetch
#                   (default: the current branch of that repo; else master)
#   TWEAKCC_GIT     git URL of tweakcc to BUILD FROM SOURCE
#                   (default: https://github.com/Piebald-AI/tweakcc.git — upstream)
#   TWEAKCC_REF     branch/tag/commit of tweakcc to build
#                   (default: main — tracks new CC releases fastest)
#   TWEAKCC_VERSION if set (e.g. 'latest' or '4.1.1'), use the RELEASED tweakcc
#                   via npx instead of building from git. Lighter, but can lag a
#                   brand-new CC release (see README/BACKGROUND).
#   CC_BIN          path to the Claude Code native binary (default: auto-detect)
#   CC_PIN          1 (default): install the exact Claude Code version the rules
#                   support — min(tweakcc's newest prompts, this repo's ccVersion).
#                   If a different version is installed, ALL existing installs (npm
#                   global, ~/.claude/local, ~/.local native) are removed first, and
#                   CC's auto-updater is disabled (DISABLE_AUTOUPDATER=1 in
#                   ~/.claude/settings.json) so the pin/patch aren't auto-reverted.
#                   0: leave Claude Code as-is and build for the installed version.
#
set -Eeuo pipefail

# Default the rule source to THE REPO THIS SCRIPT WAS RUN FROM, so `./install.sh`
# from a clone installs that clone's rules (a fork installs the fork's; a merged
# upstream installs upstream's). Falls back to the upstream project when install.sh
# isn't inside a git checkout (e.g. piped from curl). Explicit UNNERF_REPO/UNNERF_REF
# still override. NOTE: a local clone is cloned at its committed HEAD — commit local
# rule changes (or set UNNERF_REPO) before installing; uncommitted edits won't apply.
_self="${BASH_SOURCE[0]:-$0}"
_self_dir="$(cd "$(dirname "$_self")" 2>/dev/null && pwd || true)"
_self_repo="$(git -C "${_self_dir:-.}" rev-parse --show-toplevel 2>/dev/null || true)"
_self_ref="$(git -C "${_self_dir:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$_self_ref" = "HEAD" ]; then _self_ref=""; fi   # detached HEAD: no usable branch name
UNNERF_REPO="${UNNERF_REPO:-${_self_repo:-https://github.com/BenIsLegit/tweakcc-system-prompts-unnerfed.git}}"
UNNERF_REF="${UNNERF_REF:-${_self_ref:-master}}"
TWEAKCC_GIT="${TWEAKCC_GIT:-https://github.com/Piebald-AI/tweakcc.git}"  # tweakcc source to BUILD FROM (default: upstream)
TWEAKCC_REF="${TWEAKCC_REF:-main}"             # branch/tag/commit to build (default: main; tracks new CC releases fastest)
TWEAKCC_VERSION="${TWEAKCC_VERSION:-}"         # set (e.g. 'latest') to use a RELEASED tweakcc via npx instead of building from git
CC_PIN="${CC_PIN:-1}"                          # 1: pin Claude Code to the exact version the rules support (uninstall existing installs, install target, disable auto-update); 0: build for the installed version as-is
# Turn CC's auto-updater OFF for everything this script invokes. `claude` (the
# version checks below) and tweakcc both shell out to claude, and CC's runtime
# updater would otherwise npm-update the global install to the LATEST version
# mid-run — replacing the version we pin and reverting the un-nerf. When CC_PIN=1
# this is also persisted to ~/.claude/settings.json (step 3b) so the pin survives
# later launches; without it the next `claude` start re-updates and un-does both.
export DISABLE_AUTOUPDATER=1
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

cleanup() { [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; return 0; }  # return 0: never let the EXIT trap (e.g. on --help, before WORKDIR is set) trip the ERR trap
trap cleanup EXIT
trap 'die "failed at line $LINENO (exit $?)"' ERR

usage() { sed -n '2,/^set /{ /^set /q; p; }' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

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
  # Corepack-managed pnpm (including the `corepack enable pnpm` fallback below)
  # asks "Corepack is about to download <pnpm>... [Y/n]" the first time it has to
  # fetch a pnpm build. That prompt is written to stderr, which the pnpm commands
  # below send to /dev/null, so it stays invisible while still blocking on stdin —
  # hanging the build forever with no output. Tell corepack to fetch without
  # prompting so the build runs unattended.
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  if ! command -v pnpm >/dev/null 2>&1; then
    corepack enable pnpm >/dev/null 2>&1 || npm i -g pnpm >/dev/null 2>&1 \
      || die "tweakcc builds with pnpm; install pnpm (npm i -g pnpm) and retry"
  fi
  # </dev/null: belt-and-suspenders so that if any pnpm step still tries to read
  # from the terminal it fails fast instead of hanging behind the redirects above.
  ( cd "$dir" && pnpm install --silent --prefer-offline >/dev/null 2>&1 \
      && pnpm build:dev >/dev/null 2>&1 ) </dev/null \
    || die "tweakcc build failed under $dir — run 'pnpm install && pnpm build:dev' there to see why"
  [ -f "${dir}/dist/index.mjs" ] || die "tweakcc build produced no dist/index.mjs"
  TWEAKCC="node ${dir}/dist/index.mjs"
  info "tweakcc built: $($TWEAKCC --version 2>/dev/null | head -1)"
}

# Lower of two X.Y.Z versions (numeric per component). Used to pick the CC
# version that both this repo's rules and tweakcc's prompt data support.
ver_min() { printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1; }

# Highest Claude Code version tweakcc has prompt data for on main, i.e.
# max(data/prompts/prompts-*.json). Echoes X.Y.Z, or nothing if the listing
# can't be fetched (offline / API rate-limited) — the caller then falls back.
tweakcc_latest_prompt_version() {
  curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/Piebald-AI/tweakcc/contents/data/prompts?ref=main" 2>/dev/null \
    | grep -oE 'prompts-[0-9]+\.[0-9]+\.[0-9]+\.json' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u | tail -1
}

# Remove EVERY Claude Code install we can find — the npm global package, the
# legacy local install (~/.claude/local), and the native build (~/.local/share/
# claude plus its ~/.local/bin/claude launcher) — so the target version installs
# clean with no stale binary shadowing it. User DATA in ~/.claude (projects,
# history, settings) is deliberately left untouched. </dev/null so an unexpected
# prompt fails fast instead of hanging (cf. the corepack fix).
cc_uninstall_all() {
  local npm_root logf="${WORKDIR}/cc-uninstall.log" removed=0
  [ -n "${HOME:-}" ] || die "HOME is not set — refusing to remove install directories"
  npm_root="$(npm root -g 2>/dev/null || true)"
  if [ -n "$npm_root" ] && [ -d "${npm_root}/@anthropic-ai/claude-code" ]; then
    info "uninstalling npm global @anthropic-ai/claude-code"
    npm rm -g @anthropic-ai/claude-code >"$logf" 2>&1 </dev/null \
      || { sed 's/^/      /' "$logf" >&2 2>/dev/null || true; die "'npm rm -g @anthropic-ai/claude-code' failed (a global uninstall may need sudo). Fix the error above, or set CC_PIN=0."; }
    removed=1
  fi
  if [ -d "${HOME}/.claude/local" ]; then
    info "removing legacy local install ${HOME}/.claude/local"
    rm -rf "${HOME}/.claude/local"; removed=1
  fi
  if [ -d "${HOME}/.local/share/claude" ]; then
    info "removing native build ${HOME}/.local/share/claude"
    rm -rf "${HOME}/.local/share/claude"; removed=1
  fi
  if [ -e "${HOME}/.local/bin/claude" ] || [ -L "${HOME}/.local/bin/claude" ]; then
    info "removing launcher ${HOME}/.local/bin/claude"
    rm -f "${HOME}/.local/bin/claude"; removed=1
  fi
  [ "$removed" = 1 ] || warn "found no known Claude Code install to remove — installing fresh"
}

# Install an EXACT Claude Code version via npm. npm pins a precise version and
# needs no pre-existing `claude` (the native installer would), so it's the
# reliable way to reinstall after cc_uninstall_all. </dev/null per the above.
cc_install_npm() {
  local version="$1" logf="${WORKDIR}/cc-install.log"
  info "installing @anthropic-ai/claude-code@${version} via npm"
  npm install -g "@anthropic-ai/claude-code@${version}" >"$logf" 2>&1 </dev/null \
    || { sed 's/^/      /' "$logf" >&2 2>/dev/null || true; die "npm could not install @anthropic-ai/claude-code@${version} (a global npm install may need sudo). Fix the error above, install it yourself, or set CC_PIN=0."; }
}

# Persist DISABLE_AUTOUPDATER=1 into ~/.claude/settings.json so the un-nerf patched
# into the binary (and any version pin) survives normal `claude` launches —
# otherwise CC's auto-updater npm-updates to the latest version on the next start
# and reverts both. Merges into existing settings via node; NEVER clobbers on a
# parse error. Exit codes from the node helper: 0 wrote, 2 already set, 3 failed.
cc_persist_disable_autoupdate() {
  local settings="${HOME}/.claude/settings.json" rc
  mkdir -p "${HOME}/.claude"
  if node -e '
      const fs = require("fs"), p = process.argv[1];
      let raw = null;
      try { raw = fs.readFileSync(p, "utf8"); } catch (e) { if (e.code !== "ENOENT") process.exit(3); }
      let j = {};
      if (raw && raw.trim()) { try { j = JSON.parse(raw); } catch (e) { process.exit(3); } }
      if (typeof j !== "object" || j === null || Array.isArray(j)) process.exit(3);
      if (j.env && j.env.DISABLE_AUTOUPDATER === "1") process.exit(2);
      j.env = j.env || {};
      j.env.DISABLE_AUTOUPDATER = "1";
      fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
    ' "$settings"; then rc=0; else rc=$?; fi
  case "${rc:-0}" in
    0) info "added DISABLE_AUTOUPDATER=1 to ${settings} to turn off Claude Code's auto-updater"
       info "  why: CC's auto-updater replaces the binary with a newer stock build on the next launch, which would silently revert this un-nerf (and any version pin)."
       info "  note: CC will no longer self-update. After any deliberate CC upgrade, re-run this script — each new version's changed prompts must be re-un-nerfed." ;;
    2) info "CC auto-update already disabled in ${settings} (DISABLE_AUTOUPDATER=1)" ;;
    *) warn "could not update ${settings} — add '\"env\": { \"DISABLE_AUTOUPDATER\": \"1\" }' yourself, or CC will auto-update and revert the un-nerf" ;;
  esac
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
CC_INSTALLED="$(claude --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
[ -n "$CC_INSTALLED" ] || die "could not parse the Claude Code version from 'claude --version'"
CC_VERSION="$CC_INSTALLED"   # the version we build/patch for; may be re-pinned in step 3b

if [ -n "${CC_BIN:-}" ]; then
  CC_BIN_USER=1   # explicit CC_BIN: don't re-resolve it after a version change
else
  CC_BIN_USER=0
  # Resolve the `claude` launcher to the real native binary (often claude.exe even on Linux).
  cc_link="$(command -v claude)"
  CC_BIN="$(readlink -f "$cc_link" 2>/dev/null || realpath "$cc_link" 2>/dev/null || echo "$cc_link")"
fi
[ -f "$CC_BIN" ] || die "Claude Code binary not found at: $CC_BIN (set CC_BIN=/path/to/binary)"
info "installed: Claude Code v${CC_INSTALLED}"
info "binary: ${CC_BIN}"

# ---------------------------------------------------------------------------
# 3. Fetch the latest un-nerf scripts + rules from git
# ---------------------------------------------------------------------------
log "Fetching latest un-nerf scripts from git"
info "${UNNERF_REPO} @ ${UNNERF_REF}"
# If the rule source is a LOCAL git checkout, pull it current FIRST: `git clone`
# of a local path copies its committed HEAD, so a stale checkout would clone (and
# install) stale rules and report a stale ccVersion in step 3b. Remote-URL
# sources are fetched fresh by the clone below, so they skip this. Skipped under
# --dry-run (a pull would mutate your checkout); --ff-only + warn so a diverged,
# dirty, or offline checkout never silently rewrites history or hard-fails.
if git -C "$UNNERF_REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] would 'git -C ${UNNERF_REPO} pull --ff-only' to ensure the latest rules"
  else
    info "updating local checkout: git -C ${UNNERF_REPO} pull --ff-only"
    git -C "$UNNERF_REPO" pull --ff-only --quiet \
      || warn "could not fast-forward ${UNNERF_REPO} (diverged, dirty, or offline) — continuing with its current HEAD"
  fi
fi
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
# 3b. Pin Claude Code to the exact version the un-nerf rules support
# ---------------------------------------------------------------------------
# This repo's rules are written against the STOCK prompt text of ONE specific CC
# version (system-prompt-checksums.json -> ccVersion), and tweakcc can only
# extract/patch versions it has prompt data for. The newest version BOTH support
# is min(tweakcc's latest published prompts, this repo's ccVersion). Un-nerfing
# any other CC version risks rules whose stock text drifted (so they silently
# stop applying) or a binary tweakcc can't patch — so install exactly that
# version: if a different one is installed, uninstall every existing Claude Code
# (npm global and/or native/local) and install the target. CC_PIN=0 skips this
# and builds for whatever CC is installed.
if [ "$CC_PIN" = 1 ]; then
  log "Resolving the Claude Code version the rules support"
  # Source B: the version this repo's stock prompts were last synced to. Read it
  # from the freshly cloned rule set; under --dry-run (no clone) use the local checkout.
  repo_root="$REPO"
  [ -f "${repo_root}/system-prompt-checksums.json" ] || repo_root="${_self_repo:-}"
  repo_ver="$(grep -m1 '"ccVersion"' "${repo_root}/system-prompt-checksums.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
  [ -n "$repo_ver" ] || die "could not read ccVersion from system-prompt-checksums.json — cannot determine the supported CC version"
  # Source A: the newest version tweakcc has prompt data for (max prompts-*.json).
  tw_ver="$(tweakcc_latest_prompt_version || true)"
  if [ -n "$tw_ver" ]; then
    CC_VERSION="$(ver_min "$tw_ver" "$repo_ver")"
    info "tweakcc newest prompts v${tw_ver} | this repo v${repo_ver} -> target v${CC_VERSION}"
  else
    CC_VERSION="$repo_ver"
    warn "could not list tweakcc's prompt versions via the GitHub API; targeting this repo's v${repo_ver} (sync-version.mjs will confirm tweakcc has prompts for it)"
  fi

  if [ "$CC_INSTALLED" = "$CC_VERSION" ]; then
    info "Claude Code is already at the supported v${CC_VERSION} — leaving it as is"
  elif [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] would uninstall every Claude Code install (npm global / ~/.claude/local / ~/.local native) and install v${CC_VERSION} via npm"
  else
    log "Re-pinning Claude Code: v${CC_INSTALLED} -> v${CC_VERSION} (uninstall existing, then install)"
    cc_uninstall_all
    cc_install_npm "$CC_VERSION"
    hash -r 2>/dev/null || true   # drop any cached `claude` path from before the reinstall
    command -v claude >/dev/null 2>&1 || die "after reinstall, 'claude' is not on PATH — ensure your npm global bin directory is on PATH, then re-run"
    new_ver="$(claude --version 2>/dev/null | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
    [ "$new_ver" = "$CC_VERSION" ] || die "after reinstall, 'claude --version' reports '${new_ver:-unknown}', not the requested v${CC_VERSION}"
    if [ "$CC_BIN_USER" = 0 ]; then
      cc_link="$(command -v claude)"
      CC_BIN="$(readlink -f "$cc_link" 2>/dev/null || realpath "$cc_link" 2>/dev/null || echo "$cc_link")"
      [ -f "$CC_BIN" ] || die "after reinstall, the Claude Code binary was not found at: $CC_BIN"
    fi
    info "Claude Code is now v${CC_VERSION} (binary: ${CC_BIN})"
  fi
else
  info "CC_PIN=0: building for the installed Claude Code v${CC_INSTALLED} (rules may not apply cleanly if it differs from the supported version)"
fi

# ---------------------------------------------------------------------------
# 4. Build the un-nerfed prompts for THIS CC version
# ---------------------------------------------------------------------------
log "Building un-nerfed prompts for v${CC_VERSION}"
if [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] would: npm install (gray-matter), sync-version.mjs ${CC_VERSION} --download, apply-unnerfs.py,"
  info "[dry-run]        tweakcc --apply (patch the binary), then set DISABLE_AUTOUPDATER=1 in ${HOME}/.claude/settings.json"
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
    # The un-nerf landed — ensure CC's auto-updater is off so a background update
    # can't replace this binary and silently revert it. Idempotent: only writes (and
    # prints the reason) when DISABLE_AUTOUPDATER isn't already set.
    cc_persist_disable_autoupdate
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
