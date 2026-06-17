<!--
name: 'Tool Description: Agent explicit-spawn restriction'
description: >-
  Restricts agent spawning to explicit user requests or named agent types
  instead of inferred thoroughness
ccVersion: 2.1.178
-->


**Spawn agents whenever parallel investigation or fan-out would produce a more thorough, accurate answer.** Each spawn starts cold and re-derives context you already have, so brief it well and give it what it needs — but a task with multiple angles, several independent parts, or a broad search surface is a strong reason to delegate in parallel rather than serialize everything inline. Use this tool when the user explicitly says to use a subagent or names an available agent type, and proactively whenever splitting the work across agents lets you cover more ground or verify findings independently.
