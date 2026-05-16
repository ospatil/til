# TIL (Today I Learned)

🔗 **[til.omkarpatil.dev](https://til.omkarpatil.dev/)**

A collection of technical notes and explanations I write to understand various topics. Built with [Astro](https://astro.build) with full-text search powered by [Pagefind](https://pagefind.app/).

## Adding content

- **Markdown** — Drop `.md` files into `src/pages/`. Add frontmatter to use the layout:

  ```yaml
  ---
  layout: ../layouts/GistLayout.astro
  ---
  ```

- **HTML** — Drop self-contained `.html` files into `public/pages/`.

The index page automatically discovers all pages and lists them using the first `<h1>` heading (or `<title>` for HTML files) as the link text.

## Project structure

```sh
src/
├── layouts/
│   └── GistLayout.astro    # GitHub light theme layout for markdown
└── pages/
    ├── index.astro          # Auto-generated index page with search
    └── *.md                 # Markdown content pages
public/
└── pages/
    └── *.html               # Self-contained HTML pages
```

## Development

```sh
npm install
npm run dev       # localhost:4321 (search won't work in dev)
npm run build     # Build to ./dist/ and generate search index
npm run preview   # Preview build with working search
```

## Deployment

Deployed to [Cloudflare Workers](https://workers.cloudflare.com/) — builds and deploys are configured through the Cloudflare dashboard, triggered on push to `main`.
