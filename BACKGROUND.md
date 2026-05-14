# Background

Where these un-nerfed prompts came from and how tweakcc works.

---

## What is tweakcc?

[tweakcc](https://github.com/Piebald-AI/tweakcc) is a community tool that makes Claude Code's system prompts editable. Since v2.1.113, Claude Code ships as a compiled Bun native binary with its prompts baked in as string literals. You can't just open a config file and change them.

tweakcc handles that. When you run it, it:

1. Finds the Claude Code binary on disk.
2. Extracts every system prompt, tool description, agent prompt, skill body, and reference blob into `.md` files under `~/.tweakcc/system-prompts/` (Windows: `C:\Users\<you>\.tweakcc\system-prompts\`).
3. Records a hash of each original prompt in `systemPromptOriginalHashes.json`.
4. On demand, recompiles the binary with your edited `.md` content substituted in, and records applied hashes in `systemPromptAppliedHashes.json`.
5. Keeps a backup of the original binary (~234 MB) so you can always roll back.

Edit any prompt in a text editor, run tweakcc, and Claude Code uses your version from that point on. That folder is exactly what this repository mirrors.

### Why tweakcc and not the gist's patcher?

The script in [roman01la's gist](#the-original-gist) predates the native-binary era. It worked by installing Claude Code from npm (which shipped plain JavaScript), running `sed`-style replacements against `cli.js`, and repointing the `claude` symlink. As of v2.1.113, Anthropic moved to a compiled Bun binary with bytecode integrity checks, and that approach stopped working.

tweakcc is the modern equivalent: same philosophy (edit the prompts), different mechanism (binary patching with hash verification and rollback).

---

## Which fork to use

Upstream [Piebald-AI/tweakcc](https://github.com/Piebald-AI/tweakcc) is stuck at Claude Code v2.1.113 (last release: `4.0.11`, commit `2e1d03e`). Running it against v2.1.114+ fails because several patch regexes don't match the newer minified output, and some required PRs haven't merged.

Use [**BenIsLegit/tweakcc-fixed**](https://github.com/BenIsLegit/tweakcc-fixed) instead. Published as [`tweakcc-fixed`](https://www.npmjs.com/package/tweakcc-fixed) on npm. It bundles upstream PRs (#601 WASMagic import guard, #646 React Compiler output support, #655 Bun bytecode fallback + `clearBytecode`, #664 `\"` handling) plus additional fixes (scoped backslash-doubling, `verbose:X` destructure guard, adapted minified-shape regexes, and a batch of `userMessageDisplay` theme/layout fixes). Targets Claude Code through **v2.1.140**.

```bash
npx tweakcc-fixed@latest            # interactive UI
npx tweakcc-fixed@latest --apply    # apply customizations
```

Always use `@latest` because the fork updates frequently. The `~/.tweakcc/` layout and config format are identical between the two, so switching back to upstream later is painless.

---

## Where the edits came from

The un-nerfs in this repo have two origins, layered in order.

### The original gist

[roman01la's patch-claude-code.sh](https://gist.github.com/roman01la/483d1db15043018096ac3babf5688881) is a bash script that applied 11 string replacements to Claude Code's old `cli.js` distribution. Each one flipped a "be brief" instruction into a "be thorough" instruction. The gist author observed that stock Claude Code has roughly a 5:1 ratio of brevity directives to thoroughness directives, and that imbalance was causing the model to cut corners on actual work.

I didn't run the script (it targets a distribution format that no longer exists). But the patches served as a template. I translated the 11 edits into tweakcc `.md` format by hand, and that became the starting point for this repo.

**The gist's 11 patches:**

| # | What it targeted | What changed |
|---|---|---|
| 1 | "simplest approach that works" | "correctly and completely solves" |
| 2 | "do the minimum the task requires" | "do the work a senior developer would do" |
| 3 | "don't add abstractions beyond what the task requires" | softened to allow reasonable cleanup |
| 4 | anti-gold-plating clause | carve-out for fixing obviously broken adjacent code |
| 5 | error-handling guidance | add validation at real boundaries (I/O, network, user input) |
| 6 | "don't refactor" | softened |
| 7 | "match the scope of the request" | "address closely related issues you discover" |
| 8 | explore-agent "as quickly as possible" | removed; completeness preferred |
| 9 | final-report brevity cap on subagents | removed |
| 10 | "one-line docstrings max" | removed; meaningful docs allowed |
| 11 | "2-sentence end-of-turn summary" cap | removed; scale to the work |

**A/B evidence from the gist author:** porting Box2D (~30k lines of C) to JavaScript. Unpatched Claude Code produced 1,419 lines with an O(n^2) broad phase and no sub-stepping. Patched Claude Code produced 1,885 lines (+33%) with a dynamic AABB tree, 4-level sub-stepping, and soft contact constraints. The patched run produced an actual physics engine port. The unpatched run produced a toy.

The six files that carry the gist's DNA directly:

- `system-prompt-tone-concise-output-short.md`
- `system-prompt-doing-tasks-no-unnecessary-error-handling.md`
- `system-prompt-executing-actions-with-care.md`
- `system-prompt-agent-thread-notes.md`
- `agent-prompt-explore.md`
- `agent-prompt-general-purpose.md`

### My extensions

Starting from those six files, I extended the same thesis across the full prompt set. Whenever Claude Code was reflexively terse in a way that hurt output quality ("here's the fix, no explanation"), I traced the behavior to the prompt causing it, edited that prompt, and committed. The local git history at `~/.tweakcc/system-prompts/` documents every change.

The major areas beyond the gist:

- Mid-turn updates can use whatever space they need
- End-of-turn summaries scale with the work, no hard 2-sentence cap
- Code comments and docstrings are allowed to be meaningful
- Core communication-style and thinking-frequency prompts favor depth over token minimization
- Subagent and explore prompts demand thorough reports with file paths, code excerpts, and reasoning
- Tool-usage, compaction, loop-check, and thread-notes prompts produce full-context summaries
- Removed caps on subagent usage ("use the minimum number of subagents," "not excessively")
- PR-review, dream/memory, learning-insights, and batch-recipe prompts ask for thorough output
- Loop/cron confirmations and onboarding walkthroughs give full context instead of one-liners

---

## How the repo was built

1. **tweakcc extraction.** Ran tweakcc against Claude Code v2.1.113. Got 271 stock `.md` files.
2. **Gist translation.** Hand-translated the gist's 11 patches into tweakcc `.md` edits. Six files changed.
3. **Iterative un-nerfing.** Extended the thesis to more prompts over time, committing each change.
4. **Mirror copy.** Copied everything from `~/.tweakcc/system-prompts/` into this public repo. The public mirror has its own git history, separate from the private working repo.
5. **Re-apply script.** Added [`scripts/apply-unnerfs.py`](./scripts/apply-unnerfs.py) so future Claude Code bumps don't require hand-reverting every file. See [MAINTENANCE.md](MAINTENANCE.md).

The repo is kept in sync with newer releases via that script.

**Files deliberately excluded:**

- `native-binary.backup` (234 MB; not mine to redistribute)
- `native-claudejs-orig.js` / `native-claudejs-patched.js` (12 MB each; same reason)
- `systemPromptOriginalHashes.json` / `systemPromptAppliedHashes.json` (machine-specific)
- `config.json`, `prompt-data-cache/`, `.claude/`, `.serena/` (local state)

Run tweakcc yourself and these get generated for your install.
