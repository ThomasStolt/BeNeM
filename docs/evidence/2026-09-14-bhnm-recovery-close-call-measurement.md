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
