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
10. [Authentication & Protected Routes](#10-authentication--protected-routes)
11. [Content Security Policy in a SPA](#11-content-security-policy-in-a-spa)
12. [Version Gotchas & Setup](#12-version-gotchas--setup)

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

## 10. Authentication & Protected Routes

A pure SPA has no `hooks.server.ts`, no server load functions, and no form actions - so the server-side auth machinery (populating `event.locals.user`, redirecting before render) is gone. Auth becomes a client + API concern.

### The Core Rule: Client Guards Are UX, the API Is Security

With adapter-static + fallback, anyone can navigate directly to `/admin` - the host serves the shell, JS boots, and your guard runs *after*. You cannot prevent that. Security lives in exactly one place: the **API**, which authorizes every request. The SPA's only jobs are (1) don't render protected UI to logged-out users, and (2) attach credentials to API calls. A bypassed guard yields an empty shell and 401s - no data leaks.

> Never treat a client-side route guard or client-side role check as a security boundary. It is cosmetic. The API is the authority.

### Carrying the Session: Cookie vs Token

| Model | How | Security tradeoff |
| --- | --- | --- |
| **httpOnly cookie** (recommended) | API sets `Secure; HttpOnly; SameSite` cookie on login; browser attaches it automatically | Token unreadable by JS - XSS can't exfiltrate it. Needs CSRF care (`SameSite=Lax` handles most) |
| **Token in JS** | API returns a JWT; SPA stores it and sends `Authorization: Bearer` | Immune to CSRF, but XSS can steal the token (especially in localStorage). In-memory is safer but lost on refresh |

httpOnly isn't total XSS immunity - injected script can still make requests *while the page is open* (the cookie rides along) - but it prevents *theft* of a reusable credential.

### Token model: the Bearer header

If you choose tokens over cookies, the SPA attaches the JWT itself. Wrap `fetch` so every request carries the header, and point your queryFns at it:

```ts
// src/lib/api.ts
let accessToken = ''                         // in-memory (see storage note)
export const setToken = (t: string) => { accessToken = t }

export const api = (path: string, init: RequestInit = {}) =>
  fetch(path, { ...init, headers: { ...init.headers, Authorization: `Bearer ${accessToken}` } })
```

- **Storage:** keep the access token **in memory**, not `localStorage` - localStorage is readable by any injected script (XSS exfiltration). In-memory is lost on reload, so you re-acquire it via refresh below.
- **Refresh:** access tokens are short-lived. On a `401`, call `/refresh` (its refresh token ideally in an httpOnly cookie), store the new access token, and retry. If the refresh token also lives in JS, it's XSS-exposed too - the inherent weakness of the pure-token model.
- **Claims without `/me`:** because the token is readable in JS, you can decode its payload (e.g. with `jwt-decode`) for `roles`/`groups` directly - no `/me` round trip (the OIDC "decode the ID token" pattern below). The cookie model can't do this, which is why it needs `/me`.
- **Validation is the API's job:** the SPA only *reads* claims for UI gating; the API *verifies* the token's signature and claims on every request. Never trust a client-side decode for authorization.

### Origin Topology (CDN / S3 + CloudFront)

Serving the SPA from a CDN does **not** force cross-origin. Front both with one CloudFront distribution and route by path, so the browser sees a single origin (httpOnly `SameSite=Lax` cookies, zero CORS):

```text
CloudFront (app.example.com)
  /api/*  -> origin: Go API (ALB / API GW / Lambda)   [no caching, forward cookies]
  /*      -> origin: S3 bucket (static SPA)            [cached, immutable assets]
```

Config gotchas: the `/api/*` behavior must forward cookies and disable caching; static assets stay cached. Fallbacks when origins can't be unified:

- **Sibling subdomains** (`app.` + `api.example.com`): set cookie `Domain=example.com`, `SameSite=Lax`. Cross-origin but *same-site* - cookie still sent.
- **Truly cross-site** (different registrable domains): `SameSite=None; Secure` + CORS with `Access-Control-Allow-Credentials: true`, an exact allowed origin, and `credentials: 'include'`. Avoid - third-party cookies are being deprecated/partitioned.

### Knowing Auth State: `['me']` as a Query

No server hook means the SPA learns its state at runtime by hitting an authenticated endpoint. TanStack Query is the natural home - one cached, shared source of truth, with `isPending` as the boot "checking auth" state:

```ts
// src/lib/auth.ts
import { queryOptions } from '@tanstack/svelte-query'
export const meQuery = () => queryOptions({
  queryKey: ['me'],
  queryFn: async () => {
    const r = await fetch('/api/me', { credentials: 'include' })
    if (r.status === 401) return null          // known logged-out (cacheable)
    if (!r.ok) throw new Error('auth check failed')
    return r.json()                            // { id, name, roles: [...] }
  },
  staleTime: 5 * 60_000
})
```

### Guarding Routes

Use route groups and guard in the protected group's universal `+layout.ts`. `ensureQueryData` fetches `/me` once and serves cache thereafter:

```ts
// src/routes/(app)/+layout.ts
import { redirect } from '@sveltejs/kit'
import { queryClient } from '$lib/query'
import { meQuery } from '$lib/auth'
export const load = async () => {
  const user = await queryClient.ensureQueryData(meQuery())
  if (!user) redirect(303, '/login')           // client-side (UX) redirect
  return { user }
}
```

The guard mounts after the shell, so direct navigation flashes briefly before redirecting (no protected *data* loads - the API 401s). For zero flash, also gate rendering with `{#if user}` in the layout component.

### Per-Navigation: No Repeated `/me`

`ensureQueryData` returns cached data without fetching (it ignores `staleTime`), and a dependency-free layout load won't re-run between sibling pages - so navigating is **zero `/me` calls**. You don't need per-navigation checks because **every data request re-validates the cookie at the API**; session expiry surfaces as a 401 on the next call:

```ts
// src/lib/query.ts - global 401 handler
new QueryClient({
  queryCache: new QueryCache({
    onError: (err) => {
      if (err?.status === 401) { queryClient.setQueryData(['me'], null); goto('/login') }
    }
  }),
  defaultOptions: { queries: { staleTime: 30_000 } }
})
```

Optionally set `refetchOnWindowFocus` on `['me']` to re-validate when the user returns to the tab.

### Login & Logout

Login/logout are mutations; on logout, `clear()` scrubs cached private data so it can't be read afterward:

```ts
// login: createMutation(() => ({ mutationFn: postCreds, onSuccess: () => queryClient.invalidateQueries({ queryKey: ['me'] }) }))
async function logout() {
  await fetch('/api/logout', { method: 'POST', credentials: 'include' })
  queryClient.clear()
  goto('/login')
}
```

### Reading Authorization Data (Groups/Roles)

With httpOnly cookies the SPA *can't* read the credential - that's the point. Get claims from the **`/me` payload**, not the cookie: the API returns non-sensitive identity + roles, you cache them in `['me']`, and gate UI on them. An admin route guard mirrors the auth guard:

```ts
// src/routes/(admin)/+layout.ts
const user = await queryClient.ensureQueryData(meQuery())
if (!user?.roles.includes('admin')) redirect(303, '/forbidden')
```

This is UX only - admin API endpoints check the role server-side on every request. Roles can go stale if a user is demoted mid-session (UI lags, but the API already rejects them); `refetchOnWindowFocus` / a short `staleTime` converges it.

### OIDC: Token-in-Browser vs BFF

> **Decision:** pure static hosting with no backend → token-in-browser (with mitigations). Already have an API server, or the app is security-sensitive (PII, admin, financial) → BFF.

OIDC (Cognito, Auth0, Okta, Entra, Keycloak) issues an **ID token** (JWT, client-readable claims incl. groups), an **access token** (the API credential), and a refresh token. "Decode the ID token for groups" is real and common - but it's one of two models, and the choice is the same cookie-vs-token tradeoff:

| | Token-in-browser (public client + PKCE) | BFF (server runs OIDC) |
| --- | --- | --- |
| Where tokens live | Browser (JS) | Server session - never in browser |
| Read groups via | decode ID token in JS | `/me` payload (BFF extracts the claim) |
| API credential | access token as Bearer | session cookie -> BFF attaches access token |
| XSS risk | token exfiltration | cookie can't be stolen |
| Infra | pure static SPA + IdP SDK | needs a backend (your API) |

The BFF model is just the httpOnly-cookie design above with OIDC upstream - the browser never sees a JWT:

```text
Browser --/auth/login--> BFF --redirect--> IdP
Browser <-set httpOnly cookie- BFF <-code+PKCE -> tokens- IdP (callback)
Browser --/api/* (cookie)--> BFF --Bearer access token--> resources
```

It composes with the CloudFront topology (`/auth/*` + `/api/*` -> backend, `/*` -> S3), and groups still arrive via `/me`, so the SPA code is identical to the cookie model.

Both have a place: **token-in-browser** suits pure-static SPAs with no backend (accept the XSS tradeoff plus mitigations - short-lived tokens, rotating refresh, strict CSP); **BFF** suits anything security-sensitive or that already has an API server. One rule for both: **never send the ID token to your API** - its audience is the client; APIs validate the access token (token model) or the session cookie (BFF).

---

## 11. Content Security Policy in a SPA

A pure SPA can't use CSP **nonces** - they must be minted per request by a server, and a static SPA has none. Use **hashes** instead, computed at build.

In practice most of your code is **external bundles** (`<script src>`), already covered by `script-src 'self'` - hashes only matter for the small inline scripts SvelteKit emits (its bootstrap + serialized data). SvelteKit hashes those for you:

```js
// svelte.config.js
kit: { csp: { mode: 'auto', directives: { 'script-src': ['self'] } } }
```

With `adapter-static`, `mode: 'auto'` resolves to **hash** (it picks hashes for prerendered pages, nonces for SSR). Since there's no server to set a response header, SvelteKit injects the policy as a `<meta>` tag in the prerendered HTML.

Two things `<meta>` can't carry - `frame-ancestors` and reporting - plus HSTS and the other security headers must be set as real response headers on your **CDN/host** (CloudFront response-headers policy, Netlify `_headers`, nginx). If the build emits no inline scripts at all, plain `script-src 'self'` is enough and you need no hashes.

> Full treatment of CSP directives, source values, and the nonce-vs-hash mechanics: [Browser Security & Caching](/browser-security-and-caching/#2-security-headers).

---

## 12. Version Gotchas & Setup

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
- [SvelteKit Auth (best practices)](https://svelte.dev/docs/kit/auth)
- [OAuth 2.0 for Browser-Based Apps (IETF BCP)](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-browser-based-apps)
