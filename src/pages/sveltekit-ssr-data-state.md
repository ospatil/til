---
layout: ../layouts/GistLayout.astro
---

# SvelteKit SSR, Data Loading & State

A reference covering SvelteKit architecture, request flows, SSR, data loading patterns, mutations, Svelte 5 components, and state management.

---

## Table of Contents

1. [Architecture & Request Flow](#1-architecture--request-flow)
2. [Hooks](#2-hooks)
3. [Load Functions](#3-load-functions)
4. [Streaming & Deferred Data](#4-streaming--deferred-data)
5. [Data Invalidation](#5-data-invalidation)
6. [Form Actions](#6-form-actions)
7. [API Routes (+server.ts)](#7-api-routes-serverts)
8. [Error Handling](#8-error-handling)
9. [Page Options](#9-page-options)
10. [Remote Functions (Experimental)](#10-remote-functions-experimental)
11. [SSR Gotchas](#11-ssr-gotchas)
12. [Components & Props](#12-components--props)
13. [Snippets & {@render}](#13-snippets--render)
14. [State Management](#14-state-management)
15. [Derived State & Effects](#15-derived-state--effects)

---

## 1. Architecture & Request Flow

### Key Files Overview

| File                | Location              | Runs On     | Purpose                               |
| ------------------- | --------------------- | ----------- | ------------------------------------- |
| `hooks.server.ts`   | `src/hooks.server.ts` | Server only | Intercepts every server request       |
| `hooks.client.ts`   | `src/hooks.client.ts` | Client only | Client-side error handling (optional) |
| `hooks.ts`          | `src/hooks.ts`        | Both        | Universal hooks (reroute, transport)  |
| `+layout.server.ts` | Route directories     | Server only | Server-side layout data loading       |
| `+layout.ts`        | Route directories     | Both        | Universal layout data loading         |
| `+layout.svelte`    | Route directories     | Both        | Layout UI component                   |
| `+page.server.ts`   | Route directories     | Server only | Server-side page data loading         |
| `+page.ts`          | Route directories     | Both        | Universal page data loading           |
| `+page.svelte`      | Route directories     | Both        | Page UI component                     |

### SSR vs CSR Summary

| Aspect                   | SSR (Initial Load)  | CSR (Navigation)          |
| ------------------------ | ------------------- | ------------------------- |
| Server hooks.server.ts   | Runs                | Runs (for data fetch)     |
| Server load functions    | On server           | On server (via fetch)     |
| Universal load functions | On server           | In browser                |
| Component rendering      | On server to HTML   | In browser to DOM         |
| onMount()                | Not on server       | For new components        |
| Hydration                | After HTML loads    | Not needed                |
| Layout reuse             | Full render         | Unchanged layouts kept    |

### Initial SSR Request Flow

When a user first visits a page (full page load):

```text
Browser sends GET request
         |
         v
[SERVER]
  1. hooks.ts -> reroute()                     [runs FIRST, can rewrite URL paths]
  2. hooks.server.ts -> handle()               [every request, sets event.locals]
  3. Route matching                            [identifies layouts in hierarchy]
  4. Server load functions (parallel)          [+layout.server.ts, +page.server.ts]
  5. Universal load functions (on server)      [+layout.ts, +page.ts]
  6. Component rendering to HTML string
  7. HTML + serialized data + JS bundles sent
         |
         v
[BROWSER]
  8. HTML immediately visible
  9. JS bundles load, hooks.client.ts -> init()
 10. Svelte hydrates (attaches event listeners)
 11. Universal load functions reuse SSR fetch responses
 12. onMount() callbacks execute
 13. Page is interactive
```

### Client-Side Navigation Flow

When user clicks a link (after initial load):

```text
User clicks link
         |
         v
[BROWSER]
  1. hooks.ts -> reroute() (cached per URL)
  2. Route matching (determines what needs to rerun)
         |
         v
[SERVER]
  3a. Browser fetches __data.json endpoint
      hooks.server.ts -> handle() runs
      Server load functions execute, return JSON
         |
         v
[BROWSER]
  3b. Universal load functions run in browser
  4. Only new/changed components render
  5. onMount() runs for NEW components only
  6. URL updates via History API
```

### Data Flow Between Load Functions

```text
                SERVER                            CLIENT
                                                  
+layout.server.ts                                 
  return { user: ... }                            
         |                                        
         v                                        
+layout.ts                                        
  load({ data, fetch }) {                         Same code runs here
    // data = { user } from server                during navigation
    return { ...data, extra }                     
  }                                               
         |                                        
         v                                        
+page.server.ts                                   
  return { dashboard: ... }                       
         |                                        
         v                                        
+page.svelte                                      
  let { data } = $props()                         
  // data = { user, extra, dashboard }            
```

---

## 2. Hooks

### hooks.server.ts (Server Hooks)

Runs on the server for every request. Available exports:

| Export        | Purpose                                                   |
| ------------- | --------------------------------------------------------- |
| `handle`      | Intercepts every request, modifies request/response       |
| `handleFetch` | Modify fetch calls made during SSR                        |
| `handleError` | Custom server-side error handling                         |
| `init`        | Runs once when server starts                              |

```typescript
import type { Handle, HandleServerError } from '@sveltejs/kit'

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.user = await getUser(event.cookies)
  return resolve(event)
}

export const handleError: HandleServerError = ({ error, event }) => {
  console.error(error)
  return { message: 'Something went wrong' }
}
```

### Chaining Handle Functions with `sequence`

```typescript
import { sequence } from '@sveltejs/kit/hooks'
import type { Handle } from '@sveltejs/kit'

const logger: Handle = async ({ event, resolve }) => {
  const start = Date.now()
  const response = await resolve(event)
  console.log(`${event.request.method} ${event.url.pathname} - ${Date.now() - start}ms`)
  return response
}

const auth: Handle = async ({ event, resolve }) => {
  const sessionId = event.cookies.get('session')
  if (sessionId) {
    event.locals.user = await getUserFromSession(sessionId)
  }
  return resolve(event)
}

const authorize: Handle = async ({ event, resolve }) => {
  if (event.url.pathname.startsWith('/admin') && !event.locals.user?.isAdmin) {
    return new Response('Forbidden', { status: 403 })
  }
  return resolve(event)
}

export const handle = sequence(logger, auth, authorize)
```

Each handler MUST call `resolve(event)` to continue the chain, or return a Response directly to short-circuit.

### hooks.client.ts (Client Hooks)

Runs in the browser only. Limited exports:

| Export        | Purpose                              |
| ------------- | ------------------------------------ |
| `handleError` | Custom client-side error handling    |
| `init`        | Runs once when app starts in browser |

There is NO `handle` function for client hooks.

### hooks.ts (Universal Hooks)

| Export      | Purpose                                                   |
| ----------- | --------------------------------------------------------- |
| `reroute`   | Rewrite URL paths before routing (e.g., i18n)             |
| `transport` | Custom serialization for server/client boundary           |

```typescript
import type { Reroute } from '@sveltejs/kit'

export const reroute: Reroute = ({ url }) => {
  if (url.pathname === '/de/ueber-uns') return '/en/about'
}

export const transport = {
  Date: {
    encode: value => value instanceof Date && value.toISOString(),
    decode: value => new Date(value)
  }
}
```

`reroute` runs FIRST before any other hooks, does NOT change the browser URL, and results are cached per unique URL on the client.

---

## 3. Load Functions

### Server vs Universal Load Functions

| Aspect                  | `.server.ts` (Server Load)         | `.ts` (Universal Load)              |
| ----------------------- | ---------------------------------- | ----------------------------------- |
| Runs on                 | Server only                        | Server during SSR, client on nav    |
| Access to               | DB, secrets, `event.locals`        | `fetch`, public APIs                |
| Code shipped to client  | No                                 | Yes                                 |
| During client nav       | Called via internal `__data.json`   | Runs directly in browser            |

### Execution Order

**During SSR (all on server):**
```text
1. +layout.server.ts (root)          -+
2. +layout.server.ts (nested)         | Server loads (PARALLEL unless await parent())
3. +page.server.ts                   -+
                |
                v
4. +layout.ts (root)                 -+
5. +layout.ts (nested)                | Universal loads (on SERVER during SSR)
6. +page.ts                          -+
                |
                v
7. Components render with merged data
```

**During Client Navigation:**
```text
1-3. Server loads run on SERVER via fetch (batched into single __data.json request)
                | (JSON response)
                v
4-6. Universal loads run in BROWSER
                |
                v
7. Components update in BROWSER
```

### SvelteKit's Special fetch

SvelteKit provides a special `fetch` in load functions:

| Feature                      | Description                                            |
| ---------------------------- | ------------------------------------------------------ |
| Direct invocation during SSR | Internal API routes called directly without HTTP       |
| Credential preservation      | Automatically forwards cookies for same-origin         |
| Response deduplication       | During hydration, reuses SSR responses                 |
| Relative URL support         | Works with relative URLs on the server                 |

Even when `fetch` calls an internal endpoint directly during SSR (no HTTP), the request still passes through `hooks.server.ts -> handle()`.

```text
During SSR:
  +page.ts calls fetch('/api/data')
    -> SvelteKit intercepts, NO HTTP request
    -> Directly invokes /api/data/+server.ts
    -> STILL goes through hooks.server.ts -> handle()

During Client Navigation:
  +page.ts calls fetch('/api/data')
    -> Normal HTTP request over the network
    -> hooks.server.ts -> handle() runs on server
```

### Parallel vs Sequential Execution

By default, all load functions run in parallel. Use `await parent()` only when you need parent data:

```typescript
// PARALLEL (default) - faster
export async function load({ params }) {
  const data = await getData(params)
  return { data }
}

// SEQUENTIAL - only when you need parent data
export async function load({ params, parent }) {
  const [parentData, data] = await Promise.all([
    parent(),
    getData(params)
  ])
  return { ...parentData, data }
}
```

| Use Case                     | Recommendation                          |
| ---------------------------- | --------------------------------------- |
| Need data from parent layout | Use `await parent()`                    |
| Auth check before fetching   | Use `await parent()` to get user first  |
| Independent data fetching    | Don't use `parent()`                    |
| Need parent data + own data  | Use `Promise.all([parent(), getData()])` |

### When Load Functions Rerun

| Trigger                   | Server Load             | Universal Load                |
| ------------------------- | ----------------------- | ----------------------------- |
| Initial page load (SSR)   | Server                  | Server, then Client (hydrate) |
| Client navigation         | Via fetch               | Client                        |
| `params` change           | If depends on params    | If depends on params          |
| `url.searchParams` change | If accessed             | If accessed                   |
| `invalidate(url)`         | If depends on url       | If depends on url             |
| `invalidateAll()`         | Always                  | Always                        |
| Parent load reruns        | If calls `parent()`     | If calls `parent()`           |

### Universal Load Function Behavior

Universal loads run in **either** context depending on how the page was reached:

- **Direct visit (SSR):** Runs on server only. Data serialized to client. Does NOT re-run during hydration.
- **Client navigation:** Runs in browser only. Fetches data client-side.

```typescript
// +page.ts - runs on server OR client, never both for the same request
export async function load({ fetch }) {
  const posts = await fetch('/api/posts').then(r => r.json())
  return { posts }
}
```

### Bypassing HTTP for Internal Data

When `+page.server.ts` needs the same data as an API route, call the shared function directly instead of fetching:

```typescript
// lib/posts.server.ts
export async function getPosts(userId?: string) {
  return db.posts.where('userId', userId).findAll()
}

// routes/api/posts/+server.ts (external clients use this)
import { getPosts } from '$lib/posts.server'
export async function GET({ locals }) {
  return json({ posts: await getPosts(locals.user?.id) })
}

// routes/blog/+page.server.ts (internal - skip HTTP layer)
import { getPosts } from '$lib/posts.server'
export async function load({ locals }) {
  return { posts: await getPosts(locals.user?.id) }
}
```

---

## 4. Streaming & Deferred Data

Load functions can return unresolved promises. The page renders immediately with available data while slow queries stream in progressively.

### Returning Promises (No Await)

```typescript
// +page.server.ts
export async function load() {
  return {
    // Resolved immediately — blocks rendering
    post: await db.posts.findOne(),

    // Streamed — page renders before these resolve
    comments: db.comments.findAll(),        // Note: no await!
    relatedPosts: db.posts.findRelated()
  }
}
```

```svelte
<!-- +page.svelte -->
<script>
  let { data } = $props()
</script>

<!-- Available immediately -->
<article>
  <h1>{data.post.title}</h1>
  <p>{data.post.content}</p>
</article>

<!-- Streams in progressively -->
{#await data.comments}
  <p>Loading comments...</p>
{:then comments}
  {#each comments as comment}
    <div>{comment.text}</div>
  {/each}
{:catch error}
  <p>Error loading comments</p>
{/await}

{#await data.relatedPosts}
  <p>Loading related...</p>
{:then posts}
  {#each posts as post}
    <a href="/blog/{post.slug}">{post.title}</a>
  {/each}
{/await}
```

### When to Stream

| Data Type               | Approach        | Reason                              |
| ----------------------- | --------------- | ----------------------------------- |
| SEO-critical content    | `await` (block) | Must be in initial HTML             |
| Page title, main body   | `await` (block) | Needed for meaningful first paint   |
| Comments, related items | Stream (no await) | Non-essential, can load after       |
| Analytics, recommendations | Stream       | Slow queries shouldn't block render |

### Nested Layouts and Streaming

Streamed data from layout load functions works the same way — child pages render immediately while layout data streams in:

```typescript
// +layout.server.ts
export async function load() {
  return {
    user: await getUser(),                // blocks (needed for nav)
    notifications: getNotifications()     // streams (sidebar indicator)
  }
}
```

---

## 5. Data Invalidation

### Triggers for Load Function Re-execution

| Trigger                | Scope      | Use Case                      |
| ---------------------- | ---------- | ----------------------------- |
| Navigation             | Automatic  | New params / different route  |
| Search params change   | Automatic  | Query string changes          |
| Form actions           | Automatic  | After form submission         |
| `invalidate(key)`      | Selective  | Refresh specific dependencies |
| `invalidate(url)`      | Selective  | Refresh specific API calls    |
| `invalidateAll()`      | Everything | Nuclear refresh               |

### Custom Dependencies with `depends()`

```typescript
// +page.server.ts
export async function load({ depends }) {
  depends('app:posts')
  return { posts: await db.posts.findAll() }
}
```

```svelte
<script>
  import { invalidate } from '$app/navigation'

  async function refreshPosts() {
    await invalidate('app:posts')
  }
</script>
```

### URL-based Invalidation

SvelteKit automatically tracks URLs used in `fetch` as dependencies:

```typescript
export async function load({ fetch }) {
  const stats = await fetch('/api/stats').then(r => r.json())
  return { stats }
}
```

```svelte
<script>
  import { invalidate } from '$app/navigation'
  // Re-runs load functions that fetched from /api/stats
  await invalidate('/api/stats')
</script>
```

### Polling Pattern

```svelte
<script>
  import { invalidate } from '$app/navigation'
  import { onMount } from 'svelte'

  onMount(() => {
    const interval = setInterval(() => invalidate('dashboard:metrics'), 10000)
    return () => clearInterval(interval)
  })
</script>
```

### When NOT to Invalidate

- Client-only state changes (just update `$state`)
- Data that can be filtered client-side (use `$derived`)

---

## 6. Form Actions

Form actions are server-side functions that handle form submissions. They work without JavaScript (progressive enhancement).

### Basic Structure

```typescript
// +page.server.ts
import { fail, redirect } from '@sveltejs/kit'

export const actions = {
  create: async ({ request }) => {
    const data = await request.formData()
    const title = data.get('title')?.toString()

    if (!title || title.length < 3) {
      return fail(400, { error: 'Title must be at least 3 characters', title })
    }

    await db.posts.create({ title })
    return { success: true }
  },

  delete: async ({ request }) => {
    const data = await request.formData()
    await db.posts.delete(data.get('id'))
    redirect(303, '/posts')
  }
}
```

```svelte
<script>
  import { enhance } from '$app/forms'
  let { form } = $props()
</script>

<form method="POST" action="?/create" use:enhance>
  <input name="title" value={form?.title ?? ''} />
  <button>Create</button>
  {#if form?.error}
    <p class="error">{form.error}</p>
  {/if}
</form>
```

### Action Return Types

| Return              | Effect                                  |
| ------------------- | --------------------------------------- |
| `{ success: true }` | Data available via `form` prop          |
| `fail(400, data)`   | Stays on page, data in `form` prop      |
| `redirect(303, url)` | Navigates to URL                       |
| `error(401, msg)`   | Shows error page                        |

### Custom `use:enhance` Callbacks

```svelte
<form
  method="POST"
  use:enhance={() => {
    loading = true
    return async ({ result, update }) => {
      loading = false
      if (result.type === 'success') showToast('Done!')
      await update()
    }
  }}
>
```

### Key Behaviors

- Actions auto-invalidate load functions (no manual invalidation needed)
- Access action responses via `let { form } = $props()`
- `use:enhance` makes it SPA-like; without it, full page reload
- Multiple forms on one page can target different named actions

---

## 7. API Routes (+server.ts)

API routes handle HTTP requests directly. They live alongside page routes and support all HTTP methods.

### Basic API Route

```typescript
// src/routes/api/posts/+server.ts
import { json, error } from '@sveltejs/kit'
import type { RequestHandler } from './$types'

export const GET: RequestHandler = async ({ url, locals }) => {
  const limit = Number(url.searchParams.get('limit') ?? 10)
  const posts = await db.posts.findAll({ limit, userId: locals.user?.id })
  return json(posts)
}

export const POST: RequestHandler = async ({ request, locals }) => {
  if (!locals.user) error(401, 'Unauthorized')

  const { title, body } = await request.json()
  const post = await db.posts.create({ title, body, authorId: locals.user.id })
  return json(post, { status: 201 })
}
```

### Dynamic Route Parameters

```typescript
// src/routes/api/posts/[id]/+server.ts
export const GET: RequestHandler = async ({ params }) => {
  const post = await db.posts.findById(params.id)
  if (!post) error(404, 'Not found')
  return json(post)
}

export const DELETE: RequestHandler = async ({ params, locals }) => {
  if (!locals.user) error(401, 'Unauthorized')
  await db.posts.delete(params.id)
  return new Response(null, { status: 204 })
}
```

### Response Types

```typescript
import { json, text, redirect, error } from '@sveltejs/kit'

// JSON response
return json({ data: 'value' })

// Custom headers
return json(data, {
  headers: { 'Cache-Control': 'max-age=60' }
})

// Plain text
return new Response('Hello', {
  headers: { 'Content-Type': 'text/plain' }
})

// Redirect
redirect(307, '/new-location')

// Error
error(404, 'Not found')
```

### When to Use API Routes vs Load Functions

| Use Case                        | Use                  |
| ------------------------------- | -------------------- |
| Page needs data for SSR         | Load function        |
| External clients need endpoint  | API route            |
| Webhooks, third-party callbacks | API route            |
| Form mutations                  | Form actions         |
| Shared data between page + API  | Shared lib function  |

---

## 8. Error Handling

### Error Types

| Type       | Cause                            | How it's handled                    |
| ---------- | -------------------------------- | ----------------------------------- |
| Expected   | `error(status, message)` thrown  | Shows `+error.svelte` with message  |
| Unexpected | Unhandled exception              | Shows `+error.svelte`, generic msg  |

### Throwing Expected Errors

```typescript
import { error } from '@sveltejs/kit'

export async function load({ params }) {
  const post = await db.posts.findById(params.id)
  if (!post) error(404, 'Post not found')
  return { post }
}
```

### +error.svelte Pages

Error boundaries that catch errors from load functions and rendering. SvelteKit walks up the layout tree to find the nearest `+error.svelte`:

```svelte
<!-- src/routes/+error.svelte (root error page) -->
<script>
  import { page } from '$app/state'
</script>

<h1>{page.status}</h1>
<p>{page.error?.message}</p>
```

### Error Boundary Hierarchy

```text
src/routes/
├── +layout.svelte          # If THIS errors, no +error.svelte can catch it
├── +error.svelte           # Catches errors from child routes
├── blog/
│   ├── +error.svelte       # Catches blog-specific errors
│   ├── +page.svelte        # Error here → caught by blog/+error.svelte
│   └── [slug]/
│       └── +page.svelte    # Error here → caught by blog/+error.svelte
└── admin/
    └── +page.svelte        # Error here → caught by root +error.svelte
```

If a root layout errors, there's no `+error.svelte` that can render (since it's inside the layout). Use `handleError` hooks for logging in that case.

### handleError Hooks

Customize error handling and logging:

```typescript
// hooks.server.ts
export function handleError({ error, event, status, message }) {
  console.error(error)

  // Return a safe error object (never expose internals)
  return {
    message: status === 404 ? 'Not found' : 'Internal error',
    code: crypto.randomUUID()  // correlation ID for support
  }
}
```

```typescript
// hooks.client.ts
export function handleError({ error, event, status, message }) {
  Sentry.captureException(error)
  return { message: 'Something went wrong' }
}
```

The object returned from `handleError` becomes `page.error` in `+error.svelte`.

### Error Shape

You can type the error object in `app.d.ts`:

```typescript
// src/app.d.ts
declare global {
  namespace App {
    interface Error {
      message: string
      code?: string
    }
  }
}
```

---

## 9. Page Options

| Option          | Default   | Description                                       |
| --------------- | --------- | ------------------------------------------------- |
| `ssr`           | `true`    | Whether to server-render the page                 |
| `csr`           | `true`    | Whether to load the SvelteKit client (hydration)  |
| `prerender`     | `false`   | Whether to generate static HTML at build time     |
| `trailingSlash` | `'never'` | How to handle trailing slashes                    |

```typescript
// +page.ts or +layout.ts
export const ssr = false   // SPA mode
export const csr = true
export const prerender = false
```

### Combinations

| Combination                   | Result                                |
| ----------------------------- | ------------------------------------- |
| `ssr: true, csr: true`        | Default - full SSR with hydration     |
| `ssr: false, csr: true`       | SPA mode - client-only rendering      |
| `ssr: true, csr: false`       | Static HTML - no JavaScript           |
| `prerender: true, ssr: true`  | Static at build time, with hydration  |
| `prerender: true, csr: false` | Fully static pages (no JS)            |

### Decision Guide

```text
              Need SEO?
                 |
         +-------+-------+
         |               |
        YES             NO -> ssr = false (SPA mode)
         |
   Content changes
   frequently?
         |
    +----+----+
    |         |
   YES       NO -> prerender = true (static generation)
    |
ssr = true (default)
```

Options set in `+layout.ts` are inherited by all child pages (children can override).

---

## 10. Remote Functions (Experimental)

SvelteKit 2.27+ introduces remote functions: type-safe RPC-style communication. Declared in `.remote.ts` files, they always execute on the server but can be called like regular functions.

**Status:** Still experimental as of SvelteKit 2.60+. Not subject to semver — breaking changes can ship in any release. The API has evolved significantly since introduction.

### Four Core Types

| Type        | Purpose                    | Progressive Enhancement | Use Case                   |
| ----------- | -------------------------- | ----------------------- | -------------------------- |
| `query`     | Read dynamic data          | N/A                     | Fetching posts, user data  |
| `form`      | Write data via forms       | Works without JS        | Creating/updating records  |
| `command`   | Write data programmatically | Requires JS            | Like buttons, quick actions |
| `prerender` | Read static data at build  | N/A                     | Per-deployment data        |

### Additional Query APIs (Added Post-2.27)

| API             | Version | Purpose                                              |
| --------------- | ------- | ---------------------------------------------------- |
| `query.batch`   | 2.35    | Batches requests within same macrotask (solves n+1)  |
| `query.run()`   | 2.56    | One-off imperative access bypassing the cache        |
| `query.live`    | 2.59    | Real-time data via AsyncIterable with auto-reconnect |
| `invalid()`     | 2.47    | Throws field-specific or form-wide validation errors |

### Basic Example

```typescript
// src/routes/blog/data.remote.ts
import { command, form, query } from '$app/server'
import * as db from '$lib/server/database'
import * as v from 'valibot'

export const getPosts = query(async () => {
  return await db.sql`SELECT * FROM posts`
})

export const getPost = query(v.string(), async (slug) => {
  return await db.sql`SELECT * FROM posts WHERE slug = ${slug}`
})

export const createPost = form(
  v.object({ title: v.pipe(v.string(), v.nonEmpty()) }),
  async ({ title }) => {
    await db.sql`INSERT INTO posts (title) VALUES (${title})`
  }
)
```

### Single-Flight Mutations

`form` and `command` can combine mutation + data refresh in one request:

```typescript
// Mutation that also refreshes related queries
const result = await deletePost(postId).updates(getPosts)
```

### Remote Functions vs Load Functions

Remote functions are **complementary to load functions, not a replacement**. The SvelteKit team has explicitly stated load functions continue as a core concept with no deprecation planned.

| Scenario                             | Load Functions | Remote Functions |
| ------------------------------------ | -------------- | ---------------- |
| Page-level data needed before render | Preferred      | Works            |
| SEO-critical data in initial HTML    | Preferred      | Works with SSR   |
| Component-level data fetching        | Awkward        | Preferred        |
| Interactive features                 | Requires +server.ts | Preferred   |
| Native TypeScript (no `$types`)      | No             | Yes              |
| Real-time data streams               | Not supported  | `query.live`     |
| Sub-page granular refetching         | Route-level only | Per-component  |

Remote functions address load function pain points (colocation, granularity, type safety, mutations) but load functions remain the right choice for route-level data orchestration.

### Are They API Endpoints?

**No.** Remote functions generate HTTP endpoints at framework-managed URLs (`/_app/remote/...`), but these are **not designed for external consumption**:

- The URL structure is an implementation detail — no stable contract
- Wire format uses **devalue** (not JSON) — supports `Date`, `Map`, `Set` but external clients can't easily consume it
- No versioning or API documentation support

For external APIs (mobile apps, third-party services), use `+server.ts` routes.

### Can They Be Private?

**No.** Every exported function from a `.remote.ts` file generates a reachable HTTP endpoint. There is no "private" mode.

- `.remote.ts` files **cannot** be placed in `src/lib/server/` — the framework prohibits this
- Security is imperative, not structural — check auth inside the function body

```typescript
import { getRequestEvent } from '$app/server'
import { error } from '@sveltejs/kit'

export const getSecretData = query(async () => {
  const event = getRequestEvent()
  if (!event.locals.user) error(401, 'Unauthorized')
  return await db.secrets.findAll()
})
```

For truly private server-only logic (no HTTP endpoint), use regular modules in `$lib/server/` and call them from load functions, hooks, or `+server.ts`.

### SSR Behavior

During SSR, remote functions execute **directly in-process** — no HTTP round-trip (same optimization as SvelteKit's special `fetch` with `+server.ts`). Results are serialized into the HTML payload, so the client doesn't re-request during hydration.

### Coexisting with +server.ts Routes

Remote functions and API routes serve different purposes and don't conflict. For shared logic:

```typescript
// $lib/server/posts.ts — shared core logic
export async function getPosts(userId?: string) {
  return db.posts.findAll({ where: { userId } })
}

// routes/blog/data.remote.ts — for SvelteKit app's internal use
import { query } from '$app/server'
import { getPosts } from '$lib/server/posts'
import { getRequestEvent } from '$app/server'

export const posts = query(async () => {
  const { locals } = getRequestEvent()
  return getPosts(locals.user?.id)
})

// routes/api/posts/+server.ts — for external clients (REST API)
import { json } from '@sveltejs/kit'
import { getPosts } from '$lib/server/posts'

export async function GET({ locals }) {
  return json(await getPosts(locals.user?.id))
}
```

### Enabling

```javascript
// svelte.config.js
export default {
  kit: {
    experimental: { remoteFunctions: true }
  },
  compilerOptions: {
    experimental: { async: true }  // Required: enables await in components
  }
}
```

Both flags are required. Always validate arguments with Standard Schema (Valibot, Zod) since endpoints are publicly accessible.

### Notable Breaking Changes

| Version | Change                                                         |
| ------- | -------------------------------------------------------------- |
| 2.56    | Reworked client-driven refresh; added `run()` method to queries |
| 2.58    | `requested` yields `{ arg, query }` instead of raw argument   |
| 2.59    | Server-side `refresh` promise semantics changed                |

If adopting remote functions, pin your SvelteKit version and review changelogs before upgrading.

---

## 11. SSR Gotchas

### State Leak Prevention

Module-level state persists across requests on the server. This is one of the most persistently dangerous footguns in SvelteKit — user-specific data stored in a module-level variable can **leak between different users' requests**.

```typescript
// stores/counter.svelte.ts
function createCounter() {
  let count = $state(0)
  return { get count() { return count }, increment: () => count++ }
}

export const counter = createCounter() // DANGER: shared across all requests!
```

```text
Request A (User Alice):
  imports counter -> gets cached module instance
  counter.increment() -> count = 1

Request B (User Bob):
  imports counter -> gets SAME cached instance
  counter.count is ALREADY 1 (Alice's data!) <- STATE LEAK
```

This affects **any** global mutable state on the server — not just Svelte stores or runes. Any shared variable in a module is a potential leak vector.

| State Location         | Created Per            | Shared Across Requests | Safe for SSR |
| ---------------------- | ---------------------- | ---------------------- | ------------ |
| `$state` in components | Component instance     | No                     | Yes          |
| Module-level singleton | Module load (once)     | Yes                    | **No**       |
| Context-based store    | Component tree         | No                     | Yes          |
| `event.locals`         | Request                | No                     | Yes          |

**Why this persists:** There is no framework-level solution that automatically sandboxes module state per request. The fundamental Node.js module caching behavior hasn't changed. Developers must be aware of this and choose the right pattern.

See: [sveltejs/kit#4339](https://github.com/sveltejs/kit/discussions/4339), [sveltejs/svelte#12947](https://github.com/sveltejs/svelte/discussions/12947)

### Safe Patterns for Shared State in SSR

#### Pattern 1: Context API (Recommended)

Scopes state per component tree (and thus per request during SSR):

```typescript
// stores/my-store.svelte.ts
import { getContext, setContext } from 'svelte'

const MY_STORE_KEY = Symbol('myStore')

function createMyStore() {
  let value = $state('')
  return {
    get value() { return value },
    set value(v: string) { value = v }
  }
}

export function setMyStore() {
  const store = createMyStore()
  setContext(MY_STORE_KEY, store)
  return store
}

export function getMyStore() {
  return getContext<ReturnType<typeof createMyStore>>(MY_STORE_KEY)
}
```

```svelte
<!-- +layout.svelte - Initialize ONCE at the top -->
<script lang='ts'>
  import { setMyStore } from '$lib/stores/my-store.svelte'
  let { children } = $props()
  const myStore = setMyStore()
</script>
{@render children()}
```

```svelte
<!-- Any descendant component -->
<script lang='ts'>
  import { getMyStore } from '$lib/stores/my-store.svelte'
  const myStore = getMyStore()
  const value = $derived(myStore.value)
</script>
```

**Limitation:** `setContext`/`getContext` must be called during component initialization (synchronously in the `<script>` block). You cannot call them inside `onMount`, event handlers, or async functions.

#### Pattern 2: event.locals (For Request-Scoped Server Data)

Data set in hooks is scoped per request and available in all server load functions:

```typescript
// hooks.server.ts
export const handle: Handle = async ({ event, resolve }) => {
  event.locals.user = await getUser(event.cookies)
  event.locals.theme = event.cookies.get('theme') ?? 'light'
  return resolve(event)
}

// Any +page.server.ts or +layout.server.ts
export async function load({ locals }) {
  return { user: locals.user, theme: locals.theme }
}
```

#### Pattern 3: safe-ssr (Community Solution)

The [`safe-ssr`](https://github.com/AlbertMarashi/safe-ssr) package uses `AsyncLocalStorage` to provide globally-importable stores that are automatically isolated per request. It allows module-level store declarations that behave like singletons on the client but are request-scoped on the server.

This is a community solution, not officially endorsed by Svelte.

### Decision Guide: Where to Put Shared State

| Data Type                     | Pattern                        |
| ----------------------------- | ------------------------------ |
| User session / auth           | `event.locals` + load function |
| UI state (theme, sidebar)     | Context API in root layout     |
| Global client-only state      | Module-level (SSR: false only) |
| Data needed before components | Load functions                 |
| Cross-component reactive state | Context API                   |

---

## 12. Components & Props

### Smart vs Presentational Components

- **Smart components** (pages): Own state, handle business logic, make API calls
- **Presentational components**: Receive props, emit via callbacks, never mutate external state

### Svelte 5 Callback Props Pattern

In Svelte 5, `createEventDispatcher` is deprecated. Use callback props:

```svelte
<!-- DataTable.svelte (Presentational) -->
<script>
  let {
    items = [],
    loading = false,
    onselect = () => {},
    ondelete = () => {}
  } = $props()

  function toggleSelect(user) {
    onselect(user, !isSelected(user))
  }
</script>

<table>
  {#each items as user (user.id)}
    <tr>
      <td><input type="checkbox" onchange={() => toggleSelect(user)} /></td>
      <td>{user.name}</td>
      <td><button onclick={() => ondelete(user.id)}>Delete</button></td>
    </tr>
  {/each}
</table>
```

```svelte
<!-- +page.svelte (Smart) -->
<script>
  import DataTable from '$lib/components/DataTable.svelte'
  let { data } = $props()
  let users = $state(data.users)

  function handleSelect(user, selected) {
    // business logic
  }

  function handleDelete(userId) {
    users = users.filter(u => u.id !== userId)
  }
</script>

<DataTable items={users} onselect={handleSelect} ondelete={handleDelete} />
```

### Two-Way Binding with $bindable

```svelte
<!-- NumberInput.svelte -->
<script>
  let {
    value = $bindable(0),
    min = 0,
    max = 100,
    step = 1
  } = $props()

  function increment() { if (value < max) value += step }
  function decrement() { if (value > min) value -= step }
</script>

<button onclick={decrement}>-</button>
<input type="number" bind:value {min} {max} {step} />
<button onclick={increment}>+</button>
```

```svelte
<!-- Parent -->
<script>
  let quantity = $state(1)
</script>
<NumberInput bind:value={quantity} min={1} max={10} />
```

### Context for Component Trees

Use `setContext`/`getContext` to share state without prop drilling:

```javascript
// lib/contexts/theme.svelte.js
import { getContext, setContext } from 'svelte'

const THEME_KEY = Symbol('theme')

export function createThemeContext() {
  let theme = $state('light')
  const context = {
    get theme() { return theme },
    toggleTheme() { theme = theme === 'light' ? 'dark' : 'light' }
  }
  setContext(THEME_KEY, context)
  return context
}

export function getThemeContext() {
  return getContext(THEME_KEY)
}
```

**When to use context:**
- Theme/UI state across many components
- User authentication data
- Complex multi-step form state

**When NOT to use context:**
- Simple parent-child (use props)
- Only 1-2 components need the data

### Module Scripts

`<script module>` runs once when the file is first imported (not per instance). Shared across all component instances:

```svelte
<script module>
  let totalInstances = 0
  export const COMPONENT_NAME = 'Counter'
</script>

<script>
  totalInstances++
  let count = $state(0)
</script>
```

---

## 13. Snippets & {@render}

Svelte 5 replaces slots with **snippets** — a more powerful, explicit composition model. Snippets are declared with `{#snippet}` and rendered with `{@render}`.

### Basic Snippets (Replace Slots)

```svelte
<!-- Card.svelte -->
<script>
  let { header, children } = $props()
</script>

<div class="card">
  {#if header}
    <div class="card-header">
      {@render header()}
    </div>
  {/if}
  <div class="card-body">
    {@render children()}
  </div>
</div>
```

```svelte
<!-- Usage -->
<Card>
  {#snippet header()}
    <h2>My Title</h2>
  {/snippet}

  <p>This is the default content (children).</p>
</Card>
```

### Snippets with Parameters

Snippets can receive arguments, enabling render-prop patterns:

```svelte
<!-- List.svelte -->
<script>
  let { items, renderItem, empty } = $props()
</script>

{#if items.length === 0}
  {@render empty?.()}
{:else}
  <ul>
    {#each items as item, index}
      <li>{@render renderItem(item, index)}</li>
    {/each}
  </ul>
{/if}
```

```svelte
<!-- Usage -->
<script>
  let users = $state([{ name: 'Alice', role: 'Admin' }, { name: 'Bob', role: 'User' }])
</script>

<List items={users}>
  {#snippet renderItem(user, i)}
    <span>{i + 1}. {user.name} ({user.role})</span>
  {/snippet}

  {#snippet empty()}
    <p>No users found.</p>
  {/snippet}
</List>
```

### Local Snippets (Within a Component)

Snippets can be defined locally for reuse within the same component:

```svelte
<script>
  let { data } = $props()
</script>

{#snippet userBadge(user)}
  <span class="badge" class:admin={user.role === 'admin'}>
    {user.name}
  </span>
{/snippet}

<div class="header">
  {@render userBadge(data.currentUser)}
</div>

<div class="sidebar">
  {#each data.team as member}
    {@render userBadge(member)}
  {/each}
</div>
```

### Slots to Snippets Migration

| Svelte 4 (Slots)              | Svelte 5 (Snippets)                    |
| ----------------------------- | --------------------------------------- |
| `<slot />`                    | `{@render children()}`                 |
| `<slot name="header" />`     | `{@render header()}`                   |
| `<slot prop={value} />`      | `{@render children(value)}`            |
| `let:prop` on consumer       | `{#snippet children(prop)}`            |
| `$$slots.name` check         | `{#if name}{@render name()}{/if}`      |

### Key Differences from Slots

- Snippets are **first-class values** — they can be stored in variables, passed around, conditionally chosen
- Snippets have **explicit parameter types** (TypeScript-friendly)
- Snippets are **lexically scoped** — they close over the declaring component's state
- `children` is just a prop (no special `<slot>` element)

### Typing Snippet Props

```typescript
import type { Snippet } from 'svelte'

interface Props {
  children: Snippet
  header?: Snippet
  renderItem: Snippet<[item: User, index: number]>
}

let { children, header, renderItem }: Props = $props()
```

---

## 14. State Management

### Shared State with Runes (Module-Level)

For client-only apps or state that doesn't need SSR safety:

```javascript
// stores.svelte.js
class CartStore {
  items = $state([])

  // Use getters for computed values in classes — they're reactive
  // because they read $state properties
  get total() {
    return this.items.reduce((sum, item) => sum + (item.price * item.quantity), 0)
  }

  get itemCount() {
    return this.items.reduce((sum, item) => sum + item.quantity, 0)
  }

  addItem(product) {
    const existing = this.items.find(item => item.id === product.id)
    if (existing) {
      existing.quantity += 1
    } else {
      this.items.push({ ...product, quantity: 1 })
    }
  }

  removeItem(productId) {
    this.items = this.items.filter(item => item.id !== productId)
  }

  clear() { this.items = [] }
}

export const cartStore = new CartStore()
```

Note: In classes, use native `get` accessors (not `$derived`) for computed values. The getters are reactive because they read `$state` fields. Use `$derived` in component scripts and standalone `.svelte.js` modules.

```svelte
<script>
  import { cartStore } from '$lib/stores.svelte.js'
</script>

<span>Items: {cartStore.itemCount} | Total: ${cartStore.total.toFixed(2)}</span>
<button onclick={() => cartStore.clear()}>Clear</button>
```

### State Location Decision

| Need                            | Approach                     |
| ------------------------------- | ---------------------------- |
| Component-local state           | `$state` in component        |
| Parent-child communication      | Props + callbacks            |
| Deep component tree sharing     | Context (`setContext`)       |
| Global client-side state        | Module-level class/runes     |
| SSR-safe shared state           | Context-based stores         |
| Server data for page rendering  | Load functions               |

---

## 15. Derived State & Effects

### Runes Quick Reference

| Rune                | Purpose                                                |
| ------------------- | ------------------------------------------------------ |
| `$state`            | Reactive state                                         |
| `$state.raw`        | Non-proxied state (reassign only, no deep reactivity)  |
| `$state.snapshot`   | Static snapshot of a reactive proxy                    |
| `$state.eager`      | Immediate (non-batched) UI updates (v5.41+)            |
| `$derived`          | Computed value from reactive dependencies              |
| `$derived.by`       | Computed value with complex logic (block body)         |
| `$effect`           | Side effect after DOM update                           |
| `$effect.pre`       | Side effect before DOM update                          |
| `$effect.root`      | Manual effect lifecycle scope                          |
| `$effect.tracking()`| Returns true if in a tracking context                  |
| `$props`            | Declare component props                                |
| `$props.id()`       | SSR-safe unique ID per component instance (v5.20+)     |
| `$bindable`         | Two-way bindable prop                                  |
| `$inspect`          | Debug reactive values (dev only)                       |
| `$inspect.trace()`  | Trace which state caused re-runs (v5.14+)              |
| `$host`             | Access host element (custom elements only)             |

### $derived (Computed Values)

```svelte
<script>
  let items = $state([])
  let searchQuery = $state('')

  // Simple expression
  let filtered = $derived(
    items.filter(item => item.name.toLowerCase().includes(searchQuery.toLowerCase()))
  )

  // Complex logic with $derived.by
  let summary = $derived.by(() => {
    const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0)
    return { total, count: items.length, empty: items.length === 0 }
  })
</script>
```

Since Svelte 5.25, `$derived` values can be temporarily overridden by reassignment (useful for optimistic UI). The override resets when dependencies change:

```svelte
<script>
  let count = $state(0)
  let doubled = $derived(count * 2)

  // Temporarily override for optimistic UI
  doubled = 999  // shows 999 until count changes
  count++        // doubled resets to computed value (2)
</script>
```

### $effect (Side Effects)

Use sparingly. Only for synchronizing with external systems:

```javascript
// DOM/Browser API sync
$effect(() => {
  localStorage.setItem('theme', theme)
  document.documentElement.setAttribute('data-theme', theme)
})

// External API with cleanup
$effect(() => {
  if (!userId) return
  const controller = new AbortController()

  fetch(`/api/users/${userId}`, { signal: controller.signal })
    .then(res => res.json())
    .then(data => userData = data)

  return () => controller.abort()
})

// Event listeners
$effect(() => {
  function handleResize() { width = window.innerWidth }
  window.addEventListener('resize', handleResize)
  return () => window.removeEventListener('resize', handleResize)
})
```

### $effect.pre (Before DOM Update)

```javascript
$effect.pre(() => {
  if (element) {
    savedScrollTop = element.scrollTop
  }
})
```

### When NOT to Use $effect

| Instead of $effect for...          | Use...                    |
| ---------------------------------- | ------------------------- |
| Computing derived values           | `$derived`                |
| Handling user interactions         | Event handlers            |
| Component communication            | Props / callbacks         |
| Simple state updates               | Functions                 |

### Lifecycle in Svelte 5

```text
Initial Mount:
  1. Script execution (state and effects registered)
  2. Template processing
  3. $effect.pre (before DOM insertion)
  4. DOM update
  5. $effect (after DOM changes)
  6. onMount (component fully mounted)

Subsequent Updates:
  1. State change
  2. $effect.pre (only for relevant effects)
  3. DOM update
  4. $effect (only for relevant effects)
```

In Svelte 5 with runes, `beforeUpdate`/`afterUpdate` are replaced by `$effect.pre` and `$effect` which offer granular control — they only react to specific state changes, not every component update.

---

## References

- [SvelteKit Loading Data](https://svelte.dev/docs/kit/load)
- [SvelteKit Hooks](https://svelte.dev/docs/kit/hooks)
- [SvelteKit Routing](https://svelte.dev/docs/kit/routing)
- [SvelteKit Remote Functions](https://svelte.dev/docs/kit/remote-functions)
- [SvelteKit Glossary](https://svelte.dev/docs/kit/glossary)
- [Global State in Svelte 5](https://mainmatter.com/blog/2025/03/11/global-state-in-svelte-5/)
- [How to Share State in Svelte 5](https://joyofcode.xyz/how-to-share-state-in-svelte-5)
