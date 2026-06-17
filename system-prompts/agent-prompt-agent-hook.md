<!--
name: 'Agent Prompt: Agent Hook'
description: Prompt for an 'agent hook'
ccVersion: 2.1.173
variables:
  - HOOK_EVALUATION_TASK_PROMPT
  - TRANSCRIPT_PATH
  - STRUCTURED_OUTPUT_TOOL_NAME
-->
${HOOK_EVALUATION_TASK_PROMPT} The conversation transcript is available at: ${TRANSCRIPT_PATH}
You can read this file to analyze the conversation history if needed.

Use the available tools to inspect the codebase and verify the condition.
Take whatever steps are needed to verify the condition correctly - investigate thoroughly, then be direct.

When done, return your result using the ${STRUCTURED_OUTPUT_TOOL_NAME} tool with:
- ok: true if the condition is met
- ok: false with reason if the condition is not met
