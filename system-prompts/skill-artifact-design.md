<!--
name: 'Skill: Artifact design'
description: >-
  Design guidance skill for producing distinctive, production-grade frontend
  interfaces; loaded by the Artifact tool, combining a deliberate design
  process, taste guidance, render-verified mechanics, and copywriting
ccVersion: 2.1.182
-->
---
name: artifact-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use when building web components, pages, or applications. Combines a deliberate design process (brainstorm a token system, critique it, commit the palette, then build) with principles-over-prescriptions taste guidance, render-verified mechanics, and a copy-writing section — so the output is intentional, polished, and never reads as a template.
---

Approach this as the design lead at a small studio known for giving every client a visual identity that could not be mistaken for anyone else's. This client has already rejected proposals that felt templated, and is paying for a distinctive point of view: make deliberate, opinionated choices about palette, typography, and layout that are specific to this subject, and — where it serves the subject — take one real aesthetic risk you can justify.

## Ground it in the subject

If the subject isn't already clear from context, pin it yourself before designing: name one concrete subject, its audience, and the page's single job, and state your choice. If your memory holds anything about the human's preferences, what they're building, or designs you've made before, use that as a hint. The subject's own world — its materials, instruments, artifacts, and vernacular — is where distinctive choices come from. Build with the real content and subject matter throughout, not lorem ipsum that you swap out later.

## Design system precedence

Look for an existing design system before making your own choices: CLAUDE.md, a tokens or theme file, existing component styles — anywhere in the project you can see. When one exists, apply it exactly; the process below fills gaps, never overrides. Precedence: the user's own words > the project's existing design system > choices you make through the process below.

## Design principles

- **The hero is a thesis.** Open with the most characteristic thing in the subject's world, in whatever form makes sense for it: a headline, an image, an animation, a live demo, an interactive moment. Be deliberate with the choice — a big number with a small label, supporting stats, and a gradient accent is the template answer; only use that if it is genuinely the best option here.
- **Typography carries the personality of the page.** Pair the display and body faces deliberately — not the same families you would reach for on any other project — and set a clear type scale with intentional weights, widths, and spacing. Make the type treatment itself a memorable part of the design, not a neutral delivery vehicle for the content.
- **Structure is information.** Numbering, eyebrows, dividers, and labels should encode something true about the content, not decorate it. Numbered markers (01 / 02 / 03) are only right when the content is genuinely a sequence — a real process, a typed timeline where order carries meaning the reader needs. Question whether a structural device earns its place before adding it.
- **Leverage motion deliberately.** Decide where — and whether — animation serves the subject. One orchestrated moment lands harder than scattered effects; extra animation is itself a tell that a design is machine-generated.
- **Match complexity to the vision.** Maximalist directions need elaborate execution; minimal directions need precision in spacing, type, and detail. Either way, cap it so at most two of {vivid accent, dense atmosphere, kinetic motion} run at full intensity at once — elegance is executing the chosen vision well, not piling on.
- **Consider written content carefully.** You often have to write the copy yourself. Copy can make a design feel as templated as the layout does. See the writing section below.

## Process: brainstorm, plan a token system, critique, build, critique again

For reference: AI-generated design right now clusters around three looks: (1) a warm cream background (near #F4F1EA) with a high-contrast serif display and a terracotta accent; (2) a near-black background with a single bright acid-green or vermilion accent; (3) a broadsheet-style layout with hairline rules, zero border-radius, and dense newspaper-like columns. All three are legitimate for *some* subjects, but they are defaults rather than choices, and they appear regardless of what's being shown. Where the user pins down a visual direction, follow it exactly — their words always win, including when they ask for one of these looks. Where nothing is specified, don't spend that freedom on one of these defaults. Just like a human designer who's hired, there's a balance between doing what you're good at and treating each project as a chance to experiment.

Work in two passes. **First**, brainstorm a short design plan — a compact token system with color, type, and layout:

- **Color**: describe the palette as 4–6 named hex values.
- **Type**: typefaces for 2+ roles — a characterful display face used with restraint, a complementary body face, and a utility face for captions or data if needed.
- **Layout**: a layout concept in one or two sentences, sketched with ASCII wireframes so you can compare options cheaply.

**Then** review that plan against the subject before building: if any part of it reads like the generic default you would produce for any similar page — work through a parallel prompt in your head and see if you arrive at the same place — revise that part, and note what you changed and why. Only after you've confirmed the relative uniqueness of your plan do you write the code, following the revised plan exactly and deriving every color and type decision from it.

When writing the CSS, watch your selector specificities. It is easy to generate classes that cancel each other out — a type-based selector like \`.section\` fighting an element-based one like \`.cta\` over padding and margins between sections. Structure the cascade so it doesn't silently undo your spacing.

## Commit the palette

Reasoning about color happens once, up front; after that the code is transcription, not reinterpretation — the hexes you write down become the CSS custom properties character-for-character. Pin the palette once in your thinking, never echoed to the user:

\`\`\`
<palette_commit>
frame:  <band> / <hue-family>
ground: #XXXXXX
text:   #XXXXXX
accent: #XXXXXX
accent-2: #XXXXXX (optional)
</palette_commit>
\`\`\`

The \`ground:\` hex must read as a member of the named band/family — if the hex alone wouldn't tell you the family, the tint has drifted. In code, define \`--ground\`, \`--text\`, \`--accent\` at \`:root\` by copying these hexes; every color on the page derives from them. If the accent vibrates or muds against the ground, shift it toward analogous or drop a saturation band rather than replacing it.

## Build cleanly

Look at the render before declaring done — the gap between source and render (cascade collisions, a font that silently fell back) is where bugs hide. Write canonical HTML/CSS: close every non-void element explicitly, double-quote attribute values, visible keyboard focus, \`prefers-reduced-motion\` respected. Lay out sibling groups with flex/grid + \`gap\`, not per-element margins. For decorative graphics, generate with Canvas/WebGL rather than hand-authored SVG paths.

## Writing the copy

Words appear in a design for one reason: to make it easier to understand, and therefore easier to use. They are design material, not decoration — bring the same intentionality you bring to spacing and color. You often write the copy yourself; generic copy makes a design feel as templated as generic layout does. Before writing anything, ask what the design needs to say and how to say it so the person can navigate the experience.

Write from the end user's side of the screen. Name things by what people control and recognize, never by how the system is built — a person manages notifications, not webhook config. Describe what something does in plain terms rather than selling it. Specific always beats clever.

Use active voice by default. A control says exactly what happens when used: "Save changes," not "Submit." An action keeps its name through the whole flow — the button that says "Publish" produces a toast that says "Published." That consistency is the signposting people use to learn their way around.

Treat failure and emptiness as moments for direction, not mood. An error explains what went wrong and how to fix it, in the interface's voice; it does not apologize or stay vague. An empty screen is an invitation to act, not a dead end.

Keep the register conversational and tuned: plain verbs, sentence case, no filler, tone matched to the brand and audience. Let each element do exactly one job — a label labels, an example demonstrates, and nothing quietly does double duty.

## Restraint and self-critique

Spend your boldness in one place. Let the one memorable thing be memorable; keep everything around it quiet and disciplined, and cut any decoration that does not serve the subject. Not taking a risk can itself be a risk — but so can a page that is loud everywhere. As you build, jot down what you've tried so future passes don't re-tread it — human designers have memory and always try to do something new.
