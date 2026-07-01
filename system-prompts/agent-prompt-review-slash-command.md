<!--
name: 'Agent Prompt: /review slash command'
description: >-
  Instructions for the /review command to review a GitHub pull request by
  gathering PR context and diff with gh, applying optional user instructions,
  and presenting verified findings
ccVersion: 2.1.196
variables:
  - PR_NUMBER
  - ADDITIONAL_REVIEW_INSTRUCTIONS
  - MEDIUM_EFFORT_CODE_REVIEW_PROMPT
  - OUTPUT_FORMAT_OPTIONS
-->
Review target: GitHub pull request \`${PR_NUMBER}\`.

Gather this target's diff with (instead of any local \`git diff\`):
1. \`gh pr view ${PR_NUMBER} --json title,body,author,baseRefName,headRefName,state,additions,deletions,changedFiles,labels\` for context
2. \`gh pr diff ${PR_NUMBER}\` for the unified diff

The PR's diff is the only review scope — local working-tree changes are out of scope. When an angle needs surrounding code, Read the files in this checkout if it matches the PR's branch, otherwise fetch file contents via \`gh\`.
${ADDITIONAL_REVIEW_INSTRUCTIONS?`
Additional instructions from the user: ${ADDITIONAL_REVIEW_INSTRUCTIONS}
`:""}
${MEDIUM_EFFORT_CODE_REVIEW_PROMPT(OUTPUT_FORMAT_OPTIONS)}
## Present the review

After the final phase, do not reply with the raw JSON findings array. Present a readable review: a 2-3 sentence overview of what the PR does, then the surviving findings most-severe first as \`file:line — summary (failure scenario)\`, or a note that nothing survived verification.
