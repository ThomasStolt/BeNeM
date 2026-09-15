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

## Part 3.10 — Prediction, recorded BEFORE the identification run (2026-09-15, 16:3x UTC)

Written before a single identification push was sent, so the result can refute it.

**Measured first (no pushes):** all six live registrations report `apns_environment =
production` and `device_name = iPhone`. `SELECT DISTINCT` returns one value for each. So none
is an Xcode debug build, and **the "one phone, two rows as a sandbox/production pair" theory is
dead.** These are six distinct install events on TestFlight or App Store builds.

**The untested theory, and the prediction it implies.** iOS issues a **new** device token when
an app is reinstalled, and the middleware deletes a row only on APNs `410`, which Apple returns
lazily — sometimes not for days. Stale rows therefore accumulate silently and still return
`200`. Thomas has two or three iPhones against six production rows, so most of the older rows
should be dead registrations of phones that already appear again under a newer token.

| target | registered | prediction |
|---|---|---|
| `...a0f85792` | 2026-05-30 | **rings** — this is the row that was always first and was confirmed to produce a notification on Thomas's phone on 2026-09-15 (§3.8) |
| `...32295bdd` | 2026-06-04 | **silent, accepted 200** — stale, superseded by a later reinstall |
| `...86587674` | 2026-09-02 | **silent, accepted 200** — stale |
| `...b26fb517` | 2026-09-04 | **rejected 400 BadDeviceToken**, no ring |
| `...0c56a19b` | 2026-09-14 17:37 | **rings** — registered during the 2.13.3 verification cycle |
| `...018ab51d` | 2026-09-15 10:50 | **rings** — Thomas's iPhone 13 Pro Max, confirmed working in the QR measurement |
| FCM `faLoG1PCQS0` | 2026-09-15 10:12 | **rings** — the Android Web Push, delivered successfully at 15:01 |

**Summary prediction: at most three distinct iPhones ring; `32295bdd` and `86587674` are
accepted with `200` and reach nobody; `b26fb517` is rejected.**

**What would refute it:** any of `32295bdd` / `86587674` ringing, or fewer than three iPhones
ringing in total, or the colleague's phone appearing on a token predicted stale. If the
colleague's phone rings nothing at all, that is consistent with the separate finding that their
QR onboarding never registered them — which would mean the colleague is **not in this table**.

Result recorded in the section that follows, against this prediction, whether or not it held.

---

## Part 3.11 — Identification run: APNs result (2026-09-15, 16:45–16:48 UTC)

Seven targets, one push each, ~20 s apart, each body carrying its own token's last 8
characters. Thomas's colleague was warned before the run. **The ring column is not yet filled
— it can only come from the people holding the phones.**

| target | APNs result | predicted | prediction held? |
|---|---|---|---|
| `...a0f85792` | `200` accepted | rings | pending |
| `...32295bdd` | **`410 Unregistered`** | silent, accepted `200` | **partly wrong** — dead as predicted, but *rejected*, not accepted |
| `...86587674` | `200` accepted | silent, accepted `200` | pending |
| `...b26fb517` | **`400 BadDeviceToken`** | rejected `400`, no ring | **correct** |
| `...0c56a19b` | `200` accepted | rings | pending |
| `...018ab51d` | `200` accepted | rings | pending |
| FCM `faLoG1PCQS0` | sent, not expired | rings | pending |

So APNs accepts **four** of six iPhone tokens plus the Web Push subscription; one is
unregistered and one is malformed.

### What the 410 timestamps say — the useful part

APNs returns the moment a token stopped being valid, and both are informative:

- **`...32295bdd` has been unregistered since 2026-09-08 16:35:14 UTC** — a week. It survived
  every notification in that week only because the fan-out bug meant nothing past the first row
  was ever contacted. The sequential fan-out surfaced it on its first real use.
- **`...62f21e50` reported unregistered since 2026-05-29 00:35:25 UTC** when it 410'd at 15:01
  today — yet it was **registered at 10:45:56 today**, hours before. A device POSTed a token
  that Apple has considered dead since May. That is not a token iOS would have just issued, so
  something is re-registering a *stale cached* token rather than the current one — a restored
  backup carrying old `UserDefaults`, or the client sending `cachedDeviceToken` instead of the
  live one. This is the strongest lead so far for the `...62f21e50` investigation and it points
  at the client, not at phone settings.

### Note on cleanup

The run called `apns.send_to_all` directly rather than going through `_fan_out`, so the `410`
did **not** delete `...32295bdd` — the row is still present. Deliberate: a measurement should
not mutate the thing being measured. It will be cleaned by the next real webhook.

---

## Part 3.12 — The fleet, finally identified (2026-09-15, 16:5x–17:00 UTC)

Three rounds of one-push-per-token, with the humans reporting what appeared.

| token | phone | established by |
|---|---|---|
| `...0c56a19b` | **iPhone 13 Pro Max** — Thomas, private | round 1 |
| `...018ab51d` | **iPhone 15** — Thomas, work | round 1 |
| `...86587674` | **iPhone 13 Pro** — Jonah | round 3, after he toggled notifications |
| FCM `faLoG1PCQS0` | **Edge 60** — Android | round 1 (only one Android, so unambiguous) |
| `...a0f85792` | **never claimed** | — |
| `...32295bdd` | dead, `410` since 2026-09-08 | — |
| `...b26fb517` | dead, `400 BadDeviceToken` | — |

The three unclaimed/dead rows were deleted at Thomas's instruction, after being backed up to
`/data/deleted_tokens_backup.json` on the VPS so they can be restored. Six rows became three.

### The prediction (Part 3.10) was mostly wrong — and wrong in the direction that matters

| target | predicted | actual | verdict |
|---|---|---|---|
| `...a0f85792` | rings, Thomas's phone | accepted `200`, never claimed | **wrong** |
| `...32295bdd` | silent, accepted `200` | `410 Unregistered` | **half** — dead, but rejected |
| `...86587674` | silent, stale row | **live phone**, notifications switched off | **wrong** |
| `...b26fb517` | rejected `400` | `400 BadDeviceToken` | correct |
| `...0c56a19b` | rings | rings — 13 Pro Max | correct |
| `...018ab51d` | rings, 13 Pro Max | rings, **iPhone 15** | right that it rings, wrong phone |
| FCM | rings | rings | correct |

One of seven fully right on the first attempt. The theory under the prediction — that stale
rows accumulate because APNs reports `410` lazily — explained two rows, not the fleet.

**The specific error worth keeping:** `86587674` was written off as a stale row when it was a
live phone with notifications turned off. That is the *device-settings* explanation which §3.8
had parked and explicitly said to **retest before assuming**, and which the fan-out discovery
had made me treat as retired. Both causes were real, in different phones, at the same time.
Finding one true cause is not evidence that a previously suspected one is false.

### `...a0f85792` — unresolved, and it is the important one

This row was registered 2026-05-30 and, because the fan-out bug served only the first row of an
unordered query, **it was the only token BeNeM contacted for months**. It accepted `200` in
both identification rounds, and no phone was reported as showing it.

That is not the same as proof that it reached nobody — no one was explicitly asked "did
anything show `a0f85792`", so its absence from the reports is weak evidence, not a measurement.
But if it is indeed a device nobody carries, it explains the entire silent-phones history in
one line: every alert was delivered, successfully, to a phone that no longer exists, while
three live phones were never contacted at all.

The row is deleted but recoverable from the backup, so the question stays answerable.

### Two observations from the same window

- **`86587674` re-registered three times** (16:53:54, 16:57:03, 16:58:33), the same token each
  time, each producing a new row id. Turning notifications off did **not** invalidate the token
  and APNs kept returning `200` throughout — so a phone suppressing notifications on-device is
  invisible to the middleware by construction. No amount of server-side instrumentation can
  detect it; only the client can report it.
- **No `[Unregister]` line appeared** in that window, only `[Register]`s, although the in-app
  toggle was switched off and on. Either the toggle-off path did not fire `DELETE /register`,
  or it was already off and only switched on. Not established from one observation — worth a
  deliberate check, because if toggling off does not unregister, a user who disables
  notifications in the app keeps receiving them.

---

## Part 3.13 — Live concurrency burst against 2.14.0 (2026-09-15, 17:15:38 UTC)

The verification the fix was deployed for, and the one the 09-15 14:49 accident stood in for.
Four `POST /webhook` requests released simultaneously from four threads behind a barrier, all
landing inside **30 ms** of each other — deliberately the shape that wedged 2.13.4.

### Ingest

```
17:15:38.902  [Webhook] PROBLEM — burst-test-3 — Incident 903 — Queued delivery to 4 target(s)
17:15:38.924  [Webhook] PROBLEM — burst-test-4 — Incident 904 — Queued delivery to 4 target(s)
17:15:38.929  [Webhook] PROBLEM — burst-test-1 — Incident 901 — Queued delivery to 4 target(s)
17:15:38.931  [Webhook] PROBLEM — burst-test-2 — Incident 902 — Queued delivery to 4 target(s)
```

All four answered `200 {"status":"ok","notified":4}` in **54–83 ms** — far inside BHNM's ~30 s
timeout, so no retry storm.

### Delivery — 16 sends, in four clean groups

```
17:15:39.359  0c56a19b   17:15:39.850  0c56a19b   17:15:40.336  0c56a19b   17:15:40.822  0c56a19b
17:15:39.500  018ab51d   17:15:39.988  018ab51d   17:15:40.475  018ab51d   17:15:40.959  018ab51d
17:15:39.637  86587674   17:15:40.126  86587674   17:15:40.613  86587674   17:15:41.097  86587674
17:15:39.711  webpush    17:15:40.197  webpush    17:15:40.682  webpush    17:15:41.173  webpush
```

**Every fan-out completed in full, in registration order, one after another with no
interleaving.** No `[Deliver] TIMEOUT`, no failure, no drop, no backlog warning. Sixteen
deliveries in **1.81 s**, ~0.113 s per send — which also validates the 0.15 s seed proposed for
the drain-time estimator.

### Per target

| target | phone | webhooks served |
|---|---|---|
| `...0c56a19b` | iPhone 13 Pro Max — Thomas, private | **4 / 4** |
| `...018ab51d` | iPhone 15 — Thomas, work | **4 / 4** |
| `...86587674` | iPhone 13 Pro — Jonah | **4 / 4** |
| FCM `faLoG1PCQS0` | Edge 60 — Android | **4 / 4** |

### Against the defect it fixes

| | 2.13.4, 14:49 (2 webhooks, 255 ms apart) | 2.14.0, 17:15 (4 webhooks, 30 ms apart) |
|---|---|---|
| fan-outs completed | 0 of 2 | **4 of 4** |
| targets served | ~3 of 16 attempted | **16 of 16** |
| `[Deliver] TIMEOUT` | 2 | **0** |
| wall time | 60 s, then abandoned | **1.81 s** |

Whether each notification actually *rang* is a separate question for the people holding the
phones; "sent" and "rang" are not the same, as Jonah's phone demonstrated earlier today.

---

## Part 3.14 — `...62f21e50` resolved: an old install, not a client defect (2026-09-15, 17:4x UTC)

Every event for this token, across the live container and every log dump:

```
2026-09-14T16:09:49.994  [Unregister] Token removed: ...62f21e50
2026-09-15T09:57:11.664  [APNs] Token gone (410)  → [Cleanup] Removed
2026-09-15T10:14:55.272  [APNs] Token gone (410)  → [Cleanup] Removed
2026-09-15T15:01:43.926  [APNs] Token gone (410)  → [Cleanup] Removed
```

Its last registration was **10:45:56 on 2026-09-15**, and it has **not reappeared since 15:01** —
two and a half hours and a four-webhook burst later, the table holds only `0c56a19b`, `018ab51d`
and `86587674`.

### What it was

10:45:56 is **roughly two minutes before the QR reinstall measurement** on the iPhone 13 Pro Max,
which follow-up 2 records as reinstalled and fetching from 10:48, registering `...018ab51d` at
10:50:50. So `...62f21e50` is the **old install's final registration**, made on a last launch just
before the app was deleted. Once the app that held it was gone, nothing offered it again — which
is exactly the silence observed after 15:01.

**This retires the theory I proposed earlier**, that a client was re-sending a stale *cached*
token. It could not have been: `cachedDeviceToken` is in-memory only and never persisted, so the
app has no cached token to re-send across launches. The token was being supplied by iOS to a live
install, repeatedly, until that install was deleted. **No client defect is evidenced here.**

### The part that remains odd, stated as odd

APNs reported this token unregistered **since 2026-05-29 00:35:25 UTC** while it was actively
registering in September. The plausible reading is that the app was deleted and reinstalled back
in May, iOS reissued the same token value, and APNs's invalidation record was never refreshed —
its timestamp is *"when APNs last confirmed the token invalid"*, not a guarantee about the
present. That is an explanation, not a measurement, and nothing here depends on it.

Practical consequence worth keeping: **a `410` timestamp is not evidence about the current
device.** Reading it as "this phone has been dead since May" would have been wrong.

### The real finding: registrations are untraceable

This took far longer than it should have because **`[Register]` does not log which token it
saved**:

```
[Register] Token saved for: iPhone (APNs: production)      ← which token?
[Unregister] Token removed: ...62f21e50                    ← says exactly which
```

Every registration in the log is anonymous, so a token's history cannot be reconstructed — the
timeline above had to be assembled from `410`s and one lucky `[Unregister]`. One-line fix: log
the last 8 characters, as `[Unregister]`, `[APNs]` and `[Cleanup]` all already do.

Related: that `[Unregister]` at 2026-09-14 16:09:49 is the **only one in the entire log history**
(9 `[Register]` lines against it), and it belongs to this token.

---

## Part 6 — `[header]` on a plain WebHook: measured, and it works (2026-09-15, 18:42 UTC)

The gate on the whole S1 header design. BMC documents the `[header]` block in a walkthrough that
says to pick *Active Response Webhook*; BeNeM's method must be plain **`WebHook`**, and the only
example on the box was on an unused method that had never fired.

### The rig

Temporary Action `BeNeM header capture (temporary)` in the `BeNeM` group, one plain **WebHook**
method, `SSL disabled`, `Auth Token None`, `24x7`, → `http://192.168.2.224:8787/capture?m=hdr`.
**The live `Mobile BeNeM Notification` method was never touched** and paged normally throughout.

Pre-flight, because the 09-14 run never proved reachability and paid for it:

- The Mac's address was re-checked rather than reused — still `192.168.2.224` (`en21`), and BHNM
  independently agrees: device `MacBook-Pro-Thomas.local`, `dev_index 126`, `ip 192.168.2.224`,
  `monitor: 1`.
- **The Mac was set to `sleep 1` on *both* battery and AC** — one minute idle. The listener would
  have died mid-run and produced an empty capture, which would then have been misattributed to
  `[header]` not working. Run under `caffeinate -dimsu`; `pmset -g assertions` confirmed
  `PreventSystemSleep` held. Settings unchanged.

The probe secret was **64 hex characters** (`deadbeef` × 8), the same shape as a real one, so a
length cap or truncation would surface here rather than on the migration.

### The capture, verbatim

```
2026-09-15T18:42:14.662911+00:00  from 192.168.2.211  POST /capture?m=hdr
--- headers ---
  Host: 192.168.2.224:8787
  User-Agent: curl/7.61.1
  Accept: */*
  X-Webhook-Token: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  Content-Type: application/json
  Content-Length: 317
--- body ---
{ "incident_id": "29570", "hostname": "raspi-050", "host_address": "192.168.2.50",
  "host_state": "DOWN", "notification_type": "PROBLEM", "severity": "", "site": "New_York",
  "category": "Raspberry Pi", "service_desc": "", "output": "<br />Ping CRITICAL: Packet Loss 100%",
  "incident_time": "Tue Sep 15 20:42:13 2026" }
```

### Every question answered

| question | answer |
|---|---|
| Does `[header]` reach the wire on a **plain WebHook**? | **Yes.** Both custom headers arrived, from `192.168.2.211`. |
| Does a **64-character** value survive? | **Yes, intact.** No truncation, no length cap. |
| Does `Authorization` survive with `AUTHORIZATION TOKEN = None`? | **Yes** — it is not stripped or overwritten. |
| Do the header block and the JSON body **coexist**? | **Yes.** All eleven fields arrived, `Content-Length: 317`. `[header]` does not consume the body. |
| What `Content-Type` actually arrives? | **`application/json`.** |

### Consequences

1. **The S1 header design is confirmed on the method type BeNeM actually needs.** Option (a) in
   the spec stands; option (c), the body field, is no longer needed as a fallback.
2. **`Authorization: Bearer` is available**, so the recommendation to use it — rather than a
   custom header that loggers do not redact — is implementable as written.
3. **A wart is retired as a side effect.** Both method types previously sent JSON under
   `application/x-www-form-urlencoded`, which is why the middleware's form-decode fallback was
   load-bearing for every real webhook (§2). With `Content-Type` set in the `[header]` block the
   body arrives correctly typed, and that fallback becomes what it was always meant to be — a
   defensive path, not the main one. **Do not delete it**: existing deployments that have not
   migrated their Action still depend on it.
4. **BHNM's webhook client is `curl/7.61.1`**, and the URL query string survives — useful when
   reasoning about what it will and will not do.

### RECOVERY leg — `[header]` is not PROBLEM-only (19:15:40 UTC)

raspi-050 reconnected at ~19:05; BHNM raised RECOVERY at 19:15:40, the usual poll-plus-close-delay
after the host came back. Same incident, 29570.

```
2026-09-15T19:15:40.626020+00:00  from 192.168.2.211  POST /capture?m=hdr
--- headers ---
  User-Agent: curl/7.61.1
  Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  Content-Type: application/json
  X-Webhook-Token: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  Content-Length: 365
--- body ---
{ "incident_id": "29570", ..., "host_state": "UP", "notification_type": "RECOVERY", ...,
  "output": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%  RTA = 0.555 ms",
  "incident_time": "Tue Sep 15 20:42:13 2026" }
```

All three headers present, `application/json`, both 64-character values intact, body complete. So
the `[header]` block is **method-level configuration, applied to every notification type the
method delivers** — not something that only survives on PROBLEM. Header *order* differs between
the two captures, which is immaterial but worth not being surprised by.

One detail that re-confirms §2: **`incident_time` carries the original incident time**
(`20:42:13` local = 18:42 UTC, the PROBLEM), not the recovery time. Anything reasoning about
recovery latency from this field will be wrong by the whole outage.

### Teardown

- Temporary Action **deleted** — banner *"Action Contact: BeNeM header capture (temporary) has
  been removed"*, and a search for `capture` returns **"No actions match your search"**. The
  `BeNeM` group is back to `IN USE 1`, one action, `Mobile BeNeM Notification`, its Method
  untouched throughout (SSL enabled, Auth Token disabled, 24X7, original URL and payload).
- **The Actions counter is not trustworthy**: it read 16 before the run, 17 with the temporary
  Action added, and **18 after deleting it**. The Methods counter behaved correctly (15 → 16 →
  15). The 09-14 run saw the same counter move without a corresponding change. Verify by
  searching, not by the number.
- Listener stopped, port 8787 free, the `caffeinate` assertion released.
- Captures preserved: 3 entries (one self-test, PROBLEM, RECOVERY).

### Production was unaffected

The live method delivered the same incident normally, through 2.14.0's queue:

```
18:42:14.661  [Webhook] PROBLEM — raspi-050 — Incident 29570
18:42:14.662  [Webhook] Queued delivery to 4 target(s)
18:42:15.093  [APNs] Sent to ...0c56a19b     (13 Pro Max)
18:42:15.232  [APNs] Sent to ...018ab51d     (iPhone 15)
18:42:15.373  [APNs] Sent to ...86587674     (Jonah)
```

**One capture, no retries** — the listener answered `200` immediately, so BHNM's three-retry
behaviour never engaged. Consistent with §3.3.

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

**5. Turning notifications off in the app does not reliably stop the paging.** Established
2026-09-15 from the code path, not from the single observation that prompted it.

Three places call `unregisterWithMiddleware` — `ServerConfigView.saveConnection` (switch turned
off), `ServerConfigView.deleteConnection`, and `ContentView.handleConnectionChange`. **All three
are gated on `AppDelegate.shared?.cachedDeviceToken` inside an `if let` / `guard let` with no
`else` branch.** When it is `nil` the unregister is skipped silently: no log line, no retry, no
recorded intent.

`cachedDeviceToken` is declared `var cachedDeviceToken: String? = nil` and is **in memory only**.
It is populated in `didRegisterForRemoteNotificationsWithDeviceToken` and never persisted, so it
is `nil`:

- for the first moments of **every** launch, until APNs answers; and
- for an entire session whenever `requestAuthorization` did not grant
  (`guard granted else { return }` means `registerForRemoteNotifications()` is never called).

So a user who launches BeNeM and promptly switches notifications off stays registered on the
middleware. iOS-level permission is untouched, so the pushes keep arriving **and displaying**.
The app says notifications are off and the phone still pages. That is a broken promise in
shipped code, and nothing anywhere reports it — the same invisibility class as defects 1 and 2.

Even on the happy path the call is best-effort: `unregisterWithMiddleware` fires and forgets,
printing errors and never retrying or verifying.

**What the logs say, and what they do not.** Across every log available (current container and
all dumps) there are **9 `[Register]` lines and 1 `[Unregister]`**. That establishes the path is
reachable, not how often it should have fired — people register more often than they
unregister, so the ratio alone proves nothing. The defect rests on the code path, which is
deterministic.

**Not yet established on a device.** Proposed A/B, one phone against the lab:

1. Confirm the phone is registered (row present in `device_tokens`).
2. Force-quit BeNeM. Relaunch and **immediately** — within a second, before APNs answers — open
   Settings → the server → switch notifications off → Save.
3. Check for `[Unregister]` and whether the row is gone. Fire a probe: **if the phone buzzes,
   the defect is confirmed.**
4. Control: repeat, but wait ~10 s after launch before toggling. Expect `[Unregister]` to fire,
   the row to disappear, and the probe to be silent.

**Proposed fix, and it is small.** `didRegisterForRemoteNotificationsWithDeviceToken` already
has the branch where the active connection has `notificationsEnabled == false` — today it
prints and returns. Make that branch **unregister** instead of doing nothing. The token has just
arrived, so it is available exactly when the earlier attempt lacked it, and the app then
self-heals on the next launch regardless of why the original DELETE was skipped. Persisting the
token in `UserDefaults` closes the same gap from the other side and is worth doing as well.

**5b. Nothing reconciles the in-app switch with the OS permission — and the PWA is ahead of
iOS here, but not everywhere.** Confirmed by grep 2026-09-15.

The per-connection switch is **not** duplication of the OS setting and stays: `notificationsEnabled`
lives on `SavedConnection`, so a user with two BHNM servers can mute one; iOS Settings is
app-wide. They also act at different points — the switch stops the middleware **sending**, the OS
setting lets the push arrive and drops it silently. Only the switch is per-server, and only the
switch saves anything server-side.

The defect is that neither client reconciles them. **iOS never reads the notification
authorization state at all**: the only `authorizationStatus` calls in the app are
`AVCaptureDevice.authorizationStatus(for: .video)` in `QRScannerView`, and `getNotificationSettings`
appears nowhere. So the switch can read ON while iOS denies everything, with no signal. Jonah's
phone was in exactly that state, and it cost two days.

### Where each client stands

| | iOS | PWA |
|---|---|---|
| Per-connection switch | **yes** — `SavedConnection.notificationsEnabled` | **yes** — `SavedServer.pushEnabled` (different name; easy to miss in a grep) |
| Reads the OS permission state | **no** | **yes** — `Notification.permission` in `pushRegistration.ts` |
| Shows the denied state in the UI | **no** | **yes** — *"Permission denied — enable in browser settings"* |
| Blocks the switch when the OS denies | **no** | **yes** — the toggle is `disabled` |
| Deep-links to OS settings | **no** — the pattern exists, for the camera only | n/a — browsers expose no such API |
| Re-checks when the app returns to foreground | **no** | **no** — `useState(getPushState)` runs once on mount; there is no `visibilitychange` listener anywhere in `pwa/src` |
| Removes the registration server-side on toggle-off | attempted, **silently skipped** when the token is nil (item 5) | **yes** — `unsubscribeFromPush()` |
| Registration state confirmed by the middleware | **no** | **no** — the "Registered and active" label is local belief (open defect 2) |

So the asymmetry runs both ways but not evenly: the PWA is ahead on OS-state awareness in three
respects and on reliable un-subscription; iOS is ahead in none. **Both** share the foreground
re-check gap and the middleware-confirmation gap. The two clients should converge on one model
even though the mechanisms differ.

### Design for the iOS half, riding with item 5

Reuse the camera pattern in `QRScannerView` rather than inventing a second one — it already does
`authorizationStatus` → denied → alert → `UIApplication.openSettingsURLString`:

1. Read `UNUserNotificationCenter.current().getNotificationSettings` and surface
   `authorizationStatus` **next to the switch**, not on a separate screen.
2. When the OS is denying, the row says so and offers **Open Settings** via
   `openSettingsURLString`, exactly as the camera alert does. The switch itself should not claim
   to be ON while the OS denies.
3. **Re-check on foreground** (`scenePhase == .active` / `willEnterForeground`), since the user
   can change it in Settings while the app is backgrounded. This one is worth doing on the PWA
   too, via `visibilitychange` — it is the one gap both clients share.
4. Label both controls so "off" is never ambiguous: *this switch stops the server sending;
   Settings stops the phone showing.*

`getNotificationSettings` is asynchronous and returns on an arbitrary queue — hop to the main
actor before touching the view state.

**3. `400 BadDeviceToken` is never cleaned up.** Only `410` triggers removal, so a token in that
state is retried on every incident forever. Token `…b26fb517` is in this state now.

**4. Android notifications arrive only in the shade**, not as a heads-up banner with sound —
a notification-channel importance setting. Material for a paging product.

---

# Part 7 — Measurement 2, PWA half: a 401 versus a dead network (2026-09-15, ~19:5x–20:2x UTC)

Runbook: `docs/runbooks/2026-09-15-one-sitting-device-measurements.md`, Measurement 2. The phone
half is still outstanding; this is the browser half, which needed nobody but the browser.

**The question.** Whether stale-data-while-disconnected is *already* a defect today, independent
of revocation. Stated as a prediction before measuring, so a wrong prediction would be visible:
the code suggested the two arms would be indistinguishable with a warm cache and faintly
distinguishable with a cold one, by the error string in the `isError && !data` empty state. **The
prediction was wrong in the app's disfavour** — see "What the prediction got wrong" below.

## 7.0 A blocker first: the PWA host does not resolve on the work Mac

| probe | result |
|---|---|
| `dig benem.hurrikap.org` (LAN resolver `192.168.2.11`) | **NXDOMAIN**, `flags: qr aa` — answered *authoritatively* |
| `dig @1.1.1.1 / @8.8.8.8 / @9.9.9.9` | `172.104.142.164`, all three agree |
| `curl --resolve benem.hurrikap.org:443:172.104.142.164 https://benem.hurrikap.org/` | **HTTP 200 in 0.05 s** |
| `dig bhnm-apns.hurrikap.org` | resolves normally |

Split-horizon DNS: the LAN resolver is authoritative for `hurrikap.org` and has no record for the
PWA host, while public DNS does. The box and the route are fine. This is the open "LAN DNS" item,
now root-caused.

**Test-only workaround, and its removal.** Thomas added one line to `/etc/hosts`:

```
172.104.142.164 benem.hurrikap.org
```

Deliberately *not* Chrome's Secure DNS setting: that toggle changes resolution for every host in
the profile, including the lab at `bhnm-b.tstolt.com`, and would have traded the lab for the PWA.
`--host-resolver-rules` was also rejected — it maps exactly one host, but needs a separate Chrome
instance, which has neither the extension attached nor the configured `benem_servers` in
localStorage.

**Removal confirmed 2026-09-15 20:19 UTC**, as the last step, because a stale hosts entry would
mask the real DNS fix later:

```
$ grep -n "benem" /etc/hosts   → no benem entry
$ curl --max-time 6 https://benem.hurrikap.org/   → 000, could not resolve (expected)
```

## 7.1 Method

Four cells: each arm with the cache **warm** (incident list fully loaded before the arm was
applied) and **cold** (the arm in force from the first paint).

- **Arm A — the server refuses the credential.** The app's own requests, with the `X-Proxy-Token`
  header rewritten to a wrong value, so the **401 is genuinely from the middleware**
  (`{"detail":"Invalid proxy token"}`) rather than from a stub. Cold cell: the stored token
  replaced with a same-length bogus value, the original backed up verbatim and restored after.
  **The production `.env` was not touched** — the runbook's server-side rotation would have
  refused the three live phones as well, for no gain.
- **Arm B — the network is gone.** Warm cell: the three signals a browser gives a page when the
  radio is off — `navigator.onLine` false, an `offline` event, `fetch` rejecting with
  `TypeError: Failed to fetch`. **Simulated, not the real radio; labelled as such.** Cold cell:
  real, measured with the hosts entry removed.

## 7.2 The four cells

**Arm A — 401.**

| # | observation | warm cache | cold cache |
|---|---|---|---|
| 1 | incident list | 15 stale incidents, unchanged | **blank** — no rows, no empty state |
| 2 | time to first change | **no change in 20 s** after two real 401s | **none, ever** (12 s sampled, 3 loads) |
| 3 | anything saying it is wrong | **no** | **no** |
| 4 | refresh | fires `/bhnm/api/v1/incidents` → 401, then the legacy fallback `/bhnm/api/incident_api.php` → 401. UI unchanged | **no refresh control exists** — `RefreshRing` renders only when `dataUpdatedAt > 0` |
| 5 | background 30 s and return | not measurable, see 7.4 | not measurable |
| 6 | connection badge | **`connected`. Green. Throughout.** | **`unknown`. Grey.** Never `disconnected` |

**Arm B — no network.**

| # | observation | warm cache (simulated) | cold cache (real) |
|---|---|---|---|
| 1 | incident list | 15 stale incidents, unchanged | **the app does not open at all** — Chrome's `DNS_PROBE_FINISHED_NXDOMAIN` page. Separately, with the shell already served from the Workbox precache: blank content, header and tab bar only |
| 2 | time to first change | **none in 10 s** with no user action | n/a — no app on screen |
| 3 | anything saying it is wrong | **no** | Chrome says so; **the app never does** |
| 4 | refresh | **hangs indefinitely** — see 7.5 | no app on screen |
| 5 | background and return | not measurable | not measurable |
| 6 | connection badge | **`connected`. Green.** | grey `unknown` in the precache case; no badge at all in the error-page case |

## 7.3 The answer

**Warm cache: NOT distinguishable.** Green `connected` badge, the same fifteen stale rows, no
message, in both arms. The only difference is invisible to the user — one arm sent two requests
that came back 401, the other sent none.

**Cold cache: NOT distinguishable.** Blank screen, grey `unknown` badge, no message and no
control to tap, in both arms.

**So it is a defect today, independent of revocation**, and it raises the priority of
incident-freshness Part 3 rather than merely confirming it: Part 3 was scoped to the detail
screen, and this says the list screen and the badge have the same disease.

### What the prediction got wrong

The prediction was that the cold cells would differ by an error string, because
`IncidentListScreen.tsx:44` renders *"Could not reach BHNM"* with `(error as Error).message` on
`isError && !data`. **In all three cold loads that branch did not render.** Read directly from the
query cache: `status: "pending"`, `fetchStatus: "paused"`, `error: null` — so `isError` was false
and there was nothing to render. The hypothesis offered here first — that a failing first attempt
with `retry: 1` leaves the query pending with the retry paused — **was tested and refuted**; see
7.7. See 7.6 for the independence check on this observation.

### The badge, which needs none of that mystery solved

`components/AppHeader.tsx:34`:

```tsx
const derivedStatus: ConnectionStatus =
  !config.isConfigured ? 'disconnected' :
  isLoading             ? 'checking'     :
  isError               ? 'disconnected' :
  dataUpdatedAt > 0     ? 'connected'    :
                          'unknown';
```

`dataUpdatedAt` never resets once data has loaded, so **a warm cache reads `connected`
permanently regardless of what happens next.** The badge does not report the connection; it
reports that data arrived at some point in the past. That is the doctrine violation as one
ternary, and it explains the entire warm-cache row without reference to the paused-query
question. Design direction is recorded in the incident-freshness spec, Part 3.

## 7.4 What could not be measured, and why

Observation 5 in every cell. The extension-driven tab reports `document.visibilityState ===
"hidden"` permanently, so background-and-return could not be produced, and React Query's
interval refetch — gated on visibility by design — **fired not once in 155 s** with a 120 s
interval. An artifact of the harness, not the product. The phone half of the runbook covers it.

## 7.5 Defect found in passing: Refresh hangs forever while offline

`IncidentListScreen.onRefresh` awaits `queryClient.invalidateQueries(...)` and then `refetch()`.
While the query is paused neither promise settles, so the control hangs with **no timeout and no
feedback**: the tap does nothing, nothing spins, nothing errors. Observed as two CDP evaluations
timing out at 45 s after the tap, UI unchanged throughout. It is the one control a user reaches
for when they suspect the data is stale — which is exactly when it fails. Queued as handoff
item 10.

## 7.6 Independence check on the paused-query observation

Challenged on review: was Arm A run in a tab that had earlier been put offline for Arm B, without
a hard reload? A lingering offline state in React Query's online manager would produce exactly the
`paused` / `error: null` that was observed.

**Refuted by sequence.** In the measurement tab, in order: the tab was created *after* the hosts
entry, loaded healthy (`connected`, 15 rows); Arm A warm was applied as a header rewrite only —
no `onLine` spoofing, no `offline` event; the three cold Arm A loads followed, each a **full page
load**, which resets the online manager regardless; the key was restored and the app returned to
`success/idle` with 15 rows; **only then** was Arm B's offline simulation applied for the first
time. No offline state of any kind existed in that tab before or during the Arm A cells, and
`navigator.onLine` was measured `true` inside the paused state.

**Still not independently re-run, deliberately.** A fresh never-offline tab would settle it
beyond the timeline argument, but it needs the hosts entry re-added, and re-adding a
deliberately-removed test-only workaround to re-prove something the sequence already excludes is
not worth the risk of leaving it behind. **Status, stated exactly:** the challenge was raised on
review and **answered by sequence, not by re-measurement**; the hypothesis was withdrawn by the
reviewer on that basis. The observation is measured and reproducible — 3 of 3 cold loads — and
**not independently reproduced.** Both halves of that sentence are the honest state; neither is
to be rounded up.

The mechanism question that remains — whether a failing first attempt with `retry: 1` leaves the
query at `pending` / `paused` / `error: null` rather than reaching `error` — is about React
Query's own behaviour, not about this deployment, and is settled in `pwa/src/lib/api/__tests__/`
rather than by another browser sitting. See 7.7.

## 7.7 The paused-query signature, settled in vitest

The mechanism question was about React Query's own behaviour, not about this deployment, so it was
settled with a test rather than another browser sitting:
`pwa/src/lib/api/__tests__/query-failure-state.test.ts`, three cases against the app's real
`fetchJson` and `main.tsx`'s exact defaults (`retry: 1`, `staleTime: 30_000`).

| case | result |
|---|---|
| `fetch` rejects (`TypeError: Failed to fetch`), browser online | **`status: "error"`**, `fetchStatus: "idle"`, error set |
| `fetch` resolves `401`, browser online | **`status: "error"`**, `fetchStatus: "idle"`, error set |
| React Query believes it is offline | **`status: "pending"`, `fetchStatus: "paused"`, `error: null`** |

**The hypothesis in 7.3 is refuted, and this is the correction.** A failing first attempt with
`retry: 1` does **not** leave the query pending — online, both a rejected fetch and a 401 reach
`status: "error"` with the error populated. **The error branch is reachable, not unreachable**, and
`IncidentListScreen.tsx:44` is not the bug.

The only condition that reproduces the observed triple is React Query believing it is offline. So
the browser observation means the page's `onlineManager` was offline, despite `navigator.onLine`
reading `true` in that same page and a hand-rolled `fetch` returning 401 from it at that moment.

**What this changes about the fix.** The defect is not a missing error branch — it is that
**nothing in the PWA renders the paused state at all.** React Query has a first-class "I am not
even trying, because I believe there is no network" state, and the app has no appearance for it:
no list, no error, no spinner, no refresh control, and a grey `unknown` badge. That is precisely
the doctrine's third state — *unverified* — going unrendered, and it is the same defect class as
the badge ternary rather than a separate one. Part 3's four states must therefore cover *paused*,
not only *loading / resolved / gone / unreachable*.

**Still open, and not claimed as understood:** *why* `onlineManager` was offline on those three
loads. It correlates with the refused credential and not with the tab being hidden — the healthy
load in the same tab fetched normally — and the app never calls `onlineManager` or sets
`networkMode` anywhere in `pwa/src`. Dispatching an `online` event and forcing
`networkMode: 'always'` did not unpause it. The three tests above stay as a regression guard on
the signature regardless of what the cause turns out to be.

---

# Part 8 — S1 change 1a deploy (2026-09-15, 20:42–20:46 UTC) — **VERIFICATION INCOMPLETE**

Status written first, because the doctrine applies to this file too: **1a is deployed and
healthy, and it is NOT yet verified on the wire.** Do not record it as verified until Part 8.3
is filled in.

## 8.1 Order, and why it is this order

Deploy **first**, seed **second**. The reverse leaves a window in which the old `save_servers()`
is live while seeded accepted lists exist, and one portal save in that window erases them
silently — the unresolved-secret fallback then hides the damage until 1b. Deploying first means
the fixed `save_servers()` is already running before there is any list to lose.

Push is a **prerequisite**, not a follow-up: `upgrade.sh` pulls from origin and exits early when
local matches remote, so nothing unpushed can be deployed. Recorded as a rule in
`middleware/CLAUDE.md`.

## 8.2 What was done, in order

| time (UTC) | step | result |
|---|---|---|
| 20:41 | push `main` | `746b922..0b49a42`, 8 commits |
| 20:42:37 | log dump | `/root/logdumps/benem-middleware-20260915T204237Z-pre-2.15.0.log`, 126 KB |
| 20:42 | tag images for rollback | `bhnm-apns-bhnm-apns:pre-2.15.0`, `bhnm-apns-benem-admin:pre-2.15.0` |
| 20:43 | **before** device set | 3 devices — `…0c56a19b`, `…86587674`, `…018ab51d`, all `production`; 1 Web Push subscription (id 13, FCM); **`SELECT COUNT(DISTINCT active_secret)` = 1**, which is the single global secret the whole design describes; 4 servers, none carrying `webhook_secrets` |
| 20:44 | `./upgrade.sh` | all three images rebuilt and recreated; `/health` → **2.15.0**, `registered_devices: 3`; admin 1.6.3 healthy; PWA serving |
| **20:45:43** | **seed** | `servers.json` backed up, then every one of the 4 servers seeded with the current secret — fingerprint **`95e54469`**. No value printed at any point |
| 20:46 | cache reload | all 4 servers `200 {"status":"ok"}` |

**The seed timestamp is 2026-09-15T20:45:43Z.** Any `[Webhook] FALLBACK` line *before* that
instant belongs to the window between deploy and seed and is expected. Any FALLBACK line *after*
it is a failed verification.

## 8.3 Verification — first attempt FAILED, and the criterion is what caught it

The acceptance criterion, as a pass/fail rather than a note:

> After the seed, a webhook must produce a `[Webhook]` line reading `server=<name>`, and there
> must be **ZERO** `FALLBACK` lines after 20:45:43Z. Any FALLBACK after the seed means the seed
> did not take, and that is a failed verification.

**It failed, at 21:02:09Z:**

```
[Webhook] PROBLEM — benem-1a-verify — Incident 999001
[Webhook] FALLBACK — no server lists secret=95e5…; using the pre-1a single-secret lookup.
[Webhook] Queued delivery to 4 target(s) for incident 999001
```

`95e5…` is the fingerprint of the secret seeded into all four servers seventeen minutes
earlier.

> **Two notes on these quotes.** The fingerprint is **truncated to four characters here**, not in
> the log: the repo's credential scanner flags `secret=<8+ hex>` and is right to, because it
> cannot distinguish an eight-character fingerprint from the eight-character secret *fragment*
> that leaked into this very file and caused the scanner to be written. The field name is quoted
> as it really was — the deployed 2.15.0 printed `secret=`. It was renamed to `secret_fp=`
> immediately afterwards, for the same reason plus a worse one: see 8.6. The middleware was telling the truth: **as far as the container was concerned, no
server listed it.**

### Root cause: an atomic rename broke the bind mount

| | inode | `webhook_secrets` |
|---|---|---|
| host `/root/BeNeM/middleware/servers.json` | **26419** | seeded, all four servers |
| container `/data/servers.json` | **17049** | empty, all four servers |

The seed script wrote a temp file and `os.replace()`d it over the target — the standard safe
write, and exactly wrong here. `docker-compose.yml` bind-mounts `servers.json` as a **file**, so
the mount is bound to the *inode*; the rename created a new one and the container kept reading
the old. The host looked correct. Nothing errored. Recorded as a trap in `middleware/CLAUDE.md`;
the fix is to write in place, which is what `benem-admin`'s own `save_servers()` does — which is
why portal saves take effect and this seed did not.

**The failure was in the seed step, not in 1a.** The deployed code did precisely what it was
designed to do: it could not resolve the secret, it said so loudly, it fell back, and all four
targets were paged. That is the safety net working, and it is why the fallback logs loudly.

### Why this was not reverted, although a revert was pre-authorised

Recorded so the departure reads as reasoning rather than improvisation. The standing
pre-authorisation was: *if verification fails, revert and redeploy immediately without asking.*
It was not exercised, on three grounds:

1. **What failed was an operator step, not the deploy.** The seed used the wrong write idiom.
   The code under test behaved exactly as specified, and the FALLBACK line is evidence *for* it,
   not against it.
2. **The system was already in the safe state.** With the container reading a pre-seed
   `servers.json`, 1a's behaviour was byte-for-byte the pre-1a behaviour — which is what a
   revert would have produced. Reverting would have discarded a good deploy to fix a bad
   `os.replace`, and left the same seed still to do afterwards.
3. **The remedy was smaller than the revert.** Re-binding the mount is one `--force-recreate`.

The pre-authorisation exists so failed code never sits on `main` while someone waits for a
reply. That hazard was absent here: `main` was fine, and the fault was on the operator's side of
the line. **If the code had been at fault, the revert was the action.**

**This is the strongest argument for the criterion being written as pass/fail.** "Observe the
log" would have produced a report of success: the push arrived on all three phones, the device
count was right, `/health` was green. The single FALLBACK line is the only thing that
distinguished a working migration from one that had not taken.

Recovered by `docker compose up -d --force-recreate bhnm-apns benem-admin`, which re-binds the
mount to the current inode.

## 8.4 Verification — PASS on re-run (21:03:26Z)

Container now on inode 26419, all four servers listing `95e54469`.

```
[Webhook] PROBLEM — benem-1a-verify — Incident 999001
[Webhook] server=SaaS Demo Server secret=95e5…
[Webhook] Queued delivery to 4 target(s) for incident 999001
[APNs] Sent to ...0c56a19b
[APNs] Sent to ...86587674
[APNs] Sent to ...018ab51d
[WebPush] Sent to https://fcm.googleapis.com/fcm/send/faLoG1PCQS0:AP...
```

`FALLBACK` count since the mark: **0**.

| check | before | after | verdict |
|---|---|---|---|
| devices | 607 `…0c56a19b`, 615 `…86587674`, 616 `…018ab51d` | identical, **same `registered_at`** | PASS — nothing re-registered |
| Web Push | 1 (id 13, FCM) | identical | PASS |
| targets notified | 4 | 4 | PASS |
| distinct `active_secret` | 1 | 1 | PASS |
| QR reissued | — | none | PASS |
| on the phone | — | *"looks identical to me"* — Thomas, on the second notification | PASS, and this is the invariant, not an aside: 1a is behaviourally inert, so identical is the required outcome |

`server_id` is `''` on all three rows. Correct: the column fills on the *next* `/register`, and
1a deliberately does not force one.

### One thing to know before reading these logs later

The probe targeted the lab, and the line says **`server=SaaS Demo Server`**. Not a bug. While
every server's accepted list holds the *same* seeded secret, resolution returns the **first
match**, so the name in the log is "the first server that accepts this secret", not "the server
that sent it". Harmless in 1a because the fan-out is over an identical list either way — and it
is precisely what 1b fixes by giving each server its own secret. Until then, **the fingerprint
is the trustworthy half of that log line; the name is not.**

## 8.5 Still outstanding: a BHNM-originated webhook

Both firings above were **probes** against `/webhook`, not webhooks BHNM sent. They exercise
server resolution identically — resolution keys only on `?secret=` — so what they prove is that
the mechanism works. What they do **not** prove is that the secret in BHNM's Action URL is the
one that was seeded.

The ACK route was attempted twice and abandoned per the rabbit-hole rule: the middleware proxy
returns 403 (its SSRF guard refuses the lab's private target), and a direct call from the VPS to
`bhnm-b.tstolt.com` also returns 403 from BHNM itself. The remaining route is a human clicking
ACK in the BHNM UI — the native `prompt()` there freezes the Chrome extension, which is why that
click has always belonged to a person.

Inference, offered as inference: devices registered with the secret the admin portal stamps into
QRs, that value is what was seeded, and real BHNM webhooks demonstrably reach those devices
today — so BHNM's URL must already carry it. That is an argument, not a measurement, and this
section stays open until a BHNM-originated webhook logs `server=` with no FALLBACK.

### Attempt 1 — the UI acknowledgement of 29546 produced NO webhook. §8.5 STAYS OPEN.

Thomas acknowledged incident 29546 in the BHNM UI, which is the one route that fires the Action
without pulling a host. **No webhook arrived.** Checked at 21:08:40Z and again at 21:09:24Z,
against both `docker logs` and the persistent host mirror `logs/middleware.log`, which survives
container recreation:

| check | result |
|---|---|
| `[Webhook]` lines after 21:03:30Z | **none.** The last webhook of any kind is the 21:03:26 probe |
| `FALLBACK` count since the seed | **0** — but see the caveat below, this window is not what it looks like |
| incident 29546 in the cached list | `"incident_state": "OPEN"`, still in `active_incidents`, cache age 62 s, polled 21:08:22Z — **BHNM does not show it acknowledged** |

**Both of the free confirmations are negative, and neither should be read around:**

- **The 2.13.0 cache patch did not fire.** It cannot: the patch is driven by the webhook, and
  there was no webhook. 29546 still reads `OPEN` after a poll that ran *after* the
  acknowledgement.
- **No "Acknowledged: …" push was delivered.** No `[Webhook]`, no `[APNs]`, no `[WebPush]` lines
  at all in that window.

**What this does and does not establish.** It does not establish that ACK never fires a webhook —
because BHNM itself still reports the incident as `OPEN`, so the more likely reading is that the
acknowledgement did not register at all, and a notification for an event BHNM does not believe
happened is not expected. Distinguishing the two needs the thing this project already has a rule
for: **search for the object, do not trust the surrounding state.** Confirm in the BHNM UI
whether 29546 shows as acknowledged, by whom and at what time. If it does, then an ACK that
registers but fires no Action is a separate and significant defect. If it does not, the click
did not take and the test simply has to be repeated.

**Caveat on the FALLBACK count, which would otherwise be misread.** `docker logs` for
`benem-middleware` begins at the container recreate of 21:03:14Z, so "zero FALLBACK since the
seed mark" is measured over a log that *starts after the failure it is meant to cover*. The
21:02:09Z FALLBACK is in the previous container's stream and in the host mirror. Use
`logs/middleware.log` for any window spanning a recreate; the container's own log cannot answer
it. Counting from `docker logs` alone is exactly the mistake the Actions counter taught.

## 8.6 Two defects in 1a's own logging, found while reading these logs

**1. The fingerprint was redacted out of the only log that survives a restart.** The mirrored
host log shows `secret=<redacted>`, not the fingerprint. The 2.13.2 redaction filter rewrites
anything matching `(secret|token|password|key|pwd)=…`, and `secret=<fp>` matches. So the field
built to answer *"is anybody still on the old secret?"* was blanked in `logs/middleware.log` —
the persistent one, the only one that can answer that question across a week or a container
recreate. It survived in `docker logs` only, which is the ephemeral stream.

A filter doing its job on a field that did not need protecting, silently removing the signal 1b
depends on. Fixed by renaming the field to **`secret_fp=`**, which the filter does not match.
The same rename also stops the repo's credential scanner flagging the evidence file, and for the
same underlying reason: `secret=<8 hex>` is indistinguishable from a leaked fragment, so nothing
that is *not* a secret should be published under that name.

**2. The resolved server name is arbitrary while the secret is shared.** Resolution returned the
first match, so a lab-targeted webhook logged `server=SaaS Demo Server`. Not a cosmetic problem:
a log line is read as fact by whoever did not run the deploy, and per-server behaviour gets built
on it.

**Guarded rather than noted.** `_server_for_webhook_secret` (returning one server) is replaced by
`_servers_for_webhook_secret` (returning the **list** of every server that accepts the secret),
so no caller can be handed an arbitrary winner in the first place. The log label names a server
**only when exactly one matches**; otherwise it reads
`server=<ambiguous: N servers share this secret>` and names nobody. Registration binding follows
the same rule: `server_id` is stored only when unambiguous, because an arbitrary `server_id` on a
device row is worse than an empty one — it would survive into 1b as data nobody knows is fiction.

Both options offered in review were considered; this is the stronger of the two. Refusing to
resolve at all on ambiguity was rejected: during 1a *every* server shares the seeded secret, so
that would send every webhook down the FALLBACK path and destroy the 1b signal, which depends on
FALLBACK meaning "somebody is on an unlisted secret". After 1b, secrets are unique, exactly one
server matches, and the label always names it.

## 8.7 §8.5 CLOSED — a BHNM-originated webhook, 2026-09-15 22:05:23Z

Thomas unplugged raspi-050 at ~21:35Z. BHNM raised incident **29586** and fired the Action.
Read from `logs/middleware.log`, the persisted log, not from `docker logs`:

```
2026-09-15 22:05:23,831Z [Webhook] PROBLEM — raspi-050 — Incident 29586
2026-09-15 22:05:23,832Z [Webhook] server=<ambiguous: 4 servers share this secret> secret_fp=95e54469
2026-09-15 22:05:23,832Z [Webhook] Queued delivery to 4 target(s) for incident 29586
2026-09-15 22:05:24,297Z [APNs] Sent to ...0c56a19b
2026-09-15 22:05:24,437Z [APNs] Sent to ...86587674
2026-09-15 22:05:24,577Z [APNs] Sent to ...018ab51d
2026-09-15 22:05:24,671Z [WebPush] Sent to https://fcm.googleapis.com/fcm/send/faLoG1PCQS0:AP...
```

| acceptance criterion | result |
|---|---|
| a **BHNM-originated** webhook, not a probe | **PASS** — BHNM raised 29586 itself from a real outage |
| `server=` present | **PASS** — and correctly as the *ambiguous* label, which is the right answer while four servers share one secret. The guard shipped hours earlier is doing exactly its job on its first real webhook |
| **zero** FALLBACK after the seed | **PASS, with one exception already on the record.** The persisted log holds exactly one FALLBACK ever — 21:02:09Z, the stale-inode failure of 8.3. Zero since the mount was fixed at 21:03:14Z |
| `secret_fp=` surviving the redaction filter | **PASS**, and the same file proves the defect and the fix side by side: `21:02:09 … secret=<redacted>` against `22:05:23 … secret_fp=95e54469` |
| `notification_type` matches the event | **PASS** — `PROBLEM`, an unplugged host |

**The inference in 8.5 is retired.** BHNM's Action URL does carry the seeded secret; it is measured
now, not argued.

### Correction: the Service Engine reading was wrong

While waiting, `BHNM-B-SE01` was declared down (incident 29585, 21:51:23) and raspi-050 had no
incident, from which this file inferred that raspi-050 *is* the remote Service Engine and
therefore could not be detected by itself. **That inference was wrong.** raspi-050 got its own
host incident, 29586, at 22:05 — it was simply slow. The SE going down first is real and
unexplained; the conclusion drawn from it was not.

### Two lab facts worth keeping

1. **Host-down detection took about 30 minutes** (~21:35 pull → 22:05:23 webhook), with the SE
   noticed at 21:51. Any future test that pulls a host should budget that, and should not read
   a quiet ten minutes as a failure — this session nearly did.
2. **`BHNM-B-SE01` going down produced NO webhook, while raspi-050 going down produced one.**
   Both are `host` incidents on the same BHNM. See the finding below.

## 8.8 FINDING — coverage is scoped in BHNM and invisible from inside BeNeM

Measured, in one window, on the same server:

| incident | device | type | opened | webhook |
|---|---|---|---|---|
| 29585 | `BHNM-B-SE01` | `host` | 21:51:23Z | **none** — searched the whole persisted log by incident id |
| 29586 | `raspi-050` | `host` | ~22:05Z | fired, 4 targets paged |
| 29546 | `Synology920` | `service` | 15:48Z | none (acknowledged in the UI, also no webhook) |

Two host-down incidents, minutes apart, on one server: **one paged, one did not.** Whatever the
mechanism — the action group attached per device or per group, or notification criteria that
exclude some objects — **coverage is configured per-object inside BHNM, and nothing in the BeNeM
app or the admin portal tells a user which of their devices are covered.**

This is the doctrine's failure in its most expensive form yet. The earlier instances rendered
unverified state as healthy in a UI; this one renders *absence of a page* as identical to *no
incident*. An engineer watching a silent phone cannot distinguish "nothing is wrong" from "this
device was never wired to page me", and a paging product's entire value is that distinction.
Worse than the green badge, because there is no affordance to be suspicious of.

**Not diagnosed further, deliberately** — which mechanism it is needs the BHNM Action
configuration read, and the extension cannot open that menu (four attempts, §8.9). The finding
does not depend on which mechanism it turns out to be.

**`INSTALL.md` §7 does not tell an administrator to attach the action group to everything they
expect to be paged about.** That is the minimum fix and it is documentation. The product fix is
larger: BeNeM cannot currently answer "which of my devices will page me?", and until it can, the
answer a user assumes is "all of them".

## 8.9 The acknowledgement: one confirmation passes, one fails

Thomas acknowledged 29586 in the BHNM UI at ~22:06:5xZ. This is the first real-world ACK outside
the measurement rig.

```
2026-09-15 22:06:56,856Z [Webhook] ACKNOWLEDGEMENT — raspi-050 — Incident 29586
2026-09-15 22:06:56,858Z [Webhook] server=<ambiguous: 4 servers share this secret> secret_fp=95e54469
2026-09-15 22:06:56,858Z [Webhook] Queued delivery to 4 target(s) for incident 29586
2026-09-15 22:06:57,193Z [APNs] Sent to ...0c56a19b
2026-09-15 22:06:57,309Z [APNs] Sent to ...86587674
2026-09-15 22:06:57,427Z [APNs] Sent to ...018ab51d
2026-09-15 22:06:57,486Z [WebPush] Sent to https://fcm.googleapis.com/fcm/send/faLoG1PCQS0:AP...
```

**Confirmation 1 — the "Acknowledged: …" push: PASS.** `notification_type` is `ACKNOWLEDGEMENT`,
which also exercises the 2.13.0 wire-literal handling, and all four targets were delivered to.
Also worth noting for its own sake: the *same device* produced PROBLEM at 22:05:23 and
ACKNOWLEDGEMENT at 22:06:56, so a plain WebHook method does deliver both — the 09-14 finding
about Active Response Webhook being PROBLEM-only is confirmed again from the other direction.

**Confirmation 2 — the 2.13.0 cache patch marking it ACKNOWLEDGED immediately: FAIL.** No
`[Webhook] Cache patched:` line was emitted. Not a logging gap — the patch genuinely did nothing.

### Why, and it is worse than this one incident

`incident_cache.note_state_override_any_server()` walks the cached buckets and patches only the
servers whose cache **already contains** the incident, returning the count. `main.py` then logs
only `if n:`. So when the incident is not cached, the call is a **silent no-op** — no patch, no
log, no error, and a return value nobody checks against zero.

29586 was raised at 22:05:23 and acknowledged 93 seconds later. Measured at 22:07: **29586 is not
in the cache at all**, neither `active_incidents` nor `closed_incidents`, with the cache 50
seconds old. The refresh cycle is 120 s, so the acknowledgement arrived inside the window before
the incident had ever been cached. There was nothing to patch, and nothing said so.

**The strong version of this finding:** in the entire persisted log, `Cache patched` appears
**three times, and every one is `-> CLOSED`**. Not once `-> ACKNOWLEDGED`. The log covers
2026-09-14 onward, so this is not proof the ACK path has never worked — but it is zero
observations of it working, against three of the RECOVERY path working.

The design comment at `incident_cache.py:139` says the override exists to survive "an in-flight
cycle whose getincidents snapshot predates the ack". The case it does not survive is the one
that just happened: an incident acknowledged *before its first cache cycle*, which is precisely
the fast-acknowledgement case a paging product should expect — somebody is woken, looks, and acks
within two minutes.

**Fix shape, not built:** record the override keyed by incident id regardless of whether the
incident is currently cached, and apply it when the incident first appears — the override already
has a 5-minute TTL, which covers two cycles. And make the zero-patch case **loud**, because a
silent no-op with an unchecked return value is how this stayed invisible.

## 8.10 What could not be checked, and by whom

The BHNM Action configuration — which devices or groups the `BeNeM` action group is attached to,
and its notification criteria — was **not** read. Four attempts through the browser extension
(direct link click, menu click, coordinate click, hover) failed to open Administration → Actions;
the menu does not respond to synthetic events, and no URL for that page is recorded anywhere in
this repository. It needs a human with the UI open, and §8.8's finding does not depend on it.
