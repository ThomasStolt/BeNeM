# Security hardening, the connection probe and diagnostics — session handoff

**Date:** 2026-09-18, written at 21:50Z.
**Supersedes:** `docs/superpowers/2026-09-17-proxy-allowlist-and-webhook-payload-handoff.md` for
**state**. That file remains the authority for the older decision records.

Written for a reader with no memory of this work. **Every state claim below was observed, not
recalled** — the raw output is inline. Thomas exercised all four clients and the browser before
this was written; the unit is closed.

---

## (a) What landed

**Eighteen commits, `81c5159..27f447e`, all pushed.** Three middleware releases, one PWA release,
one iOS build that is **deliberately not released**.

| commit | what changes in behaviour |
|---|---|
| `81c5159` | evidence: a server's api_key reached the OTHER configured servers. **CROSS**, filed HIGH |
| `c19d479` | **middleware 2.17.0 — key-target binding.** A request authenticated with a server's api_key may target **only that server**. Mismatch is 403 in ~59 ms |
| `48e3ccf` | deploy record for 2.17.0; corrected sizing of the PROXY_TOKEN item |
| `cc27566` | withdrew the deploy-window cause for the iPhone 15 stall; named the request-arrival blind spot |
| `b7fa7ad` | **`PROXY_TOKEN` rotated.** The shared push secret is no longer the operator token. Config only, no code |
| `a6ef22c` | corrected the rotation's predicted casualty — bigger than stated, not zero |
| `c798a03` | **iOS: the save probe sends the api_key**, not the push secret. 403 stops blaming the key |
| `fbc2aae` | iOS: **Save stays pressable** when nothing changed — it is also the only retry |
| `941d95f` | **Both clients probe `incident_api.php`**, not the broken `ha_status_api.php`. O(1) and it checks the credential |
| `3fac487` | **Three-outcome verdict** — verified / auth-failed / **inconclusive**. A save says what it verified |
| `a95a0c8`, `33358bf` | wording: the PIN is SaaS-only; "credentials" not "API key" |
| `95e3559` | PWA 0.16.3 deployed; **a deploy does not reach an already-open browser** |
| `71b4f92` | **iOS unit-test target.** Adds `ServerDraft` only — the app is untouched, so this commit reverts alone |
| `adde589` | **iOS: a toggle no longer destroys the webhook secret**, and the add/edit lock-out is gone |
| `1b87765` | **middleware 2.18.0** `/health` reduction, versions in the topology, secret masking, QR unlock |
| `abd71a4` | **PWA 0.17.0** — and the rule that a deploy must state what it deployed |
| `27f447e` | **iOS 2.13.2 (44)** installed on the 13 Pro Max. **NOT released** |

### The behaviour changes that matter

- **2.16.0 (yesterday) made `servers.json` the allowlist.** A proxy target that is not a configured
  server is refused, 403 in ~39 ms instead of a 60 s hang.
- **2.17.0 binds a key to its target.** 2.16.0 stopped an api_key being a relay to the whole
  internet; it did **not** stop key A reaching server B, and the cold-cache fall-throughs sent the
  *caller's own* credential to a header-supplied host. The trigger was a wrong `X-BHNM-Target`,
  not an attacker. One guard, in `_validate_proxy_target`, because all six call sites route
  through it. Duplicate api_keys now refuse at load with 503, named by fingerprint.
- **`PROXY_TOKEN` rotation** made the operator exemption mean something. It had the same value as
  `WEBHOOK_SECRET`, which is the push secret on four phones and in every QR code — so the binding
  exemption was held by every client. One line in `.env` plus a recreate of two containers.
- **2.18.0 reduced `/health`** to liveness and version, and dropped the fleet-wide device count
  from `/api/v1/diagnostics`. It also added `server.bhnm.version`.
- **Both clients' connection probe** now hits the endpoint the app actually uses, with a
  constant-size reply, and reports **inconclusive** rather than guessing.
- **iOS gained a unit-test target.** Seven pure-logic tests, no view or snapshot or UI tests.

---

## (b) Deployed state — observed 2026-09-18T21:48:30Z

```
### /health (unauthenticated)
{"status":"running","version":"2.18.0"}

### /api/v1/diagnostics (authenticated)
middleware: 2.18.0 | keys: ['server_time', 'version']
bhnm reachable: True | version: None | fails: 0
  incidents        cached=True age=85 count=16 fails=0
  tactical         cached=True age=11 count=15 fails=0
  thresholds       cached=True age=18 count=37 fails=0
  maintenance_map  cached=True age=54 count=41 fails=0

### PWA
bundle: /assets/index-BtxzrBca.js
"0.17.0"

### containers
benem-middleware StartedAt=2026-09-18T21:18:05.336Z RestartCount=0
benem-pwa        StartedAt=2026-09-18T21:26:42.818Z RestartCount=0
benem-admin      StartedAt=2026-09-18T10:40:39.233Z RestartCount=0
benem-proxy      StartedAt=2026-09-14T15:36:58.253Z RestartCount=0
```

**`bhnm.version: None` is the correct answer for this server, not a failure** — on-prem BHNM
exposes no api_key-readable version. The SaaS demo server on the same endpoint returns
`'26.3-01.17.el8.noarch'`.

**Secrets, by fingerprint only:**

```
PROXY_TOKEN    fp 4275908e     <- rotated 2026-09-17T14:26Z
WEBHOOK_SECRET fp 95e54469     <- deliberately unchanged
  SaaS Demo Server     api_key len=59 fp=bfa916f3 cache=False
  ThomasLabServer      api_key len=15 fp=4ad371ae cache=True
  Steve                api_key len=60 fp=96d6e234 cache=False
  Luiz                 api_key len=9  fp=60270a6e cache=False
```

**The refusal log, whole file:** `not owned by this key` **2** · `not in servers.json` **8** ·
`OPERATOR TOKEN selected` **2** · **errors or tracebacks today: 0**.

**Rollback images:** `bhnm-apns-bhnm-apns:pre-2.18.0`, `bhnm-apns-benem-pwa:pre-0.16.3`, plus the
2.17.0 set. Pre-deploy log dumps in `/root/logdumps/`.

---

## (c) Lab state — observed 2026-09-18T21:48Z

Devices **searched by name, never counted**, per the `CLAUDE.md` rule:

```
raspi-050    rows found: 1 | UP | lastUpdateTime 2026-09-18 23:46:05 | dur 2d 1h 53m 26s
BHNM-B-SE01  rows found: 1 | UP | lastUpdateTime 2026-09-18 23:48:06 | dur 2d 8h 22m 35s
```

Both `lastUpdateTime` values advancing, so the engine is alive. `host_down` empty,
`0 in maintenance, 41 host rows`.

**The Bandwidth anomaly still pages: 102 anomaly webhooks today**, last delivery 21:45:58Z to all
four APNs tokens plus WebPush. The BeNeM Action Group remains attached to `U6-Pro-EG` /
`UAP-AC-LR` / `UAP-AC-Pro-DB` / `UAP_AC_M` — **a change Thomas made, not new BHNM behaviour.**
Nobody has yet ruled on whether that volume is wanted.

`servers.json` holds four servers, four distinct keys, only `ThomasLabServer` cached.

---

## (d) Verified vs unverified

### VERIFIED — measured in the field

| thing | how |
|---|---|
| **2.17.0 refuses a target the key does not own** | **403**, and a **real client** is on that line: `user-agent='BeNeM/38 CFNetwork/3860.700.2 Darwin/25.6.0'` on `https://lpolli.ddns.info:9443` |
| **2.17.0 still relays to the owned target** | 200 in 0.26 s, 2356 bytes, decoded |
| **The old operator value is dead** | **401 in 40 ms**, `{"detail":"Invalid proxy token"}` — the 401 branch, not the operator branch |
| **Paging survived the rotation** | waited for, not asserted: a real anomaly at 14:40:18Z, `secret_fp=95e54469`, 5 targets, APNs + WebPush |
| **`/health` carries nothing else** | exactly `['status','version']`, and **none of the four server ids appears** in the body |
| **`bhnm.version` on both server classes** | on-prem `None`, SaaS `'26.3-01.17.el8.noarch'` |
| **The connection probe is O(1)** | 51 bytes good key, 46 bad, independent of estate size. `getincidents` cannot be bounded: `limit=1` and `count=1` both returned the identical 1921 bytes |
| **iOS save flow, all three tests** | passed on build 39 on the 13 Pro Max |
| **The four clients and the browser on the final build** | Thomas, 2026-09-18: versions correct, health card gone, push toggle preserves the secret, mask as designed |
| **The test bundle is not in the shipped app** | `find BeNeM.app -name "*.xctest"` → empty |

### NOT VERIFIED

| thing | why |
|---|---|
| **Store build 36 against the rotated deployment** | nobody has run the App Store build since the rotation. See (e)1 — the reasoning is sound but it is reasoning |
| **Steve's and Luiz's clients** | only Thomas's four were exercised. A mismatched-target client of theirs breaks by design and nobody here would see it |
| **The inconclusive verdict branch** | no way to provoke it short of pointing at a non-BHNM host that answers |
| **benem-admin → `/internal/cache/reload` after the rotation** | verified structurally, both containers hold the new fingerprint; never exercised, and it fails silently by design |
| **A RECOVERY arriving while an override is PENDING** | still never exercised — needs an ACK and a recovery inside the same 300 s TTL |
| **S1 1b per-server isolation** | every server still shares one seeded webhook secret, so resolution stays `<ambiguous: 4>` by construction |
| **Whether an anomaly RECOVERY is always sent** | captured, but "does every clear produce one" is unmeasured |

---

## (e) Parked items, RANKED

### 1. iOS App Store release — the top item, and it is not cosmetic

**The store build, 2.13.1 (36), cannot add or edit a server manually any more.** Its save probe
sends the push secret as `X-Proxy-Token`, which authenticated only because `PROXY_TOKEN` and
`WEBHOOK_SECRET` held the same value. Since the rotation that probe gets **401**, and because
`saveConnection()` runs only on a 200, the edit is discarded under an alert blaming the API key
and PIN.

**QR / deep-link import is unaffected** — `DeepLinkHandler.swift:127-144` saves directly with no
probe — so an onboarding flow still works and nobody is locked out of the app. But manual add and
edit is broken on every phone that is not Thomas's.

2.13.2 (44) fixes it and is built, installed and field-verified on the 13 Pro Max. **It has not
been released.** This is a real reason to ship, not a nicety.

### 2. Credential strength — rotate the short api_keys

`ThomasLabServer` is **15 characters**, `Luiz` is **9**. Both are simultaneously proxy tokens
(`main.py:194`). The 2.17.0 binding reduced what a leaked key *grants* to one server; it did
nothing about how guessable the key is.

**New this session, and it makes the case visible rather than theoretical:** the mask rule shows
the last 4 characters only at 16 characters or more. **Both of these keys therefore display as
dots alone** — the UI cannot help you tell them apart, because revealing 4 of 9 characters would
give away nearly half. A key too short to display safely is a key too short to be safe.

Rotation touches `servers.json`, the QR codes and the phones. It is a planned change, not a quick
fix.

### 3. §8.8 coverage-visibility, decision 1 — **still the highest-priority DESIGN**

The read-only measurement of whether the BHNM API exposes action-group assignment. **Deferred
twice this week** — it was the single next action in the 2026-09-17 handoff and never started,
because the CROSS defect outranked it and then this work did.

It needs no lab change and no deploy, and it decides whether BeNeM can state its coverage as fact
or must admit it cannot know. `specs/2026-09-16-coverage-visibility-design.md`, decision 1, still
unanswered by Thomas. **Do not start the §8.8 build from it** — that design is STOP AT DESIGN.

### 4. Caddy's error log stores full request headers in cleartext

`benem-proxy`'s `http.log.error` entries contain the complete request header block, **including
`X-Proxy-Token` and `Cookie`**, in `docker logs`, permanently. Scope is small only because Caddy
has no access log and there has been one error — nothing redacts it.

**Now entangled with item 6 and with the request-arrival blind spot:** any access log added to
answer "did this client reach us" must not repeat this.

### 5. The five unlogged refusal paths

2.17.0 logs the allowlist refusal, the binding refusal, the operator selection and the
config-unreadable case. Still silent: **401** missing/invalid token (`main.py:186,198`), **400**
target not http/https (three sites), **502** no target configured (five sites). A misconfigured
client can still be turned away without a trace — and the 401 path is exactly what the store build
is hitting today, invisibly.

### 6. Restricting `/health` to the Docker network

2.18.0 reduced the payload; the endpoint is still public. **Checked: nothing would break.**
`upgrade.sh` calls it inside the container, benem-admin never calls it, BHNM monitors the VPS by
**ping only** (`Host check triggered from Service PING`), and nothing in the repo polls it.
**What could not be ruled out from here: an external uptime service Thomas set up outside BHNM**,
which would fail silently.

### 7. The incident cache cost model note — written, unshipped

`specs/2026-09-16-incident-cache-cost-model-design.md`. Enrich-on-change plus a rolling sweep under
a load budget. Ruled but not built; six open decisions at the end of it.

### 8. The 2.15.2 recovery-while-pending field check — two minutes

Anomalies fire on their own every ~30 minutes, so this needs no hardware. Acknowledge fast after a
`WARNING` and hope the clear lands inside the 300 s TTL. Runbook
`2026-09-16-first-anomaly-webhook-capture.md` Part 3.

### 9. EXTERNAL — BHNM tickets Thomas has opened

**Not ours to fix. Do not design around them without saying so.**

- **`ha_status_api.php` behind a terminating proxy.** Returns `"API require HTTPS connection."` to
  a request made over real HTTPS and ignores `X-Forwarded-Proto`, as `200 OK` with a PHP-serialized
  body. Report: `docs/evidence/2026-09-18-bhnm-ha-status-https-bug.md`. **Already worked around** —
  both clients probe `incident_api.php` now.
- **No api_key-readable version endpoint on-prem.** `/cloudversion` works on SaaS and is
  session-gated on-prem. Until it exists, the topology shows **"version unknown"** there by design.

---

## (f) Withdrawn claims and known-wrong beliefs

**Carried forward. Do not resurrect these.** Items 1–13 are in the 2026-09-17 handoff §(f) and
still stand — in particular **"the Service Engine sends webhooks"** (it does not, the appliance
does), **"an SE outage fires the action group"** (EXTERNAL, two explanations already collapsed),
**"anomaly incidents cannot page"** (they can; the action group was not attached), and
**`/app/logs/middleware.log` is not the log** (`/logs/middleware.log` is).

### New this session

14. **"The 2.16.0 deploy window caused the morning iPhone 15 stall."** It recurred at ~14:16Z with
    no deploy near it, same device, same signature — `status: -1` at **10,015 ms**, the URLSession
    `catch` branch hitting `timeoutInterval: 10`. Two occurrences, one near a deploy: **coincidence,
    not cause.** Ruled client-side: pushes landed on that phone during the same seconds its HTTPS
    calls were timing out, and its middleware URL is identical to the two working clients.
15. **"The PROXY_TOKEN rotation has a blast radius of one diagnostic button."** Wrong twice. There
    is no "Test Connection" button — the control is labelled **"Test & Save"** / **"Save"**, it runs
    in both modes, and a 401 **discards the edit** rather than merely failing a test. See (e)1.
16. **"Rotating PROXY_TOKEN means touching benem:// links, QR codes and four phones."** That blast
    radius belongs to `WEBHOOK_SECRET`. `proxy_token` was removed from the QR payload on
    2026-09-15 and **no client ever read it** — `benem-admin/main.py:236-249` says so in the code,
    and `.env.example:86` was stale, now corrected.
17. **"A green suite means the code that runs is tested."** Between `71b4f92` and `adde589` the
    seven iOS tests guarded a parallel implementation, because the view still held its own copies.
    Thomas caught it by asking for the call sites. **Quote the call sites, do not assert the
    wiring** — `ServerConfigView.swift:52, 55-56, 242, 491` today.
18. **"A changed bundle hash proves what was deployed."** It proves it to someone with shell
    access on the VPS. PWA 0.16.3 shipped twice with the same version string, so the Settings
    screen said the same thing either side. See (g).

---

## (g) Rules added this session — pointers, not restatements

- **Root `CLAUDE.md`** — *a client-decoded payload may only ever GAIN fields.* The middleware
  deploys in minutes and iOS in days, onto phones that are not ours, so add-deploy-ship-then-remove
  is the only safe order. **Check the shipped code, not HEAD:**
  `git show <release-commit>:path`. Swift treats a non-optional property as required and fails the
  whole decode on a missing key.
- **Root `CLAUDE.md`** — *every deploy bumps the version of what it deploys, and the pre-deploy
  check reads the running version BEFORE tagging the rollback image.* Written after PWA 0.16.3
  shipped twice and after a rollback tag named a version that never existed.
- **Root `CLAUDE.md`** (2026-09-17) — *the test suite runs before every **COMMIT**, not before every
  push*, and *do not relax a guard to fit the evidence.* Both were exercised again today: the
  credential scanner flagged hex-shaped mask fixtures and **the fixtures were changed, not the
  scanner**.
- **2026-09-17 handoff §(f) item 10** — *before writing "cannot", ask what observation distinguishes
  it from "did not".* If there isn't one in hand, write "did not".
- **`middleware/CLAUDE.md`** — never trust a silence, never copy a log into the container, and the
  live log path.
- **In code, as prose rather than a constant** — *never reveal more than a quarter of a secret*,
  above `SECRET_REVEAL_MINIMUM_LENGTH = 16` in `pwa/.../ServerForm.tsx` and
  `ServerDraft.secretRevealMinimumLength`, so nobody lowers it to make a short key display nicely.

---

## (h) The single next action

**Decide the iOS App Store release.**

It is (e)1, it is the only item with a user-visible defect live on other people's phones, and the
fix is built, installed and field-verified. **The store build cannot add or edit a server
manually**, and the failure blames the API key and PIN, so anyone hitting it will debug the wrong
thing.

**What must be true before it starts:**

1. **Thomas decides to release** — this is a product call, not a technical one.
2. **Nothing is mid-deploy.** Currently true: middleware 2.18.0 and PWA 0.17.0 are live and
   verified, tree clean, `local == remote`.
3. **The reader has read (d) NOT VERIFIED and (f)**, so no withdrawn belief is resurrected — in
   particular **not** "the rotation's blast radius is one diagnostic button".

Release notes material is in `ios/CHANGELOG.md` under **2.13.2**, which is already written and
covers every change in the build.

**Do not start §8.8's build** from item 3 — that design is STOP AT DESIGN until decisions 2 and 3
are ruled. **Do not rotate the short api_keys** without a plan; it touches `servers.json`, the QR
codes and the phones.
