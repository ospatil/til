---
layout: ../layouts/GistLayout.astro
tags: [oidc, oauth, authentication, security, guide]
---

# OAuth 2.0 & OIDC: Flows, CLI Auth & JWT Verification

A step-by-step walkthrough of the three OpenID Connect / OAuth 2.0 flows you actually meet in practice: **Authorization Code + PKCE** (browser/mobile), the **server-driven three-legged** flow (confidential client / BFF), and the **Device Authorization** flow (TVs, CLIs). Each is built from the same parts, so we start with those, then cover how CLIs and headless tools fit in, which flow to choose, and how to read and verify the JWTs these flows produce.

For what happens *before* these flows - how the user actually logs in, passwordless - and *after* the token, deciding what they're allowed to do, see the companion [Passwordless Auth & Authorization](/passwordless-auth-and-authorization).

---

## Table of Contents

1. [The Cast & the Tokens](#1-the-cast--the-tokens)
2. [Authorization Code + PKCE](#2-authorization-code--pkce-browser--mobile)
3. [Server-Driven Three-Legged (BFF)](#3-server-driven-three-legged-flow-confidential-client--bff)
4. [Device Authorization Flow](#4-device-authorization-flow-tvs-clis-iot)
5. [CLI Applications](#5-cli-applications)
6. [Which Flow, When](#6-which-flow-when)
7. [JWT Structure, Claims & Verification](#7-jwt-structure-claims--verification)
8. [Refresh Tokens & Rotation](#8-refresh-tokens--rotation)

*Diagram colors: indigo = request / redirect · green = token / response · amber = pending · red = failure.*

---

## 1. The Cast & the Tokens

Every flow is a negotiation between the same actors:

- **Resource Owner** - the human (you).
- **Client** - the app wanting access. Either **public** (can't keep a secret: SPA, mobile, CLI) or **confidential** (can: a backend server).
- **Authorization Server (AS)** - the identity provider (Cognito, Auth0, Okta, Entra, Keycloak). Issues tokens.
- **Resource Server** - the API that accepts the access token.

And three tokens come out the other end - conflating them is the classic mistake:

| Token | Audience | Purpose |
| --- | --- | --- |
| **ID token** (JWT) | the client | Proves *who* the user is. Read it for identity/claims. **Not** an API credential. |
| **Access token** | the API | The credential sent to the Resource Server (`Authorization: Bearer`). May be a JWT or opaque. |
| **Refresh token** | the AS | Long-lived; exchanged for new access/ID tokens. Highly sensitive. |

Two parameters keep the flows honest, and they're easy to mix up:

- `state` - random value echoed back on the redirect; the client checks it to block **CSRF** on the callback.
- `nonce` - random value embedded in the request and returned *inside the ID token*; the client checks it to block **token replay**.

### ID token vs access token: read one, send the other

The single rule that prevents most mistakes is **audience** (the `aud` claim):

- The **ID token's** audience is *your client*. It's meant for the app to **read** - decode it for identity and claims (`sub`, `email`, `name`, `groups`). Don't send it to an API.
- The **access token's** audience is the *API* (resource server). It's meant for the app to **send** - `Authorization: Bearer`. Treat it as opaque: its format is a contract between the AS and the API, not something the client should parse.

Crossing these is the classic anti-pattern: sending the ID token to an API, or reading the access token for identity. (Decoding an access token's JWT payload client-side *happens to work* in the token-in-browser model, but it relies on a format you aren't the audience for - don't depend on it.)

### So what does the access token actually do in OIDC?

In *pure* OIDC, the access token has one defined job: **the UserInfo endpoint.** The ID token is a snapshot of identity at login; UserInfo is the live endpoint, and the access token authorizes it:

```http
GET /userinfo
Authorization: Bearer <access_token>
```

It returns claims scoped by what you requested (`openid profile email …`). If the ID token already carries everything the app needs, you never call UserInfo - which is exactly why the access token often *looks* unused in login-only apps.

More broadly, **OIDC is OAuth 2.0 plus an identity layer** - the access token's original OAuth job is unchanged: it's the credential for *any* protected API, the provider's (Google Calendar, MS Graph) or your own backend:

- **Login + call an API** (e.g. read your calendar): read the **ID token** to learn who the user is; send the **access token** to the Calendar API.
- **Login only** (just sign into your app): read the ID token, mint your own session, and the access token is used at most once for UserInfo (e.g. an avatar) then ignored.

So if an app neither calls UserInfo nor any API, the access token legitimately goes unused - it isn't missing a purpose; the ID token simply satisfied the need.

---

## 2. Authorization Code + PKCE (Browser / Mobile)

The flow for **public clients** - a SPA or mobile app that can't hold a client secret. PKCE (Proof Key for Code Exchange, RFC 7636) replaces the secret with a per-flow proof, so a stolen authorization code is useless to anyone else.

1. **Make the proof.** The client generates a random `code_verifier` and derives `code_challenge = BASE64URL(SHA256(verifier))`.
2. **Authorize.** Redirect the browser to the AS `/authorize` endpoint with `response_type=code`, the `code_challenge`, `state`, `nonce`, and scopes.
3. **User logs in** and consents at the AS (the client never sees the password).
4. **Get the code.** The AS redirects back to the app with a short-lived `code` and the `state`.
5. **Redeem it.** The client POSTs to `/token` with the `code` and the original `code_verifier` - **no client secret**.
6. **Verify.** The AS checks `SHA256(verifier)` equals the stored `code_challenge`, proving it's the same client that started the flow.
7. **Tokens.** The AS returns the ID token and access token (and optionally a refresh token).
8. **Call the API** with `Authorization: Bearer <access_token>`.

![Authorization Code + PKCE - sequence diagram](/diagrams/oidc-pkce.svg)

*Front channel (browser redirects) in indigo; token/data responses in green. All on TLS.*

On the wire (the numbered steps):

```http
# 2 · authorization request   (browser → AS)
GET https://as.example.com/authorize
      ?response_type=code
      &client_id=spa-client
      &redirect_uri=https://app.example.com/cb
      &code_challenge=BASE64URL(SHA256(code_verifier))
      &code_challenge_method=S256
      &scope=openid%20profile
      &state=xyz

# 4 · redirect back with code   (AS → browser)
HTTP/1.1 302 Found
Location: https://app.example.com/cb?code=AUTH_CODE&state=xyz

# 5 · token request   (browser → AS)
POST https://as.example.com/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&code=AUTH_CODE
&redirect_uri=https://app.example.com/cb&code_verifier=<original random string>

# 7 · token response   (AS → browser)
HTTP/1.1 200 OK
{
  "token_type": "Bearer",
  "expires_in": 3600,
  "id_token": "<JWT>",
  "access_token": "<token>"
}

# 8 · call the API   (browser → API)
GET https://api.example.com/resource
Authorization: Bearer <access_token>
```

---

## 3. Server-Driven Three-Legged Flow (Confidential Client / BFF)

When a **backend server** drives the login, it's a confidential client: it authenticates to the token endpoint with a `client_secret` on a back channel the browser never sees. The tokens stay on the server; the browser only ever gets an **httpOnly session cookie**. This is the Backend-For-Frontend (BFF) pattern.

1. Browser hits the app's `/login`.
2. Server responds with a `302` redirect to the AS `/authorize` (with `client_id`, `redirect_uri`, `state`, `scope`, `response_type=code`).
3. Browser follows it to the AS; the user authenticates and consents.
4. AS redirects the browser back to the server's `/callback` with the `code`.
5. Server exchanges the code on the **back channel**: `POST /token` with `code` + `client_secret` (and PKCE too, ideally).
6. AS returns the ID, access, and refresh tokens *to the server*.
7. Server stores the tokens server-side and sets an httpOnly session cookie, then redirects the browser into the app.

![Server-driven three-legged flow (BFF) - sequence diagram](/diagrams/oidc-server-side.svg)

*Steps 1-6 are front channel (browser); steps 7-8 are the confidential back channel. Tokens never reach JS.*

On the wire (the numbered steps):

```http
# 2 · server redirects you to the AS   (app server → browser)
HTTP/1.1 302 Found
Location: https://as.example.com/authorize?response_type=code&client_id=web-app
  &redirect_uri=https://app.example.com/callback&scope=openid&state=xyz

# 6 · callback hits the server   (browser → app server)
GET https://app.example.com/callback?code=AUTH_CODE&state=xyz

# 7 · back-channel token exchange   (app server → AS)
POST https://as.example.com/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&code=AUTH_CODE&redirect_uri=https://app.example.com/callback
&client_id=web-app&client_secret=<SERVER SECRET>

# 8 · token response   (AS → app server)
HTTP/1.1 200 OK
{
  "id_token": "<JWT>",
  "access_token": "<token>",
  "refresh_token": "<token>"
}

# 9 · server sets the session cookie   (app server → browser)
HTTP/1.1 302 Found
Set-Cookie: __Host-session=...; HttpOnly; Secure; SameSite=Lax; Path=/
```

---

## 4. Device Authorization Flow (TVs, CLIs, IoT)

For input-constrained devices with no browser (or no keyboard) - a smart TV, a CLI tool. The device can't host a redirect, so the user approves on a **second device** (their phone) while the first device **polls** for the result (RFC 8628).

1. Device calls `POST /device_authorization` with its `client_id` and scopes.
2. AS returns a `device_code`, a short human `user_code`, a `verification_uri`, and a polling `interval`.
3. Device displays the `user_code` and URL: *"Go to example.com/device and enter WDJB-MJHT."*
4. Device starts polling `POST /token` (grant `device_code`) - the AS answers `authorization_pending`.
5. On their phone, the user opens the `verification_uri`, enters the code, authenticates, and consents.
6. The AS marks the `device_code` approved.
7. The device's next poll succeeds - the AS returns the tokens.

![Device Authorization flow - sequence diagram](/diagrams/oidc-device.svg)

*Polling shown in amber (pending); the approval happens out-of-band on the phone.*

On the wire (the numbered steps):

```http
# 1 · device authorization request   (device → AS)
POST https://as.example.com/device_authorization
client_id=tv-app&scope=openid

# 2 · response   (AS → device)
HTTP/1.1 200 OK
{
  "device_code": "...",
  "user_code": "WDJB-MJHT",
  "verification_uri": "https://as.example.com/device",
  "interval": 5
}

# 4 · poll the token endpoint   (device → AS) - repeats every `interval` seconds
POST https://as.example.com/token
grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=...&client_id=tv-app
  → HTTP/1.1 400  { "error": "authorization_pending" }

# 8 · once approved, the next poll succeeds   (AS → device)
HTTP/1.1 200 OK
{
  "id_token": "<JWT>",
  "access_token": "<token>",
  "refresh_token": "<token>"
}
```

---

## 5. CLI Applications

A CLI has no UI of its own for passwords or MFA, so it **delegates the interactive login to a browser** and then holds the resulting tokens. Two distinct concerns show up: getting the tokens in the first place, and *staying* authorized as sessions and Conditional Access windows lapse.

### Interactive login: the loopback redirect

This is the default for `gh auth login`, `az login`, `gcloud auth login`, and Git Credential Manager. The CLI starts a throwaway web server on `localhost`, opens your browser to authenticate, and the Authorization Server redirects the code straight back to that local port - Authorization Code + PKCE (RFC 8252):

![CLI loopback redirect (PKCE) - sequence diagram](/diagrams/oidc-cli-loopback.svg)

On the wire (the numbered steps):

```http
# 2 · CLI opens the browser to the AS   (loopback redirect_uri)
GET https://as.example.com/authorize
      ?response_type=code&client_id=cli
      &redirect_uri=http://127.0.0.1:51789/callback
      &code_challenge=...&code_challenge_method=S256&state=xyz

# 5 · AS redirects the code to the CLI's local listener
HTTP/1.1 302 Found
Location: http://127.0.0.1:51789/callback?code=AUTH_CODE&state=xyz

# 7 · CLI exchanges the code   (CLI → AS)
POST https://as.example.com/token
grant_type=authorization_code&code=AUTH_CODE
&redirect_uri=http://127.0.0.1:51789/callback&code_verifier=<random>

# 8 · tokens → stored in the OS keychain
HTTP/1.1 200 OK
{
  "id_token": "<JWT>",
  "access_token": "<token>",
  "refresh_token": "<token>"
}
```

Two things this makes concrete:

- It needs a **local browser** and the ability to **bind a localhost port** - fine on your laptop, impossible over a bare SSH session.
- The **browser never writes the keychain.** The AS redirects the code to the CLI's own listener; the CLI - a native process running as *you* - exchanges it and stores the tokens. (The earlier "how does a browser update the keychain?" puzzle: it doesn't; a process you launched does, and your login keychain is user-writable.)

### Headless: device flow

When there's no local browser or you can't catch a localhost redirect - an SSH'd-in server, a container, a TV - use the **device flow** (§4). The CLI prints a code + URL, you approve on any device, the CLI polls. `az login --use-device-code` is the explicit switch. Caveats: more friction (type a code, poll), and **device-code phishing** (someone sends you a real code to approve *their* device), which leads some orgs to block it via Conditional Access.

### Staying authorized: transport credential vs identity session

A different problem from logging in: even with a perfectly valid credential, an org policy can require your *identity session* to have re-authenticated recently. This is the **Azure DevOps over SSH** case - `git pull` starts failing until you log into the browser, then works again. The key insight is that the credential and the session are **separate axes**:

- The **SSH key** authenticates the *transport* - it identifies who you are and doesn't expire on its own.
- A **Conditional Access** sign-in-frequency policy independently requires your *Entra session* to be fresh. When that window lapses, the server refuses the operation even though the key is fine.

![ADO over SSH with Conditional Access - sequence diagram](/diagrams/oidc-ado-ssh-ca.svg)

On the wire - not an OAuth exchange, just git over SSH plus a server-side policy check:

```console
$ git pull          # SSH key authenticates fine, but the Entra session is stale
remote: TF400813: The user '<id>' is not authorized to access this resource.
fatal: Could not read from remote repository.

#  → open the browser, sign in to dev.azure.com (refreshes the Entra session)

$ git pull          # same SSH key - the Conditional Access check now passes
Already up to date.
```

So "fixing it by logging into the browser" changes **nothing on your machine** - the same SSH key is used before and after. The browser refreshed a **server-side** Entra session; Azure DevOps re-checked it and let the next pull through. The two are correlated server-side by your identity, not by any local file or shared token.

These session policies target the **cloud resource + your identity**, not your device - which is why a customer's tenant can enforce them even though it doesn't manage your machine. (A device-*compliance* policy would need management - and would block you outright rather than prompt a refresh.)

### Same repo over HTTPS (GCM)

Clone the *same* ADO repo over HTTPS (`git clone https://dev.azure.com/…`) and the picture flips - now **Git Credential Manager** is in play (the SSH remote bypassed it entirely). GCM runs the Entra OAuth login via the **loopback flow above**, stores the resulting token in your **keychain**, and replays it on each git operation. Conditional Access then shows up at a different point:

| | SSH (key) | HTTPS (GCM) |
| --- | --- | --- |
| Credential | static key in `~/.ssh` | OAuth token in the **keychain** (via GCM) |
| Who prompts re-auth | server rejects → you open a browser | **GCM** opens the browser (loopback) |
| Where the "session" lives | server-side Entra session | local token + server-side CA, reassessed at refresh |
| CA enforced | at the git operation | at token **refresh** (Continuous Access Evaluation, ~1 h) |

So on HTTPS the "session expired, go log in" symptom is concretely GCM's silent token refresh failing a Conditional Access check and popping a browser for interactive re-auth - after which the new token lands back in your keychain. Same outcome as SSH (periodic browser re-auth), but here a local credential really is involved, and **GCM** - not the server's rejection - drives the prompt.

### At a glance

- **Logging a CLI in, local machine** → loopback Authorization Code + PKCE (`gh` / `az` / `gcloud`).
- **Logging a CLI in, headless / remote** → device flow.
- **CLI suddenly needs re-auth though nothing changed** → an identity-session / Conditional Access window lapsed; refresh it interactively. The transport credential was never the problem.

---

## 6. Which Flow, When

| | Code + PKCE | Server-side (BFF) | Device |
| --- | --- | --- | --- |
| Client type | Public (SPA, mobile) | Confidential (backend) | Public, input-constrained |
| Client secret | None (PKCE instead) | Yes (back channel) | None |
| Where tokens live | In the browser/app | Server-side; cookie to browser | On the device |
| Redirect URI | Required | Required | None (polling) |
| XSS exposure of tokens | Yes - mitigate | No (httpOnly cookie) | N/A (no browser) |
| Best for | Static SPAs, native apps | Security-sensitive web apps with a backend | TVs, CLIs, IoT |

- **Building a SPA or mobile app?** Authorization Code + PKCE. It's the modern default for public clients.
- **Have a backend and care about XSS?** Server-side / BFF - tokens never touch JS; the browser holds only an httpOnly session cookie.
- **No browser or keyboard on the client?** Device flow.

PKCE is no longer "just for public clients" - current guidance is to use it in the server-side flow too, layered on top of the client secret. The Implicit and Resource Owner Password flows are deprecated; don't use them.

---

## 7. JWT Structure, Claims & Verification

OIDC ID tokens (and many access tokens) are **JWTs**. Reading one is easy; *trusting* one is the part that matters.

### Structure: three Base64URL parts

A JWT is `header.payload.signature` - three Base64URL segments joined by dots:

```text
eyJhbGciOiJSUzI1NiIsImtpZCI6ImFiYzEyMyJ9      ← header
.eyJpc3MiOiJodHRwczovL2FzLmV4YW1wbGUuY29t...   ← payload (claims)
.NHVaYe26MbtOYhSKkoKYdFVomg4i8ZJd8_-RU8VNbf...  ← signature
```

Decoded, the first two parts are just JSON:

```json
// header
{
  "alg": "RS256",
  "kid": "abc123",
  "typ": "JWT"
}

// payload (claims)
{
  "iss": "https://as.example.com",
  "sub": "248289761001",
  "aud": "spa-client",
  "exp": 1735689600,
  "iat": 1735686000,
  "nonce": "n-0S6_WzA2Mj",
  "email": "alice@example.com"
}
```

**Base64URL is encoding, not encryption** - anyone can read the header and payload. The *signature* is what makes a JWT trustworthy: it's computed over `header.payload` with the issuer's private key, so only the issuer could have produced it and any tampering breaks it. Never trust a JWT's claims until you've verified the signature.

### Standard claims

| Claim | Meaning | Validate |
| --- | --- | --- |
| `iss` | Issuer (the AS) | equals the issuer you expect |
| `sub` | Subject - stable user id | use as the user key |
| `aud` | Audience | ID token → your `client_id` · access token → your API |
| `exp` | Expiry (epoch seconds) | now < exp |
| `iat` / `nbf` | Issued-at / not-before | freshness; now ≥ nbf |
| `nonce` | Replay guard (ID token) | equals the nonce you sent |
| `azp` | Authorized party | equals `client_id` when there are multiple audiences |
| `auth_time` | When the user authenticated | for `max_age` / re-auth checks |

Profile claims (`email`, `name`, `picture`, `groups`, …) appear according to the granted `scope`.

### Verifying the signature via the well-known endpoints

The verifier doesn't hold the issuer's key - it discovers it:

![Verifying a JWT via JWKS - sequence diagram](/diagrams/oidc-jwt-verify.svg)

```http
# 1 · discovery document
GET https://as.example.com/.well-known/openid-configuration
→ {
    "issuer": "https://as.example.com",
    "jwks_uri": "https://as.example.com/.well-known/jwks.json",
    "authorization_endpoint": "...",
    "token_endpoint": "..."
  }

# 3 · the JSON Web Key Set (public keys)
GET https://as.example.com/.well-known/jwks.json
→ {
    "keys": [
      {
        "kid": "abc123",
        "kty": "RSA",
        "use": "sig",
        "alg": "RS256",
        "n": "<modulus>",
        "e": "AQAB"
      }
    ]
  }
```

The steps: (1) fetch the **discovery** doc → read `issuer` and `jwks_uri`; (2) fetch the **JWKS** → a set of public keys, each tagged with a `kid`, and **cache it**; (3) read the token header's `kid` and pick the matching key; (4) verify the signature with that key (RS256 → the RSA public key from `n`/`e`); (5) validate the claims from the table above.

Don't hand-roll this - use a vetted library:

```js
import { jwtVerify, createRemoteJWKSet } from 'jose'

const JWKS = createRemoteJWKSet(new URL('https://as.example.com/.well-known/jwks.json'))

const { payload } = await jwtVerify(idToken, JWKS, {
  issuer: 'https://as.example.com',
  audience: 'spa-client'          // signature, kid, exp, iss, aud checked for you
})
// then verify payload.nonce === expectedNonce yourself (for ID tokens)
```

### Gotchas

- **Pin the algorithm.** Reject `alg: none` and enforce the expected `alg` (e.g. RS256). Otherwise an attacker can mount an "alg confusion" attack - swap RS256 for HS256 and sign with the *public* key as an HMAC secret.
- **Cache JWKS by `kid`**, and refetch on an unknown `kid` - issuers rotate keys.
- **Clients validate ID tokens; APIs validate access tokens.** Don't verify a token you aren't the audience for. Opaque (non-JWT) access tokens can't be verified locally at all - the API uses token introspection instead.

### Token formats: JWS, JWE & opaque

Everything above assumes a **signed JWT (JWS)** - the OIDC default: readable by anyone, trusted via its signature. Two other shapes turn up:

- **JWE (encrypted JWT, RFC 7516)** - when the payload itself must stay confidential, the JWT is *encrypted*, not just signed; you decrypt with your private key before reading. OIDC permits encrypted ID tokens, but most deployments stick with plain JWS since TLS already protects the wire.
- **Opaque / reference tokens** - the usual alternative for **access tokens**: a random string with no readable content. The API can't verify it offline; it calls the AS's **introspection** endpoint (RFC 7662):

```http
POST https://as.example.com/introspect
Authorization: Basic <api client credentials>
Content-Type: application/x-www-form-urlencoded

token=<opaque access token>

→ HTTP/1.1 200 OK
{
  "active": true,
  "sub": "248289761001",
  "scope": "openid profile",
  "exp": 1735689600
}
```

The tradeoff: a JWT is self-contained and verified offline (fast, but valid until it expires - hard to revoke early); an opaque token is revocable instantly (the AS just stops returning `active: true`) at the cost of a network call per check. ID tokens are always JWTs; the access-token format is the issuer's choice.

Beyond OIDC you may also meet non-JWT formats - **PASETO** (a JWT alternative that removes the algorithm-negotiation footguns), **CWT** (compact binary tokens for IoT), and **Biscuit / macaroons** (attenuable capability tokens). OIDC mandates JWT, so these won't appear as ID/access tokens, but they show up in adjacent systems.

### Sender-constrained tokens (DPoP & mTLS)

Everything so far uses **bearer** tokens: whoever holds the token can use it, so a stolen one is fully usable. Sender-constrained tokens bind the token to a key the client must prove it holds:

- **DPoP (RFC 9449)** - the client generates a key pair and attaches a signed `DPoP` proof header to each request; the AS binds the access token to that key. A stolen token is useless without the private key. Lightweight and aimed at public clients - the natural hardening for the XSS-exposed token model.
- **mTLS-bound tokens (RFC 8705)** - the token is bound to the client's TLS client certificate; common in enterprise and server-to-server setups where a client cert already exists.

Both turn "stolen token = game over" into "stolen token = useless without the key." If your threat model includes token theft - and for public clients it should - prefer DPoP where the AS supports it.

---

## 8. Refresh Tokens & Rotation

Access tokens are deliberately short-lived (minutes to an hour). Instead of re-prompting the user, the client trades a **refresh token** for a fresh access token (and usually a new ID token):

```http
POST https://as.example.com/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token&refresh_token=<refresh token>&client_id=cli
  (+ client_secret for confidential clients)

→ HTTP/1.1 200 OK
{
  "access_token": "<new>",
  "id_token": "<new>",
  "refresh_token": "<new or same>"
}
```

**Rotation** is the security practice for public clients: each refresh returns a *new* refresh token and invalidates the old one. If a leaked refresh token is used by an attacker, the legitimate client's next refresh fails (its token was already spent) - the AS sees the reuse, revokes the whole token family, and forces a fresh login. That caps the damage of a stolen refresh token.

Practical notes:

- **Storage:** confidential clients keep refresh tokens server-side; in the browser a refresh token is XSS-exposed, so public SPAs should use rotation + short lifetimes or, better, the BFF pattern that keeps it server-side.
- **Revocation (RFC 7009):** logout should call the AS's `/revoke` endpoint to kill the refresh token, not just discard it locally.
- Sender-constraining (DPoP / mTLS) applies to refresh tokens too, blunting refresh-token theft.

---

## References

- [RFC 7519 - JSON Web Token (JWT)](https://datatracker.ietf.org/doc/html/rfc7519)
- [RFC 7517 - JSON Web Key (JWK / JWKS)](https://datatracker.ietf.org/doc/html/rfc7517)
- [OpenID Connect Discovery 1.0](https://openid.net/specs/openid-connect-discovery-1_0.html)
- [RFC 6749 - OAuth 2.0](https://datatracker.ietf.org/doc/html/rfc6749)
- [RFC 7636 - PKCE](https://datatracker.ietf.org/doc/html/rfc7636)
- [RFC 8628 - Device Authorization Grant](https://datatracker.ietf.org/doc/html/rfc8628)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [OAuth 2.0 for Browser-Based Apps (BCP)](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-browser-based-apps)
- [RFC 7516 - JSON Web Encryption (JWE)](https://datatracker.ietf.org/doc/html/rfc7516)
- [RFC 7662 - Token Introspection](https://datatracker.ietf.org/doc/html/rfc7662)
- [RFC 7009 - Token Revocation](https://datatracker.ietf.org/doc/html/rfc7009)
- [RFC 9449 - DPoP (Demonstrating Proof of Possession)](https://datatracker.ietf.org/doc/html/rfc9449)
- [RFC 8705 - mTLS Client Authentication & Certificate-Bound Tokens](https://datatracker.ietf.org/doc/html/rfc8705)
