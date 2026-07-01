# tweakcc system prompts — un-nerfed edition

**Claude Code's own system prompts, rewritten to make the model thorough instead of terse.** Claude Code ships with its prompts baked into the binary, and they lean hard on brevity — "be concise," "do the minimum," "report back in two sentences" — by roughly 5:1 over instructions to be thorough. Those directives don't just shorten chat replies; they push the model to write shallower code, investigate less, and under-report what it found. This repo extracts the prompts, flips the brevity directives that cap *engineering depth and investigation* into instructions to be thorough (while keeping the ones that merely stop it from wall-of-texting a trivial question), and patches them back into the binary with [tweakcc](https://github.com/Piebald-AI/tweakcc) — so Claude Code does the careful, senior-grade version of the work by default.

This is the live set I run daily — not cleaned up for public consumption, in-progress un-nerfs and all.

> [!NOTE]
> **Built from Claude Code v2.1.196** — 81 un-nerf rules across 62 files, `--check` clean, reconstructed byte-identically to a tweakcc extraction. It's a **stopgap**: the latest release is v2.1.197, but tweakcc hasn't published its prompt data yet (the usual hours-to-days publish lag), so re-sync when it lands. Full sync record: [UNNERF-GUIDE.md](UNNERF-GUIDE.md) Part 9.

**Docs:** [Un-nerf guide](UNNERF-GUIDE.md) (objectives + upgrade playbook) · [Maintenance](MAINTENANCE.md) (script flags) · [Background](BACKGROUND.md) (how tweakcc works)

---

## Install

You need [tweakcc](https://github.com/Piebald-AI/tweakcc) to patch these into your Claude Code binary.

**Quick (recommended).** [`install.sh`](install.sh) detects your CC version, rebuilds that version's stock prompts, replays every un-nerf, patches the binary, and **verifies the change actually landed** — failing loudly and leaving your binary clean if it didn't:

```bash
./install.sh          # --help for options (--prompts-only, --dry-run)
```

It runs non-interactively and builds tweakcc from `main` on purpose: tweakcc's npm releases can lag a fresh CC build by hours-to-days, and `main` carries the prompt-locator/repack fixes soonest. (Set `TWEAKCC_VERSION=latest` to use a released tweakcc via `npx` instead.)

**Manual.** Extract stock prompts, then overlay the un-nerfed ones:

```bash
rm -rf ~/.tweakcc/system-prompts     # clean slate — tweakcc won't overwrite edited files
npx tweakcc@latest                   # extract fresh stock via the TUI
cp system-prompts/*.md ~/.tweakcc/system-prompts/   # overlay this repo's un-nerfs
npx tweakcc@latest --apply           # a bare --apply is what applies .md edits
# then restart any running Claude Code sessions
```

On Windows, swap `rm -rf`→`Remove-Item -Recurse -Force` and `cp`→`Copy-Item`. Leave the rest of `~/.tweakcc/` alone — `config.json`, the hash files, and `native-binary.backup` must survive. Always confirm the patch took (unpack + grep) before trusting it; see [UNNERF-GUIDE.md](UNNERF-GUIDE.md) Part 7.

You don't have to patch anything to get value here — the files stand alone as a prompt-engineering reference. Browse [`system-prompts/`](system-prompts), diff stock against un-nerfed to see how brevity directives shape behavior, or cherry-pick individual `.md` files; each is self-contained.

---

## The un-nerf thesis

Claude Code's stock prompts carry far more instructions to be brief than to be thorough — roughly 5:1. They fall into four groups:

1. **Chat brevity** — "respond in 2-3 sentences." Controls the text Claude sends you. Mostly fine; nobody wants an essay for "what's the git status."
2. **Implementation brevity** — "don't add abstractions," "simplest approach." Controls the code Claude writes. Produces shallow implementations.
3. **Process brevity** — "as quickly as possible," "2-sentence summary." Controls how Claude investigates and reports. Produces under-investigation and under-reporting.
4. **Thoroughness** — "think step by step," "consider edge cases." Already good — just outnumbered.

The whole project is one rule: **keep group 1, flip groups 2 and 3, amplify group 4.** The goal isn't verbosity — it's thoroughness. The stock prompts conflate the two; they aren't the same.

---

## Before / after

**Tone** — `system-prompt-tone-concise-output-short.md`

> **Stock:** Your responses should be short and concise.
>
> **Un-nerfed:** Your responses should be thorough, clear, and rich with explanation, reasoning, and context. Favor depth and completeness over brevity […] There is no word limit; use whatever length the task genuinely warrants.

**Implementation scope** — `system-prompt-doing-tasks-no-additions.md`

> **Stock:** Don't add features, refactor, or introduce abstractions beyond what the task requires […] Three similar lines is better than a premature abstraction.
>
> **Un-nerfed:** Implement the task completely and to a senior-engineer standard. Handle the edge cases, error paths, and failure modes the task implies […] Leave every file you touch clearer than you found it. And never ship a half-finished implementation.

The pattern holds throughout: stock leads with the prohibition and caps work at the literal ask; the un-nerf leads with the requirement and preserves any genuinely-good clause (safety caveats, "never half-finished").

---

## Repo layout

```
├── install.sh                    # one-command installer (fetches latest rules from git)
├── system-prompt-checksums.json  # MD5 of every STOCK prompt; drives change detection
├── scripts/
│   ├── sync-version.mjs          # rebuild stock prompts + auto-diff the checksum manifest
│   ├── prompt-checksums.mjs      # MD5 manifest tool
│   └── apply-unnerfs.py          # replay all un-nerfs after a CC version bump
└── system-prompts/               # 526 markdown files (Claude Code v2.1.196)
```

`system-prompts/` holds the un-nerfed prompts (`tool-description-*`, `system-prompt-*`, `system-reminder-*`, `data-*`, `agent-prompt-*`, `skill-*`, `tool-parameter-*`). The checksum manifest fingerprints **stock**, not the un-nerfed files — so on a version bump `sync-version.mjs` reports exactly what Anthropic changed, uncoloured by the un-nerfs. See [UNNERF-GUIDE.md](UNNERF-GUIDE.md).

---

## Compatibility

- **Claude Code:** built from v2.1.196 (stopgap toward v2.1.197). Per-prompt `ccVersion:` frontmatter spans v2.0.14–v2.1.196. Upgrade playbook: [UNNERF-GUIDE.md](UNNERF-GUIDE.md).
- **Models:** tuned for current Claude (Opus 4.8 / Sonnet 4.6 / Haiku 4.5). Older or smaller models may over-explain trivial asks.
- **Watch for over-verbosity** — the main failure mode. If Claude writes essays for "what time is it?", start with `system-prompt-communication-style.md` and `system-prompt-tone-concise-output-short.md`. Thorough output also costs more tokens; plan accordingly.

---

## Credits & license

- **[tweakcc](https://github.com/Piebald-AI/tweakcc)** by Piebald AI — the tool that makes this possible.
- **[roman01la's gist](https://gist.github.com/roman01la/483d1db15043018096ac3babf5688881)** — the original thesis and first 11 patches, translated into tweakcc format ([BACKGROUND.md](BACKGROUND.md#the-original-gist)).
- **Anthropic** — for Claude Code, and for not going out of their way to stop community patching.

Prompt text in `system-prompts/*.md` is Anthropic's copyright, extracted by tweakcc and modified; redistributed as a modified subset on a fair-use / research basis. The docs and repo organization are **CC0 / public domain**.

These change Claude Code's behavior in ways that may not suit your workflow — test in a throwaway session first, and keep the tweakcc binary backup so you can roll back. Something misbehaving? Open an issue or PR.
