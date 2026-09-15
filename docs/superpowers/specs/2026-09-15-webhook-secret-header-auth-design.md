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
2. **There is no allowlist** (Part 1.1), so nothing server-side can refuse a retired secret, and
   deprecation cannot be enforced — only observed.

### The separate change that would make rotation cheap

Not folded into S1; costed here so the option is on record. Give `servers.json` a
`webhook_secrets: ["new", "old"]` field, have `/webhook` and `/register` accept any entry, and
fan out to the union. Both secrets then work during a rollout, devices migrate lazily as people
re-scan, and the old one is dropped by deleting an array element once the admin device list
shows nobody on it. ~20 lines plus the admin UI, and it needs queue item 5 (device overview) to
be visible. **Recommend sequencing it after item 5, not before.**

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

Wire shape: **`401` with a JSON body `{"error": "credential_revoked"}`** on both the proxy path
and `/register`. The status code alone is not enough — a captive portal or a misconfigured
reverse proxy can produce a bare `401`, and treating that as revocation would throw an engineer
out of the app on hotel wifi. The body discriminates; a `401` without it is treated as
unreachable, not revoked.

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

**Proposed canonical name: `pushEnabled`.** It is the more precise of the two — the control
governs *push delivery*, not notifications in general, and the rest of the vocabulary in
`shared/` is already "push" (`push-payload-spec.md`, "Per-server push notification
configuration" in `feature-spec.md`). It is also the name that needs no migration on the side
that already uses it.

**Nothing is renamed yet.** The immediate step is to record the canonical name and both current
spellings in `shared/feature-spec.md`, so the mapping is discoverable by the grep that currently
misleads. When the iOS rename does happen it is not free: the field is `Codable` and the name is
a persisted JSON key, so it needs a `decodeIfPresent` fallback to the old key or every existing
installation silently loses its per-server setting — the same shape as the migration already in
`SavedConnection.init(from:)`.

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

## Decisions needed from Thomas

1. **Approve the Part 6 measurement?** One temporary Action in the `BeNeM` group plus the capture
   listener; the live Method untouched. Nothing else here can start until it runs.
2. **`Authorization: Bearer` or `X-Webhook-Token` on `/webhook`?** Recommendation: `Authorization`,
   because loggers redact it by name and custom headers are logged verbatim.
3. **Deprecation: loud forever, or a hard cut?** Recommendation: loud forever; docs change now.
4. **The `WEBHOOK_SECRET`-is-global contradiction (Part 5, finding 1)** — is the portal wrong or
   is INSTALL.md §7.5 wrong? This changes what the docs sweep should say.
5. **Rotation as a follow-on item** — schedule the overlap-window design after queue item 5, or
   drop it?
6. **Canonical name `pushEnabled`** (Part 12) — agreed as the one name, recorded in `shared/`
   now and renamed on iOS later? Or keep `notificationsEnabled` and rename the PWA instead?
7. **Part 13 sitting** — when, and is one session with the phone and the lab workable?
