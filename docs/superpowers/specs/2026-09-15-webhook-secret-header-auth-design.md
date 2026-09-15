# Design: get the webhook secret out of the URL (security board S1)

**Status:** DESIGN ONLY — awaiting Thomas's ruling. No code, no lab change, nothing deployed.
**Date:** 2026-09-15
**Board item:** `shared/credentials-and-keys-overview.md` §3 **S1**
**Scope note:** S1 is closed only when no secret travels in a URL *anywhere*, including docs.

---

## Part 0 — What was measured today (read-only)

Two things were inspected. Neither wrote to the lab: the Edit Action Method form was opened
and left without saving.

### 0.1 The AUTHORIZATION TOKEN dropdown on 26.3

Read straight out of the form's `<select name="auth_token">` on `bhnm-b.tstolt.com` (26.3):

| value | label |
|---|---|
| `None` | None |
| `JWT` | JWT Token |

**Two options. That is the whole list.** No "Bearer", no "API key", no "custom header" —
so the dropdown itself cannot carry a static shared secret in a header.

Selecting `JWT` reveals four fields, labels read from the DOM:

| field name | label | placeholder |
|---|---|---|
| `jwt_header_prefix` | Header Prefix | `Bearer` |
| `token_key` | Token Key | `token` |
| `login_url` | Login Url | — |
| `login_payload` | Token Authentication Payload | — (stored value renders as `*******`) |

So `JWT` is a **login-then-call flow**: BHNM POSTs `login_payload` to `login_url`, reads the
field named by `token_key` out of the login response, and sends
`Authorization: <Header Prefix> <token>` on the webhook request. BMC's own docs confirm this
verbatim for the Helix ITSM integration (`AR-JWT` / `access_token`).

One detail worth keeping: **`login_payload` is masked in the BHNM UI.** The URL field and the
payload field are not.

### 0.2 The `[header]` block — the finding that decides this design

The `BMC_II_Host` group on the same box carries a webhook method (BMC's own BHOM forwarder
template, currently `NOT IN USE`) whose WEBHOOK DATA PAYLOAD begins:

```
[header]
{
 "Content-Type"  : "application/json"
}
[header]

{ ...json body with macros... }
```

BMC documents this publicly, in the BHNM ITSM-integration page:

> In the "WEBHOOK DATA PAYLOAD" field, enter something like: `[header] { "X-Requested-By":
> "XMLHttpRequest", "Content-Type": "application/json" } [header] { … }`
> **Each header element must be on its own line. This includes the header tags and braces.**
> You can dynamically replace payload values using the built-in macros.

**BHNM can send arbitrary request headers on a webhook, with no JWT, no login endpoint and no
token lifecycle.** That is the mechanism S1 needs, and it is a documented product feature
rather than a trick.

Source: <https://docs.bmc.com/xwiki/bin/view/IT-Operations-Management/Operations-Management/BMC-Helix-Network-Management/NetworkManagement/Administering/Integrations/BMC-Helix-ITSM-Integration/>

### 0.3 The one thing not measured — and it gates the build

BMC documents `[header]` in a walkthrough that says to pick **Active Response Webhook**. Our
method must be plain **WebHook** (Part 2 of the 09-14 evidence: Active Response never delivers
RECOVERY/ACK/DEACK). The `[header]` example on this box *is* on a plain WebHook method — but
that method is `NOT IN USE` and has never fired, so nothing proves the engine parses the block
for that method type.

**Nothing below should be built until one capture run settles it.** See Part 6.

---

## Part 1 — What the secret actually is today

Not a password. A **capability**: a bearer string that is simultaneously the routing key.

```
BHNM Action Method URL  ──?secret=S──►  /webhook   ──►  SELECT … WHERE active_secret = S
iOS / PWA  ──X-Webhook-Token: S──►  /register      ──►  INSERT … active_secret = S
```

Three consequences that shape every option:

1. **The middleware holds no list of valid secrets.** `/webhook` with an unknown secret returns
   `{"status":"ok","notified":0}`; `/register` stores whatever string it is handed. There is no
   allowlist to check against, so the server cannot distinguish a live secret from a
   rotated-away one, and cannot refuse one.
2. **Clients never put it in a URL.** iOS (`AppDelegate.swift:107,136`) and the PWA
   (`pushRegistration.ts:82`) already send `X-Webhook-Token` on `/register`. The QR carries it
   inside an AES-GCM blob (`benem://configure?p=<ciphertext>`), which is not a URL-borne secret
   and should not be "fixed".
3. **Only one hop puts it in a URL: BHNM → middleware.** That is the entire fix surface.

Where it lives at rest: BHNM's Action Method row; `WEBHOOK_SECRET` in the admin container's
env; `device_tokens.active_secret` (plaintext) for every device; each device's saved connection;
every generated `benem://` link in the admin log. **Not** in `servers.json` — that file holds
the BHNM API key and PIN, nothing push-related.

---

## Part 2 — Options for the BHNM→middleware hop

### (a) `[header]` block — **recommended**

```
[header]
{
"Content-Type": "application/json",
"Authorization": "Bearer <secret>"
}
[header]
{ ...the existing 15-macro body, unchanged... }
```
URL becomes `https://bhnm-apns.example.com/webhook` — no query string.

- No new endpoint, no token issuance, no expiry, no clock, no second HTTP call in the alert path.
- Kills the exposure S1 names: BHNM's outbound log, any egress proxy, any access log that
  records query strings, `Referer`.
- **Bonus:** fixes `Content-Type: application/x-www-form-urlencoded` on a JSON body, which the
  09-14 evidence flagged as making the form-decode fallback load-bearing for every real webhook.
- Cost: one field edit in BHNM, ~6 lines in `main.py`, a docs sweep.

### (b) `JWT Token` dropdown — **rejected, with reasons**

It is the only *dropdown* option, and it is the wrong tool here:

- The static shared secret does not go away; it moves into `TOKEN AUTHENTICATION PAYLOAD` one
  hop earlier. Genuine gain: that field is masked in the BHNM UI. Genuine loss: everything else.
- It requires a `/webhook/login` endpoint, JWT signing and verification, expiry handling, and a
  per-server credential store the middleware does not have (Part 1.1).
- **It puts a second HTTP call in front of every page.** If login fails at 03:00 during the
  outage that is generating the alert, nothing is delivered. An alert path that depends on two
  requests to the same box is strictly less reliable than one.
- Unknowns nobody has measured: whether BHNM caches the token, whether it re-logs-in on 401,
  what it does when login times out.

Reach for it only if `[header]` fails to reach the wire *and* Thomas wants the credential masked
in the BHNM UI.

### (c) Secret as a body field — **the fallback if 0.3 fails**

`"secret": "<secret>"` as a 16th macro line. Needs no BHNM feature at all — the payload field is
just macro-substituted text, so it cannot fail the way (a) might. Same exposure profile as (a):
out of URLs and access logs, still readable by any BHNM admin.

Its one real downside: a malformed body would then fail auth and parsing together, and the
credential sits in the data. Keep it in reserve, documented, not built unless needed.

### Header name: `Authorization: Bearer`, not `X-Webhook-Token`

Tempting to reuse `X-Webhook-Token` — the clients already send it, so one name across all hops.
Reject that for `/webhook`:

**Caddy's access logger redacts `Authorization`, `Proxy-Authorization`, `Cookie` and
`Set-Cookie` by default, and logs every other header verbatim.** The same is true of most proxy
and APM loggers. Naming the header `X-Webhook-Token` would move the credential out of the query
string and straight back into any access log the day somebody enables one — repeating S1 one
layer down. (Today's `Caddyfile` has no `log` directive, so Caddy writes no access log at all —
that is a default we would be silently depending on.)

So: `/webhook` reads `Authorization: Bearer <secret>`. `/register` keeps `X-Webhook-Token` —
changing it would break every client in the field for no security gain, since that header is
read, not logged. Accept `X-Webhook-Token` on `/webhook` too, as a one-line second source, for
anyone whose proxy strips `Authorization`.

**Measure with (a):** with AUTHORIZATION TOKEN set to `None`, does a `[header]`-supplied
`Authorization` reach the wire, or does BHNM strip/overwrite it? If it is stripped, fall back to
`X-Webhook-Token` and note the logging caveat in INSTALL.md.

---

## Part 3 — Middleware change

`/webhook` resolves the secret from, in order:

1. `Authorization: Bearer <s>`
2. `X-Webhook-Token: <s>`
3. `?secret=<s>` — **deprecated**

and logs which one it used, on every single webhook:

```
[Webhook] auth via header — incident 29483
[Webhook] auth via QUERY STRING (deprecated) — incident 29483 — the secret is in the URL and
          lands in logs and proxies; move it to the [header] block, INSTALL.md §7.3
```

That one line is not decoration. It is the whole safety net of Part 4, and it is the
instrument-before-hypothesising rule applied before the change rather than after it.

No rate limiting on the warning: real webhooks are rare (31 in eleven days), and a line per
alert is what makes a missed migration visible.

Everything downstream is untouched — the secret is still the lookup key, `get_tokens_for_secret`
is unchanged, no schema change, no client change, no migration of stored rows.

Proposed release: **middleware 2.14.0**.

---

## Part 4 — Migrating without missing an alert

The hazard is that editing BHNM's Action Method and deploying the middleware are two
uncoordinated events, and there is exactly **one** live Method. A single flip that turns out
wrong means every alert 4xx's until somebody notices — the silent-paging failure mode this
project has now hit three times.

Ordered so that no step can drop an alert:

| # | Step | Alert path during this step |
|---|---|---|
| 1 | Deploy 2.14.0 (accepts all three sources) | unchanged — the live Method still uses the query string |
| 2 | Probe both forms against production by hand; confirm the two log lines | unchanged |
| 3 | In BHNM: **add** the `[header]` block. **Leave `?secret=` in the URL.** | both present; middleware prefers the header |
| 4 | Wait for one real alert (or a hand-triggered one). Read the log line. | covered by the query string if the header did not arrive |
| 5 | Only if step 4 says `auth via header`: remove `?secret=` from the URL | header proven before the fallback is removed |
| 6 | Watch for one more real alert | — |

Step 3+4 is the whole trick: **the two mechanisms overlap for one alert, and the log says which
one won.** No maintenance window, no coordination, and a wrong guess about `[header]` costs
nothing.

Rollback at any point: put `?secret=` back in the URL. One field.

### How long the query path stays accepted

Recommendation: **indefinitely, but loudly.**

S1's harm is that a *deployment* puts the secret in a URL. That harm ends at step 5 — not when
the code path is deleted. For a self-hosted product with an unknown install base, a date-based
removal means somebody's paging breaks on an upgrade they did not read. Deleting the branch is
cosmetic; migrating the deployments is the fix.

So: docs stop showing the query form **immediately** (that is the part of S1 the docs sweep
closes), the log shouts at anyone still using it, and the branch is removed only when Thomas
wants it gone. If a hard cut is preferred, tie it to an observable, not a date — zero deprecated
hits for 30 consecutive days — and say so in the release notes.

**Thomas's call.** I have no strong view; the loud-forever option is one `if` cheaper.

---

## Part 5 — Rotation cost, stated honestly

The reviewer asked specifically. The answer is uncomfortable and should not be softened:

### Today

| Where the secret lives | What rotation requires | Who |
|---|---|---|
| BHNM Action Method | edit one field | BHNM admin |
| `WEBHOOK_SECRET` env, admin container | edit `.env`, recreate `benem-admin` | VPS admin |
| Every `benem://` link and QR ever issued | regenerate, redistribute | admin, per user |
| Each device's saved connection | **re-scan the QR**, or hand-edit Push Secret in Settings | **every engineer** |
| `device_tokens.active_secret` rows | new row on next `/register`; **old rows linger forever** | nobody |
| `servers.json` | **nothing** — the webhook secret is not in it | — |

Between the BHNM edit and an engineer's re-scan, **that engineer is silently unpaged** — the app
looks healthy, the toggle reads enabled, and nothing anywhere says otherwise. The same class of
failure as the QR-onboarding defect (queue item 4).

### After this change

**Identical. Unchanged. Zero improvement.**

Moving a credential from the URL to a header changes who can *observe* it. It does nothing about
who must *re-enter* it. Saying otherwise on the security board would be wrong, so S1 should be
closed with the exposure fixed and the rotation cost left open as a separate item.

### Two findings that surfaced while costing this

1. **`WEBHOOK_SECRET` is a single global env var** (`benem-admin/main.py:39`), stamped into every
   QR the portal generates regardless of which server was selected. INSTALL.md §7.5 says *"Give
   each server its own secret … There is no global secret."* **The admin portal contradicts the
   install guide.** Either the docs are wrong or the portal is; somebody has to rule. Not part of
   S1, but it is the reason rotation is per-*estate* rather than per-server today.
   **RULED 2026-09-15 (decision 4): INSTALL.md was the wrong document and is corrected.** The
   portal's global env var is the truth on the ground; §7.5's per-server promise was never
   implemented. Change 1 is what finally makes the promise true.
2. **There is no allowlist** (Part 1.1), so nothing server-side can refuse a retired secret, and
   deprecation cannot be enforced — only observed.

### The separate change that would make rotation cheap

Not folded into S1; costed here so the option is on record. Give `servers.json` a
`webhook_secrets: ["new", "old"]` field, have `/webhook` and `/register` accept any entry, and
fan out to the union. Both secrets then work during a rollout, devices migrate lazily as people
re-scan, and the old one is dropped by deleting an array element once the admin device list
shows nobody on it. ~20 lines plus the admin UI, and it needs queue item 7 (admin device overview) to
be visible. ~~**Recommend sequencing it after item 5, not before.**~~

> **SUPERSEDED 2026-09-15 by decision 5 and Part 17.** This mechanism is **inside S1 change 1**,
> not a follow-on. The recommendation above is left visible rather than deleted so that a reader
> arriving at this paragraph does not act on it: a per-server secret split whose secrets cannot be
> rotated solves half the problem and leaves the other half looking solved. The admin device list
> (queue item 7) remains what makes "nobody is on the old secret" *observable*, but it is not a
> prerequisite for shipping the accepted list.

---

## Part 6 — The measurement that has to come first

One question decides everything: does a `[header]` block reach the wire on a **plain WebHook**
method, and does `Authorization` survive with AUTHORIZATION TOKEN = `None`?

**Proposed rig** — the same one as 2026-09-14, recipe in evidence §1.4:

- Rebuild the stdlib capture listener on the engineer's Mac, `192.168.2.224:8787`.
- Add **one temporary Action** to the `BeNeM` group with **one plain WebHook Method** pointed at
  `http://192.168.2.224:8787/capture?m=hdr`, carrying a `[header]` block with
  `Content-Type`, `Authorization: Bearer probe-not-a-real-secret` and `X-Webhook-Token: probe`.
- Trigger one host down/up on raspi-050.
- Read: which headers arrived, in what case, whether `Authorization` survived, and what
  `Content-Type` ended up as.
- Delete the temporary Action.

**The live BeNeM Method is not touched.** Worst case is a temporary object in the group, exactly
as on 09-14, and the production alert path cannot be affected.

~20 minutes. It also retires a second open question for free — whether `Content-Type` can be
corrected — and if the answer is "headers do not arrive", the design falls back to option (c)
with no work wasted.

**This lab change needs Thomas's approval before it happens.**

---

## Part 7 — The docs sweep (this is half of S1)

S1 is not closed while a doc shows the query form. Every occurrence outside
`docs/evidence/` and `docs/superpowers/` (both are historical records and stay as written):

| File | What changes |
|---|---|
| `docs/INSTALL.md:404` | webhook URL loses `?secret=`; the `[header]` recipe replaces it, quoting BMC's one-element-per-line rule |
| `docs/INSTALL.md:685–691` | the S1 paragraph in §12.5 is **rewritten, not deleted** — URL exposure gone; static shared bearer, readable by any BHNM admin, and the rotation cost from Part 5 remain |
| `docs/INSTALL.md:672` | rotation table row replaced with Part 5's honest version |
| `docs/INSTALL.md:754` | troubleshooting curl uses `-H "Authorization: Bearer …"` |
| `docs/INSTALL.md` (new) | a line recording that `[header]` is measured on 26.3 and unverified below it |
| `middleware/README.md:78,128,148,208` | four occurrences |
| `middleware/CLAUDE.md:77,216` | routing description + the hand-probe curl |
| `middleware/.env.example:32` | comment |
| `README.md:114` | root readme |
| `shared/push-payload-spec.md:11` | the cross-platform contract |
| `shared/credentials-and-keys-overview.md:82,103` | the table row and the S1 board row |
| `middleware/benem-admin/main.py:258` + `templates/push.html` | the Push Config page prints the copy-paste webhook recipe; it becomes URL + `[header]` block |
| `middleware/tests/*` (~15 call sites) | **left as they are** — they exercise the deprecated path, which still works, and that is worth keeping covered. Add two header cases, do not rewrite fifteen. |

**Parked, deliberately not touched:** `docs/benem-runtime-architecture.html` / `.json` both
render `POST /webhook?secret=` and the line *"the secret is the only gate"*. Those two files are
on the parked list pending Thomas's ruling and are **not** edited here. They will need a pass
before S1 can be marked closed — flagging it now so it is not discovered later.

---

## Part 8 — What breaks for the current release

| | Impact |
|---|---|
| iOS 2.13.1 (36), App Store | **none** — never puts the secret in a URL |
| PWA (live) | **none** — same |
| Existing self-hosted middlewares | **none** — the query path still works, they just get a log line |
| BHNM lab | one Method edit, reversible by retyping one field |
| Admin portal | Push Config's copy-paste string changes; no behaviour change |
| QR / `benem://` links | **unchanged** — secret is inside the AES-GCM blob, not the URL |
| Test suite (151 green) | stays green; two cases added |

**No client release is required for S1.** That is the whole reason this is cheap, and it is
worth stating on the board explicitly.

---

## Part 9 — What this does not fix

Listed so the board records reality rather than a green tick:

- The secret is still a **static shared bearer credential** with no expiry.
- Any BHNM admin who can open the Action Method can read it — the payload field is **not** masked
  (only JWT's `TOKEN AUTHENTICATION PAYLOAD` is).
- It is still stored in plaintext in `device_tokens.active_secret` and on every device.
- Anyone holding it can still push arbitrary alert text to every engineer's phone.
- **Rotation costs exactly what it costs today** (Part 5).
- `/register` still accepts any string, so the middleware cannot enforce retirement.

S1 as written is about the secret travelling in a URL. This closes that, and nothing more.

---

## Part 10 — Revocation, and what the client shows when the server disagrees with it

Added 2026-09-15 by ruling. Revocation does not exist today, and it is the **client half of the
per-server secret allowlist** in Part 5, so the two are one feature and are designed together.
The connecting idea: *what does the app display when its own belief and the server's answer do
not match?* Everything below is one answer to that.

### 10.1 A distinguishable "no longer accepted"

The app must be able to tell three outcomes apart, and today it can tell apart none of them:

| outcome | meaning | client behaviour |
|---|---|---|
| **accepted** | credential valid | normal |
| **refused** | this credential is no longer accepted | **terminal** revoked state |
| **unreachable** | network failure, TLS failure, server down | transient — retry, and say so |

Wire shape: **`401`, plus a JSON body `{"error": "credential_revoked"}`, plus proof the response
came from the middleware** — all three, on both the proxy path and `/register`.

The status code alone is nowhere near enough. A captive portal, a corporate proxy or a
misconfigured reverse proxy can produce a bare `401`, and some portals return arbitrary JSON.
**An engineer thrown out of their paging app in a hotel lobby is the worst false positive this
feature can produce**, and it would be indistinguishable from real revocation because the state
is terminal by design. So the client requires, as an `AND`:

1. status `401`;
2. body parses as JSON with `error == "credential_revoked"`; **and**
3. the response identifies itself as the middleware. **Checked: no such marker exists today** —
   `VERSION` appears only inside the `/health` and `/api/v1/diagnostics` JSON bodies, and the
   only custom response headers in the live deployment are Caddy's `X-Content-Type-Options` and
   `X-Frame-Options`. So this must be **added**: a `version` field in the revocation body
   itself, e.g. `{"error": "credential_revoked", "version": "2.14.0"}`. Preferred over a new
   response header because a reverse proxy can strip or rewrite headers and the body is already
   JSON the client must parse anyway. This is the condition a captive portal cannot satisfy by
   accident.

Anything failing any of the three is **unreachable**, not revoked. When in doubt the client
stays connected and retrying: a false "still working" self-corrects on the next request, a false
"you are revoked" does not.

`403` is deliberately not used: it is what the existing proxy already returns for SSRF-blocked
targets (`main.py`), and overloading it would make two unrelated conditions indistinguishable.

### 10.2 What happens to cached data

For a monitoring app, silently showing yesterday's incidents is worse than showing nothing —
an engineer glancing at a green board cannot tell it is stale. On revocation:

- **Cleared immediately:** cached incidents, tactical overview, threshold counts, maintenance
  map, device lists. Anything that asserts a *current* state of the world.
- **Kept:** the connection entry itself (name, URL, symbol, colour) and the ACK user, so the
  administrator can re-issue a QR and the user recognises which server was revoked. The stored
  secret is **wiped** — it is dead and keeping it invites a confusing retry.
- **The screen:** the server's row shows *"Access revoked — contact your administrator"* in the
  error colour, with the server name. Incident and tactical screens for that connection show an
  empty state carrying the same sentence, **not** a spinner and not stale rows. If the user has
  another working connection, offer to switch to it.

### 10.3 Revoked is terminal

No retry loop, no spinner, no background polling. The state persists across launches and is left
only by a successful re-onboarding (new QR, or an edited secret). Re-check **once** on a manual
"Try again" the user taps, never automatically — a fleet of revoked apps quietly hammering a
middleware is how a revocation becomes an outage.

### 10.4 It must not fire during a rotation overlap

This is the concrete reason the allowlist and the overlap window in Part 5 are one mechanism.
During rotation both the old and the new secret are in the server's accepted list, so a device
still holding the old one is **accepted**, not refused, and sees nothing at all. Revocation is
what happens when a secret is *removed from the list*, which is a deliberate administrative act
after the admin device overview shows nobody still using it. Without the overlap window,
rotating would tell every engineer simultaneously that they had been thrown out.

**Rule to encode: a secret is never removed from the accepted list in the same operation that
adds its replacement.**

### 10.5 Is stale-data-while-disconnected already a defect today?

**Unmeasured. Do not assume.** The measurement, which must happen before this part is built:

- Point the app at the middleware, load incidents so the cache is warm.
- **(a)** Make the proxy return `401` (retire the token server-side) and record exactly what each
  client shows: stale incidents? a spinner? an error? how long before anything changes?
- **(b)** Kill the network instead and record the same.
- If (a) and (b) look identical to the user, that is a defect **today**, independent of
  revocation, and it is the same class as the green-icon-on-a-dead-host wave.

iOS must be measured on a device against the lab, per the standing rule. PWA can be measured in
a browser. **Queue both so Thomas's part is one sitting** — see Part 12.

---

## Part 11 — "Registered and active" is local belief, not a verified fact

Same class as a green device icon on a dead host: the UI asserting health it has not verified.
Jonah's phone displayed a confident enabled toggle while being completely unreachable. **Stop at
design.**

### 11.1 The endpoint

`POST /register/status`, mirroring `/register`: `X-Webhook-Token` header for the secret, body
`{"token": "<device token>"}`. A POST for a read is deliberate — it keeps the device token out of
the query string, consistent with the whole point of S1.

```json
{ "registered": true,
  "registered_at":  "2026-09-15T16:58:33Z",
  "last_push_at":   "2026-09-15T17:15:41Z",
  "last_status":    200,
  "last_error":     null,
  "server_name":    "ThomasLabServer" }
```

`{"registered": false}` returns **`200`, not `404`** — "you are not registered" is a successful
answer to the question, and a `404` would be indistinguishable from a middleware that has no such
route, which is exactly the confusion this endpoint exists to end.

Depends on the `last_push_at` / `last_status` / `last_error` columns proposed in the evidence
file's follow-up 1. Those are worth adding for the admin portal anyway; this makes them
load-bearing.

### 11.2 Three states, and the third is the point

| state | when | what the row says |
|---|---|---|
| **confirmed** | server says registered | "Registered · last alert delivered 2 minutes ago" |
| **not registered** | server says no | "Not receiving alerts — tap to register" |
| **unknown** | the status call itself failed | "Can't reach the push server · last confirmed 14:03" |
| **revoked** | `401` + `credential_revoked` | "Access revoked — contact your administrator" |

**Today the UI collapses "unknown" into "fine", which is the whole defect.** The rule, and it is
the same one the device-status wave established: never render *unverified* as *good*.

A **Send test push** button belongs on the same row — the only control that proves the path end
to end rather than asserting it.

### 11.3 When it is called

On foreground, after registering, and when the Settings screen appears. **Not on a timer.**

### 11.4 Cross-platform, one item

Both clients need it, and both need the foreground re-check underneath it — `scenePhase ==
.active` on iOS, `visibilitychange` on the PWA. Same defect, different mechanism, same pass.
The PWA's version is `useState<PushState>(getPushState)`, which evaluates once on mount, so a
user who revokes permission in browser settings keeps seeing a stale state until remount.

---

## Part 12 — One concept, two names

`notificationsEnabled` on iOS (`SavedConnection`), `pushEnabled` on the PWA (`SavedServer`). The
same per-connection control with two names, in a monorepo whose `shared/` directory exists to
prevent exactly this. It already caused a wrong conclusion: a grep for `notificationsEnabled`
across the repo returns nothing on the PWA side and reads as "the PWA has no per-connection
control", which is false. The next person greps and reaches the same wrong conclusion.

**Canonical name: `pushEnabled`.** Approved 2026-09-15. The deciding reason is not brevity but
collision: **`notificationsEnabled` reads as the OS notification setting**, which is a different
control with different scope and a different effect — app-wide versus per-connection, and
"stop the phone showing" versus "stop the server sending". That ambiguity is precisely what cost
a round of this investigation, when a switch reading ON while iOS denied everything looked like
a working configuration. `pushEnabled` names the thing it actually governs — push delivery — and
matches the vocabulary already in `shared/` (`push-payload-spec.md`, "Per-server push
notification configuration" in `feature-spec.md`). It also needs no migration on the side that
already uses it.

**Nothing is renamed yet, and no rename gets its own commit.** Record the canonical name and both
current spellings in `shared/feature-spec.md` so the mapping is discoverable by the grep that
currently misleads, then **apply the rename at the next natural touch of each file** rather than
in a sweep.

The iOS side is not free: the field is `Codable` and its name is a persisted JSON key, so it
needs a `decodeIfPresent` fallback to `notificationsEnabled` or **every existing installation
silently loses its per-server setting** — the same shape as the migration already in
`SavedConnection.init(from:)`.

**The direction of the failure is what makes the fallback mandatory rather than tidy.** That
initialiser defaults the field to `false`:

```swift
notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
```

So a rename without a fallback does not merely lose a preference — it **fails closed**, silently
switching push **off** for every connection that had it on, on the next launch after the update.
For a paging product that is the wrong direction to fail in: the app keeps working, looks
healthy, and nobody is paged. It is the same failure shape as the QR-onboarding defect and the
same one the `CLAUDE.md` doctrine exists to prevent. A rename that fails *open* would be merely
annoying; this one goes quiet.

---

## Part 13 — Measurements that need Thomas, batched into one sitting

Grouped deliberately so his involvement is one session rather than three.

1. **Unregister A/B** (evidence item 5): force-quit, relaunch, toggle notifications off within a
   second, check for `[Unregister]` and probe. Control: same with a 10 s wait.
2. **401 vs network-down on iOS** (Part 10.5): warm the cache, retire the credential
   server-side, record what the screen shows; then repeat with the network down.
3. **`...62f21e50`**: whether the phone re-registering a token Apple has rejected since May is
   restoring from backup or sending a cached token.

All three are the same rig — one phone, the lab, and the middleware log open. The PWA halves of
2 can be done in a browser without him.

## Part 14 — Severity: the links were each on the board, and nobody joined them

Measured 2026-09-15. Each step below was already known and recorded separately; the chain is
what nobody had written down.

1. **The QR payload carries `push_secret` *and* `proxy_token`.** Both are put there by
   `benem-admin/main.py` when an administrator generates an onboarding link.
2. **In this deployment those two are the same 64-character value.** `WEBHOOK_SECRET` and
   `PROXY_TOKEN` are read from two distinct environment variables by correct code, and the
   `.env` sets both to one string. Verified: equal length, equal SHA-256, `a == b` true.
3. **The webhook secret is global, not per-server.** Building the QR payload through the
   portal's own code path for all four configured servers yields **four distinct `api_key`
   values and one `push_secret`**. `servers.json` has no webhook-secret field at all.
4. **The QR blob is encrypted with a static AES key that ships inside the public App Store
   binary** — board item **S4**, `ios/BeNeM/Secrets.swift`, known and accepted.
5. **The webhook secret travels in a URL** — board item **S1**, this document — so it also
   lands in BHNM's outbound logs, any egress proxy, and any access log that records query
   strings.

**Joined up:** extracting the static key from the shipped binary and obtaining *any* BeNeM QR
yields a credential that (a) pushes arbitrary alert text to every registered engineer, (b)
authenticates API-proxy calls and therefore reads BHNM data, and (c) does both **across all four
servers at once**, because the secret is global. Step 5 means the same credential is also
recoverable without the binary at all, from a log.

**`docs/INSTALL.md` §7.5 promises isolation the code does not provide:** *"Give each server its
own secret … A device only receives alerts from the server whose secret it registered with.
There is no global secret."* Every clause of that is false as deployed. The docs must be
corrected in the same change that fixes the portal, and until then the promise is the more
dangerous half — an administrator reading it has no reason to look.

---

## Part 15 — Is `PROXY_TOKEN` used by anything? Measured, and the answer is "almost nothing"

The hope was that `PROXY_TOKEN` could be rotated immediately, severing the leaked-URL-to-BHNM-data
link today without touching QR re-issue. **It cannot, but only just.**

### Every `X-Proxy-Token` sender

| sender | sends | notes |
|---|---|---|
| iOS `ContentView.swift:198` → `NetreoAPIService.swift:57` | **the `api_key`** (`proxyToken: apiKey`) | every normal data path |
| PWA `incidents.ts`, `tactical-overview.ts`, `thresholds.ts`, `maintenance.ts`, `diagnostics.ts` | **`config.apiKey`** | every normal data path |
| iOS `ServerConfigView.swift:309` | **`draftPushSecret`** | the **Test Connection** button |
| `benem-admin` internal call | `PROXY_TOKEN` | server-to-server, same `.env` |

**No client reads `proxy_token` out of the QR payload.** Neither `DeepLinkHandler.swift` nor
`pwa/src/lib/qr-parser.ts` mentions it — it is carried, encrypted, and ignored. That is a
credential shipped to every device for nothing, and it should be dropped from the payload.

### Why rotation is not free

`_verify_proxy_token` accepts the global `PROXY_TOKEN` **or** any `api_key` in `servers.json`.
Probed live against the catch-all proxy route:

```
random value                        -> 401 {"detail":"Invalid proxy token"}
a servers.json api_key              -> passes auth (403 from BHNM upstream)
WEBHOOK_SECRET (= PROXY_TOKEN today)-> passes auth (403 from BHNM upstream)
```

So **Test Connection authenticates only because the two values are equal.** `draftPushSecret` is
the webhook secret; it is not an `api_key`, so with a rotated `PROXY_TOKEN` it would match
neither branch and the button would return `401` on the shipped App Store build.

**Conclusion: something does use it, so rotation waits for the overlap window**, as ruled.

### The fix that makes rotation free, and the wrinkle in it

`ServerConfigView.swift:309` should send `draftApiKey`, exactly as every other call site does —
sending the *push* secret in the *proxy* header is the anomaly. One line.

The wrinkle: `_verify_proxy_token` accepts only `api_key`s **already present in `servers.json`**,
and Test Connection is most useful precisely when a server is *not* yet known to the middleware.
The global `PROXY_TOKEN` is currently what lets an unknown-to-the-middleware client test a
connection at all. So the one-line change is necessary but not sufficient, and what Test
Connection should authenticate with for an unknown server is an open question.

---

## Part 16 — Should `PROXY_TOKEN` exist at all? (design question, not a build)

`PROXY_TOKEN` is a **single global credential granting proxy access to every configured server**,
sitting beside per-server `api_key`s that already work and that every real data path already
uses. That is the same design flaw as the global webhook secret, one layer down: one string,
whole-estate blast radius, no per-server revocation, and nothing that can be rotated for one
tenant.

Rather than assume it must be kept, the question to settle is whether it should exist:

- **Drop it.** Authenticate the proxy on `api_key` alone — already the only thing clients send
  for data. Cost: the unknown-server Test Connection case (Part 15) needs another answer, and
  `benem-admin`'s internal call needs a credential of its own, which it can have without being
  the same one every device holds.
- **Keep it, scoped.** Retain a global token but restrict it to `/internal/*` and admin-origin
  calls, never the `/api/v1/*` data routes. The leak of a data credential then cannot become an
  admin credential.
- **Keep it as is.** Only defensible if something genuinely needs whole-estate proxy access from
  a client, and Part 15 found nothing that does.

Recommendation: **scope it**, then drop it once Test Connection has a per-server answer. Either
way it should come out of the QR payload immediately, since nothing reads it.

## Part 17 — S1 ships as TWO changes, in this order (ruling, 2026-09-15)

**Change 1 — per-server secret split**, with the accepted-list and overlap-window mechanism from
Part 5. **Change 2 — header transport**, Parts 2–4. Not combined.

**Why, and it is not caution for its own sake.** A combined migration touches BHNM Action
configuration, middleware authentication, QR generation and every device registration *at the
same time*. This week was three days spent untangling failures that hid behind one another — a
method type that never delivered recoveries, masking a handler that never returned, masking a
fan-out that served only the first row, masking a phone whose notifications were switched off.
Each was invisible until the one in front of it was removed. A migration with four simultaneous
moving parts is precisely the shape that makes the next failure unattributable: an alert that
does not arrive could be the Action config, the auth path, a stale QR, or a device that never
re-registered, and no log distinguishes them.

Two touches per Action is cheap at four servers. Unattributable paging failures are not.

**Order matters, and it is this way round for a reason.** The split comes first because the
header change is *transport* — it moves an existing credential to a different part of the
request — whereas the split changes *which devices a secret reaches*. Doing transport first
would mean migrating a credential that is about to be replaced anyway, and every device would be
touched twice. Doing the split first means change 2 migrates a secret that is already correct.

**Each change independently verifiable**, which is the whole point:

| | change 1 | change 2 |
|---|---|---|
| verified by | one alert per server reaching only that server's devices | one alert whose log line reads `auth via header` |
| rollback | remove the new secret from the accepted list | put `?secret=` back in the URL |
| devices touched | re-scan, staged behind the overlap window | **none** |
| BHNM Action fields | URL (or none, if secrets are per-server in `servers.json`) | payload `[header]` block, then URL |

### Change 1 splits again, into 1a and 1b (ruling, 2026-09-15)

Same reasoning that split S1 into two changes, applied one level down: **1a is mechanism with no
behavioural change, 1b is the operational split.** Separately deployable, separately verifiable,
separately reversible.

#### 1a — mechanism only. No behavioural change. No device touched.

Scope:

- An **accepted-secrets list per server** in `servers.json`.
- **Server resolution on `/webhook`** — the handler learns which server a webhook came from.
- **Per-server binding on `/register`** — a registration records which server it belongs to.
- A **server dimension in the token lookup**, so a fan-out can be scoped to one server's devices.
- The **admin portal reads per-server** rather than from the single global `WEBHOOK_SECRET` env var.

**Seed every server's accepted list with the CURRENT global secret.** That is the whole reason
this is safe to ship alone: every existing device keeps working, no QR is reissued, nobody
re-onboards, and paging behaves exactly as it does today. The change is invisible from the outside
— which is the point, because it means any change that *is* visible after deploying it is a bug in
1a and nothing else.

**Why it gets its own deploy and its own verification: this is where the risk lives.** It touches
the webhook handler and the registration path, and this week those two have bitten three times —
a handler that never returned, a fan-out that served only the first row, and a registration that
never happened. A mechanism change landing on top of an operational migration would make the
fourth one unattributable.

Verified by: an alert still reaches every device it reaches today, a fresh `/register` still
succeeds, and `/health` still reports the same device count — with no QR reissued and no phone
touched.

#### 1b — the operational split.

New per-server secrets, new QRs, Thomas and Jonah re-onboard, then the global secret is retired
from the accepted lists. Rollback is removing the new secret from a list; the global one is still
accepted until the last step.

**Required step of 1b, not a nicety: REMOVE the unresolved-secret fallback.**

1a falls back to the pre-1a single-secret lookup when no server lists the incoming secret. That
fallback is **1a's safety net and 1b's obstacle**, and the two facts are the same fact: while it
exists, a device still holding the global secret keeps being paged *through it*, so retiring the
global secret from the accepted lists **does not actually split anything**. The migration would
report success while every un-migrated device carries on exactly as before, and the first person
to notice would be whoever eventually stopped being paged for an unrelated reason.

So 1b is not complete when the global secret leaves the accepted lists. **1b is complete when the
fallback is deleted and an unresolvable secret is refused.** Sequence inside 1b: new secrets
issued → everyone re-onboarded → the loud log quiet for long enough to cover every device →
global secret removed from the lists → **fallback removed** → an unresolved webhook now fails
loudly instead of silently succeeding.

**While the fallback remains, it logs loudly every single time it fires.** Not a debug line: the
number of devices still on the old path must be *visible*, not inferred from someone's memory of
who re-scanned. That log is the same cheap 1b signal described below, and it is what makes the
"quiet for long enough" gate a measurement rather than a belief.

**The dependency the queue order hides.** The global secret cannot be safely retired without
seeing **which devices still use it** — retire it blind and whoever has not re-scanned stops being
paged, silently, which is the exact failure mode this spec exists to prevent. That visibility is
queue item 7, the admin device overview.

**Ruling on which comes first: item 7 does NOT need to move ahead of 1b. A cheaper signal
suffices, for this fleet.** The middleware should log which server and which accepted-secret entry
each `/register` and each `/webhook` arrived with; with three devices and four servers, reading
that log answers "is anybody still on the global secret?" directly, and it is a handful of lines
rather than a portal feature. The admin overview remains the right long-term home and item 7 is
where it lands — but blocking an operational migration on a UI feature, when a log line answers
the same question for a three-device fleet, is the kind of sequencing this project has already
paid for once.

**Resolution during 1a is ambiguous, and must never name a server.** Every server carries the
same seeded secret, so the first match is arbitrary. The resolver returns the *list* of matching
servers and the log names one only when exactly one matches; otherwise it prints
`server=<ambiguous: N servers share this secret>`. After 1b, secrets are unique and it always
names one.

**Rejected, and recorded so it is not re-proposed: refusing to resolve at all when ambiguous.**
It sounds like the stricter choice and is the opposite. During 1a every webhook is ambiguous by
construction, so refusing would send *every* webhook down the FALLBACK path — and FALLBACK is the
1b signal, whose entire meaning is "somebody is on an unlisted secret". Making it fire constantly
destroys the measurement that gates retiring the global secret.

**Log the resolved server name and a short non-reversible fingerprint of the secret — never the
secret, and never a prefix of it.** Name the field `secret_fp=`, not `secret=`: the 2.13.2
redaction filter rewrites `secret=…` and blanked the fingerprint in the *persisted* log, the only
one that survives a container recreate — so the 1b question would have been answered "nobody"
when it meant "we can no longer tell". A truncated SHA-256 is enough to tell two secrets apart in a
log, and 2.13.2 is the precedent for why this warning is written down rather than assumed.

The gate on retiring the global secret is therefore: *no `/register` and no `/webhook` has arrived
on the global secret's fingerprint for long enough to cover every device*, not *we think everyone
re-scanned*.

---

## Part 18 — What Test Connection should authenticate against

Measured 2026-09-15, and it reframes the problem:

- **`ServerConfigView` is reached from exactly two places**, both in `SettingsView`: edit an
  existing connection, or add one manually. **The QR/deep-link path never opens it** —
  `DeepLinkHandler` writes the connection straight to `UserDefaults`. So Test Connection is
  **manual-configuration only** and is not on the onboarding path at all.
- **A failed test does not block anything.** `saveDisabled` checks only empty fields and
  `isTesting`; it does not consult `testStatus`. The user still saves and uses the server.

So the button is a setup-time reassurance, not a gate — which is what makes rotating
`PROXY_TOKEN` ahead of the next release a real option rather than a breakage (Part 15).

**The design catch:** the button matters most for a server the middleware does **not** know yet,
so "accept any `api_key` in `servers.json`" cannot be the whole answer. Three shapes:

1. **Authenticate with the key the user just typed.** The request already carries
   `password=draftApiKey` in its body and `X-BHNM-Target`. Let the proxy, for this one route,
   accept the request when the *upstream* accepts the credentials — the middleware is relaying a
   login attempt, not guarding its own resource. Simple, but it makes an unauthenticated route
   that will happily relay to any target, so it needs the existing SSRF `_validate_proxy_target`
   and a rate limit.
2. **Bypass the proxy entirely.** What Test Connection actually tests is *"can I reach this BHNM
   and do these credentials work"* — a question about BHNM, not about middleware auth. Have the
   app call BHNM directly. Honest about what is being measured, and needs no proxy credential at
   all. Fails where the app cannot reach BHNM directly, which is exactly the deployment the
   proxy exists for — so it would report failure for a working configuration.
3. **Test the middleware and BHNM separately, and say which failed.** Two checks, two results:
   *"middleware reachable ✓ / BHNM reachable ✗"*. More code, and the only shape that does not
   collapse two very different failures into one red indicator — which is the same
   `CLAUDE.md` doctrine problem in miniature: today a single "test failed" cannot distinguish
   a wrong API key, an unreachable BHNM, and a middleware that rejected the proxy token.

**Recommendation: 3**, with 1 as the mechanism for its BHNM leg. It is the only one that
answers the question the user is actually asking, and it removes the last client-side use of
`PROXY_TOKEN` as a side effect.

Interim, regardless: `ServerConfigView.swift:309` should stop sending `draftPushSecret` as
`X-Proxy-Token`. Sending the *push* secret in the *proxy* header is an anomaly that only works
because the deployment set both env vars to one value.

## Decisions — ALL DECIDED 2026-09-15. Do not reopen.

Ruled in the decision sitting of 2026-09-15 — Thomas's calls and the reviewer's rulings, relayed
by Thomas. Recorded with reasoning so the reasoning is not re-derived. **With these, S1 change 1
is unblocked.**

1. **Part 6 measurement — SPENT. It ran, and it passed.** Approved and executed before this
   sitting; do not re-ask. Result in Part 6 and in the evidence file: `[header]` works on a plain
   WebHook method (not only on Active Response Webhook), a 64-character value survives intact,
   `Authorization` survives with `AUTHORIZATION TOKEN = None`, a header block and a JSON body
   coexist, and `Content-Type: application/json` arrives correctly. The gate on S1 change 2 is
   therefore open.
2. **`Authorization: Bearer` on `/webhook`. Settled.** Caddy and most loggers redact
   `Authorization` by name; custom headers such as `X-Webhook-Token` are logged verbatim, which
   is how a secret ends up in a log file nobody is watching.
3. **Deprecation: loud forever. Settled.** No hard cut. **"Closed" means no supported
   configuration uses the URL form** — not that the URL form has been made to fail. Docs change
   now.
4. **The `WEBHOOK_SECRET`-is-global contradiction: INSTALL.md was the wrong document, and is
   corrected.** Settled. The portal's single global env var is the truth on the ground; §7.5's
   per-server promise was never implemented. The docs sweep corrects INSTALL.md rather than
   claiming the portal is broken.
5. **Rotation is NOT a follow-on. The overlap window (Part 15) is part of S1.** Settled — this
   supersedes the framing of the original question. It ships inside S1 change 1, not after queue
   item 5, because a per-server secret split whose secrets cannot be rotated solves half the
   problem and leaves the other half looking solved.
6. **`pushEnabled` is canonical. Settled.** Recorded in `shared/` now; iOS renames at the next
   natural touch of each file with a `decodeIfPresent` fallback (Part 12). The PWA already uses
   `pushEnabled` — confirmed by observation, the stored server record on the live PWA carries
   `pushEnabled` today.
7. **Part 13 sitting — Thomas's calendar. The runbook stands as written:**
   `docs/runbooks/2026-09-15-one-sitting-device-measurements.md`. Nothing to re-plan; it is a
   scheduling item, not a design item.
8. **`PROXY_TOKEN`'s future: scope it to `/internal/*`, then drop it from the data path.**
   *Reviewer, accepting the recommendation in Part 16.* **Sequenced AFTER the Test Connection
   fix**, because that button is the one thing still depending on it — removing the dependency
   before fixing its only consumer would break the consumer. `proxy_token` is already gone from
   the QR payload (commit `a36e37b`), so nothing new is required there.
9. **Rotate `PROXY_TOKEN` now — YES**, *Thomas's call*, with one condition and a fixed procedure.
   **Condition:** unless Thomas says someone outside himself and Jonah will be configuring a
   server this week. **Tell Jonah first**, so a red indicator is not mistaken for a broken setup.
   **Procedure, in order:**
   1. Back up `.env`.
   2. Rotate `PROXY_TOKEN` (and only it — `WEBHOOK_SECRET` is a separate decision).
   3. Restart the middleware.
   4. **Verify both apps still load incidents** — they authenticate with `api_key`, so they must
      be unaffected. This is the check that proves the rotation was scoped correctly.
   5. **Verify `check-env.sh` goes green, including the new identical-values check** — the check
      that `PROXY_TOKEN` and `WEBHOOK_SECRET` are no longer byte-identical.
   6. **Confirm Test Connection now fails on 2.13.1 — observed, not assumed.** The regression is
      expected; recording it as an observation now means it is not rediscovered later as a
      mystery. Measured basis for accepting it: Test Connection is manual-config only, is never
      reached during QR onboarding, and a failed test does not block saving.
10. **Correct INSTALL.md §7.5's false isolation promise now, ahead of the overlap window.**
   Settled, and consistent with 4 — a document promising isolation the system does not provide
   is worse than one that is silent, and it must not wait on the rotation work.

**Also settled in the same sitting:** S1 ships as **two changes** — change 1 (per-server secret
split + rotation/allowlist, including the overlap window) and change 2 (header transport) — not
as one.
