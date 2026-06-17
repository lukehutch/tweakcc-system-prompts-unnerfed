# tweakcc system prompts — un-nerfed edition

Modified [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) system prompts that remove the "be brief, be minimal" directives and replace them with instructions to be thorough. These are the actual files I use daily. Nothing here is cleaned up for public consumption — this is the live set, including all in-progress un-nerfs.

> [!NOTE]
> Currently aligned with **Claude Code v2.1.179**.

|  |  |
|---|---|
| [Install](#install) | Get these running on your machine |
| [The thesis](#the-un-nerf-thesis) | Why these edits exist |
| [Examples](#beforeafter-examples) | What the changes look like |
| [Maintenance](MAINTENANCE.md) | Keeping up with new Claude Code releases |
| [Background](BACKGROUND.md) | How tweakcc works, where these edits came from |

---

## Install

You need [tweakcc](https://github.com/Piebald-AI/tweakcc) to patch these into your Claude Code binary.

### Quick install (recommended)

[`install.sh`](install.sh) detects your Claude Code version, downloads the latest un-nerf rules straight from this repo, rebuilds that exact version's stock prompts, replays every un-nerf onto them, patches the binary, and then verifies the un-nerf actually landed:

```bash
# clone, then:
./install.sh                 # ./install.sh --help for options (--prompts-only, --dry-run)
```

It applies **only the system-prompt patches** (`tweakcc --apply --patches …`), which sidesteps a real problem on recent Claude Code releases: a bare `tweakcc --apply` also runs tweakcc's *UI* patches, whose regexes lag new CC versions and abort the whole repack. One interactive step remains — tweakcc's extractor is a TUI that can't be driven headlessly — and the script walks you through it (then continues automatically).

### Manual install

Prefer to do it by hand, or want a pinned release? Grab the un-nerfed prompts as a release zip from [Releases](https://github.com/BenIsLegit/tweakcc-system-prompts-unnerfed/releases) (pick the tag matching your CC version), then:

```bash
# 1. Wipe any existing tweakcc prompts (tweakcc won't overwrite edited files,
#    so a clean slate avoids conflicts)
rm -rf ~/.tweakcc/system-prompts          # Unix
# Remove-Item -Recurse -Force "$HOME\.tweakcc\system-prompts"  # Windows

# 2. Extract fresh stock prompts from your Claude Code binary (interactive TUI)
npx tweakcc@latest

# 3. Drop the un-nerfed prompts on top of the stock ones (overwriting stock).
#    Replace <PATH-TO-DOWNLOADED-ZIP> with where you saved the release asset.
unzip -o <PATH-TO-DOWNLOADED-ZIP> -d ~/.tweakcc/system-prompts/   # Unix
# Expand-Archive -Force <PATH-TO-DOWNLOADED-ZIP> "$HOME\.tweakcc\system-prompts" # Windows

# 4. Patch the binary — apply ONLY the system-prompt patches by id, because a
#    bare `--apply` may fail on recent CC versions (its UI patches lag upstream).
npx tweakcc@latest --apply --patches "$(cd ~/.tweakcc/system-prompts && ls *.md | sed 's/\.md$//' | paste -sd,)"

# 5. Restart any running Claude Code sessions
```

Leave the rest of `~/.tweakcc/` alone when you wipe `system-prompts/`. Files like `config.json`, `systemPromptOriginalHashes.json`, and `native-binary.backup` need to survive.

You don't have to patch anything to get value from this repo. The files work as a prompt-engineering reference on their own — browse [`system-prompts/`](system-prompts) on GitHub, or unzip the release asset and read them locally. The diffs between stock and un-nerfed text are a case study in how brevity directives shape model behavior. And if you only want one or two changes, cherry-pick individual `.md` files. Each one is self-contained.

---

## The un-nerf thesis

Claude Code's stock prompts contain way more instructions to be brief than instructions to be thorough. Count them yourself. They fall into four groups:

1. **Chat brevity** — "respond in 2-3 sentences," "terse one-liner is fine." These control the text Claude sends you. Mostly fine. Nobody wants a wall of text for "what's the git status."
2. **Implementation brevity** — "don't add abstractions," "don't gold-plate," "simplest approach." These control the code Claude writes. They cause shallow implementations.
3. **Process brevity** — "as quickly as possible," "report back concisely," "2-sentence summary." These control how Claude investigates and reports. They cause under-investigation and under-reporting.
4. **Thoroughness** — "think step by step," "consider edge cases." These exist, but they're outnumbered roughly 5:1.

The principle: **keep group 1, flip groups 2 and 3, amplify group 4.**

That's it. Every edit in this repo follows that rule. The goal isn't making Claude verbose. It's making Claude thorough. The stock prompts treat those as the same thing, and they're not.

---

## Before/after examples

### Tone directive (`system-prompt-tone-concise-output-short.md`)

**Stock:**
> Your responses should be short and concise.

**Un-nerfed:**
> Your responses should be thorough, clear, and rich with explanation, reasoning, and context. Favor depth and completeness over brevity — the user benefits from understanding the full picture, including tradeoffs, related observations, and the reasoning behind decisions. There is no word limit; use whatever length the task genuinely warrants to produce genuinely helpful output.

### Error handling (`system-prompt-doing-tasks-no-unnecessary-error-handling.md`)

**Stock:**
> Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don't use feature flags or backwards-compatibility shims when you can just change the code.

**Un-nerfed:**
> Add error handling and validation at real boundaries where failures can realistically occur (user input, external APIs, I/O, network). Trust internal code and framework guarantees for truly internal paths. Don't use feature flags or backwards-compatibility shims when you can just change the code.

The stock version leads with the prohibition ("don't add"). The un-nerfed version leads with the requirement ("add ... at real boundaries"). Same safety caveat, opposite default.

### Implementation scope (`system-prompt-doing-tasks-no-additions.md`)

**Stock:** "Don't add features, refactor, or introduce abstractions beyond what the task requires. A bug fix doesn't need surrounding cleanup [...] Three similar lines is better than a premature abstraction. No half-finished implementations either."

**Un-nerfed:** "Implement the task completely and to a senior-engineer standard. Handle the edge cases, error paths, and failure modes the task implies, even if unstated [...] When a bug fix exposes adjacent breakage or you touch code that is plainly flawed, fix it and say what you did rather than working around it. Leave every file you touch clearer than you found it. And never ship a half-finished implementation."

The stock version caps the work at the literal ask, which produces shallow code. The un-nerfed version demands a complete, robust, senior-grade implementation while keeping the genuinely good "never half-finished" clause.

> [!NOTE]
> Earlier editions of this README highlighted a `system-reminder-thinking-frequency-tuning.md` flip ("Avoid unnecessary thinking" → "Think as deeply as the work benefits from"). Anthropic **removed that reminder entirely** somewhere between v2.1.142 and v2.1.179, so there is no longer a "think less" directive to flip — a rare case of upstream moving in the un-nerf direction on its own. The rule was retired during the v2.1.179 sync.

---

## Repo layout

```
system-prompts-github/
├── README.md
├── MAINTENANCE.md
├── BACKGROUND.md
├── install.sh                    # one-command installer; fetches the latest rules from git
├── scripts/
│   ├── sync-version.mjs          # rebuilds stock prompts for a given CC version
│   └── apply-unnerfs.py          # re-applies all un-nerfs after a CC version bump
└── system-prompts/               # 513 markdown files (Claude Code v2.1.179)
    ├── system-prompt-*.md        # core behavioral instructions, tone, task guidance (135)
    ├── tool-description-*.md     # tool descriptions shown to the model (130)
    ├── system-reminder-*.md      # injected into user messages (73)
    ├── agent-prompt-*.md         # subagent system prompts (61)
    ├── skill-*.md                # user-facing skill bodies (58)
    ├── data-*.md                 # reference data blobs (50)
    └── tool-parameter-*.md       # parameter-level tool descriptions (5)
```

Counts are approximate. The full inventory is whatever `ls system-prompts/` shows.

---

## Compatibility

- **Claude Code version:** Aligned with v2.1.179. Individual prompts carry `ccVersion:` frontmatter ranging from v2.0.14 to v2.1.179. When Anthropic ships a new version, see [MAINTENANCE.md](MAINTENANCE.md) for the update workflow.
- **Model family:** Tuned for current Claude models (Opus 4.8 / Sonnet 4.6 / Haiku 4.5). Older or smaller models might over-explain simple responses with these prompts active.
- **Over-verbosity:** This is the main failure mode to watch for. If Claude starts writing essays in response to "what time is it?", look at `system-prompt-communication-style.md` and `system-prompt-tone-concise-output-short.md` first.
- **Token cost:** Thorough output uses more tokens. Plan accordingly.

---

## Credits

- **[tweakcc](https://github.com/Piebald-AI/tweakcc)** by Piebald AI — the tool that makes all of this possible.
- **[roman01la's patch-claude-code.sh gist](https://gist.github.com/roman01la/483d1db15043018096ac3babf5688881)** — the original thesis and first 11 patches, which I translated into tweakcc format. See [BACKGROUND.md](BACKGROUND.md#the-original-gist) for the full breakdown.
- **Anthropic** — for Claude Code, and for not going out of their way to stop community patching.

---

## License / disclaimer

The prompt text in `system-prompts/*.md` was extracted from Claude Code by tweakcc, then modified. The original prompt content is Anthropic's copyright. I'm redistributing a modified subset under fair-use / research-use terms, same basis the tweakcc project operates on.

The README, docs, and repo organization are **CC0 / public domain**.

**This is not Anthropic-endorsed or Anthropic-supported.** Applying these will change Claude Code's behavior in ways that might not suit your workflow. Test in a throwaway session first. Keep the tweakcc binary backup so you can roll back.

If something here behaves badly, open an issue or PR.
