# Maintenance

How to keep these un-nerfed prompts current when Anthropic ships a new Claude Code release.

## Quick version

Every Claude Code update can change the wording of any system prompt. When that happens, run [`sync-version.mjs`](./scripts/sync-version.mjs) to rebuild `system-prompts/` from tweakcc's published JSON for the new version, then run [`apply-unnerfs.py`](./scripts/apply-unnerfs.py) to replay the un-nerfs against the new text. Together the two scripts handle most of the refresh automatically. You only step in when upstream changed the exact wording that a rule targets.

---

## The apply-unnerfs.py script

Located at [`scripts/apply-unnerfs.py`](./scripts/apply-unnerfs.py). Stdlib-only Python, no pip install. Safe to run repeatedly.

The script reads every `.md` file in `system-prompts/`, matches each against a table of `(stock_text, unnerf_text)` rules, and does string replacement. For each rule, one of four things happens:

| Result | Meaning |
|---|---|
| **APPLIED** | Found the stock text, replaced it with the un-nerfed version. File rewritten. |
| **SKIPPED** | Un-nerfed text already present. Nothing to do. |
| **NORMALIZED** | No content change needed, but CRLF line endings were fixed to LF. |
| **FAIL** | Neither stock nor un-nerfed text found. Upstream drifted. Needs your attention. |

It also normalizes any accidental CRLF line endings back to LF.

### Flags

| Flag | What it does |
|---|---|
| *(none)* | Apply all rules to `./system-prompts/`. Writes to disk. |
| `--dry-run` | Report what would change without writing anything. |
| `--check` | Like `--dry-run`, but exits 1 if any rule would apply or fail. Good for CI. |
| `--only FILE` | Restrict to one filename (just the name, no path prefix). |
| `--verbose` | Show context on SKIPPED entries too. |
| `--dir PATH` | Target a different prompts directory. |

---

## The sync-version.mjs script

Located at [`scripts/sync-version.mjs`](./scripts/sync-version.mjs). Node.js ES module, pinned to `gray-matter@4.0.3` — the exact dependency tweakcc itself uses. Takes a Claude Code version and rebuilds every `.md` in `system-prompts/` from the matching `prompts-X.Y.Z.json` that tweakcc publishes alongside its own releases.

The output is **byte-identical** to what tweakcc's extractor would produce against a freshly installed Claude Code binary at that version — because the script calls the same `matter.stringify()` with the same options as tweakcc's [`generateMarkdownFromPrompt`](https://github.com/Piebald-AI/tweakcc/blob/main/src/systemPromptSync.ts). Verified by diffing 294/294 files against a fresh `~/.tweakcc/system-prompts/` extraction on v2.1.142, and re-confirmed on the v2.1.179 sync by checking the reconstructed prompt text against the string literals in the actual installed binary (`tweakcc unpack` → grep): every distinctive line was present, the only "misses" being lines whose sole non-ASCII char (an emoji or `×`) is stored `\u`-escaped in the binary.

### One-time setup

```bash
cd scripts
npm install --ignore-scripts --save-exact
```

That installs `gray-matter@4.0.3` (and its transitive deps) into `scripts/node_modules/`. The lockfile is checked in, so the install is reproducible. Re-running is idempotent and safe.

### Usage

```bash
node scripts/sync-version.mjs 2.1.140              # most common — local clone first, GitHub fallback
node scripts/sync-version.mjs                      # prompts interactively for version
node scripts/sync-version.mjs 2.1.140 --dry-run    # preview without writing
node scripts/sync-version.mjs 2.1.140 --download   # skip local clone, always fetch from GitHub
```

### Flags

| Flag | What it does |
|---|---|
| *(none)* | Wipe `./system-prompts/*.md` and rewrite from the JSON for the given version. |
| `--tweakcc-dir PATH` | Override the local tweakcc clone path. Default: `G:/Cathedral/repos_external/tweakcc`. |
| `--target PATH` | Override the output directory. Default: `./system-prompts/`. |
| `--download` | Skip the local-clone check and always fetch from GitHub. |
| `--dry-run` | Report what would change without writing. |
| `--no-clear` | Don't delete existing `.md` files before writing. |
| `-h`, `--help` | Show usage. |

### Where the prompts come from

The script reads `data/prompts/prompts-{version}.json` from your local tweakcc clone first (default path: `G:/Cathedral/repos_external/tweakcc`), and falls back to fetching it from `https://raw.githubusercontent.com/Piebald-AI/tweakcc/refs/heads/main/data/prompts/` when the local file is missing. The JSON itself is tweakcc's pre-extracted form of the prompts; Piebald-AI regenerates it whenever they cut a tweakcc release that supports a new Claude Code version.

### When NOT to use it

If Anthropic just shipped a new Claude Code release and tweakcc hasn't published the matching `prompts-X.Y.Z.json` yet, the script will exit 1 with a 404 from GitHub. tweakcc typically lags a few hours behind a CC release. When this happens, use the binary-extraction fallback at the bottom of the next section.

---

## Full workflow after a Claude Code bump

The fast path uses [`sync-version.mjs`](./scripts/sync-version.mjs) to skip the binary-extraction step entirely. Once tweakcc has published `prompts-X.Y.Z.json` for the new release (usually within hours of a Claude Code drop), you can rebuild the whole prompts tree without touching your local Claude Code install.

> [!IMPORTANT]
> **On recent Claude Code releases, patch system prompts by id.** As of the v2.1.179 sync, upstream `tweakcc@latest` (4.0.14) extracts and `unpack`s the binary correctly, but a bare `tweakcc --apply` also runs tweakcc's *UI* patches (e.g. `patches-applied-indication`), whose regexes lag the newer minified output and make the whole repack abort. Apply **only the system-prompt patches** instead:
> ```bash
> npx tweakcc@latest --apply --patches "$(cd ~/.tweakcc/system-prompts && ls *.md | sed 's/\.md$//' | paste -sd,)"
> ```
> [`install.sh`](./install.sh) does exactly this (with only the *changed* ids) and then verifies the result. `tweakcc-fixed@latest` remains an option but targets CC through v2.1.142; see [BACKGROUND.md](BACKGROUND.md#which-fork-to-use).

### Updating this repo

1. **Sync the stock prompts.** `node scripts/sync-version.mjs X.Y.Z`. This wipes `./system-prompts/` and rewrites every `.md` from tweakcc's `prompts-X.Y.Z.json`. The script tries your local tweakcc clone first (default `G:/Cathedral/repos_external/tweakcc`), falling back to GitHub. Don't commit yet — run `git diff` first to see exactly what Anthropic changed upstream.

2. **Run the re-apply script.** `python scripts/apply-unnerfs.py`. Read the report.

3. **Fix any FAILs.** Open each failed file, find the passage the rule targets (the report quotes the first 200 chars as a search term), and compare the new upstream wording against the old. Usually the drift is cosmetic and you just need to update `stock` in the rule to match the new wording byte-exactly. If upstream removed the passage entirely, delete the rule and note it in the commit.

4. **Re-run until clean.** Keep running `apply-unnerfs.py` until the report shows only APPLIED, SKIPPED, and NORMALIZED. No FAILs.

5. **Check for new prompts.** `git status` will show untracked `.md` files for anything Anthropic added. Read each one and decide if it introduces a brevity nerf worth flipping. Some new prompts (structured JSON generators with word caps, for example) should stay stock. Use the [un-nerf thesis](README.md#the-un-nerf-thesis) to decide.

6. **Commit.** The updated `.md` files and any `apply-unnerfs.py` rule changes together, while the diff is still small and the context is fresh.

That's everything needed to keep this repo current. The remaining steps are for users who also want to patch their **local** Claude Code binary so it actually uses the un-nerfed prompts.

### Applying the un-nerfs to your local Claude Code

7. **Copy to tweakcc.** From the repo root:
   ```bash
   cp system-prompts/*.md ~/.tweakcc/system-prompts/
   ```

8. **Patch the binary.** `npx tweakcc-fixed@latest --apply`.

9. **Restart Claude Code** and verify a representative un-nerfed prompt actually made it in by triggering the relevant behavior.

### Fallback: when tweakcc hasn't published yet

If `sync-version.mjs` exits 1 with a 404 because tweakcc lags behind a fresh Claude Code release, do the binary-extraction loop manually. tweakcc won't overwrite files you've edited, so the cleanest approach is wiping its local prompts directory and getting a clean stock extraction from the new binary:

1. **Update Claude Code** the normal way (installer, npm upgrade, whatever).
2. **Wipe `~/.tweakcc/system-prompts/`.**
   ```bash
   rm -rf ~/.tweakcc/system-prompts          # Unix
   # Remove-Item -Recurse -Force "$HOME\.tweakcc\system-prompts"  # Windows
   ```
   Leave the rest of `~/.tweakcc/` alone. `config.json`, hash files, and `native-binary.backup` need to survive.
3. **Re-extract with tweakcc.** `npx tweakcc-fixed@latest`. It reads the new binary and writes fresh stock `.md` files with no conflicts.
4. **Copy the fresh stock into this repo:**
   ```bash
   cp ~/.tweakcc/system-prompts/*.md system-prompts/
   ```

Then resume from step 2 ("Run the re-apply script") above.

---

## Adding a new un-nerf

1. Read the `.md` file you want to change. Find the passage to flip.

2. Open [`scripts/apply-unnerfs.py`](./scripts/apply-unnerfs.py) and add a `Rule(stock=..., unnerf=..., description=...)` entry under the matching filename key in `RULES`. Create the key if the file is new.
   - `stock` must match what's in the file byte-exactly, including trailing whitespace and any template literals like `${VAR}`.
   - `unnerf` is the replacement. Write it in the same thorough-over-brief voice as the rest.
   - `description` is a short scannable label (e.g. `"tone body: flip 'short and concise' to 'thorough'"`).

3. Preview: `python scripts/apply-unnerfs.py --dry-run --only <filename>`

4. Apply: run without `--dry-run` once you're happy with the preview.

5. Verify: `git diff` should show only the replacement you expected.

6. Confirm idempotent: `python scripts/apply-unnerfs.py --check`

7. Commit the script change and the un-nerfed `.md` together.

---

## Understanding FAIL reports

A FAIL in the report looks like this:

```
system-prompts/some-file.md
  [FAIL    ] <rule description>
             Expected stock text (first 200 chars):
               'Briefly explain what ...'
             Expected un-nerf text (first 200 chars, for reference):
               'Explain thoroughly what ...'
             Neither was found in the file.
             Action: open the file and locate the passage.
```

The two quoted excerpts tell you both what you're looking for (the pre-drift stock) and what the result should be (the target un-nerf). The file path tells you exactly where to go.

Three common causes:

- **Upstream reworded the passage.** Anthropic tweaked the phrasing in a new release. Find the new wording in the file, update `stock` in the rule to match. The `unnerf` usually doesn't need to change unless the new wording is structurally different.
- **Upstream removed the passage.** The nerfed directive got deleted from the prompt. Delete the rule and note it in your commit.
- **Upstream replaced it with something neutral.** The brevity directive got swapped for a neutral or pro-thoroughness one. Delete the rule. The un-nerf isn't needed anymore.

---

## CI / pre-commit (optional)

`--check` exits 1 when anything would change, so you can wire it into a pre-commit hook:

```bash
python scripts/apply-unnerfs.py --check || {
  echo "Un-nerfs not fully applied. Run: python scripts/apply-unnerfs.py"
  exit 1
}
```
