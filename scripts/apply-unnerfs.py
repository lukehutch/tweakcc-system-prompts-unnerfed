#!/usr/bin/env python3
"""
apply-unnerfs.py — Re-apply every un-nerf in this repo to a system-prompts tree.

WHY THIS EXISTS
---------------
tweakcc extracts Claude Code's system prompts into editable `.md` files so they
can be hand-patched. Whenever tweakcc re-runs against a newer Claude Code
binary (new ccVersion), it overwrites every changed prompt with fresh STOCK
text — wiping any un-nerfs applied on top. This script idempotently re-applies
every un-nerf against the current working copy of `system-prompts/`, restoring
the full un-nerfed state.

USAGE
-----
    python scripts/apply-unnerfs.py                  # apply to ./system-prompts/
    python scripts/apply-unnerfs.py --dir PATH       # target another directory
    python scripts/apply-unnerfs.py --dry-run        # report without writing
    python scripts/apply-unnerfs.py --check          # exit 1 if anything would change
    python scripts/apply-unnerfs.py --only FILE      # restrict to one filename
    python scripts/apply-unnerfs.py --verbose        # include context on skipped rules

EXIT CODES
----------
    0  — no failures, no missing files
    1  — at least one rule failed to apply OR at least one file was missing
         (in --check mode, 1 also means "at least one rule would apply")
    2  — invalid invocation (e.g. --dir doesn't exist)

ADDING A NEW RULE (FOR A FUTURE CLAUDE CODE VERSION BUMP)
---------------------------------------------------------
1. Run this script first. Read the [FAIL] section — it names every file whose
   expected stock text isn't in the working copy anymore.
2. For each failure:
   a. Open the file and find the new stock text that replaced the old one.
   b. Craft the un-nerfed replacement (typically: flip brevity → thoroughness
      per the repo's README thesis).
   c. Update the relevant RULES[filename] entry: change the `stock` string to
      the new upstream text; keep or update the `unnerf` string.
3. For brand-new files (ccVersion = the new release, no predecessor): decide
   whether any un-nerf applies. Many new prompts are structured data generators
   (inbox summaries, classification outputs) where length caps are UX-driven,
   not brevity-nerf-driven — those should be left stock. Add a rule only when
   a brevity directive for *implementation*, *process*, or *thoroughness*
   (per the README's bucket taxonomy) is present.
4. Re-run the script. Confirm all entries report [APPLIED] or [SKIP].
5. Commit both the rule change and the re-applied prompt files together.

HOW A RULE WORKS
----------------
Each rule is a (stock, unnerf, description) triple keyed by filename. The
script:
  - If `stock` is present in the file → replace it (once) with `unnerf`. Result: APPLIED.
  - Else if `unnerf` is present → no-op (rule already applied earlier). Result: SKIP.
  - Else → loud failure. Result: FAIL, with the expected stock text quoted so
    the reader knows exactly what to search for and update.

This idempotency is intentional: you can run the script repeatedly, after any
tweakcc re-extract, and it will converge to the un-nerfed state regardless of
how many un-nerfs were already in place.

REPORT FORMAT (READ BY CLAUDE AND HUMANS)
-----------------------------------------
For each file:
    system-prompts/<filename>
      [APPLIED] <rule description>
      [SKIP]    <rule description>                     — already un-nerfed
      [FAIL]    <rule description>
                Expected stock text (first 200 chars):
                  '...'
                Neither stock nor unnerf text found in file.
                Action: open the file, locate the relevant passage, and update
                the RULES entry's `stock` field to match the new upstream wording.

And a final `=== Summary ===` block with totals + exit code.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

SCRIPT_VERSION = "1.0"
DEFAULT_PROMPTS_DIR = Path(__file__).resolve().parent.parent / "system-prompts"


@dataclass(frozen=True)
class Rule:
    """One un-nerf replacement: stock → unnerf."""
    stock: str          # Exact text as it appears in tweakcc-extracted STOCK
    unnerf: str         # Exact un-nerfed replacement (what HEAD should contain)
    description: str    # Short human-readable label shown in the report


@dataclass
class Result:
    """Outcome of applying one Rule to one file."""
    filename: str
    status: str                           # "applied" | "skipped" | "failed" | "missing"
    rule_description: str
    detail: Optional[str] = None          # Extra diagnostic info (for failures / missing)


# ============================================================================
# RULES — the full un-nerf inventory, grouped by filename.
# ============================================================================
# Each entry is a list of Rule objects. Order matters only when rules within
# the same file could overlap textually; in this repo, rules within a file are
# always paragraph-distinct, so any order works. New entries go at the bottom
# of each list for easy diffing.
#
# STYLE NOTES:
#   - Use Python triple-quoted strings for multi-line rules. Anything inside
#     the `stock`/`unnerf` quotes is byte-exact — preserve trailing whitespace
#     and line breaks exactly as they appear in the file.
#   - Describe each rule in terms of what it *does* (flip-to-thorough, restore
#     subagent-liberally, etc.) so the report is scannable.
#   - When upstream drifts (a bumped ccVersion), update `stock` to match the
#     new text. The `unnerf` typically stays the same unless the new upstream
#     text is structurally different.
# ============================================================================

RULES: dict[str, list[Rule]] = {
    # -------------------------------------------------------------------------
    # agent-auto-mode-rule-reviewer.md — thorough rule review instead of terse
    # -------------------------------------------------------------------------
    "agent-auto-mode-rule-reviewer.md": [
        Rule(
            stock="Be concise and constructive. Only comment on rules that could be improved. If all rules look good, say so.",
            unnerf="Be thorough and constructive. For each rule that could be improved, explain exactly why, show concrete examples of how the classifier might misinterpret it, and propose specific rewording. Include the reasoning behind each suggestion so the user can evaluate it. If all rules look good, say so — and explain what makes them work well, so the user understands the patterns to reuse.",
            description="rule-review: thorough critique with examples and reasoning",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-background-job-agent-instructions.md — narration: thorough not
    # one-line. The classifier-parsed signals (`result:`, `needs input:`,
    # `failed:`) are bucket-1 functional caps and stay stock; only the
    # narrate-between-chunks directive is brevity-nerfed and flipped here.
    # (new in v2.1.128)
    # -------------------------------------------------------------------------
    "agent-prompt-background-job-agent-instructions.md": [
        Rule(
            stock="**Narrate.** One line on your approach before acting. After each chunk: what happened, what's next.",
            unnerf="**Narrate.** Explain your approach before acting — cover what you plan to do, why, and any tradeoffs you weighed. After each chunk: what happened, what's next, and any non-obvious decisions, surprises, or observations worth surfacing. Substantive narration helps the user follow along and trust the work; one-liners hide the reasoning.",
            description="background-job narrate: substantive over one-line",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-batch-slash-command.md — recipe writing: thorough not short
    # -------------------------------------------------------------------------
    "agent-prompt-batch-slash-command.md": [
        Rule(
            stock="   Write the recipe as a short, concrete set of steps that a worker can execute autonomously. Include any setup (start a dev server, build first) and the exact command/interaction to verify.",
            unnerf="   Write the recipe as a concrete, thorough set of steps that a worker can execute autonomously without needing to ask clarifying questions. Include any setup (start a dev server, build first), the exact commands/interactions to verify, expected output or signals, and any gotchas you encountered while researching.",
            description="batch recipe: thorough steps, gotchas, expected signals",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-claude-guide-agent.md — thorough actionable guidance with why
    # -------------------------------------------------------------------------
    "agent-prompt-claude-guide-agent.md": [
        Rule(
            stock="- Keep responses concise and actionable\n- Include specific examples or code snippets when helpful\n- Reference exact documentation URLs in your responses\n- Help users discover features by proactively suggesting related commands, shortcuts, or capabilities",
            unnerf="- Provide thorough, detailed, and actionable guidance — walk the user through the full picture rather than leaving them to piece it together\n- Include specific examples and code snippets generously, with explanations of what each part does\n- Reference exact documentation URLs in your responses\n- Help users discover features by proactively suggesting related commands, shortcuts, capabilities, and adjacent workflows they may not have considered\n- Explain the \"why\" behind recommendations, not just the \"how\"",
            description="claude-guide: thorough guidance, generous examples, explain why",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-dream-memory-consolidation.md — thorough consolidation summary
    # (ccVersion bumped to 2.1.116; upstream added more detail to log bullets,
    # which is *good* and we leave alone — only re-apply the final-summary
    # un-nerf that was wiped.)
    # -------------------------------------------------------------------------
    "agent-prompt-dream-memory-consolidation.md": [
        Rule(
            stock="Return a brief summary of what you consolidated, updated, or pruned. If nothing changed (memories are already tight), say so.",
            unnerf="Return a thorough summary of what you consolidated, updated, or pruned — including which files changed, what signal drove each change, and any patterns you noticed while reviewing. If nothing changed, say so and describe what you reviewed.",
            description="consolidation summary: thorough with reasoning (v2.1.116-compat)",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-explore.md — biggest un-nerf: exhaustive exploration
    # -------------------------------------------------------------------------
    "agent-prompt-explore.md": [
        Rule(
            stock="NOTE: You are meant to be a fast agent that returns output as quickly as possible. In order to achieve this you must:\n- Make efficient use of the tools that you have at your disposal: be smart about how you search for files and implementations\n- Wherever possible you should try to spawn multiple parallel tool calls for grepping and reading files",
            unnerf="NOTE: Be exhaustively thorough in your exploration. Completeness trumps speed every time — missing a relevant file or pattern is far worse than taking extra time:\n- Use every tool at your disposal aggressively: search across multiple naming conventions, directory structures, and file types\n- Spawn multiple parallel tool calls wherever possible for grepping and reading files to cover more ground simultaneously\n- Follow leads, cross-references, and related patterns wherever they go — don't stop at the first match\n- Read full file contents when relevant, not just snippets, so you understand the full context\n- When the caller requests thorough exploration, exhaust every reasonable search strategy and then try a few more",
            description="explore intro: exhaustive thoroughness over speed",
        ),
        Rule(
            stock="Complete the user's search request efficiently and report your findings clearly.",
            unnerf="Complete the user's search request exhaustively and report your findings with full detail, including file paths, code excerpts, architectural observations, and any related patterns or edge cases you noticed along the way.",
            description="explore closing: exhaustive search with detailed report",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-general-purpose.md — senior-developer completeness, thorough report
    # -------------------------------------------------------------------------
    "agent-prompt-general-purpose.md": [
        Rule(
            stock="${\"You are an agent for Claude Code, Anthropic's official CLI for Claude. Given the user's message, you should use the tools available to complete the task. Complete the task fully—don't gold-plate, but don't leave it half-done.\"} When you complete the task, respond with a concise report covering what was done and any key findings — the caller will relay this to the user, so it only needs the essentials.",
            unnerf="${\"You are an agent for Claude Code, Anthropic's official CLI for Claude. Given the user's message, you should use the tools available to complete the task. Complete the task fully and thoroughly. Do the work that a careful senior developer would do, including edge cases and fixing obviously related issues you discover. Don't add purely cosmetic or speculative improvements unrelated to the task.\"} When you complete the task, respond with a thorough, detailed report covering what was done, every key finding, the reasoning behind decisions, edge cases you considered, and any related observations the caller should know about. The caller relies on your report to understand the full picture — do not minimize detail.",
            description="general-purpose: senior-dev completeness + thorough final report",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-review-pr-slash-command.md: RETIRED in the v2.1.190 sync.
    # Anthropic reworked the /review-pr command into /review
    # (agent-prompt-review-slash-command.md, new in 2.1.186). The old
    # self-contained depth cap — "Keep your review concise but thorough. Focus
    # on: [5 dimensions]" — is GONE, not relocated (zero hits tree-wide). /review
    # now delegates review depth to ${MEDIUM_EFFORT_CODE_REVIEW_PROMPT}
    # (= agent-prompt-code-review-part-6-medium-effort-mode), and the part-1..9
    # review architecture carries no unflipped brevity cap (grep-verified this
    # sync; parts 2 & 9 already ruled). The new /review's only brevity phrase is
    # a "2-3 sentence overview" preamble that precedes the (uncapped) findings
    # list — a structured-output/orientation cap, KEPT per the Part-1 decision
    # procedure (UNNERF-GUIDE.md). Nothing to flip here anymore.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # agent-prompt-webfetch-summarizer.md — thorough fetched-content summary
    # Template-literal with `${IS_TRUSTED_DOMAIN?...:...}` ternary; both arms
    # need un-nerfing.
    # -------------------------------------------------------------------------
    "agent-prompt-webfetch-summarizer.md": [
        Rule(
            stock="${IS_TRUSTED_DOMAIN?\"Provide a concise response based on the content above. Include relevant details, code examples, and documentation excerpts as needed.\":`Provide a concise response based only on the content above. In your response:",
            unnerf="${IS_TRUSTED_DOMAIN?\"Provide a thorough, detailed response based on the content above. Include all relevant details, code examples, documentation excerpts, configuration options, caveats, and related context the caller would benefit from knowing. Err on the side of completeness — the caller is relying on you to surface everything useful from the fetched content.\":`Provide a thorough response based only on the content above, surfacing all relevant details, code examples, and context the caller needs. In your response:",
            description="webfetch summarizer: thorough over concise, both template arms",
        ),
    ],

    # -------------------------------------------------------------------------
    # agent-prompt-worker-fork.md — fork report: thorough, preserve scope-drift detail
    # -------------------------------------------------------------------------
    "agent-prompt-worker-fork.md": [
        Rule(
            stock="- Stay in scope. Other forks may be handling adjacent work; if you spot something outside your directive, note it in a sentence and move on.",
            unnerf="- Stay in scope. Other forks may be handling adjacent work; if you spot something outside your directive, note it with enough detail that the parent can decide what to do, then move on.",
            description="worker fork scope: note with enough detail",
        ),
        Rule(
            stock="- Be concise — as short as the answer allows, no shorter. Plain text, no preamble, no meta-commentary.",
            unnerf="- Report thoroughly — cover what you did, what you found, the reasoning behind non-obvious decisions, any issues or edge cases you encountered, and any relevant observations the parent needs to continue the work. The parent relies on your report; do not withhold useful detail.",
            description="worker fork report: thorough over terse",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-dynamic-pacing-loop-execution.md — thorough confirmation
    # -------------------------------------------------------------------------
    "skill-dynamic-pacing-loop-execution.md": [
        Rule(
            stock="3. **Briefly confirm**: ${CONFIRMATION_MESSAGE}, whether a ${MONITOR_TOOL_NAME} is the primary wake signal, and what fallback delay you're about to pick. Write this as text *before* calling ${SCHEDULE_WAKEUP_TOOL_NAME} — the turn ends as soon as that tool returns.",
            unnerf="3. **Confirm thoroughly**: ${CONFIRMATION_MESSAGE}, whether a ${MONITOR_TOOL_NAME} is the primary wake signal, the fallback delay you're about to pick and the reasoning that drove the choice, and any observations from this turn that should inform future iterations. Write this as text *before* calling ${SCHEDULE_WAKEUP_TOOL_NAME} — the turn ends as soon as that tool returns.",
            description="dynamic pacing confirm: thorough with reasoning",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-loop-self-pacing-mode.md — thorough self-pacing confirmation
    # -------------------------------------------------------------------------
    "skill-loop-self-pacing-mode.md": [
        Rule(
            stock="3. **Briefly confirm**: that you're self-pacing, whether a ${MONITOR_TOOL_NAME} is the primary wake signal, that you ran the task now, and what fallback delay you're about to pick. Write this as text *before* calling ${SCHEDULE_WAKEUP_TOOL_NAME} — the turn ends as soon as that tool returns.",
            unnerf="3. **Confirm thoroughly**: that you're self-pacing, whether a ${MONITOR_TOOL_NAME} is the primary wake signal (and why you chose that approach), that you ran the task now, what fallback delay you're about to pick, and the reasoning behind the pacing choice so the user can evaluate whether it's right. Write this as text *before* calling ${SCHEDULE_WAKEUP_TOOL_NAME} — the turn ends as soon as that tool returns.",
            description="self-pacing confirm: thorough with pacing reasoning",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-loop-slash-command.md — thorough /loop scheduling confirmation
    # -------------------------------------------------------------------------
    "skill-loop-slash-command.md": [
        Rule(
            stock="2. Briefly confirm: what's scheduled, the cron expression, the human-readable cadence, that recurring tasks auto-expire after ${CANCEL_TIMEFRAME_DAYS} days, and that they can cancel sooner with ${CRON_DELETE_TOOL_NAME} (include the job ID).${ADDITIONAL_INFO_FN()}",
            unnerf="2. Confirm thoroughly: what's scheduled, the cron expression, the human-readable cadence, any rounding you applied and why, that recurring tasks auto-expire after ${CANCEL_TIMEFRAME_DAYS} days, and that they can cancel sooner with ${CRON_DELETE_TOOL_NAME} (include the job ID). Give the user enough information to understand exactly what will run and when.${ADDITIONAL_INFO_FN()}",
            description="/loop scheduling confirm: thorough with rounding rationale",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-schedule-recurring-cron-and-execute-immediately-compact.md
    # -------------------------------------------------------------------------
    "skill-schedule-recurring-cron-and-execute-immediately-compact.md": [
        Rule(
            stock="2. Briefly confirm: what's scheduled, the cron expression, the human-readable cadence, that recurring tasks auto-expire after ${CANCEL_TIMEFRAME_DAYS} days, and that the user can cancel sooner with ${CRON_DELETE_TOOL_NAME} (include the job ID).${ADDITIONAL_INFO_FN()}",
            unnerf="2. Confirm thoroughly: what's scheduled, the cron expression, the human-readable cadence, any rounding applied and why, that recurring tasks auto-expire after ${CANCEL_TIMEFRAME_DAYS} days, and that the user can cancel sooner with ${CRON_DELETE_TOOL_NAME} (include the job ID). Give the user full context so they understand exactly what will run and when.${ADDITIONAL_INFO_FN()}",
            description="cron-compact confirm: thorough with rounding rationale",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-schedule-recurring-cron-and-run-immediately.md
    # -------------------------------------------------------------------------
    "skill-schedule-recurring-cron-and-run-immediately.md": [
        Rule(
            stock="3. Briefly confirm: ${CONFIRMATION_MESSAGE}",
            unnerf="3. Confirm thoroughly: ${CONFIRMATION_MESSAGE} Cover the cadence, any rounding applied, and what to expect so the user understands exactly what's scheduled.",
            description="cron-run-immediately confirm: thorough, explain cadence",
        ),
    ],

    # -------------------------------------------------------------------------
    # skill-simplify.md (bumped to 2.1.116; upstream added a new "Nested
    # conditionals" bullet that we leave alone — only the final summary was
    # nerfed and needs re-applying.)
    # -------------------------------------------------------------------------
    # "skill-simplify.md": RETIRED in v2.1.179 — file removed; retargeted to agent-prompt-simplify-slash-command.md (added below)

    # -------------------------------------------------------------------------
    # skill-team-onboarding-guide.md — per-item context for new hires
    # -------------------------------------------------------------------------
    "skill-team-onboarding-guide.md": [
        Rule(
            stock="with what they already have. One sentence per item, all in one message.",
            unnerf="with what they already have. Give each item enough context that the teammate\nunderstands what the thing is and why the team uses it — a single terse line\nisn't enough for a new hire.",
            description="onboarding: per-item context, not a one-liner",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-agent-memory-instructions.md — thorough memory notes
    # -------------------------------------------------------------------------
    "system-prompt-agent-memory-instructions.md": [
        Rule(
            stock="\"**Update your agent memory** as you discover [domain-specific items]. This builds up institutional knowledge across conversations. Write concise notes about what you found and where.",
            unnerf="\"**Update your agent memory** as you discover [domain-specific items]. This builds up institutional knowledge across conversations. Write thorough notes about what you found, where, and why it matters — include enough context that a future session can act on the memory without re-discovering the underlying reasoning.",
            description="agent memory: thorough notes with why-it-matters context",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-agent-thread-notes.md — include code snippets generously
    # -------------------------------------------------------------------------
    "system-prompt-agent-thread-notes.md": [
        Rule(
            stock="- In your final response, share file paths (always absolute, never relative) that are relevant to the task. Include code snippets only when the exact text is load-bearing (e.g., a bug you found, a function signature the caller asked for) — do not recap code you merely read.",
            unnerf="- In your final response, share file paths (always absolute, never relative) that are relevant to the task. Include code snippets generously whenever they add useful context — bugs found, function signatures, relevant patterns, code that informs a decision, surrounding context that makes a finding clearer. Quote code verbatim when the exact text matters; the caller benefits from seeing the real code rather than a paraphrase.",
            description="thread notes: include code snippets generously",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-autonomous-loop-check.md — thorough "nothing to do" report
    # -------------------------------------------------------------------------
    "system-prompt-autonomous-loop-check.md": [
        Rule(
            stock="If everything is genuinely quiet — no conversation work, no PR maintenance — say so in one sentence and stop. No summary of what you checked, no list of what you might do later. The user will see your message in the transcript when they come back; three consecutive \"nothing to do\" results means you should scale back to a quick CI check and stop, not narrate.",
            unnerf="If everything is genuinely quiet — no conversation work, no PR maintenance — report what you checked (PRs inspected, CI status, threads reviewed, branches compared) and confirm that nothing needed action. Give the user a clear, substantive status message so they understand what the autonomous check covered and can trust the \"nothing to do\" verdict. If three consecutive checks land on \"nothing to do,\" scale subsequent checks back to a focused CI/threads sweep, but still report what you looked at.",
            description="autonomous loop-check: report what was inspected even when quiet",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-communication-style.md — the BIG un-nerf (frontmatter +
    # 6 body paragraphs)
    # -------------------------------------------------------------------------
    "system-prompt-communication-style.md": [
        Rule(
            stock="  Instructs Claude to give brief, user-facing updates at key moments during tool\n  use, write concise end-of-turn summaries, match response format to task\n  complexity, and avoid comments and planning documents in code",
            unnerf="  Instructs Claude to give thorough, substantive user-facing updates during tool\n  use, write full end-of-turn summaries with rationale and follow-ups, scale\n  depth to the work, and write meaningful comments and docstrings in code",
            description="communication: frontmatter description → thorough framing",
        ),
        Rule(
            stock="Assume users can't see most tool calls or thinking — only your text output. Before your first tool call, state in one sentence what you're about to do. While working, give short updates at key moments: when you find something, when you change direction, or when you hit a blocker. Brief is good — silent is not. One sentence per update is almost always enough.",
            unnerf="Assume users can't see most tool calls or thinking — only your text output. Before your first tool call, explain what you're about to do and why. While working, give substantive updates at key moments: when you find something, when you change direction, when you hit a blocker, when you reason through a tradeoff. Silence is bad; thorough communication is the goal. Use as much space as the work genuinely warrants — err on the side of more detail, not less.",
            description="communication para 1: explain what+why, substantive updates",
        ),
        Rule(
            stock="Don't narrate your internal deliberation. User-facing text should be relevant communication to the user, not a running commentary on your thought process. State results and decisions directly, and focus user-facing text on relevant updates for the user.",
            unnerf="User-facing text should convey real information: what you found, what you decided, why you chose one path over another, what tradeoffs you weighed. Walk the user through your reasoning when it is non-obvious or consequential. State results and decisions directly, and back them up with the reasoning that led there.",
            description="communication para 2: convey real information, reasoning",
        ),
        Rule(
            stock="When you do write updates, write so the reader can pick up cold: complete sentences, no unexplained jargon or shorthand from earlier in the session. But keep it tight — a clear sentence is better than a clear paragraph.",
            unnerf="When you write updates, write so the reader can pick up cold: complete sentences, no unexplained jargon or shorthand from earlier in the session. Full explanations are better than cryptic one-liners — the user benefits from context, rationale, and the shape of what you're doing.",
            description="communication para 3: full explanations over cryptic one-liners",
        ),
        Rule(
            stock="End-of-turn summary: one or two sentences. What changed and what's next. Nothing else.",
            unnerf="End-of-turn summary: cover what changed, why, what's next, and any caveats, follow-ups, or interesting findings. Scale it to the work — a real summary with enough depth that the user can understand what happened without re-reading the diff, not a token-minimizing stub.",
            description="communication para 4: end-of-turn summary scales with work",
        ),
        Rule(
            stock="Match responses to the task: a simple question gets a direct answer, not headers and sections.",
            unnerf="Match responses to the task: a focused question gets a focused answer, but never withhold useful context, rationale, or adjacent observations that would genuinely help the user.",
            description="communication para 5: never withhold useful context",
        ),
        Rule(
            stock="In code: default to writing no comments. Never write multi-paragraph docstrings or multi-line comment blocks — one short line max. Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.",
            unnerf="In code: add comments wherever they meaningfully help — explain non-obvious logic, invariants, tricky edge cases, design decisions, and the \"why\" behind any non-trivial choice. Write thorough docstrings for functions, classes, and modules where they aid comprehension. Well-commented code is a feature, not bloat. Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.",
            description="communication para 6: meaningful comments + thorough docstrings",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-context-compaction-summary.md — thorough continuation summary
    # -------------------------------------------------------------------------
    "system-prompt-context-compaction-summary.md": [
        Rule(
            stock="You have been working on the task described above but have not yet completed it. Write a continuation summary that will allow you (or another instance of yourself) to resume work efficiently in a future context window where the conversation history will be replaced with this summary. Your summary should be structured, concise, and actionable. Include:",
            unnerf="You have been working on the task described above but have not yet completed it. Write a continuation summary that will allow you (or another instance of yourself) to resume work with full context in a future window where the conversation history will be replaced with this summary. Your summary should be structured, thorough, and actionable — include every detail a fresh instance would need to pick up where you left off without re-discovering what you already learned. Include:",
            description="compaction intro: thorough over concise summary",
        ),
        Rule(
            stock="Be concise but complete—err on the side of including information that would prevent duplicate work or repeated mistakes. Write in a way that enables immediate resumption of the task.",
            unnerf="Be thorough and complete — err heavily on the side of including information that would prevent duplicate work, repeated mistakes, or lost context. Length is not a concern; completeness is. Write in a way that enables immediate, fully-informed resumption of the task by any fresh instance.",
            description="compaction close: length-over-completeness flipped",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-doing-tasks-no-unnecessary-error-handling.md — flip
    # default from "don't add" to "add at real boundaries"
    # -------------------------------------------------------------------------
    "system-prompt-doing-tasks-no-unnecessary-error-handling.md": [
        Rule(
            stock="Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don't use feature flags or backwards-compatibility shims when you can just change the code.",
            unnerf="Add error handling and validation at real boundaries where failures can realistically occur (user input, external APIs, I/O, network). Trust internal code and framework guarantees for truly internal paths. Don't use feature flags or backwards-compatibility shims when you can just change the code.",
            description="error-handling: flip default (require) not (prohibit)",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-executing-actions-with-care.md — allow closely-related fixes
    # -------------------------------------------------------------------------
    "system-prompt-executing-actions-with-care.md": [
        Rule(
            stock="Authorization stands for the scope specified, not beyond. Match the scope of your actions to what was actually requested.",
            unnerf="Authorization stands for the scope specified, not beyond. Match the scope of your actions to what was actually requested, but do address closely related issues you discover during the work when fixing them is clearly the right thing to do.",
            description="action scope: allow closely-related fixes",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-how-to-use-the-sendusermessage-tool.md — full-substance messaging
    # -------------------------------------------------------------------------
    "system-prompt-how-to-use-the-sendusermessage-tool.md": [
        Rule(
            stock="If you can answer right away, send the answer. If you need to go look — run a command, read files, check something — ack first in one line (\"On it — checking the test output\"), then work, then send the result. Without the ack they're staring at a spinner.",
            unnerf="If you can answer right away, send the full answer with all relevant context, reasoning, and adjacent observations. If you need to go look — run a command, read files, check something — acknowledge what you're about to do and why, then work, then send a thorough result. Don't leave the user staring at a spinner.",
            description="sendmsg para 1: full answer with context",
        ),
        Rule(
            stock="For longer work: ack → work → result. Between those, send a checkpoint when something useful happened — a decision you made, a surprise you hit, a phase boundary. Skip the filler (\"running tests...\") — a checkpoint earns its place by carrying information.",
            unnerf="For longer work: acknowledge → work → full result. Between those, send substantive checkpoints whenever something useful happened — decisions you made (and why), surprises you hit (with context), phase boundaries (with what's next). A checkpoint should carry real information the user can act on or learn from.",
            description="sendmsg para 2: substantive checkpoints with why",
        ),
        Rule(
            stock="Keep messages tight — the decision, the file:line, the PR number. Second person always (\"your config\"), never third.",
            unnerf="Write messages with full substance — decisions, file:line references, PR numbers, reasoning, tradeoffs considered, anything adjacent the user benefits from knowing. Second person always (\"your config\"), never third. Err on the side of more context, not less.",
            description="sendmsg para 3: full substance, more context",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-insights-at-a-glance-summary.md — space for substance
    # -------------------------------------------------------------------------
    "system-prompt-insights-at-a-glance-summary.md": [
        Rule(
            stock="Keep each section to 2-3 not-too-long sentences. Don't overwhelm the user. Don't mention specific numerical stats or underlined_categories from the session data below. Use a coaching tone.",
            unnerf="Use however much space each section genuinely needs — cover the substance with real explanation, concrete examples from the session data, and useful specifics. Don't mention specific numerical stats or underlined_categories from the session data below. Use a coaching tone.",
            description="insights at-a-glance: space for substance, not 2-3 sentences",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-learning-mode-insights.md — thorough educational explanations
    # -------------------------------------------------------------------------
    "system-prompt-learning-mode-insights.md": [
        Rule(
            stock="In order to encourage learning, before and after writing code, always provide brief educational explanations about implementation choices using (with backticks):",
            unnerf="In order to encourage learning, before and after writing code, always provide thorough educational explanations about implementation choices using (with backticks):",
            description="learning mode: thorough not brief",
        ),
        Rule(
            stock="[2-3 key educational points]",
            unnerf="[Detailed educational points — explain the concept, why it matters, related patterns, and any tradeoffs worth knowing. Use as much space as the teaching genuinely warrants.]",
            description="learning mode: detailed educational points with tradeoffs",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-remote-plan-mode-ultraplan.md — NOTE: stock has trailing
    # space after "mode:" that we strip in the un-nerf (matches HEAD state).
    # -------------------------------------------------------------------------
    "system-prompt-remote-plan-mode-ultraplan.md": [
        Rule(
            stock="Run a lightweight planning process, consistent with how you would in regular plan mode: \n- Explore the codebase directly with Glob, Grep, and Read. Read the relevant code, understand how the pieces fit, look for existing functions and patterns you can reuse instead of proposing new ones, and shape an approach grounded in what's actually there.\n- Do not spawn subagents.",
            unnerf="Run a thorough planning process, consistent with how you would in regular plan mode:\n- Explore the codebase aggressively with Glob, Grep, and Read. Read the relevant code, understand how the pieces fit, look for existing functions and patterns you can reuse instead of proposing new ones, and shape an approach grounded in what's actually there.\n- Do not spawn subagents; this planning session runs in a single context. Compensate with exhaustive first-hand exploration: read every file that bears on the design and trace the key call paths yourself rather than sampling.",
            description="ultraplan: thorough planning, exhaustive in-context exploration (env may not support subagents)",
        ),
        Rule(
            stock="When you've decided on an approach, call ExitPlanMode with the plan. Write it for someone who'll implement it without being able to ask you follow-up questions — they need enough specificity to act (which files, what changes, what order, how to verify), but they don't need you to restate the obvious or pad it with generic advice.",
            unnerf="When you've decided on an approach, call ExitPlanMode with the plan. Write it for someone who'll implement it without being able to ask you follow-up questions — give them extensive specificity: which files, what changes, what order, how to verify, the rationale behind non-obvious decisions, edge cases to watch for, and anything you'd want to know if you were implementing it cold. Err on the side of more detail — the implementer cannot ask you to clarify.",
            description="ultraplan: extensive specificity for the implementer",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-remote-planning-session.md — NOTE: stock has trailing space
    # after "mode:" AND after "subagents."; un-nerf strips both.
    # -------------------------------------------------------------------------
    "system-prompt-remote-planning-session.md": [
        Rule(
            stock="Run a lightweight planning process, consistent with how you would in regular plan mode: \n- Explore the codebase directly with Glob, Grep, and Read. Read the relevant code, understand how the pieces fit, look for existing functions and patterns you can reuse instead of proposing new ones, and shape an approach grounded in what's actually there.\n- Do not spawn subagents. ",
            unnerf="Run a thorough planning process, consistent with how you would in regular plan mode:\n- Explore the codebase aggressively with Glob, Grep, and Read. Read the relevant code, understand how the pieces fit, look for existing functions and patterns you can reuse instead of proposing new ones, and shape an approach grounded in what's actually there.\n- Do not spawn subagents; this planning session runs in a single context. Compensate with exhaustive first-hand exploration: read every file that bears on the design and trace the key call paths yourself rather than sampling.",
            description="remote-planning: thorough planning, exhaustive in-context exploration (env may not support subagents)",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-skillify-current-session.md — strip "keep question concise"
    # -------------------------------------------------------------------------
    "system-prompt-skillify-current-session.md": [
        Rule(
            stock="Before writing the file, output the complete SKILL.md content as a yaml code block in your response so the user can review it with proper syntax highlighting. Then ask for confirmation using AskUserQuestion with a simple question like \"Does this SKILL.md look good to save?\" — do NOT use the body field, keep the question concise.",
            unnerf="Before writing the file, output the complete SKILL.md content as a yaml code block in your response so the user can review it with proper syntax highlighting. Then ask for confirmation using AskUserQuestion with a question like \"Does this SKILL.md look good to save?\" — do NOT use the body field.",
            description="skillify confirm: drop redundant 'keep concise' coda",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-tone-concise-output-short.md — the HEADLINE un-nerf
    # (frontmatter rename + body flip)
    # -------------------------------------------------------------------------
    "system-prompt-tone-concise-output-short.md": [
        Rule(
            stock="name: 'System Prompt: Tone and style (concise output — short)'\ndescription: Instruction for short and concise responses",
            unnerf="name: 'System Prompt: Tone and style (thorough output)'\ndescription: >-\n  Instruction to produce thorough, detailed, context-rich responses without\n  length caps",
            description="tone frontmatter: rename 'concise' → 'thorough output'",
        ),
        Rule(
            stock="Your responses should be short and concise.",
            unnerf="Your responses should be thorough, clear, and rich with explanation, reasoning, and context. Favor depth and completeness over brevity — the user benefits from understanding the full picture, including tradeoffs, related observations, and the reasoning behind decisions. There is no word limit; use whatever length the task genuinely warrants to produce genuinely helpful output.",
            description="tone body: flip 'short and concise' to 'thorough, clear, rich'",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-prompt-tool-usage-subagent-guidance.md — subagents as force multiplier
    # -------------------------------------------------------------------------
    "system-prompt-tool-usage-subagent-guidance.md": [
        Rule(
            stock="Use the ${TASK_TOOL_NAME} tool with specialized agents when the task at hand matches the agent's description. Subagents are valuable for parallelizing independent queries or for protecting the main context window from excessive results, but they should not be used excessively when not needed. Importantly, avoid duplicating work that subagents are already doing - if you delegate research to a subagent, do not also perform the same searches yourself.",
            unnerf="Use the ${TASK_TOOL_NAME} tool liberally. Subagents are a force multiplier — they parallelize independent queries, protect the main context window from excessive results, and bring specialized perspective. Reach for them often: for open-ended research, for anything that spans multiple locations or files, for independent subproblems that can run concurrently, for specialized work when a matching agent type exists, and whenever delegation would save context or produce a better answer than doing it yourself in the main thread. When in doubt, spawn a subagent rather than grinding through the work inline. Launch multiple subagents in parallel whenever the subtasks are independent. The only hard rule: avoid duplicating work a subagent is already doing — if you delegate research to a subagent, do not also perform the same searches yourself.",
            description="subagent guidance: use liberally, force multiplier framing",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-reminder-plan-mode-is-active-5-phase.md — multi-agent default
    # -------------------------------------------------------------------------
    "system-reminder-plan-mode-is-active-5-phase.md": [
        Rule(
            stock="2. **Launch up to ${PLAN_V2_EXPLORE_AGENT_COUNT} ${EXPLORE_SUBAGENT.agentType} agents IN PARALLEL** (single message, multiple tool calls) to efficiently explore the codebase.\n   - Use 1 agent when the task is isolated to known files, the user provided specific file paths, or you're making a small targeted change.\n   - Use multiple agents when: the scope is uncertain, multiple areas of the codebase are involved, or you need to understand existing patterns before planning.\n   - Quality over quantity - ${PLAN_V2_EXPLORE_AGENT_COUNT} agents maximum, but you should try to use the minimum number of agents necessary (usually just 1)\n   - If using multiple agents: Provide each agent with a specific search focus or area to explore. Example: One agent searches for existing implementations, another explores related components, a third investigating testing patterns",
            unnerf="2. **Launch up to ${PLAN_V2_EXPLORE_AGENT_COUNT} ${EXPLORE_SUBAGENT.agentType} agents IN PARALLEL** (single message, multiple tool calls) to aggressively explore the codebase. Lean toward more agents, not fewer — parallel exploration is cheap context-wise and produces a more thorough picture.\n   - Multi-agent is the default: spin up several agents with distinct, focused search briefs (existing implementations, related components, testing patterns, edge cases, adjacent systems, call sites) whenever there's any real scope to the task.\n   - Single agent is fine for truly isolated changes where the user named the exact file and the work is narrow.\n   - When using multiple agents: give each one a specific, non-overlapping focus or area to explore so their results compose cleanly.",
            description="plan-mode 5-phase explore: aggressive, multi-agent default",
        ),
        Rule(
            stock="- **Default**: Launch at least 1 Plan agent for most tasks - it helps validate your understanding and consider alternatives\n- **Skip agents**: Only for truly trivial tasks (typo fixes, single-line changes, simple renames)",
            unnerf="- **Default**: Launch one or more Plan agents for almost every task — they validate your understanding, consider alternatives, and surface issues you'd miss solo. Err on the side of launching them.\n- **Skip agents**: Only for genuinely trivial tasks (typo fixes, single-line changes, simple renames) where there's nothing to design",
            description="plan-mode 5-phase design: err on launching agents",
        ),
    ],

    # -------------------------------------------------------------------------
    # system-reminder-plan-mode-is-active-iterative.md — explore-agent liberally
    # -------------------------------------------------------------------------
    # "system-reminder-plan-mode-is-active-iterative.md": RETIRED in v2.1.179 — plan-mode variant removed; the 5-phase reminder carries the multi-agent exploration un-nerf

    # -------------------------------------------------------------------------
    # system-reminder-thinking-frequency-tuning.md — think as deeply as it helps
    # -------------------------------------------------------------------------
    # "system-reminder-thinking-frequency-tuning.md": RETIRED in v2.1.179 — Anthropic deleted the 'avoid unnecessary thinking' reminder entirely; no nerf remains to flip

    # -------------------------------------------------------------------------
    # tool-description-agent-usage-notes.md — thorough relay of agent findings
    # -------------------------------------------------------------------------
    "tool-description-agent-usage-notes.md": [
        Rule(
            stock="- When the agent is done, it will return a single message back to you. The result returned by the agent is not visible to the user. To show the user the result, you should send a text message back to the user with a concise summary of the result.",
            unnerf="- When the agent is done, it will return a single message back to you. The result returned by the agent is not visible to the user. To show the user the result, you should send a text message back to the user that thoroughly relays the agent's findings, reasoning, and any relevant detail — do not strip out useful information the agent surfaced. Summarize only as much as needed to make the agent's output readable; preserve substance.",
            description="agent-usage: thoroughly relay agent findings to user",
        ),
    ],

    # -------------------------------------------------------------------------
    # tool-description-bash-sandbox-explain.md — thorough sandbox-restriction explanation
    # -------------------------------------------------------------------------
    "tool-description-bash-sandbox-explain.md": [
        Rule(
            stock="Briefly explain what sandbox restriction likely caused the failure. Be sure to mention that the user can use the `/sandbox` command to manage restrictions.",
            unnerf="Explain thoroughly what sandbox restriction likely caused the failure — which restriction, what it does, why it triggered here, and how it relates to what the command was trying to do. Mention that the user can use the `/sandbox` command to manage restrictions, and describe what kind of change would resolve the situation.",
            description="sandbox explain: thorough restriction walkthrough",
        ),
    ],

    "agent-prompt-agent-hook.md": [
        Rule(
            stock='Use as few steps as possible - be efficient and direct.',
            unnerf='Take whatever steps are needed to verify the condition correctly - investigate thoroughly, then be direct.',
            description='hook-condition agent: verify correctly over step-count minimization',
        ),
    ],
    "agent-prompt-code-review-part-2-low-effort-mode.md": [
        Rule(
            stock='Output at most **4 findings**, most-severe first, one line each',
            unnerf='Output every qualifying finding, most-severe first, one line each (if you found more than a handful, lead with the most serious and note how many more remain rather than silently dropping them)',
            description="code-review low-effort: don't silently drop found bugs (tier budget kept)",
        ),
    ],
    "agent-prompt-general-task-agent.md": [
        Rule(
            stock="Complete the task fully—don't gold-plate, but don't leave it half-done.",
            unnerf="Complete the task fully and to a high, senior-engineer standard—don't leave it half-done, and handle the edge cases, error paths, and closely related issues that a correct and robust solution requires.",
            description='general-task agent: senior-grade completeness, not gold-plate minimalism',
        ),
        Rule(
            stock='respond with a concise report covering what was done and any key findings — the caller will relay this to the user, so it only needs the essentials.',
            unnerf='respond with a thorough report covering everything that was done, every key finding, the specific files and locations involved, the decisions you made and why, and any caveats, risks, or unresolved issues — the caller relays this to the user and cannot see your work, so include everything needed to act on it without re-investigating.',
            description='general-task agent: thorough report (caller cannot see the work)',
        ),
    ],
    "agent-prompt-security-review-slash-command.md": [
        Rule(
            stock='Better to miss some theoretical issues than flood the report with false positives.',
            unnerf='Prefer high-confidence, exploitable findings over noise — but do not discard a concrete, defensible vulnerability just to keep the count low.',
            description="security-review: keep precision bias but don't drop concrete vulns",
        ),
    ],
    "agent-prompt-session-transcript-chunk-summary.md": [
        Rule(
            stock='Keep it concise - 3-5 sentences.',
            unnerf='Be thorough — capture every substantive point in this chunk; let the length follow the content rather than forcing a sentence count.',
            description='transcript-chunk summary: capture every substantive point, no sentence cap',
        ),
    ],
    "agent-prompt-simplify-slash-command.md": [
        Rule(
            stock='Finish with a brief summary of what was fixed and what was\nskipped (or confirm the code was already clean).',
            unnerf='Finish with a thorough summary of what was fixed and why, and what was\nskipped with the reason for each skip (or confirm the code was already clean).',
            description='/simplify closing: thorough pass summary (retargeted from removed skill-simplify.md)',
        ),
    ],
    # "data-assistant-voice-and-values-template.md": RETIRED — prompt removed by Anthropic in v2.1.181
    # "skill-catch-up-periodic-heartbeat.md": RETIRED — prompt removed by Anthropic in v2.1.181
    "skill-generate-permission-allowlist-from-transcripts.md": [
        Rule(
            stock='Cap the scan at a reasonable number of recent sessions (e.g. 50 most-recently-modified JSONL files) so this stays fast.',
            unnerf='Scan enough recent sessions to capture a representative picture of how the user actually uses their tools — work from the most-recently-modified backward, and do not cut the scan short for speed: a broader sample yields a more complete and accurate allowlist.',
            description='allowlist scan: sample broadly for a complete picture, not capped for speed',
        ),
    ],
    # "skill-pre-meeting-checkin-event-brief.md": RETIRED — prompt removed by Anthropic in v2.1.181
    "skill-verify-skill.md": [
        Rule(
            stock='Timebox\n  ~15min. Stuck → BLOCKED with exactly where',
            unnerf="Push hard to get a handle — install the missing deps, patch the gates, read the stack trace and try again. Fall back to BLOCKED only once you've genuinely exhausted the obvious launch paths, with exactly where",
            description='verify skill: gate BLOCKED on genuine exhaustion, not a 15-minute clock',
        ),
    ],
    "system-prompt-02-comment-why-only-guidance.md": [
        Rule(
            stock='Default to writing no comments. Only add one when the WHY is non-obvious:',
            unnerf='Comment wherever it genuinely helps a future reader, focusing on the non-obvious WHY:',
            description='comments: comment where it helps a reader, focused on the non-obvious WHY',
        ),
    ],
    "system-prompt-act-when-ready.md": [
        Rule(
            stock='If you are weighing a choice, give a recommendation, not an exhaustive survey',
            unnerf='If you are weighing a choice, lead with a recommendation and briefly name the alternatives you weighed and why they lose, not an exhaustive survey',
            description='act-when-ready: lead with a recommendation AND the alternatives weighed',
        ),
    ],
    "system-prompt-clarifying-question-research-first.md": [
        Rule(
            stock='Before asking, spend up to a minute on read-only investigation (grep the codebase, check docs, search memory) so your question is specific.',
            unnerf="Before asking, do thorough read-only investigation (grep the codebase, check docs, search memory) until your question is as specific as the available evidence allows — don't cut the investigation short to save time.",
            description='clarify-first: investigate until specific, not a one-minute time-box',
        ),
    ],
    "system-prompt-coordinator-worker-instructions.md": [
        Rule(
            stock="Complete exactly what was asked. Don't fix unrelated issues you discover — suggest them as follow-ups instead.",
            unnerf='Complete what was asked thoroughly and correctly — including any directly-related work needed to make the result actually function and be verified, not just the literal minimum. For genuinely unrelated issues you discover (especially ones that could collide with other workers on this branch), note them as follow-ups instead of fixing them inline.',
            description='coordinator-worker: finish+verify the task fully (coordination guard kept)',
        ),
        Rule(
            stock='Limit changes to what your task requires',
            unnerf='Make all the changes your task genuinely requires to be complete, correct, and verified — without expanding into unrelated areas other workers may own',
            description='coordinator-worker: make all changes the task needs (not unrelated areas)',
        ),
    ],
    "system-prompt-doing-tasks-ambitious.md": [
        Rule(
            stock='You are highly capable and often allow users to complete ambitious tasks that would otherwise be too complex or take too long. You should defer to user judgement about whether a task is too large to attempt.',
            unnerf='You are highly capable and often allow users to complete ambitious tasks that would otherwise be too complex or take too long. You should defer to user judgement about whether a task is too large to attempt — but never scale back rigor, effort, or care. Bring your full capability to every task. On anything non-trivial, think deeply, broadly, and creatively before acting: weigh multiple approaches and consider non-obvious or cross-cutting connections rather than committing to the first idea that works. Reaching the correct, complete, robust result matters far more than minimizing effort, tokens, or output — never trade away rigor, depth, or correctness for speed or brevity. Verify your work empirically: actually run the code, the tests, or the command and read the result rather than asserting from plausibility; treat your own conclusions as unverified until you have checked them; and close every gap in your reasoning, or state precisely what remains unresolved.',
            description='STANDARDS: full-effort, deep/broad thinking + empirical verification on ambitious tasks',
        ),
    ],
    "system-prompt-doing-tasks-no-additions.md": [
        Rule(
            stock="Don't add features, refactor, or introduce abstractions beyond what the task requires. A bug fix doesn't need surrounding cleanup; a one-shot operation doesn't need a helper. Don't design for hypothetical future requirements. Three similar lines is better than a premature abstraction. No half-finished implementations either.",
            unnerf='Implement the task completely and to a senior-engineer standard. Handle the edge cases, error paths, and failure modes the task implies, even if unstated, and add the validation, structure, and abstractions that make the change correct, robust, and maintainable. When a bug fix exposes adjacent breakage or you touch code that is plainly flawed, fix it and say what you did rather than working around it. Leave every file you touch clearer than you found it. And never ship a half-finished implementation.',
            description='no-additions: implement completely to a senior standard; fix plainly-broken adjacent code',
        ),
    ],
    "system-prompt-exploratory-questions-analyze-before-implementing.md": [
        Rule(
            stock='respond in 2-3 sentences with a recommendation and the main tradeoff.',
            unnerf='respond with a thorough analysis: lay out the viable options, the key tradeoffs of each, and your recommendation with the reasoning behind it.',
            description='exploratory questions: full options+tradeoffs analysis, not 2-3 sentences',
        ),
    ],
    "system-prompt-outcome-first-communication-style.md": [
        Rule(
            stock="Only write a code comment to state a constraint the code itself can't show",
            unnerf="Write a code comment whenever it captures something the code itself can't show — a constraint, a non-obvious invariant, or the reasoning behind a subtle choice",
            description='outcome-first: comment constraints, invariants, and subtle reasoning',
        ),
    ],
    "system-prompt-permission-classifier-strict-review-guidance.md": [
        Rule(
            stock='Think longer on ambiguous or borderline actions; keep reasoning brief for clear-cut ones.',
            unnerf='Think longer on ambiguous or borderline actions, and reason carefully even on clear-cut ones — err toward more deliberation, since extra scrutiny only makes the classification safer.',
            description='permission classifier: reason carefully even on clear-cut (safety-amplifying)',
        ),
    ],
    "system-prompt-phase-four-of-plan-mod.md": [
        Rule(
            stock='Include only your recommended approach, not all alternatives',
            unnerf='Lead with your recommended approach; briefly note the key alternatives you weighed and why you rejected them, so the decision is legible — but keep the focus on what to execute',
            description='plan phase-4: note key alternatives weighed for decision legibility',
        ),
    ],
    "system-prompt-subagent-delegation-examples.md": [
        Rule(
            stock='Report a punch list — done vs. missing. Under 200 words.',
            unnerf='Report a complete punch list — done vs. missing — covering every blocker you find.',
            description='subagent-delegation example: complete punch list, not a 200-word cap',
        ),
    ],
    "system-prompt-subagent-prompt-writing-examples.md": [
        Rule(
            stock='Report a punch list — done vs. missing. Under 200 words.',
            unnerf="Report a thorough punch list — done vs. missing, with specifics (file paths, line numbers) for each item. Prioritize completeness over brevity; don't drop a real blocker to hit a word count.",
            description='subagent-prompt example: complete punch list, not a 200-word cap',
        ),
        Rule(
            stock='The prompt is self-contained: it states the goal, lists what to check, and caps the response length.',
            unnerf='The prompt is self-contained: it states the goal, lists what to check, and specifies the report format (a complete done-vs-missing punch list) without artificially capping its length.',
            description='subagent-prompt example: value report completeness, not length-capping',
        ),
    ],
    "system-reminder-file-summary-completeness-disclosure.md": [
        Rule(
            stock="If after a few attempts you cannot read the file (file not found, lines too long for Read's offset/limit, no shell access), STOP retrying.",
            unnerf="If you genuinely cannot read the file after exhausting the available approaches — varying Read's offset/limit window, using shell tools where you have shell access, and trying any alternative readers — stop retrying (this is the case when the file is not found, or its lines are too long for Read's offset/limit and you have no shell access).",
            description='file-read: exhaust available approaches before giving up',
        ),
    ],
    "system-reminder-memory-extraction-recent-context-only.md": [
        Rule(
            stock='Do not waste any turns attempting to investigate or verify that content further — no grepping source files, no reading code to confirm a pattern exists, no git commands.',
            unnerf='When a fact you are about to persist is load-bearing, surprising, or could be wrong, verify it against the source before committing it — grep the source files and read the relevant code to confirm a pattern actually exists. A wrong fact written to persistent memory misleads every future session, so spend the turns needed to get load-bearing facts right; skip verification only for facts that are self-evidently correct from the conversation itself.',
            description='memory extraction: verify load-bearing facts before persisting them',
        ),
    ],
    "tool-description-agent-explicit-spawn-restriction.md": [
        Rule(
            stock='**Do not spawn agents unless the user asks.** Each spawn starts cold and re-derives context you already have — it\'s the expensive path on this plan. A task with "multiple angles," "thorough," or several parts is not a request to spawn; handle it inline with your own tools. Only use this tool when the user explicitly says to use a subagent, or names one of the available agent types.',
            unnerf='**Spawn agents whenever parallel investigation or fan-out would produce a more thorough, accurate answer.** Each spawn starts cold and re-derives context you already have, so brief it well and give it what it needs — but a task with multiple angles, several independent parts, or a broad search surface is a strong reason to delegate in parallel rather than serialize everything inline. Use this tool when the user explicitly says to use a subagent or names an available agent type, and proactively whenever splitting the work across agents lets you cover more ground or verify findings independently.',
            description='agent tool: spawn for parallel/fan-out investigation (brief them well)',
        ),
    ],
    "tool-description-bash-git-commit-and-pr-creation-instructions.md": [
        Rule(
            stock='<1-3 bullet points>',
            unnerf='<bullet points covering all notable changes — as many as the work warrants>',
            description='PR summary: as many bullets as the work warrants',
        ),
    ],
    # Sibling of the bash-git-commit PR-summary rule above (found via the v2.1.190
    # exhaustive sibling audit). The /quick-pr command emits the SAME PR body
    # template but in two arms (IS_BASH_ENV_FN ? bash-heredoc : pwsh-here-string),
    # so "<1-3 bullet points>" appears TWICE. The matcher replaces only the first
    # occurrence per rule (content.replace(stock, unnerf, 1)), so flip each arm
    # with its own rule, each anchored on the distinguishing "--body" prefix to
    # stay byte-unique. Same flip/text as the sibling above, for consistency.
    "agent-prompt-quick-pr-creation.md": [
        Rule(
            stock="--body \"$(cat <<'EOF'\n## Summary\n<1-3 bullet points>",
            unnerf="--body \"$(cat <<'EOF'\n## Summary\n<bullet points covering all notable changes — as many as the work warrants>",
            description="quick-pr summary (bash arm): as many bullets as the work warrants",
        ),
        Rule(
            stock="--body @'\n## Summary\n<1-3 bullet points>",
            unnerf="--body @'\n## Summary\n<bullet points covering all notable changes — as many as the work warrants>",
            description="quick-pr summary (pwsh arm): as many bullets as the work warrants",
        ),
    ],
    "tool-description-workflow.md": [
        Rule(
            stock='For any other task — even one that would clearly benefit from parallelism — do NOT call this tool. Use the Agent tool for individual subagents, or briefly describe what a multi-agent workflow could do and how much it would roughly cost, and ask the user whether to run it.',
            unnerf='For any other task, do NOT call this tool without that opt-in — but when a task would clearly benefit from parallelism, surface that proactively rather than staying silent: use the Agent tool for individual subagents, and describe what a multi-agent workflow could do for this task and how much it would roughly cost, then ask the user whether to run it.',
            description='workflow: keep opt-in gate, but surface beneficial parallelism proactively',
        ),
    ],

    # -------------------------------------------------------------------------
    # Consistency flips found by the v2.1.185 full-prompt audit. Each mirrors an
    # already-applied rule whose sibling instance was previously missed, or
    # closes a process-brevity cap on a human-facing report. All are bucket-3
    # (process brevity): they suppress substantive status/explanation to a human.
    # -------------------------------------------------------------------------
    "agent-prompt-code-review-part-9-fix-application.md": [
        Rule(
            # Same sentence as agent-prompt-simplify-slash-command.md (already
            # un-nerfed). --fix has just mutated the user's working tree; the
            # diff shows WHAT changed but not WHY a finding was skipped (false
            # positive vs behavior-changing vs out-of-scope) — the exact rationale
            # the user needs to review applied edits. Don't cap it at "brief".
            stock='Finish with a brief summary of what was fixed\nand what was skipped.',
            unnerf='Finish with a thorough account of what was fixed and why, and what was skipped with the specific reason for each skip.',
            description='code-review --fix report: thorough fix/skip account with reasons (mirrors simplify-slash-command)',
        ),
    ],
    "system-prompt-troubleshooting-confirmation-policy.md": [
        Rule(
            # Safety confirmation gate. A fuller explanation strictly HELPS the
            # user's decision to approve a destructive command — flipping "briefly"
            # strengthens the gate rather than weakening it. Mirrors the
            # learning-mode-insights "brief"->"thorough" educational flip.
            stock='briefly explain what the fix will do, then ask me to confirm',
            unnerf='clearly explain what the fix will do and why it is the right fix, then ask me to confirm',
            description='troubleshooting confirm gate: explain the fix clearly + why (informs the safety decision)',
        ),
    ],
    # -------------------------------------------------------------------------
    # system-prompt-coordinator-mode-orchestration.md: RETIRED in the v2.1.196
    # sync. Anthropic replaced the literal launch-note phrase — "briefly tell the
    # user what you launched and end your response." — with a runtime-interpolated
    # ${WAIT_FOR_AGENT_RESULTS_INSTRUCTION} variable. Line 44 now reads: "After
    # launching agents, ${WAIT_FOR_AGENT_RESULTS_INSTRUCTION} and end your
    # response. Never fabricate or predict agent results..." The brevity directive
    # now lives inside that variable's *value*, which is defined in the binary and
    # is NOT present in any extracted .md (grep-verified: no prompt file carries a
    # "tell the user what you launched" / wait-for-results instruction as content).
    # The tweakcc .md-patch mechanism replaces static `pieces` text and treats
    # ${VARS} as wildcards, so it cannot reach a variable's value — this un-nerf is
    # no longer applicable via .md. The surviving static text carries no nerf:
    # "and end your response" is a functional stop (KEEP) and "Never fabricate or
    # predict agent results" is a correctness guard (KEEP). Nothing left to flip.
    # -------------------------------------------------------------------------
    "system-prompt-autonomous-loop-persistence-guidance-CLAUDE_CODE_LOOP_PERSISTENT.md": [
        Rule(
            # Sibling of system-prompt-autonomous-loop-check.md (already un-nerfed):
            # a quiet "nothing to do" tick should report what was actually checked,
            # not collapse to one sentence. "keep the loop alive" (the persistence
            # behavior this file exists to enforce) is preserved.
            stock='say so in one sentence and keep the loop alive.',
            unnerf='report what you checked (PRs inspected, CI status, threads reviewed, branches compared) and confirm nothing needed action, then keep the loop alive.',
            description='loop persistence quiet-tick: substantive status report, preserve persistence (mirrors autonomous-loop-check)',
        ),
    ],
    # -------------------------------------------------------------------------
    # system-reminder-async-agent-launched.md: RETIRED in the v2.1.196 sync.
    # Anthropic rewrote this reminder in v2.1.193. The old sentence — "...avoid
    # working with the same files or topics it is using. Work on non-overlapping
    # tasks, or briefly tell the user what you launched and end your response." —
    # lost its entire "Work on non-overlapping tasks, or ... end your response"
    # clause; it now ends at "...topics it is using." The launch-note brevity
    # phrase this rule targeted is GONE (removed, not relocated: zero tree-wide
    # hits for "briefly tell the user" or a "what you launched" directive). The
    # rewritten reminder is a pure anti-duplication + don't-read-the-JSONL-transcript
    # warning with no brevity directive to flip. Retired. (Its former sibling
    # system-prompt-coordinator-mode-orchestration was retired the same sync for a
    # different structural reason — the ${WAIT_FOR_AGENT_RESULTS_INSTRUCTION}
    # variable-ization above.)
    # -------------------------------------------------------------------------
}


# ============================================================================
# LOGIC
# ============================================================================


def apply_rules(
    prompts_dir: Path,
    *,
    dry_run: bool,
    only: Optional[str],
) -> list[Result]:
    """Apply all RULES to files under prompts_dir. Return a flat list of Results."""
    results: list[Result] = []

    for filename, rules in RULES.items():
        if only and only != filename:
            continue

        path = prompts_dir / filename
        if not path.exists():
            results.append(
                Result(
                    filename=filename,
                    status="missing",
                    rule_description="(file)",
                    detail=f"File not found at: {path}",
                )
            )
            continue

        # Read as bytes so we can measure CRLF contamination without Python's
        # universal-newline mode quietly normalizing on our behalf. If a file
        # got CRLF-polluted (e.g. by a previous buggy script run, or by a
        # Windows editor), normalize to LF here and track that the file will
        # need rewriting even if no rule modifies text content.
        raw = path.read_bytes().decode("utf-8")
        content = raw.replace("\r\n", "\n")
        original = content
        # If normalization alone changed bytes on disk, ensure we write back.
        had_crlf = raw != content

        for rule in rules:
            if rule.stock in content:
                content = content.replace(rule.stock, rule.unnerf, 1)
                results.append(
                    Result(
                        filename=filename,
                        status="applied",
                        rule_description=rule.description,
                    )
                )
            elif rule.unnerf in content:
                results.append(
                    Result(
                        filename=filename,
                        status="skipped",
                        rule_description=rule.description,
                        detail="already un-nerfed",
                    )
                )
            else:
                # Neither stock nor unnerf present — drift or partial state.
                stock_preview = _truncate(rule.stock, 200)
                unnerf_preview = _truncate(rule.unnerf, 200)
                detail = (
                    f"Expected stock text (first 200 chars):\n"
                    f"  {stock_preview!r}\n"
                    f"Expected un-nerf text (first 200 chars, for reference):\n"
                    f"  {unnerf_preview!r}\n"
                    f"Neither was found in the file.\n"
                    f"Action: open {path} and locate the passage the rule targets. "
                    f"If upstream text drifted, update the rule's `stock` field in "
                    f"scripts/apply-unnerfs.py to match the new upstream wording."
                )
                results.append(
                    Result(
                        filename=filename,
                        status="failed",
                        rule_description=rule.description,
                        detail=detail,
                    )
                )

        needs_write = content != original or had_crlf
        if needs_write and not dry_run:
            # Write as bytes so Python doesn't translate LF -> CRLF on Windows.
            # The prompts repo uses LF exclusively; preserving that matters for
            # git diffs to stay small after re-applying.
            path.write_bytes(content.encode("utf-8"))
            if had_crlf and content == original:
                # No un-nerf rule touched this file, but line endings were
                # fixed. Surface that as a dedicated status so the report
                # reflects reality.
                results.append(
                    Result(
                        filename=filename,
                        status="normalized",
                        rule_description="CRLF -> LF (line-ending cleanup)",
                        detail="Fixed CRLF line endings. No rule content change.",
                    )
                )

    return results


def _truncate(s: str, limit: int) -> str:
    """One-line preview of s, truncated to limit with ellipsis, newlines escaped."""
    flat = s.replace("\n", "\\n")
    if len(flat) <= limit:
        return flat
    return flat[: limit - 3] + "..."


def format_report(results: list[Result], *, dry_run: bool, verbose: bool) -> str:
    """Produce the human+Claude-readable report."""
    by_file: dict[str, list[Result]] = {}
    for r in results:
        by_file.setdefault(r.filename, []).append(r)

    lines: list[str] = []
    header = "=== Un-nerf re-apply report"
    if dry_run:
        header += " (DRY RUN — no files written)"
    header += " ==="
    lines.append(header)
    lines.append("")

    for filename in sorted(by_file.keys()):
        file_results = by_file[filename]
        lines.append(f"system-prompts/{filename}")
        for r in file_results:
            tag = r.status.upper()
            lines.append(f"  [{tag:<8}] {r.rule_description}")
            if r.status == "failed":
                for line in (r.detail or "").splitlines():
                    lines.append(f"             {line}")
            elif r.status == "missing":
                lines.append(f"             {r.detail}")
            elif r.status == "skipped" and verbose:
                lines.append(f"             {r.detail}")
        lines.append("")

    # ---- Summary ----
    counts = {"applied": 0, "skipped": 0, "failed": 0, "missing": 0, "normalized": 0}
    for r in results:
        counts[r.status] += 1

    files_touched = len(by_file)
    files_changed = sum(
        1 for rs in by_file.values() if any(r.status == "applied" for r in rs)
    )

    lines.append("=== Summary ===")
    lines.append(f"Files processed : {files_touched}")
    lines.append(f"Files changed   : {files_changed}")
    lines.append(f"Rules applied   : {counts['applied']}")
    lines.append(f"Rules skipped   : {counts['skipped']}  (already un-nerfed; idempotent)")
    lines.append(f"Rules FAILED    : {counts['failed']}")
    lines.append(f"Missing files   : {counts['missing']}")
    if counts["normalized"]:
        lines.append(f"Line-ending fix : {counts['normalized']}  (CRLF -> LF cleanup)")

    if counts["failed"] or counts["missing"]:
        lines.append("")
        lines.append("Some rules failed or files are missing. See the per-file")
        lines.append("[FAIL] / [MISSING] entries above for next steps.")

    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> int:
    # Force UTF-8 on stdout/stderr. Windows' default cp1252 can't encode the
    # em-dashes and arrows used in rule descriptions; without this, the
    # traceback is "UnicodeEncodeError: charmap can't encode '→'".
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass  # already-reconfigured stream or not a TextIOWrapper

    parser = argparse.ArgumentParser(
        description="Re-apply the tweakcc system-prompt un-nerfs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="See the module docstring at the top of this file for full documentation.",
    )
    parser.add_argument(
        "--dir",
        type=Path,
        default=DEFAULT_PROMPTS_DIR,
        help=f"Directory of .md prompts to process (default: {DEFAULT_PROMPTS_DIR})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would change but do not modify any files.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Like --dry-run, but exit 1 if ANY rule would apply (useful in CI).",
    )
    parser.add_argument(
        "--only",
        type=str,
        default=None,
        help="Restrict processing to one filename (no path, just 'foo.md').",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Include detail on [SKIP] entries too.",
    )
    args = parser.parse_args(argv)

    if not args.dir.exists():
        print(f"ERROR: prompts directory not found: {args.dir}", file=sys.stderr)
        return 2
    if not args.dir.is_dir():
        print(f"ERROR: --dir is not a directory: {args.dir}", file=sys.stderr)
        return 2

    dry_run = args.dry_run or args.check
    results = apply_rules(args.dir, dry_run=dry_run, only=args.only)
    print(format_report(results, dry_run=dry_run, verbose=args.verbose))

    # Exit logic
    if args.check:
        # Anything that would change OR any failure -> exit 1.
        # "normalized" counts as a change because it mutates the file on disk.
        if any(
            r.status in {"applied", "failed", "missing", "normalized"}
            for r in results
        ):
            return 1
        return 0

    if any(r.status in {"failed", "missing"} for r in results):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
