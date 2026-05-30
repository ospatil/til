---
layout: ../layouts/GistLayout.astro
tags: [svelte, sveltekit, spa, tanstack-query, guide]
---

# SvelteKit Pure SPA: Loaders vs TanStack Query

Building a fully client-rendered SPA with SvelteKit (no SSR), and how data fetching works in that mode - using SvelteKit's own loaders, TanStack Query, or both. Covers what each does, how Query caches across navigations, and what's optimal.

---

## Table of Contents

1. [Architecture: Pure SPA Mode](#1-architecture-pure-spa-mode)
2. [Data Loading with SvelteKit Loaders](#2-data-loading-with-sveltekit-loaders)
3. [Where Loaders Fall Short](#3-where-loaders-fall-short)
4. [TanStack Query Setup](#4-tanstack-query-setup)
5. [Queries & Mutations (Runes Syntax)](#5-queries--mutations-runes-syntax)
6. [How Caching Works Across Navigations](#6-how-caching-works-across-navigations)
7. [Combining Loaders & Query: Three Patterns](#7-combining-loaders--query-three-patterns)
8. [Loaders vs Query: What You Trade](#8-loaders-vs-query-what-you-trade)
9. [The Optimal Setup](#9-the-optimal-setup)
10. [Version Gotchas & Setup](#10-version-gotchas--setup)

---

## 1. Architecture: Pure SPA Mode

A "pure SPA" disables server rendering entirely and ships a static shell that boots in the browser. SvelteKit supports this without a server runtime.

```js
// src/routes/+layout.ts  - disable SSR for all routes
export const ssr = false
```

```js
// svelte.config.js  - adapter-static with a fallback shell
import adapter from '@sveltejs/adapter-static'

export default {
  kit: { adapter: adapter({ fallback: '200.html' }) } // avoid index.html (conflicts with prerender)
}
```

This changes the ground rules versus an SSR app:

| Concern | Pure SPA reality |
| --- | --- |
| Server runtime | None - deploy static files to a CDN |
| `+page.server.ts`, `+layout.server.ts`, `+server.ts` | **Gone** - they need a server |
| Form actions | Gone - mutate via your API instead |
| Universal load (`+page.ts`, `+layout.ts`) | Only loader type left; runs **in the browser** |
| Data source | A **separate API** (e.g. a Go/Java/Rust service) |
| SSR state-leak footgun | **Disappears** - no shared server process |

The last row matters: with no server, a module-level singleton is safe (each user runs their own browser), which simplifies the TanStack Query setup below.

### Data Flow

Everything runs in the browser. Both loaders and `createQuery` fetch from the same external API over HTTP - the difference is that Query interposes a cache, so only misses and stale entries reach the network.

```text
                   BROWSER  (static shell served from CDN)
  +-----------------------------------------------------------+
  |  SvelteKit router  (client-side, no server runtime)       |
  |     |                                                     |
  |     +-- +page.ts load() -----------------------+          |
  |     |                                          |          |
  |     +-- +page.svelte                           |          |
  |             |                                  |          |
  |             +-- createQuery                    |          |
  |                     |                          |          |
  |                     v                          |          |
  |              +----------------+   fresh hit:   |          |
  |              |  QueryCache    |   return data  |          |
  |              | (QueryClient)  |   (no fetch)   |          |
  |              +----------------+                |          |
  |                     | miss / stale            (loader     |
  +---------------------|--------------------------|--fetch)--+
                        |                          |
                        v                          v
              +---------------------------------------------+
              |  Separate API  (Go / Java / Rust ...)       |
              |  business logic + data  --  JSON over HTTP  |
              +---------------------------------------------+
```

- **Loader path** (right): `+page.ts load()` fetches directly from the API on every navigation.
- **Query path** (left): `createQuery` reads the cache first; only a miss or stale entry falls through to the API.

> SvelteKit warns SPA mode hurts SEO and first paint (blank shell -> JS -> data = multiple round trips). The fix is to selectively prerender public pages - see [section 9](#9-the-optimal-setup).

---

## 2. Data Loading with SvelteKit Loaders

In a pure SPA only the **universal load** survives, and it runs client-side - before the page component renders.

```ts
// src/routes/posts/[id]/+page.ts
export async function load({ params, fetch }) {
  const post = await fetch(`https://api.example.com/posts/${params.id}`).then(r => r.json())
  return { post } // -> data prop in +page.svelte
}
```

```svelte
<!-- +page.svelte -->
<script>
  let { data } = $props()
</script>
<h1>{data.post.title}</h1>
```

What still works, relocated to the browser:

- `params` / `url` reactivity (re-runs on change), parallel loading, `await parent()`
- `depends()` + `invalidate()` / `invalidateAll()`
- Streaming via returned-but-unawaited promises + `{#await}`
- `error()` -> `+error.svelte`, and `redirect()` before render

The special `fetch` still dedupes, but there's no internal direct-invocation optimization anymore (no server endpoints to call).

---

## 3. Where Loaders Fall Short

Loaders are great for **route-coupled, fetch-once** data. As a general client data layer they lack:

| Need | Loaders alone |
| --- | --- |
| Cache across navigations | No - re-runs every visit |
| Background refetch / stale-while-revalidate / refetch-on-focus | No |
| Request dedup across components | No (route-level only) |
| Sub-component granular refetch | No - granularity is the whole route |
| Mutations, optimistic UI, infinite scroll | No primitives |
| Loading UX | Block navigation, or manual `{#await}` |

That gap is exactly what TanStack Query fills.

---

## 4. TanStack Query Setup

A module-level `QueryClient` singleton is safe here (no SSR = no cross-request leak):

```ts
// src/lib/query.ts
import { QueryClient } from '@tanstack/svelte-query'
export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 30_000 } }
})
```

```svelte
<!-- src/routes/+layout.svelte -->
<script>
  import { QueryClientProvider } from '@tanstack/svelte-query'
  import { queryClient } from '$lib/query'
  let { children } = $props()
</script>
<QueryClientProvider client={queryClient}>{@render children()}</QueryClientProvider>
```

---

## 5. Queries & Mutations (Runes Syntax)

**Use the v6 adapter for Svelte 5.** It's a rewrite onto runes/signals. The API differs from older tutorials: options are a **thunk** `() => ({...})`, and the result has **no `$` prefix**.

```svelte
<script>
  import { createQuery } from '@tanstack/svelte-query'
  import { page } from '$app/state'

  // reading page.params.id inside the thunk makes it auto-refetch on change
  const post = createQuery(() => ({
    queryKey: ['post', page.params.id],
    queryFn: () => fetch(`/api/posts/${page.params.id}`).then(r => r.json())
  }))
</script>

{#if post.isPending}
  <p>Loading…</p>
{:else if post.error}
  <p>{post.error.message}</p>
{:else}
  <h1>{post.data.title}</h1>
{/if}
```

Mutations replace form actions (which don't exist in a SPA):

```svelte
<script>
  import { createMutation } from '@tanstack/svelte-query'
  import { queryClient } from '$lib/query'

  const save = createMutation(() => ({
    mutationFn: (body) => fetch('/api/posts', { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['posts'] })
  }))
</script>
<button onclick={() => save.mutate({ title: 'New' })}>Add</button>
```

---

## 6. How Caching Works Across Navigations

The cache lives **above** the component tree, inside the `QueryClient` - a map keyed by serialized `queryKey`. Components don't own data; they **subscribe** to it.

- `createQuery(...)` creates an **observer** bound to a key.
- **On mount** -> observer subscribes to that cache entry.
- **On unmount** (navigating away) -> observer unsubscribes, but the entry **stays**. It's only deleted after `gcTime` elapses with zero observers.

This is why data survives navigation: it isn't stored in the page component, so unmounting the page doesn't discard it.

Loaders and Query also differ in *when* they fetch:

```text
loader:  fetch ─────► then render          (render BLOCKED on data)
query:   render (isPending) ─► fetch ─► re-render with data  (non-blocking)
```

What a new subscription (e.g. returning to a page) sees:

| Cache state on mount | Result |
| --- | --- |
| No entry | `isPending` -> run `queryFn` |
| Entry, **fresh** (within `staleTime`) | Cached data **instantly, no fetch** |
| Entry, **stale** (past `staleTime`) | Cached data instantly **+ background refetch** |
| Entry **gc'd** (past `gcTime`, no observers) | Treated as no entry -> refetch |

Default `staleTime` is `0` (stale immediately), so revisits show cached data *and* refetch in the background. Raising `staleTime` is what gives true "no network on revisit." Two components using the same key share one entry and one in-flight request - that's request dedup.

---

## 7. Combining Loaders & Query: Three Patterns

**A. Replace loaders.** No `load`; each component owns its data via `createQuery`. Routes are thin. Best for app-shell SPAs where caching/refetch dominate. You lose route-level "ready before render."

**B. Loader prefetches, component consumes.** The loader warms the cache; the component reads it live. Keeps route-level "block until ready" *and* Query's cache. Avoid duplication with a shared `queryOptions`:

```ts
// src/lib/queries.ts
import { queryOptions } from '@tanstack/svelte-query'
export const postQuery = (id) =>
  queryOptions({ queryKey: ['post', id], queryFn: () => fetch(`/api/posts/${id}`).then(r => r.json()) })
```

```ts
// +page.ts
import { queryClient } from '$lib/query'
import { postQuery } from '$lib/queries'
export const load = ({ params }) => queryClient.prefetchQuery(postQuery(params.id))
```

```svelte
<!-- +page.svelte -->
<script>
  import { createQuery } from '@tanstack/svelte-query'
  import { postQuery } from '$lib/queries'
  import { page } from '$app/state'
  const post = createQuery(() => postQuery(page.params.id)) // finds the warm cache -> no double fetch
</script>
```

> In a pure SPA, B's value is smaller than in SSR (the loader runs in the browser too, not on a server). It mainly buys **waterfall avoidance** for deep component trees and explicit block-until-ready. Reach for it selectively.

**C. Mutations + invalidation** (orthogonal - use with A or B). Shown in [section 5](#5-queries--mutations-runes-syntax); it's how you mutate without form actions.

---

## 8. Loaders vs Query: What You Trade

If you drop loaders entirely and go Query-only, this is what you give up (note: server DB access and SSR serialization are already gone in a SPA, so they don't count against Query):

| Lost capability | Recoverable in Query-only? |
| --- | --- |
| **Prerendering / SSG** (data baked into static HTML at build) | **No** - Query always fetches at runtime. Biggest loss. |
| Data-driven `<svelte:head>` on prerendered routes | No |
| Navigation blocking / no loading flash | Partially - design skeletons instead |
| Auto `+error.svelte` boundary from thrown `error()` | No - handle errors per component |
| `redirect()` before paint | Partially - usually lives in hooks/layout |
| Eager parallel fetch at nav start (waterfall avoidance) | Partially - prefetch on hover/route |

What you **don't** miss - Query matches or beats loaders: caching, dedup, background/stale-while-revalidate refetch, refetch-on-focus, retries, polling, pagination/infinite scroll, mutations, optimistic updates.

The deeper point: a loader does two jobs - **fetch data for a route** and **participate in the routing lifecycle** (block, redirect, error, prerender). Query cleanly replaces the first and has no concept of the second.

---

## 9. The Optimal Setup

Rendering strategy in SvelteKit is **per-route**, so this isn't "SPA vs prerender" - one codebase can be both:

```js
// src/routes/+layout.ts            - app is SPA by default
export const ssr = false
```

```js
// src/routes/(marketing)/+page.ts  - opt public pages back into static HTML
export const ssr = true
export const prerender = true
```

Decision guide:

```text
Is the route public / SEO-relevant / first-paint-critical?
        |
   +----+----+
   |         |
  YES        NO
   |         |
   v         v
loader +   Is the data interactive / shared / mutated?
prerender        |
=true        +---+---+
             |       |
            YES      NO (route-coupled, fetch-once)
             |       |
             v       v
        TanStack   plain universal
          Query      load()
```

- **Query** for the dynamic, app-shell part (dashboards, behind-auth, interactive).
- **Loader + `prerender=true`** for the static/SEO slice (marketing, landing, docs).
- **Pattern B** only when you need route-level "ready before render" *and* a cache.

For a fully private app with no SEO, the optimum collapses to: pure SPA + Query, **zero loaders, zero prerender**.

---

## 10. Version Gotchas & Setup

```bash
npx sv create ./
npm i @tanstack/svelte-query   # v6 - needs Svelte >= 5.25
npm i -D @sveltejs/adapter-static
```

- **Use `@tanstack/svelte-query` v6** for Svelte 5 - it migrated to runes/signals. The v5 adapter used Svelte stores and is buggy/unreliable on Svelte 5.
- v6 API: options are a **thunk** `createQuery(() => ({...}))`; result has **no `$` prefix** (`post.data`, not `$post.data`).
- Reactivity is automatic - read reactive values inside the thunk; no `$derived` / `writable` wrapping needed.
- Initial-load state is `isPending` (not `isLoading`).
- `QueryClient` as a module singleton is safe in SPA mode; in SSR you'd need one per request.

---

## References

- [SvelteKit Single-page apps](https://svelte.dev/docs/kit/single-page-apps)
- [SvelteKit adapter-static](https://svelte.dev/docs/kit/adapter-static)
- [SvelteKit Loading Data](https://svelte.dev/docs/kit/load)
- [TanStack Query - Svelte](https://tanstack.com/query/latest/docs/framework/svelte/overview)
- [TanStack Query - migrate v5 to v6](https://tanstack.com/query/latest/docs/framework/svelte/migrate-from-v5-to-v6)
- [TanStack Query - SSR & SvelteKit](https://tanstack.com/query/latest/docs/framework/svelte/ssr)
