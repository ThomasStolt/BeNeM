# Evidence: BHNM close-call / RECOVERY measurement on bhnm-b (26.3)

**Lab:** BMC Helix Network Management 26.3, `bhnm-b.tstolt.com` → **192.168.2.211** (LAN; public name is Cloudflare-fronted)
**Capture listener:** the engineer's Mac, **192.168.2.224:8787**, same /24 as BHNM
**Middleware:** `bhnm-apns.hurrikap.org`, container `benem-middleware` up since 2026-09-03T18:31:06Z

All times UTC. Nothing in this file is inferred; every line is an observation.

---

## Part 1 — Setup (2026-09-14, 14:0x–14:3x UTC)

### 1.1 Capture listener

Minimal stdlib HTTP server, appends UTC timestamp, source IP, method, path, Content-Type and the
**raw body verbatim** to a log, returns `200 {"status":"captured"}`. Accepts GET/POST/PUT/PATCH.

- URL for the Active Response Webhook method: `http://192.168.2.224:8787/capture?m=activeresponse`
- URL for the plain WebHook method: `http://192.168.2.224:8787/capture?m=webhook`

The two paths are the only difference between the methods, so a captured request identifies which
BHNM method type produced it.

Self-test from the Mac over its own LAN address returned `HTTP 200`. macOS application firewall is
**enabled**, but block-all is off, stealth mode is off, and Python already holds an
"Allow incoming connections" rule — **no firewall prompt appeared**. Reachability from another host
was not independently proven before the run.

### 1.2 What the BHNM UI actually exposes (read-only survey)

The question "which notification types trigger this action group" has an answer, and it is *none of
these screens*. Every level was opened and screenshotted without saving:

| Level | Every setting it has |
|---|---|
| **Group** (`BeNeM`) | GROUP NAME, MANUAL ALERT ACCESS LEVEL (`User`). That is all. |
| **Action** (`Mobile BeNeM Notification`) | ACTION DESCRIPTION. That is all. |
| **Method** (the middleware webhook) | URL, WEBHOOK DATA PAYLOAD, AUTHORIZATION TOKEN (`None`), SSL AUTHENTICATION (`ON`), NOTIFY HOURS (`24x7`). That is all. |
| **Host Monitoring** (`Administration → Alerts → Host Monitoring`) | Host Alert Contacts: CONTACT NAME (`BeNeM`), ESCALATION TIER (`1`), Add/Delete; Parent Configuration; Host Re-Notify Interval. That is all. |

**There is no PROBLEM / RECOVERY / ACKNOWLEDGEMENT selector anywhere in Actions Administration or in
Host Monitoring on this version.** Devices bind to the **contact group**, not to an individual
action — so any action inside the `BeNeM` group fires on the same events as the middleware's.

Screenshots: `2026-09-14-bhnm-b-actions-admin-before.jpg`, `-edit-group-benem.jpg`,
`-edit-action-mobile-benem.jpg`, `-existing-method-config-redacted.png`,
`-host-monitoring-alert-contacts.jpg`.

`Administration → Alerts → Incident Management` → **Incident Criteria Administration** carries
**Incident Close Delay Timer (Minute) = 5** — the "Alarms Cleared holds for ~5 minutes" behaviour is
this setting, not folklore. Six ordered rules exist: Configuration Change Alerts; Suppress Alerts if
Auth not working; Site Latency; CorrelateDSLStatuswithDraytek; outofbusinesshours; Forward to BHOM.
Screenshot: `2026-09-14-bhnm-b-incident-criteria-admin.jpg`.

### 1.3 The existing middleware Method, verbatim

Type **Active Response Webhook**, `SSL enabled`, `Auth Token disabled`, `24X7`,
URL `https://bhnm-apns.hurrikap.org/webhook?secret=«redacted — it is a live credential»`.

Payload as configured in the lab — **macros are `{BRACED}`, not `$PREFIXED`**:

```json
{
    "incident_id": "{INCIDENTID}",
    "hostname": "{HOSTNAME}",
    "host_address": "{HOSTADDRESS}",
    "host_state": "{HOSTSTATE}",
    "notification_type": "{NOTIFICATIONTYPE}",
    "severity": "{SERVICESTATE}",
    "site": "{SITENAME}",
    "category": "{CATEGORYNAME}",
    "service_desc": "{SERVICEDESC}",
    "output": "{OUTPUT}",
    "incident_time": "{INCIDENTTIME}"
}
```

The form states: *"Please use json format payload. Single quotes and backticks are not allowed."*

`severity` maps to `{SERVICESTATE}`, which is why severity is blank on host-down alerts — the
SERVICE\* macros have no value when the notification is about a host.

### 1.4 Objects created (the only writes made to the lab)

One Action in the existing `BeNeM` group, **`BeNeM capture (temporary)`** (index 37), carrying two
Methods. Methods have no name field in this BHNM, which is why the name sits on the Action.

| Method type | URL | SSL | Auth | Notify hours |
|---|---|---|---|---|
| Active Response Webhook | `http://192.168.2.224:8787/capture?m=activeresponse` | disabled | disabled | 24x7 |
| WebHook | `http://192.168.2.224:8787/capture?m=webhook` | disabled | disabled | 24x7 |

Both carry the same 21-macro payload (`kind` distinguishes them in the body as well as by path):

```json
{
"kind": "active_response_webhook | plain_webhook",
"notification_type": "{NOTIFICATIONTYPE}",
"renotify": "{RENOTIFY}",
"notification_number": "{NOTIFICATIONNUMBER}",
"hostname": "{HOSTNAME}",
"host_address": "{HOSTADDRESS}",
"host_state": "{HOSTSTATE}",
"incident_id": "{INCIDENTID}",
"incident_time": "{INCIDENTTIME}",
"incident_time_t": "{INCIDENTTIMET}",
"primary_alarm_status": "{PRIMARYALARMSTATUS}",
"service_state": "{SERVICESTATE}",
"service_desc": "{SERVICEDESC}",
"output": "{OUTPUT}",
"site": "{SITENAME}",
"category": "{CATEGORYNAME}",
"uid": "{UID}",
"guid": "{GUID}",
"incident_url": "{INCIDENT_URL}",
"subj": "{SUBJ}",
"datetime_gmt": "{DATETIMEGMT}",
"server_name": "{SERVERNAME}"
}
```

Screenshot: `2026-09-14-bhnm-b-capture-methods-created.png`.

**There is no test/send button on the Method screen** on this version — the form offers only
`Add Method` / `Edit Method`. The methods could not be fired on demand from the UI.

Nothing else in the lab was modified. The counter moving 14 → 15 Actions before any write of mine
was Thomas's own change in the `BMC_II_Host` group (`Mobile BeNeM Notification`, index 36); the
`Mobile` action there is index 28, older than the BeNeM action at 34.

### 1.5 The middleware's own history — before the run

Container `benem-middleware`, continuously up since **2026-09-03T18:31:06Z** (11 days):

```
     31 [Webhook] PROBLEM
      0 [Webhook] RECOVERY
      0 [Webhook] ACKNOWLEDGEMENT
      0 [Webhook] Rejected
```

Most recent three, verbatim:

```
2026-09-14T08:57:13.402378089Z [Webhook] PROBLEM — EM-TSTOLT-M1.local — Incident 29459
2026-09-14T10:12:13.678182060Z [Webhook] PROBLEM — EM-TSTOLT-M1.local — Incident 29462
2026-09-14T10:46:14.314152048Z [Webhook] PROBLEM — MacBook-Pro-Thomas.local — Incident 29469
```

**In eleven days and 31 deliveries the middleware has received exactly one notification type.** The
2026-09-03 finale recorded a single missing RECOVERY; this is the same finding at 31× the sample
size, and it is not specific to raspi-050.

---

## Part 2 — The measured run (2026-09-14, 14:55–15:11 UTC)

raspi-050 was physically disconnected by Thomas, acknowledged and un-acknowledged in the BHNM UI
while the incident was open, then reconnected. Incident **29483**. All three channels watched
throughout: the two capture URLs and the production middleware's container log.

### Every event

| # | Time (UTC) | Event | `Active Response Webhook` (= the middleware's type) | `WebHook` | production middleware |
|---|---|---|---|---|---|
| 1 | 14:55:09 | BHNM host check → `DOWN`, Ping CRITICAL 100% loss | — | — | — |
| 2 | 14:55:13.854 | | | | **`[Webhook] PROBLEM — raspi-050 — Incident 29483`** |
| 3 | 14:55:38.803 | | **PROBLEM** | | |
| 4 | 14:55:39.221 | | | **PROBLEM** | |
| 5 | 14:59:23 | Acknowledged in the UI (user `admin`, "No comment.") | — | — | — |
| 6 | 14:59:30.354 | | **nothing** | **ACKNOWLEDGEMENT** | **nothing** |
| 7 | 15:00:4x | Un-acknowledged in the UI | — | — | — |
| 8 | 15:00:54.492 | | **nothing** | **DEACKNOWLEDGEMENT** | **nothing** |
| 9 | 15:05:13 | BHNM host check → `UP` (device reconnected) | — | — | — |
| 10 | 15:05:22 | recovery notification *generated* (`datetime_gmt` in the payload) | — | — | — |
| 11 | 15:11:07.072 | recovery notification *delivered*, 5m 45s later | **nothing** | **RECOVERY** | **nothing** |

Per-event notification-type literals as captured:

| Event | `notification_type` | `renotify` | `notification_number` | `host_state` | `primary_alarm_status` | `incident_id` |
|---|---|---|---|---|---|---|
| PROBLEM (Active Response) | `PROBLEM` | `""` | `""` | `DOWN` | `DOWN` | `29483` |
| PROBLEM (WebHook) | `PROBLEM` | `UPDATE` | `1` | `DOWN` | `DOWN` | `29483` |
| ACK (WebHook) | `ACKNOWLEDGEMENT` | `UPDATE` | `1` | **`ACKNOWLEDGEMENT`** | `DOWN` | `29483` |
| un-ACK (WebHook) | **`DEACKNOWLEDGEMENT`** | `UPDATE` | `1` | `DOWN` | `DOWN` | `29483` |
| RECOVERY (WebHook) | `RECOVERY` | `UPDATE` | `1` | `UP` | `UP` | `29483` |

The middleware received exactly one webhook across the entire run: the `PROBLEM` at 14:55:13.854Z.

### Verdict

**(a) Closure does not fire — and the fault is neither the network nor the Action Group.**

The capture and the middleware sit behind different transports (plain HTTP on the LAN vs HTTPS to a
public VPS) and both are attached to the same action group, so the run isolates the variable cleanly:

- The **plain `WebHook`** method received `PROBLEM`, `ACKNOWLEDGEMENT`, `DEACKNOWLEDGEMENT` and
  `RECOVERY` — all four.
- The **`Active Response Webhook`** method, on the identical group and the identical events, received
  **only `PROBLEM`**.
- The production middleware — an `Active Response Webhook` — likewise received only `PROBLEM`.

So it is not an Action Group setting (there is no notification-type selector at any level), not the
BHNM→VPS path (the capture on the same method type also got nothing, while the other method type on
the same LAN got everything), and not a suppression rule (one method type saw every event).

**The cause is the Action Method type.** `Active Response Webhook` fires only on `PROBLEM`. The fix
is one dropdown: recreate the middleware's method as a plain `WebHook`.

This also explains the 11-day, 31-webhook `PROBLEM`-only history in §1.5 without any further theory.

**What differs between the two methods, beyond delivery:** the Active Response variant leaves
`{RENOTIFY}`, `{NOTIFICATIONNUMBER}` and `{SUBJ}` **empty**; the plain WebHook populates them
(`UPDATE`, `1`, `Device raspi-050 is DOWN` / `is UP`). Both use
`Content-Type: application/x-www-form-urlencoded` with a JSON body.

**(b) Spec items — no code changed**

1. **`DEACKNOWLEDGEMENT`, not `UNACKNOWLEDGEMENT`.** BHNM's own macro reference documents the value
   as `UNACKNOWLEDGEMENT`; the wire carries `DEACKNOWLEDGEMENT`. Any handler matching the documented
   spelling will never fire. Worse, BHNM leaves `host_state` at `DOWN` on that notification, so the
   middleware's fall-through renders it **`🔴 raspi-050 — DOWN`** — byte-identical to a fresh outage
   push for an incident that was merely un-acked. This is the highest-priority of the three.
2. **`RENOTIFY` labelling or suppression.** `{RENOTIFY}` returned **`UPDATE`** on
   `notification_number: 1`, i.e. on the *first* notification, where BHNM documents `NEW` for the
   first. So `renotify` cannot be trusted to distinguish new from repeat on this version; use
   `{NOTIFICATIONNUMBER}` instead. Neither macro is available at all while the method type is
   `Active Response Webhook` — both come through empty.
3. **`UID` in the payload contract for deep links.** `{UID}` = `8860` (the BHNM `root_id` of the
   device) and `{GUID}` = `netreo-1599587812-8860` (environment + license + root id) were both
   populated on every capture, on both method types. `{INCIDENT_URL}` also resolved, to
   `http://192.168.2.211/fw/index.php?r=incident/detaillog&incident_id=29483` — note it uses the
   BHNM-internal address, so it is only useful to clients that can reach BHNM directly.

Additional findings worth carrying into the spec:

- **`host_state` is not a host state on acknowledgement notifications** — BHNM puts the literal
  `ACKNOWLEDGEMENT` in it, while `primary_alarm_status` still reads `DOWN`. Anything that must
  reflect the device should read `{PRIMARYALARMSTATUS}`.
- **`service_state` / `service_desc` are empty on host alerts**, as BHNM documents *(Service alerts
  only)*. This is why the middleware's `severity` field is blank on host-down. `{PRIMARYALARMSTATUS}`
  is populated for hosts, services and thresholds alike and is the correct replacement.
- **The close delay is real and invisible in the payload.** `datetime_gmt` carried 15:05:22Z, the
  moment the notification was generated; the POST arrived at 15:11:07Z. Anything reasoning about
  latency from the payload timestamp will understate it by the close-delay window.
- **BHNM sends JSON with `Content-Type: application/x-www-form-urlencoded`.** The middleware's
  form-encoded fallback is load-bearing for every real webhook, not a defensive edge case.

### Lab state after the run

The capture Action `BeNeM capture (temporary)` and both its Methods are **left in place**, per
instruction, until Thomas says to remove them. Incident 29483 is closed. raspi-050 is `UP`. The
existing middleware Method was never edited.

---

## Part 3 — Four alerts per incident: the hang behind it (2026-09-14, 16:09–18:00 UTC)

Switching the production Method to type `WebHook` (Part 2's conclusion) made every incident
arrive on the phone **four times**. Chasing that duplicate exposed a fault that had been present
all along and had already left an unexplained trace in the 2026-09-03 evidence.

### 3.1 The symptom, measured

Two independent events, both delivered four times to the middleware and **once** to the capture
listener on the same action group:

| event | middleware deliveries | spacing | capture listener |
|---|---|---|---|
| PROBLEM, incident 29490 | 16:09:13.508, 16:09:46.449, 16:10:19.696, 16:10:52.722 | 32.9s, 33.2s, 33.0s | 1 (16:09:13.405) |
| RECOVERY, incident 29490 | 16:38:45.475, 16:39:18.428, 16:39:51.434, 16:40:24.660 | 33.0s, 33.0s, 33.2s | 1 (16:38:45.378) |

Not a BHNM re-notification — a per-Method delivery retry. One delivery, one banner; the phone
showed four, with BHNM's own label on three of them (Berlin time = UTC+2):

```
18:38  Host recovered.  (Host check triggered from Service PING)<br />Ping OK: Packet…
18:39  Host recovered. Retry action by system 1 of 3.  (Host check triggered from Service…
18:39  Host recovered. Retry action by system 2 of 3.  (Host check triggered from Service…
18:40  Host recovered. Retry action by system 3 of 3.  (Host check triggered from Service…
```

**`Retry action by system N of 3.` is BHNM's own text, injected into the `{OUTPUT}` macro on each
retry.** BHNM is stating plainly that its action engine considers the delivery failed.

> A wrong turn worth recording: the captured payloads contain no retry wording, and I concluded
> from that BHNM produced none. The capture endpoint is never retried, so it only ever received
> delivery #1 — the retries carry the label and I had never held one. Reasoning from the sample
> that by definition excludes the phenomenon.

### 3.2 The cause

Timing the production endpoint two ways:

| request | result |
|---|---|
| `POST /webhook` with a secret that has **no** registered devices (×3, 16:25:52) | `200`, **48–69 ms** total including TLS |
| `POST /webhook` with the **live** secret (16:56:17) | **`http=000` after 120 s** — curl's own cap; no response ever arrived |

Log accounting over the container's entire life at that point:

- `[APNs] Sent to …` lines: **0** — with `PYTHONUNBUFFERED=1` and the print present at line 84 of the running image
- `[APNs] Failed` / `[APNs] Error` / `[Cleanup]` lines: **0**
- uvicorn access lines for `POST /webhook` **with** tokens: **0**
- uvicorn access lines for `POST /webhook` **without** tokens: **3** — the three fast probes
- tracebacks or exceptions: **0**

**The handler never returned whenever it entered `send_to_all`.** `apns.py` wrapped the fan-out in a
per-request `async with httpx.AsyncClient(http2=True)`; the sends inside completed and the devices
received the push, but execution never reached the per-token prints that follow the block, the
response was never sent, and uvicorn never logged the request. Requests with no devices took the
early return before `send_to_all`, which is why they always looked healthy — and why the fault
survived every previous test.

The full chain:

```
handler enters send_to_all
  → sends succeed, phone gets the push
  → execution never leaves the fan-out
  → no response to BHNM
  → BHNM waits ~30 s, times out
  → retries 3× at 33 s, labelling each "Retry action by system N of 3."
  → four alerts per incident
```

**This retires an open note from 2026-09-03**, which recorded that "the uvicorn access log carries no
`POST /webhook` entry although it logs every other request" and left it unexplained. Same cause: the
request never completed.

### 3.3 What the Method type actually changed

The hang is **independent of Method type and predates today**. Incident 29483 (Part 2, under
`Active Response Webhook`) hung too — its access line is likewise absent — but arrived **once**.

> `Active Response Webhook` does not retry on timeout. Plain `WebHook` retries three times.

So Part 2's Method change did not create the duplicate; it made a pre-existing hang visible. Both
findings stand: the Active Response type never delivers `RECOVERY`, `ACKNOWLEDGEMENT` or
`DEACKNOWLEDGEMENT`, and the plain WebHook type exposes any endpoint that fails to answer.

### 3.4 The fix, and one self-inflicted wound

**2.13.1** — the fan-out moved to a `BackgroundTasks` job so the response returns immediately, and
`apns.py` now uses one long-lived shared `AsyncClient`. **The backgrounding is what fixed it.** The
shared client was my hypothesis for the hang itself and it was **wrong** — the fan-out still does not
complete (§3.6). It was kept because Apple asks for persistent APNs connections.

**2.13.2 — a secret leak introduced by the fix.** Once `/webhook` began returning a response, uvicorn
wrote an access line for it for the first time in the service's life:

```
INFO: … - "POST /webhook?secret=<first-8-and-last-8-of-the-live-secret, redacted 2026-09-15> HTTP/1.1" 200 OK
```

The webhook secret rides in the query string (security-board item **S1**), so the full credential
went to stdout — and would have been written to the host log file shipped in the same release. Caught
on the post-deploy verification probe, before the verification cycle ran. A redaction filter on
`uvicorn.access` / `uvicorn.error` and on the stdout mirror now rewrites `secret=`, `token=`,
`password=`, `pwd=` and `key=` to `<redacted>`; confirmed zero raw-secret occurrences afterwards. The
secret still travels in the URL — only the logging half of S1 is closed.

**How a fragment of the live secret reached the repo (found 2026-09-15).** The redaction filter
above was tested against a *real* uvicorn access line, so the test fixture carried the live lab
secret. Two tracked, pushed files were affected:

| File | What it held | Characters of the 64-char secret exposed |
|---|---|---|
| `middleware/tests/test_webhook_notification_types.py:317` | a contiguous run in the sample access line | **33 leading** |
| the same file, line 319 | `assert "…" not in out` | the same leading 8 |
| this file, §3.4 | the quoted access line, `first8…last8` | **8 leading + 8 trailing** |

Combined that is 41 of 64 hex characters — 23 unknown, so not exploitable (~2^92), and this secret
is burned and due for rotation regardless. Hygiene, not an incident, and it does **not** change the
rotation plan. The reviewer's estimate of "the first 32 characters" was close but understated it:
the evidence file also carried the **tail**, which the test file did not.

Fixed the same day: every fragment replaced with `deadbeef` repeated, and
`middleware/tests/test_no_credentials_in_repo.py` added — a `git ls-files` scan that fails the suite
on a long lowercase-hex run or on a credential keyword assigned a literal that is not an obvious
placeholder. Run against the repo as it stood before the fix, it flags **both** files. Its known
ceiling is recorded in its docstring: a bare 8-character hex fragment with no adjacent keyword is
indistinguishable from an id and is not caught.

**The rule this produced: never test a redaction filter with the string it is meant to redact.**

Also in 2.13.2: the `./logs` bind mount is created by Docker as `root` while the container runs as
`appuser`, so the log file could not be opened; a `/data/middleware.log` fallback was added and the
host directory chowned.

**2.13.3** — `clean_bhnm_text()` preserves real line breaks (`<br>`, `<br/>`, `<br />`, `</p>` → `\n`;
only spaces and tabs collapsed) rather than flattening everything, so that BHNM's likely fix for the
HTML-in-`{OUTPUT}` defect — emitting a newline — is not silently undone downstream.

### 3.5 Verification cycle (2.13.3, one down/up on raspi-050)

| check | result |
|---|---|
| PROBLEM deliveries, incident 29499 | **1** — 17:35:16.094 |
| RECOVERY deliveries, incident 29499 | **1** — 17:57:23.225 |
| retries in either window | **none** |
| uvicorn access lines | **2 for 2**, secret `<redacted>` |
| banners on the phone (DOWN) | **1** |
| response time | ~0.3 s (was: never) |
| webhook cache patch | fired live — `incident 29499 -> CLOSED (1 server(s))` |
| BHNM close-delay hold | 5m 11s (UP 17:52:12 → RECOVERY 17:57:23) |

The banner count establishes that this device is not duplicating. It says nothing about the other
registered tokens, which remain a separate open item.

### 3.6 Open — top of the list

**The APNs fan-out never completes.** No `[APNs] Sent to …` line had ever been emitted. Backgrounding
removed the user-visible fault and BHNM's retries, but the task itself still hung. Localised and
fixed the next morning — see §3.8.

> An earlier revision of this section said "deliveries themselves arrive". That was true for **one
> device in five**, and the correction matters: see §3.8.

### 3.7 Log persistence

Container recreation erased the evidence under measurement on 2026-09-03 and again today — the second
time by my own 2.13.0 deploy, which destroyed the eleven days of `[Webhook]` history in the middle of
analysing it. Since 2.13.1 stdout is mirrored to `/logs/middleware.log` on a bind mount, rotated
5 MB × 5, with a `/data/middleware.log` fallback, and a pre-deploy `docker logs` dump is now a step in
the upgrade runbook in `middleware/CLAUDE.md`. Dumps taken before all three deploys today are in
`/root/logdumps/`.


---

## Part 3.8 — The fan-out hang, traced (2026-09-15, 09:43 UTC)

Instrumented rather than hypothesised, after the previous hypothesis (per-request
`AsyncClient` teardown) proved wrong and cost a deploy. Trace lines around every await in the
delivery path, then one live-secret probe against the production middleware.

### What printed

```
[Trace] _deliver enter: 5 token(s), 0 sub(s)
[Trace] before send_to_all
[Trace] send_to_all enter, 5 token(s)
[Trace] client ready closed=False
[Trace] before gather
[Trace] _send_one enter a0f85792 → before POST a0f85792
[Trace] _send_one enter 32295bdd → before POST 32295bdd
[Trace] _send_one enter 86587674 → before POST 86587674
[Trace] _send_one enter b26fb517 → before POST b26fb517
[Trace] _send_one enter 0c56a19b → before POST 0c56a19b
[Trace] after POST a0f85792 status=200
[Trace] after read body a0f85792 bytes=0
[Trace] _send_one leave a0f85792          ← last line; nothing further, ever
```

**The hang is inside `await client.post(...)` for the 2nd–5th concurrent requests on the shared
HTTP/2 connection.** The first completes in ~430 ms; the rest never return, no `after gather`, no
exception. `httpx 0.28.1`, `h2 4.4.1`, `httpcore 1.0.9`.

Decisive detail: both the client and the request carry `timeout=10.0`, and **no `TimeoutException`
ever fired** — ten minutes later the four coroutines were still inside `client.post`. They are
blocked somewhere httpx's timeouts do not reach, which rules out a slow network and points at the
HTTP/2 connection state.

Ruling out the other candidates from the trace itself: the client is **not** created outside the
running loop (`client ready closed=False`, and one request on it succeeds), and the response body
**is** read (`after read body … bytes=0` — APNs returns an empty body on 200).

### Why this was worse than a leaked task

`get_tokens_for_secret` had no `ORDER BY`, so SQLite returned rowid order and the first row was
always the same device — id 516, the oldest registration, from 2026-05-30. **Only that one device
has ever been notified.** The other four registrations were silently dead. Thomas confirmed the probe
produced exactly one notification on his phone.

Had his live phone not held the oldest token, BeNeM would have delivered nothing at all.

### The fix (2.13.4)

- **Sends are sequential**, not `asyncio.gather` — one POST at a time on the shared connection,
  ~0.5 s per device inside a background task that nothing waits on.
- **`asyncio.wait_for(..., 60 s)` around the whole fan-out**, logging
  `[Deliver] TIMEOUT after 60.0s — fan-out abandoned for incident N, X token(s), Y subscription(s)`.
  A future stall becomes a logged error instead of silence.
- **`ORDER BY id`** added to `get_tokens_for_secret`. Relying on rowid order is how "only the oldest
  token is served" stayed invisible.

### Consequence for the two parked phones

Thomas's other two phones were parked as a device-side notification problem (iPhone Focus, Android
setup). **That conclusion is retired.** They may have been configured correctly all along and simply
never sent to — their tokens were never the first row. They are to be retested **before** any setting
on them is changed, and the result recorded here either way.


---

## Part 3.9 — 2.13.4 does not fix the fan-out: two concurrent webhooks still wedge it
### (2026-09-15, 14:49–15:02 UTC)

Fired as the closing verification of 2.13.4 — the one §3.8 left open, and the one that was to be
done "before any setting on the parked phones is changed". It failed.

### The accident that exposed it

Two `POST /webhook` requests arrived **255 ms apart** (14:49:25.397 and 14:49:25.652), from
`127.0.0.1` on two different source ports, against a single uvicorn worker. Only one probe was
issued deliberately. **The origin of the second request is not established** — most likely an
earlier SSH attempt whose `docker exec` appeared dead and landed late, except that the container
log is empty from 14:40 to 14:49, which argues against it. Recorded as unattributed rather than
guessed at. It was a lucky duplicate: it is the only reason the defect was seen.

### What happened

```
14:49:25.397  [Webhook] PROBLEM — Queued delivery to 8 target(s)      ← fan-out A
14:49:25.652  [Webhook] PROBLEM — Queued delivery to 8 target(s)      ← fan-out B
14:49:25.742  [APNs] Sent to ...a0f85792
14:49:25.857  [APNs] Sent to ...32295bdd
14:49:25.858  [APNs] Sent to ...a0f85792
14:49:25.975  [APNs] Sent to ...32295bdd
14:49:25.978  [APNs] Sent to ...86587674
              ── 60 seconds of nothing ──
14:50:25.401  [Deliver] TIMEOUT after 60.0s — fan-out abandoned, 7 token(s), 1 subscription(s)
14:50:25.402  [APNs] Sent to ...86587674
14:50:25.508  [APNs] Failed (400) BadDeviceToken
14:50:25.625  [APNs] Sent to ...0c56a19b
14:50:25.653  [Deliver] TIMEOUT after 60.0s — fan-out abandoned, 7 token(s), 1 subscription(s)
```

Both fan-outs stalled after roughly three sends and were abandoned by the 60 s guard. Tokens
`...62f21e50` and `...018ab51d` — the two newest registrations, one of them the device onboarded by
QR that morning — and the Web Push subscription **received nothing at all**.

### The control: one webhook, nothing concurrent

Same probe, same 7 tokens and 1 subscription, 12 minutes later with nothing else in flight:

```
15:01:42.781  [Webhook] PROBLEM — Queued delivery to 8 target(s)
15:01:43.220  [APNs] Sent to ...a0f85792
15:01:43.360  [APNs] Sent to ...32295bdd
15:01:43.502  [APNs] Sent to ...86587674
15:01:43.642  [APNs] Failed (400) via production: {"reason":"BadDeviceToken"}      ← ...b26fb517
15:01:43.785  [APNs] Sent to ...0c56a19b
15:01:43.926  [APNs] Failed (410) Unregistered → [Cleanup] Removed ...62f21e50
15:01:44.067  [APNs] Sent to ...018ab51d
15:01:44.145  [WebPush] Sent to https://fcm.googleapis.com/fcm/send/...
```

**All 8 targets served in 1.4 seconds. No stall, no timeout.**

### Verdict

**2.13.4 fixed concurrency *within* one fan-out and left concurrency *between* fan-outs untouched.**
The sends were made sequential inside `send_to_all`, but nothing serialises two `send_to_all` calls
running as separate `BackgroundTasks` on the same shared HTTP/2 `AsyncClient`. Two overlapping
webhooks reproduce §3.8's original condition exactly: concurrent POSTs on one HTTP/2 connection,
wedged after the first few responses, with httpx's own timeouts not firing.

This matters in production, not just under a probe: a site outage raises several host alerts in the
same second, and BHNM renotifications batch. **The single-webhook case that was verified on 09-14 is
the easy case.**

Two things did work and should be credited:

- The **60 s `asyncio.wait_for` guard added in 2.13.4 did its job** — it turned a silent, permanent
  stall into two logged `[Deliver] TIMEOUT` lines. Without it this run would have looked like
  silence again.
- The **2.13.2 redaction filter held** — both access lines read `secret=<redacted>`.

### Still open from this run

- `...b26fb517` returned **400 BadDeviceToken** again and was **not** removed — only 410 triggers
  cleanup. Open defect 3, now observed twice more.
- `...62f21e50` returned 410 and *was* cleaned, leaving 6 tokens. It had already been cleaned on
  09-15 at 09:57 and 10:14 and re-registered at 10:45:56 — a device is re-registering a token APNs
  considers dead.
- **Which physical phones buzzed at 15:01:43 is not established** and needs Thomas. Five distinct
  live tokens plus one FCM Web Push subscription were served; the §3.8 question of whether the two
  parked phones were merely never sent to is answered "they are being sent to now", but not
  "they rang".

### Side observation — SSH to the VPS was flapping throughout (2026-09-15, 14:4x–15:0x UTC)

Not chased, recorded in case it recurs. `bhnm-apns.hurrikap.org` (172.104.142.164):

- **TCP to port 22 connects** (`nc -z` succeeds), but the SSH handshake then times out —
  `kex_exchange_identification: read: Operation timed out` / `banner exchange`. So it is not a
  firewall block and not a DNS problem.
- It failed for stretches of **2–5 minutes at a time**, then worked normally (`ssh -vv` completing
  in 0.7 s), then failed again. Four consecutive attempts failed, one succeeded, four failed.
- **HTTPS was unaffected throughout** — `/health` answered in **57 ms** during the same windows,
  and the incident/tactical caches kept updating on schedule.

So the box and the application were healthy; only sshd was intermittently failing to complete a
handshake. Consistent with sshd `MaxStartups` throttling or fail2ban, but not diagnosed. It cost
several retries and one probe attempt whose outcome could not be read back.

---

## Follow-ups this measurement generated

Recorded here so they are not carried only in conversation. None are started.

**1. Admin portal: device/token overview (agreed, not yet specced).** The `Push Config` page lists
`device_name`, a truncated token and `registered_at` — which told us nothing this morning, because
iOS 16+ reports every device as `iPhone` and the page shows no delivery state. Extend that page
rather than adding a screen:

- record `last_push_at`, `last_status` and `last_error` per token in `_fan_out`, which already sees
  every result — that alone would have shown `410 Unregistered` and `400 BadDeviceToken` at a glance
- show which BHNM server each token belongs to (`active_secret` → `servers.json` name)
- per-device **Remove** (with a confirmation naming the consequence) and **Send test push**
- **user label**: `device_name` is useless, but the QR already carries a username and the app already
  stores it as the ACK user; having the app send it on `/register` turns five identical rows into
  named ones. Needs a small change on both sides.

**2. A first-time user onboarded by QR gets a working app that will never alert them.** Confirmed
on 2026-09-15, root cause found by Thomas rather than by code reading.

QR import deliberately adds a server **without making it active** — correct when the user already has
servers, wrong on a fresh install where it is the only one. The app then holds exactly one saved
connection and no active connection. Everything the user can see says it works: incidents and
tactical data load, Settings lists the server, "Enable Push Notifications" reads enabled. But
`AppDelegate.swift:47–52` needs `netreo_active_connection_id` to resolve before registering, it is
empty, so registration is skipped with a local `print` and nothing retries.

Measured on the iPhone 13 Pro Max: reinstalled, QR scanned, notifications allowed — app fetching
`/api/v1/incidents` and `/api/v1/tactical-overview` on its 30 s cycle from 10:48, and **zero
`POST /register`**. Ticking the radio button beside the server at 10:50:50 registered token
`…018ab51d` within a second; a single-token probe then returned `200` and the notification arrived.

**Fix:** when a QR import produces the only saved connection, select it. More generally, register
when the token arrives **or** when a connection becomes active, whichever is last, and re-check on
foreground.

The same signature is present on a colleague's iPhone 13 Pro — fetching data, never registered.

Two related gaps in the same area:

- Three of four devices were silently not receiving, for three different reasons (Android in-app
  switch off and never subscribed; this QR/active-connection defect; and dead tokens from previous
  installations). **In none of them did the app say so.**
- For a paging product the Settings screen should show registration state **as confirmed by the
  middleware** ("registered 2 minutes ago" vs "not registered"), plus a test-push button, rather than
  a local toggle that can silently mean nothing.

**3. `400 BadDeviceToken` is never cleaned up.** Only `410` triggers removal, so a token in that
state is retried on every incident forever. Token `…b26fb517` is in this state now.

**4. Android notifications arrive only in the shade**, not as a heads-up banner with sound —
a notification-channel importance setting. Material for a paging product.
