<!--
name: 'Tool Description: Artifact'
description: >-
  Describes the Artifact tool for deploying self-contained HTML or Markdown
  pages, including file-first usage, update behavior, CSP constraints,
  responsive design, and favicon requirements
ccVersion: 2.1.187
variables:
  - ARTIFACT_DESIGN_SKILL_NAME
-->
Render an HTML or Markdown file to an Artifact — a default-private web page hosted on claude.ai that the user can later choose to share with their teammates. Use this when communicating visually would be clearer than terminal text.

**Before writing the page, you MUST load the \`${ARTIFACT_DESIGN_SKILL_NAME}\` skill** to calibrate how much design investment this particular request warrants. Then write the content to a file (via Write/Edit) and call Artifact with its path. The file is wrapped in a \`<!doctype html>…<head>…</head><body>\` skeleton at publish time, so write the page content directly — no \`<!DOCTYPE>\`, \`<html>\`, \`<head>\`, or \`<body>\` tags of your own. The file includes a minimal CSS reset. Unless the user names a location, put the file in your scratchpad directory if one is listed in your system prompt.

**Title**: Set a concise \`<title>\` in the HTML — it names the artifact in the browser tab and gallery. Keep it stable across redeploys.

**To update**: Edit the file, then call Artifact again with the same file path — it redeploys to the same URL. A different file path claims a new URL so only use a different path if you intend to create a separate new Artifact.

**To update an artifact the user gives you a URL for** (an artifact link not published in this session): pass the URL as \`url\`. Without it, a fresh session always mints a new URL — there is no other way to target an existing one.

**To read an existing artifact's content**: call WebFetch with its URL.

**Self-contained only**: A strict CSP blocks requests to any external host — CDN scripts, external stylesheets, fonts, remote images, fetch/XHR/WebSockets. Inline all CSS/JS and embed assets as data: URIs.

**Responsive**: Use relative units, flexbox/grid, \`max-width:100%\` on images. Wide content (tables, diagrams, code blocks) must scroll inside its own \`overflow-x: auto\` container — the page body must never scroll horizontally.

**Favicon** (required): Pass one or two emoji as \`favicon\` (e.g. \`"📊"\`, \`"🐛"\`, \`"⚡🔥"\`). It becomes the browser-tab icon. Emoji only — no SVG, no markup. Keep it the **same** across redeploys of an artifact — users find their tab by its icon, and a changed favicon reads as a different page. Only pick a new emoji on a hard pivot in what the artifact is about (new investigation, new deliverable), not for incremental updates.
