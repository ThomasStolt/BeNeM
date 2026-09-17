# Proxy Allowlist, Webhook Payload and Coverage Correction — session handoff

**Date:** 2026-09-17, written at 11:36Z.
**Supersedes:** `docs/superpowers/2026-09-16-s1-1a-coverage-and-staleness-WIP-handoff.md` for *state*.
That file remains the authority for **the queue** (items 1–15) and the older decision records.

Written for a reader with no memory of this work. Every state claim below was **observed at
11:36Z**, not recalled — the raw output is inline.

---

## (a) What landed

**Four commits, `c6113f2..e9caaa0`, all pushed. One middleware release: 2.16.0.**

| commit | subject |
|---|---|
| `c0aafc9` | incident-cache cost model design, coverage correction, two defects |
| `65e2b79` | evidence: first non-host webhook payloads, captured on the wire |
| `a59a98d` | spec: proxy target allowlist |
| `e9caaa0` | **feat(middleware): servers.json becomes the proxy allowlist (2.16.0)** |

### middleware 2.16.0 — the proxy target allowlist

**The behaviour change, in one line: a proxy target that is not a configured server is now refused
with 403 instead of being relayed to.**

**What the defect was.** `_validate_proxy_target` consulted `servers.json` as a **bypass list** and
the real gate was *"does this hostname resolve to a non-private address"*. Anything public fell off
the end of the function and was **allowed**. `_verify_proxy_token` accepts **any `api_key` in
`servers.json`**, and those keys live on phones and in onboarding QR codes — so any onboarded user
held a relay to **any public host on the internet**, from the VPS's IP, with arbitrary method, path,
body and headers. The stale URL was the symptom; **the blast radius was the defect.**

**What changed:**

- `servers.json` is the **allowlist**. The public fall-through is deleted.
- Matching is on **`(scheme, host, port)`**, normalised for case, trailing slash and default port.
  Scheme is in the key because the wire capture measured `X-Proxy-Token` on 285 of 292 requests and
  `pwd=` on 67 — an http downgrade to a host configured as https would put a BHNM credential in
  cleartext on the public internet.
- **Refused targets never reach DNS.** `getaddrinfo`, the private-address loop and the
  `socket`/`ipaddress` imports are **deleted**: with only configured hosts passing, and configured
  hosts bypassing the address check by design, that branch was unreachable.
- **A configured host is allowed whatever it resolves to, including a private address.** An on-prem
  BHNM legitimately sits on one. **This is not an oversight to tidy away** — the docstring says so
  at the function.
- 403 carries a **constant** detail and **never echoes the requested target**, so the endpoint
  cannot confirm by probe which hosts are configured. The **log** carries the full target **and**
  the client `User-Agent`.
- Unreadable `servers.json` is **503** with its own detail and its own log line, **never 403**.

**The latency change is half the point.** Measured on the exact target that used to hang:

```
before:  60 s  (PROXY_TIMEOUT) then a 504, and nothing in the log
after:   39 ms  403 {"detail":"Proxy target is not a configured server."}
```

**~1500× faster to fail, and loud instead of silent.**

**The refusal log is also an instrument.** It answers *"which client is naming an unconfigured
host"* from `grep`, for every client including idle ones. That question previously needed a packet
capture and its credential exposure to answer once.

**Tests:** 15 new in `tests/test_proxy_target_allowlist.py`; suite **223 passed**. The regression
test is `test_unconfigured_public_host_is_refused_without_touching_dns`, and it was **verified
against the pre-change validator, which ALLOWED `https://vpn.hurrikap.org:8888`**.

### Evidence written

- `docs/evidence/…-measurement.md` **§8.15** (anomaly webhooks — measurement kept, **conclusion
  corrected**), **§8.16** (the `alert_type: "host"` fallback defect), **§8.17** (the orphan log),
  **§8.18** (the `[Proxy] Timeout` line resized), **§8.19** (the wire capture).
- `docs/runbooks/2026-09-16-first-anomaly-webhook-capture.md` — executed; the five conditions any
  repeat capture must run under.

### Designs written, STOP AT DESIGN

| file | subject |
|---|---|
| `specs/2026-09-17-proxy-target-allowlist-design.md` | **built and shipped as 2.16.0** |
| `specs/2026-09-16-incident-cache-cost-model-design.md` | enrich on change + a load-budget sweep. **Not built** |

---

## (b) Deployed state — observed 2026-09-17T11:35:55Z

```
### /health
{
    "status": "running",
    "version": "2.16.0",
    "registered_devices": 4,
    "apns_environment": "per-device",
    "cache": { "ThomasLabServer": { "active": 11, ...
```

```
### /api/v1/diagnostics
middleware.version: 2.16.0
bhnm.reachable: True | consecutive_failures: 0 | last_success_age_s: 4
  incidents        cached=True  age=93   count=11    fails=0 err=None
  maintenance_map  cached=True  age=3    count=41    fails=0 err=None
  tactical         cached=True  age=42   count=15    fails=0 err=None
  thresholds       cached=True  age=45   count=37    fails=0 err=None
```

```
### /api/v1/maintenance-map
keys: ['cache_age_seconds', 'host_down', 'in_maintenance', 'scheduled']
host_down: []
```

**Rollback images on the VPS:**

```
bhnm-apns-bhnm-apns:latest           15 minutes ago    <- 2.16.0
bhnm-apns-bhnm-apns:pre-2.16.0       16 hours ago      <- rollback target for 2.16.0
bhnm-apns-bhnm-apns:pre-2.15.2       38 hours ago
bhnm-apns-bhnm-apns:pre-guard        39 hours ago
bhnm-apns-bhnm-apns:pre-2.15.0       43 hours ago
bhnm-apns-bhnm-apns:rollback-2.13.4   2 days ago
```

Pre-deploy log dump: `/root/logdumps/benem-middleware-20260917T112005Z-pre-2.16.0.log` (5091 lines).

Git, observed:

```
$ git status --porcelain      (empty — clean)
$ git rev-parse HEAD          e9caaa0154a1679f5487638f3055a137863e9931
$ git rev-parse origin/main   e9caaa0154a1679f5487638f3055a137863e9931
local==remote: YES
```

**The deploy window, to the second** — needed because a client reported a gap:

```
old container, last log line   2026-09-17 11:19:45.235Z
new container StartedAt        2026-09-17 11:21:05.780Z
new container, first log line  2026-09-17 11:21:07.092Z   RestartCount=0
incidents feed cached          2026-09-17 11:23:02Z
```

Client-visible degradation window: **11:19:45 → 11:23:02 = 3 m 17 s.** The iPhone 15's reported
1–2 minute "connection lost" fits inside it. **No client was refused** — the only `REFUSED` line in
the whole log is the deploy probe's own, `user-agent='BeNeM-deploy-probe/2.16.0'`.

**`/logs/middleware.log` is the persisted log. NEVER `/app/logs/middleware.log`** — see §8.17.

---

## (c) Lab state — observed 2026-09-17T11:36Z

Devices **searched by name, never counted**, per the `CLAUDE.md` rule:

```
raspi-050    rows found: 1 | UP | lastUpdateTime 2026-09-17 13:36:04 | dur 15h 40m 57s
BHNM-B-SE01  rows found: 1 | UP | lastUpdateTime 2026-09-17 13:36:04 | dur 22h 10m 7s
```

`host_down` is `[]`. Both `lastUpdateTime` values are advancing, so the engine is alive.

`servers.json` holds **four servers**, all seeded with `webhook_secrets` fingerprint `95e54469`;
only `ThomasLabServer` has `cache_enabled: true`:

```
SaaS Demo Server   https://portal-netreo-ash-np2.onbmc.com/           cache=False
ThomasLabServer    https://bhnm-b.tstolt.com                          cache=True
Steve              https://im-ui-server-netreo.qa.sps.secops.bmc.com  cache=False
Luiz               https://lpolli.ddns.info:9443                      cache=False
```

### LAB CHANGE — the BeNeM Action Group is now attached to the Bandwidth anomaly

**Thomas attached the BeNeM Action Group to the recurring `Bandwidth` anomaly** on `U6-Pro-EG` /
`UAP-AC-LR` / `UAP-AC-Pro-DB` / `UAP_AC_M`.

**Exact time: STILL NOT RECORDED.** What exists is a measured bound:

| bound | basis |
|---|---|
| **after 2026-09-16 20:10:17Z** | incidents 29657/29658/29659 opened and produced **zero** webhooks |
| **before 2026-09-16 21:40:17Z** | the **first** anomaly webhook ever: `[Webhook] WARNING — UAP-AC-Pro-DB — Incident 29664` |

**Why a future session must not skip this:** an anomaly webhook in the log is **a change Thomas
made at a known time, not new behaviour and not a BHNM upgrade.** Reading it as "anomalies started
paging" is wrong in exactly the way §8.15's first conclusion was wrong.

**Volume, measured: 67 anomaly webhooks since 21:40Z**, roughly every 30 minutes, 5 push targets
each. That is a paging-volume question in its own right and nobody has ruled on it.

---

## (d) Verified vs deployed-but-unverified

### VERIFIED — measured in the field

| thing | how |
|---|---|
| **2.16.0 refuses an unconfigured target** | **403 in 39 ms**, constant detail, target echoed 0 times, probed from the VPS with a valid token |
| **2.16.0 still relays to a configured target** | **200 in 0.52 s**, 2345 bytes, decoded, **11 active incidents** returned through the catch-all to `bhnm-b.tstolt.com` |
| **The refusal names the client** | `[Proxy] REFUSED target not in servers.json: 'https://vpn.hurrikap.org:8888' user-agent='BeNeM-deploy-probe/2.16.0'` |
| **All four feeds cached, 0 failures on 2.16.0** | see (b) |
| **All three phones work on 2.16.0** | Thomas exercised iPhone 15, iPhone 13 Pro Max, Android after the deploy |
| **Anomaly/threshold webhooks fire once the action group is attached** | 67 webhooks, §8.15 corrected |
| **The wire form of all four notification types** | `WARNING`, `RECOVERY`, `ACKNOWLEDGEMENT`, `DEACKNOWLEDGEMENT`, all **uppercase**, §8.19 |
| **`service_desc` is EMPTY on threshold/anomaly payloads** | all six captured payloads, §8.19 |
| **`{OUTPUT}` carries no HTML on this alarm class** | all six, §8.19 |
| **2.15.2 — the PENDING path** | **PASS.** Incident **29656**, 2026-09-16: `19:43:24,746Z [Webhook] Cache not patched: incident 29656 is in no cache yet — override -> ACKNOWLEDGED recorded as pending, applies on first sighting within 300s` then `19:45:23,584Z [Cache:ThomasLabServer] Pending state override applied on first sighting: incident 29656 -> ACKNOWLEDGED`. Both lines are in `/logs/middleware.log` today; `Pending state override applied` appears **exactly once** in the whole log, so the entry was consumed and did not leak |

> **Note on the PENDING path.** Thomas's ruling for this handoff was to move it to *unverified*
> unless log lines, timestamps and an incident id could be produced. **They can**, and they are
> above. What is genuinely unexercised is the *recovery-while-pending* case — a different thing,
> listed below. Evidence: `docs/evidence/2026-09-16-2.15.2-ack-cache-patch-field-test.md`.

### DEPLOYED BUT NOT VERIFIED IN THE FIELD

| thing | why not |
|---|---|
| **A RECOVERY arriving while an override is still PENDING** | never exercised. Needs an ACK **and** a recovery inside the same 300 s TTL — i.e. the recovery must land *between* the "recorded as pending" line and the "applied on first sighting" line. Last attempt, the TTL expired 12 minutes before the RECOVERY arrived |
| **S1 1a per-server *isolation*** | every server shares one seeded secret, so resolution is ambiguous by construction. Isolation is 1b's job and 1b has not started |
| **2.15.1's ambiguity label for the unambiguous case** | only the `<ambiguous: 4>` branch has ever run in the field |
| **The rendered title/body of a threshold/anomaly push** | **[DERIVED]**, not observed — arithmetic on `main.py:620–627` from measured fields. The phone is the only witness and nobody has looked |
| **Whether an anomaly RECOVERY is always sent** | RECOVERY payloads were captured, but "does every anomaly clear produce one" is unmeasured |
| **The client's rendering of a 403** | 2.16.0 ships with **no client change** by ruling. What a phone shows on `Proxy target is not a configured server.` is unknown |

---

## (e) Parked items, RANKED

**Thomas's ranking, recorded as his.**

### 1. CREDENTIAL STRENGTH — top item for the next session

**`ThomasLabServer`'s `api_key` is 15 characters and an English phrase, and it doubles as the proxy
token.** Found incidentally: Caddy's error log printed it in full (see item 2).

**DO NOT START IT IN THIS SESSION'S TAIL.** Rotation touches `servers.json`, the onboarding QR
codes, and four phones. It is a planned change with a blast radius, not a quick fix.

Note what it means for 2.16.0: the allowlist reduced what a leaked key *grants* (the four
configured servers, instead of the whole internet). It did nothing about how guessable the key is.

### 2. Caddy's error log stores full request headers in cleartext

`benem-proxy`'s `http.log.error` entries contain the complete request header block, **including
`X-Proxy-Token` and `Cookie`**, in `docker logs`, permanently.

**Scope today is one entry because there has been one error, not because anything redacts it.**
Caddy has **no access log** — only errors — which is why it is one and not thousands. This is the
pcap concern made permanent: a capture was time-boxed and destroyed for exactly this data, and
Caddy writes it and keeps it.

### 3. The five unlogged refusal paths — the instrument is half-built

2.16.0 logs the allowlist refusal (403) and the config-unreadable case (503). **Its neighbours are
silent:**

| line(s) | status | logged |
|---|---|---|
| 186, 198 | 401 missing / invalid proxy token | **no** |
| 1131, 1400, 1474 | 400 target not http/https | **no** |
| 791, 899, 993, 1129, 1398 | 502 no target configured | **no** |

A misconfigured client can still be turned away five ways without a trace. "Make the refusal
visible" is done for one path out of six.

### 4. The 2.15.2 recovery-while-pending field check — two minutes

Anomalies now fire on their own every ~30 minutes, so this needs no hardware and no raspi-050 pull.
Acknowledge fast after a `WARNING`, then hope the clear lands inside the 300 s TTL. The runbook
`2026-09-16-first-anomaly-webhook-capture.md` Part 3 has the four log lines and the honest odds.

### 5. The incident cache cost model design note — written, unshipped

`specs/2026-09-16-incident-cache-cost-model-design.md`. Enrich-on-change plus a rolling sweep under
a load budget `B` (default 1 call/s), `n / B` surfaced to the operator in words. Ruled but not
built. Six open decisions at the end of it.

### 6. The Brotli 502 on `timeseries-metrics`

`Error -3 while decompressing data: incorrect header check`, once in the middleware log
(09:21:27Z) and once in Caddy's (10:06:20Z, status 502, iPhone 15). `HOP_BY_HOP_REQUEST` strips
`accept-encoding` precisely to prevent this, and it happened anyway on that route. The phone showed
nothing.

---

## (f) Withdrawn claims and known-wrong beliefs

**Carried forward. Do not resurrect these. Each was believed, recorded, and then refuted.**

1. **The Service Engine does NOT send webhooks — the main BHNM appliance does.** The recorded
   explanation *"a crashed SE cannot notify anyone of its own crash"* is **wrong**.
2. **An SE outage does not fire the action group — status EXTERNAL, open with BMC.** Measured
   twice. **Not ours to explain — two explanations have already collapsed, do not attempt a third.**
3. **SE Group failover is UNTESTED.** The 2026-09-16 outage measured a **standalone** engine.
4. **"raspi-050 is the Service Engine"** — wrong.
5. **"The two-hop diagnostics surface an SE outage"** — wrong. They verify the middleware reaching
   BHNM's *front end*, which answers perfectly while the engine is dead.
6. **"~30 minutes to detect a host down"** — withdrawn as contaminated. The only clean figure is
   **12 min 09 s** for *SE-outage* detection.
7. **Two premature readings of `lastUpdateTime`.** The controlled outage settled it: **it stalls.**
8. **The error branch in `IncidentListScreen.tsx:44` is NOT unreachable.** What is missing is a
   rendering for `fetchStatus: "paused"`.
9. **`[APNs] Sent to …` does not mean a phone showed anything.** It means APNs returned 200.
10. **"Anomaly incidents cannot page."** The measurement stands — 29657/29658/29659 produced no
    webhook. **The conclusion was wrong.** BHNM thresholds, anomalies included, **can** call
    webhooks; those three fired nothing because the **action group was not attached**. A
    *configuration* observation written up as a *capability* claim — "did not" reported as
    "cannot", the same error class as item 1, twice in two days.

### New this session

11. **`/app/logs/middleware.log` is NOT the log.** It is a 1 MB `docker cp` working copy, an exact
    byte-prefix of the live log, frozen at 2026-09-16 19:19:29Z. **It answers greps about anything
    later with silence, and silence is the same answer the real log gives when the event did not
    happen.** It produced a correct-looking negative result for a webhook search. The live path is
    **`/logs/middleware.log`**. See §8.17.
12. **"The vpn.hurrikap.org calls stopped, therefore the fix worked"** — wrong when first said.
    12 h 18 m of the 12 h 21 m of silence **predated** the fix; the phone was asleep. Absence of
    failure from an idle client is not evidence of correct behaviour.
13. **"The capture is a risk because it writes webhook bodies to disk"** — the wrong risk. The real
    one is that port 8889 after Caddy is plaintext and carries **`X-Proxy-Token` (285 of 292
    requests), `?secret=` (6) and `pwd=` (67)**. A capture there recreates the leak 2.13.2's
    redaction filter was written to close.

---

## (g) Rules added this session — pointers, not restatements

- **Root `CLAUDE.md`** — *the test suite runs before every **COMMIT**, not before every push.* Two
  documentation-only commits went into history red this session. The deploy pulls from origin, so a
  red commit on `main` is armed, not "caught later"; the credential guard scans **tracked files**,
  so prose breaks it; and a green suite at push time does not clear the commits underneath it.
- **Root `CLAUDE.md`** — *do not relax a guard to fit the evidence.* The fix for two md5 digests
  tripping the credential scanner was to truncate them, not to teach the scanner to ignore
  32-character hex runs.
- **Section (f) item 10** — *before writing "cannot", ask what observation distinguishes it from
  "did not".* If there isn't one in hand, write "did not". Twice in two days a sound measurement
  carried an unsound sentence.
- **`middleware/CLAUDE.md`** — *never trust a silence: make the log prove it was writing during the
  window first*, plus *never copy a log **into** the container*, plus the live log path.
- **`docs/runbooks/2026-09-16-first-anomaly-webhook-capture.md`** — the five conditions any packet
  capture on port 8889 must run under.

---

## (h) The single next action

**§8.8 coverage visibility, decision 1: the read-only measurement of whether the BHNM API exposes
action-group assignment.**

It is one read-only probe, it needs no lab change and no deploy, and **it decides the shape of the
highest-priority item in the project** — whether BeNeM can state its coverage as fact, or must
admit it cannot know.

**Its value went UP this session.** §8.15's correction established that **coverage is per-object
configuration, not a capability limit**. So coverage varies per customer and per object, an
operator can silently be wrong about what pages them, and it is **readable data**. Under the old
(wrong) conclusion the probe refined a static type table; under the correct one **the probe is the
feature**. See `specs/2026-09-16-coverage-visibility-design.md` §1c.

**What must be true before it starts:**

1. **Thomas has approved the measurement** — decision 1 in that file, still unanswered.
2. **Nothing is mid-deploy** — currently true: 2.16.0 is live, verified on all six checks, tree
   clean, `local == remote`.
3. **The reader has read `specs/2026-09-16-coverage-visibility-design.md` §1b and §1c, and section
   (f) above**, so no withdrawn belief is resurrected — in particular **not** "anomalies cannot
   page".

**Do not** start the §8.8 *build* from that measurement. The design is STOP AT DESIGN and stays so
until Thomas rules on decisions 2 and 3 in that file.

**And do not start item (e)1, credential rotation, without a plan** — it touches `servers.json`,
the QR codes and four phones.
