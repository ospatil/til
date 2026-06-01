---
layout: ../layouts/GistLayout.astro
tags: [authentication, authorization, passkeys, webauthn, security, guide]
---

# Passwordless Auth & Authorization: Passkeys, OTP & Access Control

Every protected request comes down to two questions: **who are you** (authentication) and **what may you do** (authorization). The companion piece on [OAuth 2.0 & OIDC flows](/oauth2-oidc-flows-cli-jwt) covers the middle - how tokens get issued, moved, and verified - but it treats the login itself as a black box ("the user authenticates and consents") and stops once you hold a verified token. This article fills in both ends.

**Part I** opens that black box: how login actually works *without a password* - passkeys/WebAuthn, magic links, and one-time codes. **Part II** picks up where the token leaves off: you know who the caller is, now how do you decide what they're allowed to touch?

---

## Table of Contents

**Part I - Passwordless Authentication**

1. [Why Passwordless](#1-why-passwordless)
2. [The Methods at a Glance](#2-the-methods-at-a-glance)
3. [WebAuthn & Passkeys](#3-webauthn--passkeys)
4. [Cross-Device Passkeys](#4-cross-device-passkeys)
5. [Magic Links & Email OTP (and rolling your own)](#5-magic-links--email-otp-and-rolling-your-own)
6. [Passkeys vs Passwords](#6-passkeys-vs-passwords)
7. [The IdP Landscape & Validating Tokens in Go](#7-the-idp-landscape--validating-tokens-in-go)

**Part II - Authorization**

8. [From Authentication to Authorization](#8-from-authentication-to-authorization)
9. [RBAC, ABAC & ReBAC](#9-rbac-abac--rebac)
10. [Where Decisions Live: PEP, PDP, PAP, PIP](#10-where-decisions-live-pep-pdp-pap-pip)
11. [Policy Engines](#11-policy-engines-opa-cedar-cerbos)
12. [Relationship-Based (Zanzibar) Engines](#12-relationship-based-zanzibar-engines)
13. [Two Problems That Only Show Up at Scale](#13-two-problems-that-only-show-up-at-scale)
14. [Choosing](#14-choosing)

*Diagram colors: indigo = request / structure · green = success / response · amber = pending / proximity · purple = group / accent · slate = secondary.*

---

# Part I - Passwordless Authentication

## 1. Why Passwordless

A password is a **shared secret**: you know it, the server stores a hash of it. Every weakness of password auth traces back to that single fact.

- **Phishing.** A convincing fake site asks for the password and you type it in. The secret now belongs to the attacker - nothing about a password ties it to the real site.
- **Reuse & credential stuffing.** People reuse passwords. One breached site hands attackers working credentials for dozens of others.
- **Server breach.** A leaked hash table is an offline cracking target. Weak hashes or weak passwords fall fast.
- **Phishable second factors.** SMS and TOTP help, but a real-time phishing proxy relays the code as fast as you enter it.

Passwordless auth removes the shared secret entirely. Authentication factors come in three kinds - **knowledge** (*something you know*: a password, a PIN), **possession** (*something you have*: a device, a phone, a hardware key), and **inherence** (*something you are*: a fingerprint, your face). Passwordless methods lean on possession and inherence instead of knowledge, and the strongest of them add one more property:

> **Phishing-resistant** means the credential is cryptographically bound to the real site's origin - it simply doesn't function on a look-alike domain. No human judgment required. This is the bar that passwords and OTPs can never clear, and the one WebAuthn clears by design.

---

## 2. The Methods at a Glance

"Passwordless" is an umbrella, and the methods under it differ sharply in security. Worth separating them before going deep:

| Method | Factor | Phishing-resistant | UX | Notes |
| --- | --- | --- | --- | --- |
| **Passkey (WebAuthn/FIDO2)** | Have + are | **Yes** (origin-bound) | Biometric tap | The gold standard. Private key never leaves the device. |
| **Hardware security key** | Have | **Yes** (origin-bound) | Insert / tap | Same FIDO2 protocol, in a physical token (YubiKey). |
| **Magic link** | Have (inbox) | No | Click a link | Proves control of the email account, nothing more. |
| **Email / SMS OTP** | Have (inbox / SIM) | No | Type a code | Same proof as a magic link; SMS adds SIM-swap risk. |
| **Biometric** | Are | Depends | Face / fingerprint | On the web this is a *local* unlock for a passkey, not a factor sent to the server. |
| **Client certificate (mTLS)** | Have | Yes | Transparent | Common for machine identity and enterprise; covered in the [OAuth article](/oauth2-oidc-flows-cli-jwt#sender-constrained-tokens-dpop--mtls). |

Two things to notice:

- **Not all passwordless is phishing-resistant.** Magic links and OTPs only prove you can read an inbox. A phishing proxy can relay them just fine. They eliminate the stored password and they're easy to use - but they're not in the same security class as passkeys.
- **Web biometrics are a local gate, not a network factor.** Face ID unlocks the private key *on your device*; the biometric template never travels to the server.

That second point is the heart of how WebAuthn works, so we start there.

---

## 3. WebAuthn & Passkeys

WebAuthn (the browser API) plus CTAP (Client to Authenticator Protocol - how the browser talks to a security key or platform authenticator over USB, NFC, or Bluetooth) together make up **FIDO2**. A **passkey** is the user-facing name for a WebAuthn credential - a public/private key pair scoped to one site. The core idea: replace the shared secret with public-key cryptography. The server only ever holds a **public** key; the matching **private** key never leaves your device.

Two ceremonies make it work - one to enroll, one to log in:

![WebAuthn registration and authentication ceremonies - sequence diagram](/diagrams/webauthn-ceremonies.svg)

- **Registration** (steps 1-7): the server sends a random challenge plus its `rpId` (the site's domain). Your authenticator asks for a gesture (biometric or PIN), generates a fresh key pair *for this site*, and sends back the **public key** plus an attestation. The server stores that public key against your account.
- **Authentication** (steps 8-14): the server sends a new challenge. The local gesture unlocks the private key, which **signs the challenge**. The server verifies that signature with the stored public key.

The biometric never leaves the device - it only unlocks the key locally. What crosses the wire is a signature, never a secret.

What the server stores is strikingly small - no password, no hash, nothing secret:

```text
user_id | credential_id | public_key | sign_count
```

That shape is the whole security argument:

- **The private key never transmits.** It can't be phished from you or stolen from the server, because the server never has it.
- **Origin-bound.** The key pair is tied to the exact `rpId`. A look-alike domain (`examp1e.com`) can't trigger a usable signature - phishing resistance enforced by the protocol, not by you squinting at a URL bar.
- **A breach is useless.** Public keys are, by definition, public. Leaking that table gives an attacker nothing to log in with.
- **`sign_count`** is a monotonic counter some authenticators bump on each use; the server can use it to detect cloned credentials.

On the wire, the browser API bookends each ceremony. Registration calls `navigator.credentials.create()`; login calls `navigator.credentials.get()`:

```js
// 8-12 · authentication: sign the server's challenge
const assertion = await navigator.credentials.get({
  publicKey: {
    challenge: Uint8Array.from(serverChallenge),  // fresh, random, single-use
    rpId: 'example.com',                           // must match the registered origin
    allowCredentials: [{ type: 'public-key', id: credentialId }],
    userVerification: 'preferred'                  // biometric / PIN gate
  }
})
// assertion.response.signature -> POST to the server, which verifies it
// against the stored public key for credentialId
```

One UX detail: passkeys can be **discoverable** (also called "resident keys"), meaning the authenticator stores the user handle internally. This enables *usernameless* login - the user taps their fingerprint and the authenticator offers the matching credential without the user typing an email first. Most platform passkeys (iCloud, Google) are discoverable by default; hardware keys may not be, depending on storage limits.

Don't implement the server side by hand - the signature formats (CBOR for binary encoding, COSE for key representation - both compact binary formats designed for constrained devices) are fiddly. Use a vetted library: `github.com/go-webauthn/webauthn` (Go), SimpleWebAuthn (Node), or whatever your IdP ships.

---

## 4. Cross-Device Passkeys

A passkey's private key never leaves the device it was made on - so how do you log in on a *different* device? Three answers, and only one of them is the clever protocol.

**1. Cloud sync (the common case).** Platform passkeys sync within an ecosystem via the user's account: Apple through iCloud Keychain, Google through Google Password Manager, Microsoft through the Microsoft account. Your MacBook passkey is simply already present on your iPhone. **Third-party password managers** (1Password, Bitwarden) do the same thing across ecosystems - the key lives in the vault, available anywhere the manager is installed. That breaks platform lock-in, at the cost of tying passkey security to the vault's master password.

**2. Register an additional passkey.** Log in once on the new device via a fallback (say, email OTP), then enroll a *new* passkey there. Each device gets its own key pair for the same account. Simple, no syncing needed.

**3. Cross-device authentication (different ecosystems, nothing synced).** This is the **CTAP2 hybrid transport** - an extension of that same Client to Authenticator Protocol, but operating over the network instead of USB/NFC (formerly called "caBLE" for cloud-assisted BLE). It's the one worth understanding:

![Cross-device passkey via CTAP2 hybrid - sequence diagram](/diagrams/passkey-cross-device.svg)

The device you're logging in on (a laptop with **no** local passkey) shows a **QR code**. You scan it with the **phone that holds the passkey**. The QR carries a tunnel key, and the phone then emits a **Bluetooth advertisement** so the two devices can prove they're physically near each other before opening an end-to-end encrypted tunnel (brokered by a relay). The phone does the WebAuthn ceremony locally - biometric unlock, sign the challenge - and returns only the **assertion** over the tunnel. The laptop forwards it to the server.

Two details matter:

- **The private key never moves to the laptop.** The phone signs; only a signature crosses the tunnel. The QR is a tunnel key, not the passkey itself.
- **The Bluetooth proximity check is the point.** It binds the ceremony to two co-located devices. An attacker who relays your QR code from afar can't satisfy the BLE proximity step - that's how it defeats remote phishing.

> A common mental model gets the direction backwards - imagining the phone shows the QR and the laptop signs. It's the reverse: the device **lacking** the credential displays the QR; the device **holding** the passkey scans and signs. The credential stays put; only the ceremony is delegated.

---

## 5. Magic Links & Email OTP (and rolling your own)

Magic links and one-time codes are the pragmatic, low-friction end of passwordless. Both prove the same single thing - **you control the inbox** (or phone number). They just differ in delivery: a magic link is a click, an OTP is a typed code. Neither is phishing-resistant (a proxy can relay either), but both eliminate the stored password and are easy for users.

![Email OTP / magic link flow - sequence diagram](/diagrams/email-otp-flow.svg)

The flow is short: the app generates a code, stores a hash of it with a short TTL, sends it out-of-band, and on submission compares in constant time and invalidates it. This *looks* trivial, which is exactly why it's frequently built insecurely. If you roll your own, the pieces are small but the failure modes are sharp:

| Piece | Difficulty | Notes |
| --- | --- | --- |
| OTP generation | Easy | `crypto/rand`, **never** `math/rand`. |
| Storage (code + expiry) | Easy | Redis with a TTL is ideal; Postgres works. Store a **hash**, not the raw code. |
| Email sending | Easy | SMTP or a transactional API (SES, Postmark, Resend). |
| Session / JWT issuance | Easy | `github.com/golang-jwt/jwt/v5`. |
| Rate limiting | Medium | Required on **both** send and verify. |
| Brute-force lockout | Medium | Lock after N failed attempts per identifier. |
| Constant-time compare | Easy | `crypto/subtle.ConstantTimeCompare`. |

The core of a hand-rolled implementation - generation and a safe comparison:

```go
import (
    "crypto/rand"
    "crypto/subtle"
    "math/big"
)

// 6-digit code from a cryptographic source
func newOTP() (string, error) {
    n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
    if err != nil {
        return "", err
    }
    return fmt.Sprintf("%06d", n.Int64()), nil
}

// constant-time check defeats timing attacks
func verify(input, stored string) bool {
    return subtle.ConstantTimeCompare([]byte(input), []byte(stored)) == 1
}
```

The mistakes that bite, roughly in order of how often they show up:

- **`math/rand` instead of `crypto/rand`** - predictable codes.
- **No rate limit on send** - attacker spams a victim's inbox (and your email reputation).
- **No rate limit on verify** - a 6-digit code is only 1,000,000 possibilities. Unthrottled, it's brute-forceable in minutes.
- **Not invalidating on use** - a code must be strictly single-use.
- **Long expiry windows** - keep it to 5-10 minutes.
- **Naive string comparison** - leaks timing; use `subtle.ConstantTimeCompare`.

Honestly, prefer a library or an IdP for this. The crypto is easy; it's the rate-limiting, lockout, and abuse controls where roll-your-own quietly goes wrong.

---

## 6. Passkeys vs Passwords

Even when a passkey is cloud-synced (and so, like a password, recoverable through an account), it's still categorically safer. The gains are structural, not incremental:

- **Phishing resistance** - the biggest one. The credential is bound to the origin at the protocol level. A tricked user on `examp1e.com` simply gets nothing - no human judgment involved.
- **Server breach is useless** - the database holds only public keys.
- **No reuse, no stuffing** - every site gets a unique key pair, generated automatically. A credential from site A is meaningless at site B.

Where the analogy *does* hold: if the device or vault holding your passkeys is compromised, an attacker can use them - same as a compromised password manager would expose passwords. Vault and device security still matter.

The net: passkeys remove the biggest attack vectors - phishing, breaches, reuse, stuffing - and leave just the one risk that passwords also carry: a compromised device or vault.

### What about account recovery?

The elephant in the room: what happens when you lose *all* your devices? Section 4 covers switching devices, but total loss is different - no sync target, no phone to scan a QR.

In practice, recovery works through layers:

- **Cloud sync is the first safety net.** If your passkeys sync to iCloud or Google, "losing your phone" doesn't lose the key - buy a new phone, sign into your cloud account, and the passkey is already there. The risk moves one level up: losing access to the *cloud account itself*.
- **Multiple passkeys on separate devices.** Register a second passkey on a backup device (a hardware key in a drawer, a partner's phone). One device lost doesn't mean locked out.
- **IdP-mediated recovery.** Most IdPs offer a fallback path - typically email OTP or an SMS code - to let you in long enough to register a new passkey. This re-introduces a weaker factor, but only for recovery, not daily login. It's a pragmatic trade: security of the steady-state stays high, and you accept a brief, rate-limited downgrade for the rare recovery event.
- **Recovery codes.** Some services issue a set of one-time codes at registration ("print these and put them somewhere safe"). Old-fashioned, but independent of any device or inbox.

The uncomfortable truth: there's no way to make account recovery both *fully* phishing-resistant and *self-service*. At some point, recovery has to trust a weaker proof (an inbox, a printed code, identity verification) because the strong proof (the passkey) is exactly what was lost. The design goal is to keep that weaker path narrow, rate-limited, and used as rarely as possible.

---

## 7. The IdP Landscape & Validating Tokens in Go

You rarely build all this from scratch. An **Identity Provider** handles registration, the WebAuthn ceremonies, OTP delivery, and session/token issuance, then hands your app a verified identity - typically as an OIDC JWT. Several self-hostable, open-source IdPs do passwordless as a first-class feature:

| Project | Lang | Passwordless support | Notes |
| --- | --- | --- | --- |
| **Hanko** | Go | Passkeys (primary focus) + email OTP | Purpose-built for passwordless; light (~50-80 MB). Auth-focused, limited beyond it. |
| **Zitadel** | Go | Passkeys, email OTP, TOTP | Full IdP: OIDC + SAML, RBAC, multi-tenancy. Apache 2.0. Heavier (~154 MB). |
| **Ory Kratos** | Go | "Code via email" (magic code) | Identity layer; pairs with Ory Hydra for OIDC. |
| **Keycloak** | Java | Magic link + OTP via extensions | Most battle-tested; heavyweight JVM. |
| **Authentik** | Python | Email-based flows via "stages" | Good UI, flexible flow builder. |
| **Logto** | Node/TS | Email/SMS passcode | OIDC-native, modern developer UX. |

A useful split: **Hanko** if you want passkey-first auth and little else; **Zitadel** if you want a full identity platform (auth *plus* user management, RBAC, multi-tenancy, SAML) and are effectively replacing a hosted IdP. The others sit at points in between.

Whichever you pick, the integration pattern is the same one from the [OAuth article's JWT section](/oauth2-oidc-flows-cli-jwt#7-jwt-structure-claims--verification): run the IdP as a separate service (or sidecar), and have your API **validate the JWT it issues** against the IdP's JWKS. In Go, with `github.com/lestrrat-go/jwx/v2`, the JWKS is fetched once (and auto-refreshed) and every request is verified against it:

```go
import (
    "github.com/lestrrat-go/jwx/v2/jwk"
    "github.com/lestrrat-go/jwx/v2/jwt"
)

// cache + background refresh; re-fetches on unknown kid (key rotation)
cache := jwk.NewCache(ctx)
cache.Register("https://idp.example.com/.well-known/jwks.json")
keySet, _ := cache.Get(ctx, "https://idp.example.com/.well-known/jwks.json")

func authMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
        tok, err := jwt.Parse([]byte(raw),
            jwt.WithKeySet(keySet),                       // verifies signature + kid
            jwt.WithIssuer("https://idp.example.com"),    // iss
            jwt.WithAudience("my-api"),                   // aud
            jwt.WithValidate(true),                       // exp / nbf / iat
        )
        if err != nil {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return
        }
        ctx := context.WithValue(r.Context(), userKey, tok.Subject())
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

That middleware is the seam between the two halves of this article. It answers *who are you* - the token is signed by the IdP, unexpired, and meant for this API, and `tok.Subject()` is a trustworthy user id. But it says nothing about *what you may do*. That's authorization, and it's where Part II begins.

---

# Part II - Authorization

## 8. From Authentication to Authorization

Authentication ends with a verified principal: the middleware above gives you a trustworthy `sub`, maybe an email, maybe some group claims. **Authorization** is the next question - entirely separate - *is this principal allowed to perform this action on this resource?*

Think of it this way. Showing your badge at the office door proves you work here (authentication). But whether you can enter the server room, approve a purchase order, or read the salary spreadsheet - that's a different system making a different decision based on different data (authorization).

Two things make authorization harder than it sounds:

- **It's contextual.** Who you are is the same on every request. What you're allowed to do depends on *which* resource, *which* action, and sometimes the live state of your data. "Can Alice edit *this specific doc*, right now?" is a different question from "is Alice an editor?"
- **The token isn't enough.** A JWT can carry coarse hints (OIDC scopes, a role claim), but it can't encode every per-object permission in your system, and it's frozen at login time. Authorization almost always needs more data than the token carries.

So how do you express those rules, and where do you store and evaluate them? That's what the rest of Part II covers.

---

## 9. RBAC, ABAC & ReBAC

Three models dominate. They differ in *what a permission is made of* - what's the "shape" of the rule that grants or denies access.

![RBAC vs ABAC vs ReBAC - concept diagram](/diagrams/authz-models.svg)

**RBAC (role-based)** is the one most apps start with - and many never leave. You assign users to **roles**, and roles carry permissions. "Alice is an `editor`; editors can edit documents." Clean, easy to audit, works great until permissions need to depend on *which specific resource*. Modeling "editor of document #42" forces you into a role per object (`editor_doc_42`), and that's where the role explosion starts.

**ABAC (attribute-based)** makes the decision a computation over **attributes** - properties of the user, the resource, the action, and the environment. A rule might say: "Permit if `user.department == doc.department` and the request came in before 6 PM." Very expressive, great for contextual rules (time-of-day, IP range, clearance level). The downside: the logic lives in policy rules, and answering the reverse question - "what *can* Alice see?" - means testing those rules against every possible resource. There's no index to look up.

**ReBAC (relationship-based)** derives permissions from a **graph of relationships** between objects. "Alice is a `member` of `group:eng`; `group:eng` is an `editor` of `doc:roadmap` - therefore Alice can edit the roadmap." This is Google's Zanzibar model. It handles nested groups, ownership, sharing, and folder hierarchies naturally. And because the relationships are stored in a graph, the engine can traverse it *backwards* - answering "every doc Alice can edit" efficiently, not just "can Alice edit this one doc?"

To make the difference concrete, here's the *same* permission - "Alice can edit doc:roadmap" - expressed in each model:

| Model | How the permission is represented | How the check works |
| --- | --- | --- |
| **RBAC** | Alice has role `editor`; `editor` grants `edit` on all docs | Look up Alice's roles, check if any grants `edit` |
| **ABAC** | Rule: `permit if user.department == resource.department and action == "edit"` | Evaluate the rule with Alice's attributes and the doc's attributes |
| **ReBAC** | Tuple: `doc:roadmap#editor@group:eng#member` + `group:eng#member@user:alice` | Walk the graph from Alice to doc:roadmap via `member` -> `editor` |

Notice the trade-off: RBAC is the simplest to reason about but can't express "editor of *this specific* doc" without per-doc roles. ABAC can express anything but needs to evaluate rules against every candidate to answer "what can Alice edit?" ReBAC handles per-object permissions naturally *and* can answer the reverse query efficiently - but you're maintaining a graph.

These three aren't mutually exclusive - real systems blend them. Roles are just one kind of relationship; ABAC-style conditions show up in ReBAC schemas as guards. The useful question isn't "which model is purest" but: **where do your permissions naturally live, and what queries do you need to answer cheaply?** That question leads directly to *where* you deploy the authorization logic.

---

## 10. Where Decisions Live: PEP, PDP, PAP, PIP

There's an architectural question underneath the model choice: does your authorization logic live *inside* your application code (scattered `if` statements), or do you pull it out into a **dedicated component** that your app asks "yes or no?"

The simplest version - `if user.role == "admin"` sprinkled through your handlers - works fine for one service. It breaks down when authorization logic is scattered across ten services and nobody can answer "who has access to what?" without reading all the code.

The externalized architecture has four parts (the jargon originates from XACML - an XML-era standard for access control that nobody uses directly anymore, but whose *vocabulary* stuck because it cleanly names the moving parts):

![PEP / PDP / PAP / PIP authorization architecture](/diagrams/pdp-pep.svg)

Think of it like a courthouse:

- **PEP - Policy Enforcement Point.** The bailiff at the door of your API. It intercepts every request, asks "is this allowed?", and either lets it through or returns a 403. This is your middleware.
- **PDP - Policy Decision Point.** The judge. It evaluates the rules and returns Permit or Deny. This is the engine (OPA, Cedar, SpiceDB - whatever you deploy).
- **PAP - Policy Administration Point.** The legislature. Where policies are authored, versioned, and shipped to the judge. A git repo of `.rego` files, a Cedar policy store, an admin UI.
- **PIP - Policy Information Point.** The witness stand. When the judge needs extra facts to decide - the user's department, the resource's sensitivity label, the current time - the PIP supplies them.

The payoff: **enforcement and decision decouple**. Policy can change centrally without redeploying every service. The rules are testable and auditable in one place. The cost is an extra hop (or sidecar) to operate.

The two engine families below are both PDPs - they just differ in how they represent and answer the decision.

---

## 11. Policy Engines (OPA, Cedar, Cerbos)

A **policy engine** treats authorization as a logic problem. You feed it the inputs - who's asking, what they want to do, what they want to do it to, and any relevant context - and it evaluates declarative rules to produce a yes/no. It's stateless: it doesn't store your data, you bring the facts with each request (or preload them). That makes this family a natural fit for **ABAC** and rule-heavy decisions.

The three you'll encounter:

- **OPA (Open Policy Agent).** The CNCF standard, using the **Rego** language. Dominant for Kubernetes admission control and infrastructure policy; usable for app authz too. Because it isn't a database, relationship-heavy (ReBAC) use is awkward - you'd need to bundle the relationship data into OPA's memory or pass it on every request.
- **AWS Cedar / Amazon Verified Permissions.** Cedar is a purpose-built, readable policy language; AVP is the managed service. Cedar's standout feature: it's **formally analyzable** - you can use tools to *prove* properties like "this role can never reach that resource." Useful for compliance. Watch language versioning (the v4 migration can require policy rewrites).
- **Cerbos.** A stateless PDP using **YAML** policies - simpler to adopt than Rego. Its **Query Plan** API is interesting: it compiles a policy into a database filter (essentially a SQL `WHERE` clause), which is its answer to the "list everything this user can access" problem. Your app still runs the query, but the engine writes it for you.

The defining trait of the whole family: **they verify inputs, they don't index data.** That's a strength for contextual rules ("allow if user.clearance >= doc.classification and it's business hours") and a weakness for "list every document Alice can access." That list-objects problem is exactly the gap the next family was built to close.

---

## 12. Relationship-Based (Zanzibar) Engines

The other family descends from Google's **Zanzibar** paper - the system behind Drive, Docs, and YouTube permissions. Instead of evaluating rules against attributes, it stores your authorization data as a **graph of relationship tuples** and answers checks by walking the graph.

![ReBAC / Zanzibar relationship graph - concept diagram](/diagrams/rebac-graph.svg)

A tuple reads `object#relation@subject`. For example: `doc:roadmap#editor@group:eng#member` means "members of group:eng are editors of doc:roadmap." To answer `check(alice, edit, doc:roadmap)`, the engine walks: Alice is a member of `group:eng`, that group is an editor of the doc - Permit. Nested groups, folders that pass permissions to children, per-object sharing - they all fall out of the same traversal.

Here's the real payoff compared to policy engines: because the relationships are stored and indexed, the engine can read them **backwards**. "List every object Alice can edit" is a graph query, not a brute-force scan. That makes permission-aware search, filtering, and "show me my files" screens feasible at scale.

The main open-source implementations:

| Engine | Lang | License | Notable |
| --- | --- | --- | --- |
| **OpenFGA** | Go | Apache 2.0 | CNCF Incubating; great DX (Playground, VS Code ext, CLI). The reference point. |
| **SpiceDB** | Go | Apache 2.0 | By AuthZed; **ZedToken** consistency, Watch API, many DB backends, K8s operator. |
| **Ory Keto** | Go | Apache 2.0 | Part of the Ory stack; integrates with Kratos. Fewer consistency knobs. |
| **Permify** | Go | **AGPL-3.0** | Similar model; the copyleft license can be a blocker for proprietary stacks. |

One thing blurring the line between the two families: both OpenFGA and SpiceDB now support **conditions** (sometimes called "caveats") on relationships - essentially ABAC-style guards attached to a tuple. For example, you can write a relationship that says "Alice is a viewer of doc:financials *if* the request context shows `ip_network == 'corporate'`." The relationship exists in the graph, but the engine only treats it as active when the condition is met at check time. This means you don't have to choose purely between engines - Zanzibar systems can handle contextual rules too, just not as their primary strength.

The cost: you're running what is effectively a specialized database. You have to keep its tuples in sync with your application data - when a user joins a group or a doc moves to a new folder, you write a tuple. If that sync drifts, permissions drift. The typical patterns for keeping tuples in sync: write the tuple in the same database transaction as the application change (strongest, but couples your app to the authz store), or use an **event-driven approach** - emit a domain event ("user added to group") and have a consumer write the corresponding tuple. The transactional outbox pattern works well here if you need at-least-once delivery without distributed transactions.

---

## 13. Two Problems That Only Show Up at Scale

Checking a single permission is easy in any model. Two problems appear once you have real traffic and real data, and dealing with them is most of why Zanzibar engines are as involved as they are.

### Stale data (the "New Enemy" problem)

Let's work through a concrete scenario. You remove Bob from a confidential project. A second later he opens a document in that project - and it still loads. What happened?

Here's the thing: to handle load, an authorization store runs as a **cluster** - a primary node accepts writes, and a fleet of **read replicas** answer checks. Replicas copy from the primary *asynchronously*, so they trail by milliseconds to seconds. Your removal of Bob committed to the primary, but his check happened to hit a replica that hadn't caught up yet - so it still saw "Bob is a member" and let him in.

Both engines give you tools to close that gap, but they work differently. Let's see each one handle the same "remove Bob, then check Bob" sequence.

**OpenFGA approach - consistency flag on the check:**

```text
# 1. Remove Bob from the project
POST /stores/{store}/write
{
  "deletes": {
    "tuple_keys": [{
      "user": "user:bob",
      "relation": "member",
      "object": "project:secret"
    }]
  }
}
← 200 OK

# 2. Bob immediately tries to view a doc in that project.
#    Your app knows this is a sensitive resource, so it asks
#    for a high-consistency check (read from the primary, not a replica):
POST /stores/{store}/check
{
  "tuple_key": {
    "user": "user:bob",
    "relation": "viewer",
    "object": "doc:secret-plan"
  },
  "consistency": "HIGHER_CONSISTENCY"
}
← { "allowed": false }
```

OpenFGA's model is simple: for checks where staleness could hurt, you pay for a primary read. For the other 99% of checks (loading a dashboard, rendering a sidebar), replicas are fine. The trade-off is binary - you either hit the primary or you don't. There's no way to say "I need freshness relative to *this specific write*."

**SpiceDB approach - freshness receipt (ZedToken):**

```text
# 1. Remove Bob from the project - SpiceDB returns a token
POST /v1/relationships/write
{
  "updates": [{
    "operation": "DELETE",
    "relationship": {
      "resource": { "object_type": "project", "object_id": "secret" },
      "relation": "member",
      "subject": { "object_type": "user", "object_id": "bob" }
    }
  }]
}
← { "written_at": { "token": "GhUKEzE2ODU2..." } }

# 2. Bob tries to view the doc. Your app passes the token from step 1:
POST /v1/permissions/check
{
  "resource": { "object_type": "doc", "object_id": "secret-plan" },
  "permission": "view",
  "subject": { "object_type": "user", "object_id": "bob" },
  "consistency": {
    "at_least_as_fresh": { "token": "GhUKEzE2ODU2..." }
  }
}
← { "permissionship": "NO_PERMISSION" }
```

SpiceDB's token is more precise: it doesn't force a primary read, it just guarantees the answer reflects *at least* that version. Any replica that's already caught up can serve it. You store the token alongside the action that triggered the write (e.g. return it in the API response, stash it in a session) and thread it into immediately-subsequent checks that must see that write.

**The shared idea:** most checks can tolerate a few milliseconds of staleness. Spend the cost of guaranteed freshness only on the checks where it matters - right after a security-sensitive write like revoking access.

### Listing what a user can access

"Can Alice open doc #42?" is easy. "Which docs can Alice open?" is the hard one - and it's the one that actually matters for building UIs (show me my files, filter search results by permissions, render a sidebar of accessible projects).

- **Policy engines** keep no index, so they do it the slow way: check every candidate one by one. Fine for 50 documents, hopeless for 50 million.
- **Zanzibar engines** store the relationships and read them *backwards*. A forward check asks "start at Alice, walk outward - can she reach doc #42?" The reverse query flips that: "start at *every* doc, walk inward - which ones have a path back to Alice?" Because the graph is indexed in both directions, this isn't a brute-force scan - the engine traverses only the edges connected to Alice (her groups, her org, her direct shares) and collects every object reachable from those. The result is "all docs Alice can edit" from a single graph traversal, not N individual checks.
- **Cerbos** splits the difference: it compiles the policy into a database filter and hands it to *your* database to do the narrowing.

---

## 14. Choosing

There's no universally correct engine - only fit. Two axes settle most decisions: **how relational are your permissions**, and **do you need to list accessible objects efficiently**.

| If you need... | Reach for... |
| --- | --- |
| Simple roles, a handful of permissions | Plain RBAC in your app/DB - don't over-engineer |
| Contextual rules (time, attributes, clearance), infra policy | A **policy engine** - OPA, Cedar/AVP, or Cerbos |
| Provable, auditable policies (compliance) | **Cedar** (formally analyzable) |
| Nested groups, sharing, ownership hierarchies | A **ReBAC / Zanzibar** engine - OpenFGA or SpiceDB |
| Permission-aware lists & search at scale | A **Zanzibar** engine (built to list efficiently) |
| Strong "revoke now" guarantees | SpiceDB (freshness receipts) or OpenFGA fresh reads |
| A managed service, minimal ops | **Amazon Verified Permissions** (Cedar) or AuthZed Cloud (SpiceDB) |

Practical guidance:

- **Start with RBAC.** Most applications never outgrow roles plus a few ownership checks. Add complexity only when a real requirement forces it.
- **Pick policy engines for rule-shaped problems**, Zanzibar engines for relationship-shaped ones. If you find yourself encoding a web of relationships as attribute rules, or "list everything this user can access" is getting slow - that's the signal to move.
- **License and ops are real constraints.** AGPL (Permify) may be a non-starter; running a consistent, highly-available authorization database is a commitment. A managed offering may be the better trade.
- **Keep enforcement thin and decisions centralized** - whichever engine you choose - so policy can evolve without chasing scattered `if` statements across services.

Authentication says who you are; authorization says what you can touch. Passwordless hardens the first answer; the right model keeps the second one fast and correct as you scale.

---

## References

- [WebAuthn - W3C Web Authentication](https://www.w3.org/TR/webauthn-2/)
- [FIDO2 / CTAP - FIDO Alliance](https://fidoalliance.org/specifications/)
- [FIDO Client to Authenticator Protocol (CTAP) - hybrid transport](https://fidoalliance.org/specs/fido-v2.1-ps-20210615/fido-client-to-authenticator-protocol-v2.1-ps-20210615.html)
- [passkeys.dev - cross-device and platform guidance](https://passkeys.dev/)
- [RFC 6238 - TOTP](https://datatracker.ietf.org/doc/html/rfc6238)
- [OWASP - Credential Stuffing & authentication guidance](https://owasp.org/www-community/attacks/Credential_stuffing)
- [Google Zanzibar - Consistent, Global Authorization System](https://research.google/pubs/pub48190/)
- [OpenFGA](https://openfga.dev/) · [SpiceDB / AuthZed](https://authzed.com/docs) · [Ory Keto](https://www.ory.sh/keto/) · [Permify](https://permify.co/)
- [Open Policy Agent (OPA)](https://www.openpolicyagent.org/) · [AWS Cedar](https://www.cedarpolicy.com/) / [Amazon Verified Permissions](https://aws.amazon.com/verified-permissions/) · [Cerbos](https://www.cerbos.dev/)
- [AuthZed - Alternatives to OpenFGA](https://authzed.com/learn/openfga-alternatives)
- [NIST SP 800-63B - Digital Identity Guidelines (Authentication)](https://pages.nist.gov/800-63-3/sp800-63b.html)
- Companion: [OAuth 2.0 & OIDC: Flows, CLI Auth & JWT Verification](/oauth2-oidc-flows-cli-jwt)
