---
inclusion: always
---

# TIL Authoring & Diagram Conventions

Conventions for this repo (the TIL site). Follow these when creating or editing content.

## Punctuation

- **Never use em dashes (`—`) or en dashes (`–`)** anywhere - not in markdown docs, not in diagram labels/footers.
- Use a spaced hyphen ` - ` to separate clauses, and a plain hyphen `-` for ranges (`1-6`).
- Middots `·` are fine as compact separators in diagram labels and code comments.

## TIL documents

- **Markdown**: `src/pages/*.md`. Frontmatter:
  ```yaml
  ---
  layout: ../layouts/GistLayout.astro
  tags: [topic, topic, guide]
  ---
  ```
  The first `<h1>` is the page title (the index lists pages by it). The filename is the URL slug - keep it stable; nothing should rename a published doc without checking inbound links.
- **HTML**: self-contained files in `public/pages/*.html` (served as static assets, URL `/pages/<name>.html`). Use `<body data-pagefind-body>` and `<meta name="tags" content="...">`. Match the palette/CSS in `public/pages/network-tunneling-vpns.html`.
- **Raw inline HTML/SVG is allowed in markdown** and passes through the Astro pipeline (verified). Keep an inline block contiguous (no blank lines inside) with blank lines around it.
- Style: lead sections with the *why*; use comparison tables and concrete examples; add a Table of Contents for long docs (top-level sections only). Pretty-print JSON in code blocks. For protocol/flows, keep diagram labels as short summaries and put exact URLs/headers/bodies in an adjacent ` ```http ` (or ` ```console `) block - don't cram protocol detail onto diagram arrows.
- **Tone & voice:**
  - Write like a senior engineer explaining to a peer over coffee - conversational, direct, opinionated where warranted, but technically precise.
  - Use "you" freely. Address the reader directly.
  - Vary sentence length. Mix short punchy statements with longer explanatory ones. Avoid uniformly mid-length sentences that read like a textbook.
  - Lead with a concrete scenario or the *why* before introducing jargon. Name the concept *after* the reader has an intuition for it, not before.
  - Avoid mechanical transitions ("The defining trait of...", "The payoff of externalizing is that..."). Use natural connectors - "Here's the thing:", "So...", "The net:", or just start the next thought.
  - Ground abstractions in examples. If you introduce a model/architecture/term, show what the same thing looks like concretely (a scenario, an API call, a comparison table) before moving on.
  - Opinions are welcome when they save the reader time ("Honestly, prefer a library for this", "Start with RBAC"). Flag them as opinions, not universal truths.
  - Don't over-hedge. If something is true, state it. Reserve "might/could/perhaps" for genuinely uncertain claims.
  - No filler summaries at the end of sections restating what was just said. End on the last useful point and move on.

## Diagrams (draw.io, hand-drawn style)

Workflow: author `.drawio` -> export to SVG -> reference from the doc.

1. **Author** `diagrams/<name>.drawio` (mxGraph XML).
2. **Export**: `npm run diagrams:export <name>.drawio` (or `bash scripts/export-diagrams.sh <name>.drawio` if the npm script lost its exec bit). Output goes to `public/diagrams/<name>.svg` (uses the draw.io desktop app at `/Applications/draw.io.app`; runs non-interactively).
3. **Reference** in markdown: `![alt text](/diagrams/<name>.svg)`.
4. Prefer **SVG** (vector line diagrams scale crisply); PNG only for raster content.

**Hand-drawn look**: every cell's style must include `sketch=1;curveFitting=1;jiggle=2`.

**Palette** (matches the site):

| Use | Color |
| --- | --- |
| Structure: boxes, lifelines, accents | indigo `#4f46e5` (light fill `#eef2ff`) |
| Request / redirect arrows | indigo `#6366f1` |
| Success / token / response | green `#16a34a` (light fill `#d5e8d4`) |
| Pending | amber `#d97706` (light fill `#fff2cc`, stroke `#d6b656`) |
| Failure | red `#dc2626` (light fill `#fef2f2`) |
| Secondary / muted | slate `#64748b` (light fill `#f8fafc`) |
| Accent / alt | purple `#9673a6` (light fill `#e1d5e7`) |
| Body text | `#1e1b4b` · note border `#cbd5e1` |

**Sequence-diagram recipe** (page width ~720; 3 actors centered at x=90/360/630, boxes 150 wide at x=15/285/555):

- Actors: rounded rect, `fillColor=#eef2ff;strokeColor=#4f46e5;fontStyle=1`, at top.
- Lifelines: edges with `endArrow=none;dashed=1;strokeColor=#4f46e5` and explicit `sourcePoint`/`targetPoint`.
- Step arrows: edges with `endArrow=block;endFill=1;labelBackgroundColor=#ffffff`, explicit `sourcePoint`/`targetPoint`, label = `N · short summary`; color per the palette above.
- Notes (self-actions): rounded rect `fillColor=#ffffff;strokeColor=#cbd5e1`.
- Footer: full-width rounded rect `fillColor=#eef2ff;strokeColor=#4f46e5` with a one-line takeaway.
- Give each `.drawio` unique marker ids if you ever inline SVG (avoid cross-SVG id clashes).

## Build / preview

- `npm run dev` (localhost:4321; Pagefind search does not work in dev).
- `npm run build && npm run preview` to verify the build and working search.
- Do not auto-run build/test/lint at task completion - recommend the command instead (see terminal-command-safety steering).

## Deploy

Cloudflare Workers, built/deployed from the Cloudflare dashboard on push to `main`.
