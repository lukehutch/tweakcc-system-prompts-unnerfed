# The un-nerf guide — objectives & upgrade playbook

This is the single source of truth for **what this project is trying to do** and
**how to upgrade it when Anthropic ships a new Claude Code version**. If you are
re-running the sync against a newer Claude Code, read Part 1 (so you make the
right keep/flip calls) then follow Part 2 (the workflow). The later parts are the
reference detail behind each step.

> Companion docs: [README](README.md) (what/why for users), [MAINTENANCE](MAINTENANCE.md)
> (script flags), [BACKGROUND](BACKGROUND.md) (history, how tweakcc works).
> This guide supersedes and unifies the "upgrade" material in those.

---

## Part 1 — The objective

Claude Code's stock prompts contain far more instructions to **be brief** than to
**be thorough** — roughly 5:1. That imbalance makes the model cut corners on real
work. This project rebalances it. The goal is **not verbosity** — it is
**thoroughness**. The stock prompts conflate the two; they are not the same.

Every stock brevity directive falls into one of four buckets. The whole project
is one rule applied consistently:

> **Keep bucket 1. Flip buckets 2 and 3. Amplify bucket 4.**

| # | Bucket | What it controls | Action | Example |
|---|--------|------------------|--------|---------|
| 1 | **Chat brevity** | length of conversational replies to trivial asks | **KEEP** | "respond in 2-3 sentences", "a terse one-liner is fine" for *what's the git status* |
| 2 | **Implementation brevity** | the *code* Claude writes | **FLIP** | "don't add abstractions", "simplest approach", "don't gold-plate", "do the minimum" |
| 3 | **Process brevity** | how Claude *investigates and reports to a human* | **FLIP** | "as quickly as possible", "report back concisely", "2-sentence summary", "briefly explain" |
| 4 | **Thoroughness** | "think step by step", "consider edge cases" | **AMPLIFY** | already pro-quality — strengthen it |

### The keep/flip decision procedure

When a prompt contains a brevity-signature phrase, decide with this checklist
(in order — the first match wins):

1. **Is the output a structured artifact or machine-parsed?** A title, branch
   name, commit message, JSON object, classification label, autocomplete
   suggestion, a status string parsed by a script, a notification with an
   explicit character cap. → **KEEP.** Length here is UX/format, not work depth.
   (`agent-prompt-session-title-and-branch-generation`, `system-prompt-insights-*`,
   `agent-prompt-workflow-subagent-plain-text-output`.)
2. **Is it a functional constraint?** "minimal `old_string` for uniqueness",
   "no preamble before the *required* tool call", "avoid sleep-polling",
   "CLAUDE.md must be concise" (it loads into every session). → **KEEP.** The
   brevity is doing real mechanical work.
3. **Is it safety / security?** Deny-rules, confirmation gates, classifier
   guidance. → **KEEP** (or make *stricter* — never weaker). A *fuller*
   explanation that helps a human's safety decision is a legitimate flip of the
   *explanation*, not the gate (see `system-prompt-troubleshooting-confirmation-policy`).
4. **Is it reference / documentation / example content?** Every `data-*.md` blob,
   API docs, sample prompts quoted inside a guide. → **KEEP.** A length cap
   *inside an example* is not a directive to Claude.
5. **Otherwise — does it cap engineering depth or human-facing reporting?**
   "simplest approach", "don't add/refactor/abstract", "investigate as quickly as
   possible", "keep your report short", a 2-sentence cap on an end-of-turn or
   subagent-to-human summary. → **FLIP** to thoroughness.

The hardest calls are subagent prompts: a subagent's report **to a human or to an
orchestrating agent that needs detail** should be thorough (flip), but a subagent
whose output is **parsed by a workflow script** should stay concise (keep). Same
word, opposite call — decide by *who consumes the output*.

When you flip, write the replacement in the project's voice: lead with the
*requirement* ("Make your review exhaustive…"), not the prohibition; preserve any
genuinely-good clause already present (safety caveats, "never half-finished");
keep it about **depth and completeness**, never about padding word count.

---

## Part 2 — The upgrade workflow (happy path)

When Anthropic ships Claude Code `X.Y.Z` and tweakcc has published
`prompts-X.Y.Z.json` (usually within hours — see Part 8):

```bash
# 0. one-time: install the gray-matter dep the sync script uses
cd scripts && npm install --ignore-scripts --save-exact && cd ..

# 1. Rebuild STOCK prompts for the new version AND auto-diff the checksum manifest.
#    This overwrites system-prompts/*.md with stock and rewrites
#    system-prompt-checksums.json. The diff it prints IS your review worklist.
node scripts/sync-version.mjs X.Y.Z --download

# 2. Replay the un-nerfs onto the fresh stock.
python3 scripts/apply-unnerfs.py

# 3. Read the apply report. Any [FAIL] = a rule whose stock text drifted (Part 6).
#    Fix rules until the report is all APPLIED/SKIP, then gate:
python3 scripts/apply-unnerfs.py --check    # exit 0 = idempotent & clean

# 4. Review the manifest diff from step 1 (Part 5):
#      CHANGED with a rule  -> apply-unnerfs already told you (FAIL) if it drifted
#      CHANGED without rule -> grep-triage + read; flip if it's a new bucket-2/3 nerf
#      ADDED                -> grep-triage + read each; most data-*/structured = keep
#      REMOVED              -> retire the rule(s) targeting it
git diff system-prompts/ system-prompt-checksums.json   # eyeball before committing

# 5. (optional, recommended) verify against the actually-installed binary (Part 7)

# 6. Commit the stock+un-nerf+manifest+rule changes together (Part 2, "commit").
```

**What `sync-version.mjs` prints (the key new behavior).** On every run it diffs
the freshly-generated stock against the manifest from the *previous* sync and
reports `CHANGED / ADDED / REMOVED / unchanged`, then rewrites the manifest for
the new version. This is the authoritative "what did Anthropic change" list —
and crucially it is **clean**: because it fingerprints *stock*, it is not
polluted by your own un-nerf edits the way `git diff` on the un-nerfed tree is.

If tweakcc has **not** published `prompts-X.Y.Z.json` yet, you can't run the
happy path — see Part 8 ("the publish lag") for what to do.

### Committing

Stage the prompt tree, the manifest, and any rule changes together:

```bash
git add system-prompts/ system-prompt-checksums.json scripts/apply-unnerfs.py
git commit   # message: "sync prompts to Claude Code vX.Y.Z (+/- rules, manifest)"
```

Commit while the diff is small and the context is fresh. Note in the message any
rules retired (removed prompts) or added (new nerfs), and any FAILs you resolved.

---

## Part 3 — Reading the prompts (where stock text comes from)

Claude Code (since v2.1.113) ships as a compiled Bun **native binary** with its
prompts baked in as string literals. There are two ways to get the stock text:

### A. tweakcc's published JSON (the normal source)

tweakcc publishes one `prompts-X.Y.Z.json` per supported CC version at
`https://raw.githubusercontent.com/Piebald-AI/tweakcc/refs/heads/main/data/prompts/`.
Each prompt object is `{ id, name, description, version, pieces[], identifiers[],
identifierMap }`. The `.md` body is reconstructed by interleaving `pieces` with
`${HUMAN_NAME}` placeholders from `identifierMap`; the frontmatter is `name`,
`description`, `ccVersion` (the version when *that prompt* last changed — **not**
the global CC version), and `variables`. `scripts/sync-version.mjs` does exactly
this, byte-identically to a tweakcc extraction.

> tweakcc does **not** publish every patch release, and a fresh release can lag by
> hours-to-days. If the JSON for your installed version isn't up yet, see Part 8
> ("the publish lag") — but the normal case is that the latest version is available.

### B. The installed binary, via `tweakcc unpack` (ground truth, version-independent)

`tweakcc unpack` extracts the bundled JS from *any* installed binary without
needing published JSON — useful to (a) verify the JSON-derived prompts actually
match what you're running, and (b) inspect a version tweakcc hasn't published.

```bash
CCBIN="$(readlink -f "$(command -v claude)")"   # e.g. .../@anthropic-ai/claude-code/bin/claude.exe
npx --yes tweakcc@latest unpack /tmp/cc.js "$CCBIN"   # writes ~17 MB of JS; reads only, non-destructive
```

You then search that JS for prompt text. **Escaping gotcha:** the minified JS
stores non-ASCII as escapes — em-dash `—` → `—`, and **Latin-1 U+0080–U+00FF
→ `\xHH`** (e.g. `·` → `\xb7`, `×` → `\xd7`). A naive `grep` for a phrase
containing those will miss. To match reliably, search on the longest **pure-ASCII
run** of a piece (no `` ` `` `"` `\` newline), or build an escape-aware regex
(`for each char>127: (literal|\uXXXX|\xHH)`; newlines as `(\n|literal)`). This
`\xHH` case is the exact bug that broke ~10 prompts before tweakcc PR #808.

---

## Part 4 — Detecting what changed (the MD5 manifest)

`system-prompt-checksums.json` records the MD5 of every **stock** `.md` for the
currently-synced version. It is the project's memory of "what the upstream
prompts looked like last time," so a version bump can answer precisely: which
stock prompts changed, which are new, which are gone.

- **What's hashed:** the full stock `.md` (frontmatter + body). An untouched
  prompt keeps the same `ccVersion` and is byte-identical across CC versions →
  identical MD5; any change to body *or* metadata flips it. (A pure `ccVersion`
  re-stamp with an otherwise-identical body *will* flip the hash — that's a
  conservative false-positive, not a miss. Confirm with a quick `diff`.)
- **It is STOCK hashes, not the un-nerfed files** committed in `system-prompts/`.
  Pointing a hasher at the un-nerfed tree reports the un-nerfs as "changed" — by
  design. This separation is the whole point: `git diff` on the un-nerfed tree
  mixes "Anthropic reworded this" with "my un-nerf is being reverted"; the
  manifest diff shows only Anthropic's changes.
- **Who writes it:** `sync-version.mjs` (automatically, from the stock it holds
  in memory before any un-nerf runs). For the binary-extraction fallback, the
  standalone tool writes it from a stock dir:

```bash
# Diff a stock tree against the manifest (read-only):
node scripts/prompt-checksums.mjs --dir <stock-dir>
# CI gate — exit 1 if a stock tree drifts from the manifest:
node scripts/prompt-checksums.mjs --dir <stock-dir> --check
# (Re)write the manifest for a version:
node scripts/prompt-checksums.mjs --dir <stock-dir> --ccVersion X.Y.Z --write
```

`--dir` must point at **stock** prompts (a tweakcc extraction or a
`sync-version.mjs --target` output), never the un-nerfed `system-prompts/`.

---

## Part 5 — Reviewing prompts for nerfs

Two passes: the **delta** (what changed this version) and, periodically, a **full
sweep** (catch nerfs missed in prior versions). The manifest narrows the delta to
just CHANGED+ADDED; the full sweep is reproducible via grep-triage.

### Delta review

From the manifest diff (Part 4): for each **CHANGED** file, if it has a rule,
`apply-unnerfs.py` already told you via FAIL whether the rule's target drifted.
If it has no rule, or is ADDED, grep it for brevity signatures and read the hits
in context, then apply the Part-1 decision procedure.

### Full-sweep triage (grep)

```bash
PAT='be (brief|concise|terse)|keep (it|your response) (brief|short|concise)|as (quickly|briefly) as|minimal (explanation|detail|response)|do(n.t| not) (add|over-explain|gold-plate|elaborate)|simplest (approach|solution)|the minimum|[12]-?[0-9]? sentence|no preamble|avoid (verbosity|being verbose)|terse|succinct'
# files that mention brevity but have NO rule (candidate missed nerfs):
comm -23 <(grep -rliE "$PAT" <stock-dir>/*.md | xargs -n1 basename | sort) \
         <(grep -oE '"[^"]+\.md"' scripts/apply-unnerfs.py | tr -d '"' | sort -u)
# then read the matching lines and judge each against Part 1:
grep -inE "$PAT" <stock-dir>/<candidate>.md
```

Most candidates resolve to **keep** (structured output, reference blobs,
functional uses of "minimal"/"short"). Only a real bucket-2/3 directive that
degrades engineering work or human-facing reporting gets a rule. Be conservative
— a false flip is worse than a miss.

For maximum confidence on a big sweep, partition the prompt set by category
(`system-prompt-*`, `agent-prompt-*`, `tool-description-*`, `skill-*` +
`system-reminder-*`, `data-*`) and review each slice independently against the
Part-1 buckets — `data-*` is almost always all-keep (reference blobs).

---

## Part 6 — Updating the rules

Un-nerfs live in `scripts/apply-unnerfs.py` as `Rule(stock, unnerf, description)`
triples keyed by filename. The script finds `stock` and replaces it with `unnerf`
(idempotent: if `unnerf` is already present it SKIPs; if neither is found it
FAILs).

### Adding a rule

```python
"system-prompt-foo.md": [
    Rule(
        stock="<exact stock text, byte-for-byte, incl. ${VARS} and \n>",
        unnerf="<thorough replacement in the project's voice>",
        description="<short scannable label of what it flips>",
    ),
],
```

- `stock` must be **byte-exact**: preserve `${VAR}` interpolations, trailing
  whitespace, and embedded `\n` newlines. Verify with
  `grep -cF "<phrase>" system-prompts/<file>.md` (use a single-line ASCII
  substring; for newline-spanning targets verify in Python:
  `'a\nb' in open(f).read()`).
- Prefer a **short, unique** stock substring over a whole paragraph — it's less
  likely to drift on the next version, and uniqueness-within-the-file is all the
  matcher needs.
- **Quote/escape safety:** an un-nerf containing `"` inside a `${"..."}` literal
  can break things; non-idempotent rules where `unnerf` contains `stock` verbatim
  will re-apply forever — avoid both. Gate with `--check`.

### Handling FAILs (drift) and structural changes

| Situation | Action |
|---|---|
| Upstream **reworded** the passage | Update the rule's `stock` to the new wording (the `unnerf` usually stands). |
| Upstream **removed** the passage/prompt | **Retire** the rule (delete it; note in commit). |
| Upstream **replaced** brevity with neutral/pro-thorough text | Retire the rule — the nerf is gone. |
| A prompt was **renamed** | **Retarget**: move the rule to the new filename key (e.g. `skill-simplify.md` → `agent-prompt-simplify-slash-command.md`). |

Confirm the same flip isn't needed in a **sibling** prompt — Claude Code often
duplicates a sentence across related prompts, and rules are per-file. Don't
eyeball this — run the **exhaustive sibling audit**: import `RULES`, and for each
rule grep its `stock` across every stock `.md`; any match in a file that *isn't*
the rule's own key is an un-ruled sibling to flip (unless the match is
example/reference content — e.g. a sample prompt quoted inside a guide, which
stays). This session's audit closed one such gap (`async-agent-launched`) and
confirmed one intentional keep (`skill-model-migration-guide`); see Part 9.

---

## Part 7 — Verifying against the installed binary

The manifest/`apply-unnerfs` loop proves the rules apply to the *JSON-derived*
stock. To prove the prompts match what you're actually **running** (and to catch
a patch release that changed prompts the published JSON doesn't yet cover):

```bash
CCBIN="$(readlink -f "$(command -v claude)")"
npx --yes tweakcc@latest unpack /tmp/cc.js "$CCBIN"
# for each prompt, check its longest pure-ASCII piece is present in /tmp/cc.js
# (see scripts usage / Part 3 escaping note). Near-total presence => essentially
# identical; the only expected misses are micro-prompts that are pure ${interpolation}
# with no static text long enough to fingerprint (nothing to mismatch).
```

To verify an **applied** un-nerf actually reached the binary (after `tweakcc
--apply`), unpack the *patched* binary and grep for un-nerf sentinels present and
stock sentinels gone:

```bash
# un-nerf present (expect >0):
grep -c "senior-engineer standard" /tmp/cc.js
grep -c "never trade away rigor, depth, or correctness" /tmp/cc.js
grep -c "Make your review thorough and complete" /tmp/cc.js
# stock gone (expect 0):
grep -c "introduce abstractions beyond what the task requires" /tmp/cc.js
```

`install.sh` automates exactly this and **fails loudly (leaving the binary clean)
on a no-op/partial apply** — never trust tweakcc's "applied successfully" message
alone; it can report success while patching nothing.

---

## Part 8 — tweakcc operational reference

### Commands (confirmed)

| Command | What it does |
|---|---|
| `tweakcc --apply` (bare) | **THE** system-prompt apply path. Patches every prompt whose `~/.tweakcc/system-prompts/*.md` differs from stock. Self-downloads `prompts-X.Y.Z.json`, self-creates `native-binary.backup`. |
| `tweakcc --apply --patches <ids>` | **NOT** for prompts — selects UI/theme/feature patches. Applies **zero** `.md` edits. Do not use it to apply un-nerfs. |
| `tweakcc unpack <out.js> <bin>` | Extract bundled JS from a binary (read-only, version-independent). The inspection/verify workhorse. |
| `tweakcc repack <in.js> <bin>` | Re-embed JS (as Bun bytecode; size balloons). |
| `tweakcc --restore` / `--revert` | Restore the binary from `native-binary.backup`. |
| `tweakcc --list-system-prompts [ver]` | List prompts known for a version. |

The interactive TUI extracts the full `.md` set from the binary, but **cannot be
scripted** (no TTY → the React app crashes; no non-interactive extraction flag).
Use `sync-version.mjs` (JSON) or `unpack` instead.

### The publish lag (the common blocker)

Both `sync-version.mjs --download` and `tweakcc --apply` need
`prompts-X.Y.Z.json`, which lags a fresh CC release by hours-to-days. When it's
missing (404):

- **Preferred: wait for the latest version's JSON.** Since we target only the
  latest, the simplest correct move is to re-run the happy path once
  `prompts-X.Y.Z.json` for your installed version publishes (usually within a day).
- **Stopgap only if you must ship now:** sync to the newest *published* version ≤
  installed and verify against the binary (Part 7). Treat it as temporary — re-sync
  to the latest as soon as its JSON is up; the manifest will flag whatever the
  interim version missed. Don't carry the interim version as a tracked target.
- **Applying to the binary must wait** for the matching JSON (tweakcc can't locate
  prompts without it). Build tweakcc from `main` to get the freshest CC support
  (`install.sh` does this by default); `main` carries prompt-locator/repack fixes
  before they're cut into an npm release.

### `~/.tweakcc/` layout — preserve vs move-aside

`config.json` (settings + `ccVersion`), `system-prompts/*.md`,
`prompt-data-cache/prompts-X.Y.Z.json`, `systemPromptOriginalHashes.json`,
`systemPromptAppliedHashes.json`, `native-binary.backup` (~230 MB, used by
`--restore`), `native-claudejs-{orig,patched}.js`.

A **stale** older-version state shadows new prompts and can make `--restore`
recover the wrong binary. When re-extracting fresh, **preserve `config.json`;
move the rest aside** (don't delete — the backup is huge and you may need it):

```bash
cd ~/.tweakcc && stale=".unnerf-stale-$(date +%s)" && mkdir -p "$stale"
for f in system-prompts prompt-data-cache systemPromptOriginalHashes.json \
         systemPromptAppliedHashes.json native-binary.backup \
         native-claudejs-orig.js native-claudejs-patched.js; do
  [ -e "$f" ] && mv "$f" "$stale/"
done
```

tweakcc won't overwrite an *edited* `.md`, so a clean extraction needs the
`system-prompts/` dir cleared first.

### Dead ends (don't repeat)

- `--apply --patches <ids>` to apply prompts → applies nothing.
- Stock tweakcc 4.0.14 on a fresh CC → repack abort on `patches-applied-indication`
  + Latin-1 `\xHH` locator misses (~10 prompts). Fixed in `main` / ≥ 4.1.1 (PR #808).
- `adhoc-patch` for bulk prompt edits → matches raw bytes only, breaks on any
  escaped char.
- Trusting tweakcc's "applied" message → always `unpack`+grep to verify.

---

## Part 9 — Worked example: the latest sync (v2.1.196)

We track **only the latest** Claude Code version. This section is the most recent
sync, kept as a concrete template — when you re-run the workflow against a newer
release, **replace this section** with that sync's numbers rather than appending a
history.

- **Situation (a publish-lag stopgap — Part 8):** repo aligned to v2.1.191. The
  latest Claude Code release is **v2.1.197**, but tweakcc had published prompt data
  only through **v2.1.196** (`prompts-2.1.197.json` = 404). Per Part 8 the move is
  to sync to the newest *published* version and treat it as interim: ran the Part-2
  happy path targeting **2.1.196** (jumping over 192–195 in one hop), **to be
  re-synced to 2.1.197 once its JSON publishes**. No binary fingerprint (Part 7)
  was run — the binary installed on the sync machine was still v2.1.191, older than
  both the sync target and the latest release; alignment is to the published JSON,
  which `sync-version.mjs` reconstructs byte-identically to a tweakcc extraction.
- **Manifest delta:** `sync-version.mjs 2.1.196 --download` reported **14 changed,
  7 added, 0 removed** (505 unchanged); 519 → 526 prompts. Added = 3 auth-gateway
  `data-*` pages (gateway protocol, landing page, device-code entry), 3 tool
  descriptions (`invoke-skill`, `report-code-review-findings`,
  `background-monitor` ws-source), and 1 structured-JSON agent prompt
  (`fleet-agent-suggestion` scope personalization).
- **Rule drift:** `apply-unnerfs.py` → **2 FAILs, 0 missing** — both FAILs were the
  *same* retired launch-note phrase (`briefly tell the user what you launched and
  end your response.`) in its two sibling files. The other 12 changed files carried
  no rule.
- **Two retirements (structural, not reword) — the crux of this sync:**
  - `system-prompt-coordinator-mode-orchestration`: Anthropic **variable-ized** the
    launch note. Line 44 went from "…briefly tell the user what you launched and end
    your response." to "…`${WAIT_FOR_AGENT_RESULTS_INSTRUCTION}` and end your
    response." The brevity directive now lives inside a runtime variable whose value
    is **not** in any extracted `.md`, so the tweakcc `.md`-patch mechanism (static
    `pieces` replaced; `${VARS}` are wildcards) can't reach it. Retired — the
    surviving static text ("and end your response" = functional stop; "Never
    fabricate…results" = correctness guard) carries no nerf.
  - `system-reminder-async-agent-launched`: Anthropic **deleted** the clause (in
    v2.1.193). The reminder lost "Work on non-overlapping tasks, or briefly tell the
    user what you launched and end your response." and now ends at "…topics it is
    using." — a pure anti-duplication + don't-read-the-JSONL-transcript warning.
    Retired.
  - Net: **81 rules** (−2 retired, +0 added) across **62 files**, `--check` clean.
    Note the general lesson: a nerf can leave the patchable surface by being moved
    into a `${VARIABLE}` (unreachable) as well as by being deleted — both are
    retire, not retarget, unless the phrase resurfaces as static text elsewhere.
- **Review of the delta:** grep-triage + read of all 21 changed+added files
  resolved to **keep** across the board — no new bucket-2/3 nerf. Notables: the 3
  gateway pages + `data-managed-agents-endpoint-reference` are `data-*` reference
  blobs (keep); `report-code-review-findings` reports **all** verified findings with
  no count cap (structured output, keep); `security-monitor…second-part` is a
  BLOCK/ALLOW classifier (Part-1 rule #3 — never weaken, keep); the model-migration
  guide, current-models, and LLM-apps skill are reference/sample-prompt content
  (keep); the context-tip selector (1–2-sentence tip), `/review` 2–3-sentence
  overview, artifact one-sentence title, and `fleet-agent-suggestion` 3-string JSON
  are structured-output caps (keep).
- **Exhaustive sibling audit (Part 6):** all 81 rules' stock present in their own
  stock file; **0 un-ruled siblings**. Every cross-file stock match is already
  ruled in both files (the remote-plan/remote-planning pair, general-task ↔
  general-purpose, the two subagent-example files, bash-git-commit ↔ quick-pr) or is
  the intentional `skill-model-migration-guide` keep (the "recommendation, not an
  exhaustive survey" sentence, still inside a quoted sample prompt in v2.1.196).
- **Binary check:** **skipped** this sync (installed binary v2.1.191 ≠ sync target
  v2.1.196 ≠ latest v2.1.197). On the re-sync to 2.1.197 — or if the machine
  upgrades to 2.1.197 first — run the Part-7 `unpack`+fingerprint against the real
  binary to confirm JSON-derived stock == running binary before trusting an
  `--apply`, and to catch any prompt that changed between 196 and 197.
