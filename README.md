# TIL (Today I Learned)

🔗 **[til.omkarpatil.dev](https://til.omkarpatil.dev/)**

A collection of technical notes and explanations I write to understand various topics. Built with [Astro](https://astro.build) and styled with [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) for a clean, GitHub gist-like reading experience.

## Adding content

- **Markdown** — Drop `.md` files into `src/pages/`. Add frontmatter to use the layout:

  ```yaml
  ---
  layout: ../layouts/GistLayout.astro
  ---
  ```

- **HTML** — Drop self-contained `.html` files into `public/`.

The index page automatically discovers all pages and lists them using the first `<h1>` heading (or `<title>` for HTML files) as the link text.

## Project structure

```sh
src/
├── layouts/
│   └── GistLayout.astro    # GitHub light theme layout for markdown
└── pages/
    ├── index.astro          # Auto-generated index page
    └── *.md                 # Markdown content pages
public/
    └── *.html               # Self-contained HTML pages
```

## Development

```sh
npm install
npm run dev       # localhost:4321
npm run build     # Build to ./dist/
```

## Deployment

Deployed to [Cloudflare Workers](https://workers.cloudflare.com/) — builds and deploys are configured through the Cloudflare dashboard, triggered on push to `main`.
