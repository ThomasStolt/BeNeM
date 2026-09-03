# Evidence: first `status: "DOWN"` host row captured on the wire (BHNM 26.3.01)

**Captured:** 2026-09-03T07:37:07.637704+00:00 (UTC) · lab `192.168.2.211` · BMC Helix Network Management 26.3 (Core 26.3-00.41 / SE 26.3-01.18)
**Context:** Thomas powered raspi-050 off deliberately so a real DOWN row could be observed. Until this capture every
host row ever seen on this server was `UP`; `DOWN` was documented only (`shared/BHNM_API_REFERENCE.md`, Multi-Device-Status API v1.0.9).
Wave B (host_status overlay) is written against THIS row, not the docs.

## Request

```
POST /fw/index.php?r=restful/devices/get-host-and-service-status
Content-Type: application/x-www-form-urlencoded
password=<key>&groupFilterBy=device&groupFilterValue=raspi-050&serviceFilter=host_only&recordCount=100
```

## Response — verbatim

```json
{
 "totalRecords": 1,
 "displayRecords": 1,
 "statuses": [
  {
   "deviceIndex": 5183,
   "deviceName": "raspi-050",
   "incidentID": "27728",
   "lastUpdateTime": "2026-09-03 09:35:08",
   "message": "<br />Ping CRITICAL: Packet Loss 100%",
   "status": "DOWN",
   "currentStateDuration": "21m 57s",
   "state_type": null,
   "inMaintenance": false
  }
 ]
}
```

Observations that Wave B must honour:

- `status` is the literal `"DOWN"` (upper case), the same field that carries `"UP"` on healthy rows.
- `state_type` is **`null`** on this DOWN row, exactly as on every UP row on 26.3.01. The documented `stateType`
  (SOFT/HARD) does not exist on host rows; a SOFT-vs-HARD policy therefore cannot key on it.
- `incidentID` is populated (`"27728"`) on the DOWN row and empty (`""`) on UP rows.
- `inMaintenance` is present and `false`.
- `message` carries the ping summary with HTML (`<br />Ping CRITICAL: Packet Loss 100%`).

## Same call, `groupFilterBy=category&groupFilterValue=Raspberry Pi` (the crawl the middleware runs)

```json
{
 "totalRecords": 5,
 "displayRecords": 5,
 "statuses": [
  {
   "deviceIndex": 108,
   "deviceName": "raspi-053",
   "incidentID": "",
   "lastUpdateTime": "2026-09-03 09:35:07",
   "message": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%<BR> RTA = 0.256 ms",
   "status": "UP",
   "currentStateDuration": "15d 10h 36m 56s",
   "state_type": null,
   "inMaintenance": false
  },
  {
   "deviceIndex": 124,
   "deviceName": "raspi-051",
   "incidentID": "",
   "lastUpdateTime": "2026-09-03 09:35:08",
   "message": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%<BR> RTA = 0.490 ms",
   "status": "UP",
   "currentStateDuration": "1d 23h 18m 1s",
   "state_type": null,
   "inMaintenance": false
  },
  {
   "deviceIndex": 3,
   "deviceName": "raspi-054",
   "incidentID": "27729",
   "lastUpdateTime": "2026-09-03 09:35:08",
   "message": "<br />Ping CRITICAL: Packet Loss 100%",
   "status": "DOWN",
   "currentStateDuration": "21m 58s",
   "state_type": null,
   "inMaintenance": false
  },
  {
   "deviceIndex": 5183,
   "deviceName": "raspi-050",
   "incidentID": "27728",
   "lastUpdateTime": "2026-09-03 09:35:08",
   "message": "<br />Ping CRITICAL: Packet Loss 100%",
   "status": "DOWN",
   "currentStateDuration": "21m 57s",
   "state_type": null,
   "inMaintenance": false
  },
  {
   "deviceIndex": 81,
   "deviceName": "raspi-059",
   "incidentID": "",
   "lastUpdateTime": "2026-09-03 09:35:08",
   "message": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 16%<BR> RTA = 50.526 ms",
   "status": "UP",
   "currentStateDuration": "14d 8h 14m 55s",
   "state_type": null,
   "inMaintenance": false
  }
 ]
}
```

raspi-054 read `DOWN` in the same sweep (incident 27729, opened the same second as 27728). Thomas only announced
raspi-050; raspi-054's state is reported here as observed, not explained.

## Matching incidents — `restful/incident/list` with `state=open&recordCount=500`

(`status=` is NOT the filter parameter on this server: every `status=` variant returns the string `"No Incidents found."`.
`state=open` returns the list. The middleware itself uses the legacy `/api/incident_api.php method=getincidents`.)

```json
[
 {
  "guid_incident_id": "27728",
  "incident_id": 27728,
  "device_id": 5183,
  "primary_alarm_id": 28362,
  "title": "Host raspi-050",
  "current_state": "OPEN",
  "open_timestamp": 1788419713,
  "ack_timestamp": null,
  "closed_timestamp": null
 },
 {
  "guid_incident_id": "27729",
  "incident_id": 27729,
  "device_id": 3,
  "primary_alarm_id": 28363,
  "title": "Host raspi-054",
  "current_state": "OPEN",
  "open_timestamp": 1788419713,
  "ack_timestamp": null,
  "closed_timestamp": null
 }
]
```

## Deployed middleware feed (`https://bhnm-apns.hurrikap.org/api/v1/incidents`, cache age 119 s at capture)

Active incidents contain both host incidents as `alert_type: "host"`:

```json
[
 {
  "title": "Host raspi-050",
  "incident_state": "OPEN",
  "incident_id": "27728",
  "open_time": "2026-09-03T09:15:13",
  "name": "raspi-050",
  "device_category": "23",
  "device_site": "19",
  "device_note": "",
  "alarm_counts": {
   "red": 1,
   "orange": 0,
   "yellow": 0,
   "green": 0,
   "blue": 0
  },
  "alert_type": "host"
 },
 {
  "title": "Host raspi-054",
  "incident_state": "OPEN",
  "incident_id": "27729",
  "open_time": "2026-09-03T09:15:13",
  "name": "raspi-054",
  "device_category": "23",
  "device_site": "19",
  "device_note": "",
  "alarm_counts": {
   "red": 1,
   "orange": 0,
   "yellow": 0,
   "green": 0,
   "blue": 0
  },
  "alert_type": "host"
 }
]
```

`devices/list` for raspi-050 at the same time: `poll: 1, monitor: 1` — no state field changed (there is none).


## Addendum 2026-09-03T08:06:55Z — what BHNM says about raspi-054 (incident 27729)

`/api/incident_api.php method=getincidentdetail incident_id=27729`, verbatim `detail` block:

```json
{
 "primary_alarm_log": [
  {
   "state": "DOWN",
   "type": "Host",
   "name": "raspi-054",
   "output": "<br />Ping CRITICAL: Packet Loss 100%",
   "time": "2026-09-03T09:15:09"
  }
 ],
 "relatedalarms": null,
 "incident_log": [
  {
   "state": "OPEN",
   "time": "2026-09-03T09:15:13",
   "username": "system",
   "comment": "Initialized state to OPEN"
  }
 ]
}
```

`alert_type: "Host"`, `primary_alarm_state: "OPEN"`, opened `2026-09-03T09:15:13`, `relatedalarms: null`.
BHNM's stated cause is the host check itself — 100 % packet loss on ping from the appliance at 09:15:09 local, four
seconds before raspi-050's identical alarm. There is no parent/dependency record in the incident detail and no
related alarm; BHNM does not claim a dependency, it claims unreachability. Both host rows still read `DOWN`
(`currentStateDuration` 51m at this capture). No maintenance window is active on either device
(`maint_window_api.php action=list` → `windows: []`), so the "in maintenance AND DOWN" capture is still pending.
Whether the box is physically off is Thomas's call; a ping from the engineer's Mac at capture time is recorded in the
session report, not here, because it is not a BHNM observation.


## Addendum — "in maintenance AND DOWN", captured live on raspi-054 (window created by Thomas from the PWA, start 10:25 local)

raspi-054 was DOWN by accident (Thomas: raspi-050 off is deliberate, raspi-054 off is not) when the window went active, so
this is the exact combination §5.3 of the Wave B spec had marked *unverified*. Polled every 30 s; `inMaintenance` flipped
at the first sample after the snapped start (no observable lag this time).

| sample (UTC) | host `status` | `inMaintenance` | active windows | incident 27729 state / primary alarm | in `state=open` list |
|---|---|---|---|---|---|
| 2026-09-03T08:20:48+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:21:19+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:21:50+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:22:21+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:22:51+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:23:22+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:23:53+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:24:24+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:24:55+00:00 | DOWN | False | 0 | OPEN / OPEN | yes |
| 2026-09-03T08:25:25+00:00 | DOWN | True | 1 | OPEN / OPEN | yes |
| 2026-09-03T08:25:56+00:00 | DOWN | True | 1 | OPEN / OPEN | yes |
| 2026-09-03T08:26:27+00:00 | DOWN | True | 1 | OPEN / OPEN | yes |

### Host row at the first active sample — verbatim

```json
{
 "deviceIndex": 3,
 "deviceName": "raspi-054",
 "incidentID": "27729",
 "lastUpdateTime": "2026-09-03 10:25:10",
 "message": "<br />Ping CRITICAL: Packet Loss 100%",
 "status": "DOWN",
 "currentStateDuration": "1h 10m 17s",
 "state_type": null,
 "inMaintenance": true
}
```

**BHNM keeps `status: "DOWN"` while the device is in maintenance.** The literal is unchanged; only `inMaintenance` flips.
So under Wave B the row renders **red icon + wrench** (no drop-the-row case is triggered), and the coexist doctrine holds.

### Active window — `maint_window_api.php action=list name=raspi-054`

```json
{
 "result": "completed",
 "windows": [
  {
   "start_time": 1788423900,
   "end_time": 1788427500,
   "comment": "Created by Thomas Android PWA on 2026-09-03 10:19:"
  }
 ]
}
```

### What incident 27729 does during the window

`incident_state` stays `OPEN`, `primary_alarm_state` stays `OPEN`, `acknowledged` = 0, and the
incident remains in the `state=open` list. Incident log during the window (verbatim):

```json
[
 {
  "state": "OPEN",
  "time": "2026-09-03T09:15:13",
  "username": "system",
  "comment": "Initialized state to OPEN"
 }
]
```

Conclusion for the list row: the **red incident chip and the wrench coexist** on raspi-054 — BHNM suppresses notifications
for a device in maintenance, it does not close or alter the incident. Last sample of the run: `2026-09-03T08:26:27+00:00`, unchanged.

## Addendum — Wave A verified on the PWA 0.13.1 production bundle (replacement push gate, reviewer ruling 3)

Built locally (`npm run build && npm run preview -- --host`, bundle 0.13.1 at commit b2a7815 + 6be46bd), served by
`vite preview` with `/bhnm/*` proxied to the production middleware `https://bhnm-apns.hurrikap.org` (2.10.1 — the
deployed one; middleware 2.11.0 is not needed for Wave A), lab key supplied through the gitignored `pwa/.env.local`
(`VITE_BHNM_API_KEY`), never typed into the app. Checked in Chrome at 10:30–10:33 local while raspi-050 (deliberate)
and raspi-054 (accidental, in its maintenance window) were both off the LAN.

Programmatic count over the rendered rows (`DeviceTypeIcon` background colour per `a[href^="/devices/"]`):

| result | value |
|---|---|
| rows rendered | 41 (one page — pager now reads "Page 1 of 1", the 6be46bd fix) |
| icon `up` (`rgb(2, 132, 199)`) | **38** — every `monitor = 1` device, poll 1/2/5 alike |
| icon `unknown` (`rgb(55, 65, 81)`) | **3** — BHNM-A-SE01, BHNM-A-SE02, bhnm-apns.hurrikap.org (`monitor = 0`) |
| icon `down` | 0 (Wave A cannot paint it; Wave B will) |
| Ping-Only devices Miele-T1, Shelly_MieleW1 | `up` (were grey before the fix) |
| raspi-050 | `up` icon + red chip **1** + ticker "Host raspi-050" — the documented interim state |
| raspi-054 | `up` icon + **wrench** + red chip **2** + ticker "… · Host raspi-054" — chip and wrench coexist |

Screenshots (same folder):

- `2026-09-03-pwa-0.13.1-local-devices-top.jpg` — raspi-054 (wrench + red 2), Synology920, US_24_G1_Keller, UAP-AC-LR,
  VU-Solo4k all blue; "In maintenance (1)" chip.
- `2026-09-03-pwa-0.13.1-local-devices-unmonitored-grey.jpg` — BHNM-A-SE01 / BHNM-A-SE02 grey among blue rows.
- `2026-09-03-pwa-0.13.1-local-devices-raspi-050-red-chip.jpg` — raspi-050 blue + red chip, bhnm-apns grey, "Page 1 of 1".
- `2026-09-03-pwa-0.13.0-prod-raspi-050-red-chip.jpg` — the deployed 0.13.0 at 09:44 local for comparison
  (raspi-050 already showed the red chip beside its blue icon under the old rule, because its `poll` happens to be 1).

Not covered here: iOS 2.12.1 on a device against the lab — Thomas's gate, still open.

## Addendum — RECOVERY webhook proof for middleware 2.11.1: **NOT achieved** (2026-09-03)

Sequence as executed. All times UTC (lab local = UTC+2).

| time | event | source |
|---|---|---|
| 10:24:59 | middleware 2.11.1 container started (`/webhook` 422 hygiene); only bhnm-apns rebuilt | upgrade log, `/health` |
| 10:45:22 | Thomas reports raspi-054 powered on; it answers ping from the engineer's Mac (3/3) | this session |
| 10:45:08 | BHNM's last host check still `DOWN` | host row `lastUpdateTime` 12:45:08 local |
| 10:46:14 | BHNM host check flips raspi-054 to **`UP`** (`currentStateDuration` 8 s at the 10:46:21 sample) | `get-host-and-service-status` poll |
| 10:46:42 | incident 27729 → `ALARMS CLEARED / ALARMS CLEARED` | `getincidentdetail` poll |
| 10:47:01 → 10:54:20 | middleware access log: **0** `POST /webhook`; **0** `[Webhook]` lines; **0** `[Webhook] Rejected` (422) lines | `docker logs benem-middleware` |
| — | Thomas's phone: no RECOVERY push reported | — |

**What this shows.** BHNM changed state exactly as expected and no HTTP request for `/webhook` reached the middleware at
any point between the 2.11.0 restart (09:37 UTC) and 10:54 UTC — the 2.11.0 container's log also had zero `[Webhook]`
lines for its 47 minutes, during which the incident cache grew from 18 to 30. The 2.11.1 route was therefore never
exercised by a real BHNM payload: nothing was accepted, nothing was rejected. The failure is upstream of the middleware —
BHNM did not deliver a webhook for this recovery (and, as far as the surviving logs show, for anything else today).

**What could not be checked from here.** Caddy has no access logging configured (`Caddyfile` has no `log` directive;
0 access-log lines in 39 h), so "0 hits at Caddy" carries no information. The 2.10.1 container's log (which would have
shown whether the 09:15 PROBLEM webhooks for raspi-050/054 arrived) was discarded when the container was recreated at
09:37. BHNM's notification / action-group / webhook-URL configuration is not readable through any API used by BeNeM.

**Not proven, by the reviewer's rule.** The 422 test coverage is the only proof 2.11.1 has: 93 tests pass, including
"form-encoded body with hostname → 200 and pushed". Whether a *real* BHNM payload passes the new hostname check is still
unverified on the wire and stays open until a webhook actually arrives.

**For Thomas, in BHNM:** confirm the action group attached to raspi-054's host check delivers to
`https://bhnm-apns.hurrikap.org/webhook?secret=<the secret the 5 registered devices share>`, that RECOVERY
notifications are enabled for it, and that BHNM's outbound HTTP can reach the host. Re-run the proof by taking raspi-054
down and up again (or the next real transition); the watcher command is in the session log.

## Addendum — 2.11.1 route proven with a real BHNM payload (manual webhook, 2026-09-03 11:03 UTC)

Correction to the previous addendum: Thomas *did* receive push notifications for the 09:15 UTC host-down events on his
iPhone, so BHNM's webhook delivery works. Those two PROBLEM webhooks went to the 2.10.1 container, whose log was
discarded when it was recreated at 09:37 — which is why no trace survived. What BHNM did **not** send is a RECOVERY for
raspi-054's 10:46:14 UTC return; that remains a BHNM-side configuration question (notify-on-recovery for the action
group attached to the host check), not a middleware one.

To exercise the 2.11.1 route with a real BHNM-formatted body, Thomas re-fired the notification for open incident 27728
(raspi-050, still powered off) from BHNM.

| time (UTC) | event | source |
|---|---|---|
| 11:02:47 | log watcher armed | this session |
| 11:03:30.733 | `[Webhook] PROBLEM — raspi-050 — Incident 27728` — body decoded, `hostname` present, accepted, pushed | `docker logs -t benem-middleware` |
| 11:03:48 | Thomas reports the push received on his iPhone | this session |
| — | `[Webhook] Rejected` lines since the 2.11.1 deploy: **0** | `docker logs benem-middleware` |

Notification title as built by the route for this payload: `🔴 raspi-050 — DOWN` (PROBLEM with `host_state` DOWN);
**confirmed by Thomas as the title displayed on the iPhone.**

**Result.** A real BHNM webhook body passes the 2.11.1 hostname check and is pushed end-to-end through the post-fix
route: 200, one push, zero rejections. The "form-encoded fallback" and "garbage → 422" behaviours are covered by the
suite (93 passed); the wire has now confirmed the accept path.

Observation, not a finding: the uvicorn access log carries no `POST /webhook` entry for this request although it logs
every other request; the `[Webhook]` application line is the authoritative trace. Worth a look when the S1
(secret-in-query-string) item is worked, since an access-log line would have printed the secret.

### RECOVERY timing, per Thomas, and what the log shows afterwards

BHNM holds a recovered incident in **ALARMS CLEARED for 5 minutes by default** and fires the recovery webhook only
after that window closes. BHNM's own incident log for 27729 confirms the window exactly: `OPEN` 09:15:13 →
`ALARMS CLEARED` 12:46:41 → `CLOSED` 12:51:43 (local, UTC+2). My watchers ended at 10:54 UTC, two minutes after the
window closed. Re-checked at 14:52 UTC: the 2.11.1 container still holds exactly one `[Webhook]` line (the 11:03:30
manual PROBLEM) — **no RECOVERY for raspi-054 arrived at any point after the window closed either**. So the delay
explains why nothing was seen *during* the watch, but not the absence *after* it; the notify-on-recovery setting of the
action group attached to raspi-054's host check remains the thing to check in BHNM. Rejections since deploy: 0.

## Addendum — Wave B: middleware 2.12.0 deployed, PWA 0.14.0 verified on the production bundle (2026-09-03, 15:37–15:48 UTC)

### Middleware 2.12.0 deploy (same discipline as 2.11.0/2.11.1)

Images tagged `:7381499`, `./upgrade.sh` 20 s, only `bhnm-apns` rebuilt and recreated (admin, PWA, Caddy untouched),
health gate passed at +0 s on 2.12.0, no rollback, no cache reload (the recreate restarted all four loops).

| | before 15:37:29 UTC (2.11.1) | after 15:42:23 UTC (2.12.0) |
|---|---|---|
| `/api/v1/maintenance-map` | `{"cache_age_seconds": 27, "in_maintenance": [], "scheduled": []}` | `{"cache_age_seconds": 57, "in_maintenance": [], "scheduled": [], "host_down": ["raspi-050"]}` |
| shipped-client view (PWA 0.13.1 `Array.isArray`, iOS 2.12.1 `as? [String]`) | `in_maintenance` [] / `scheduled` [] | identical — the extra key is invisible to both |
| diagnostics feeds | 4 feeds cached, 0 failures | at 15:42:23 tactical / thresholds / maintenance_map cached, incidents still on its first cycle (0 failures); at 15:42:33 **all four cached, 0 failures** (incidents 526, age 0) |
| container cycle line | `Cache updated: 0 in maintenance` | `Cache updated: 0 in maintenance, 38 host rows, 1 down` every ~63 s; ignored-literal lines 0; fetch-failed 0 |

Note on the incidents feed: the lab's active-incident count went from 30 (morning) to 399 (15:37) to **526** (15:45) —
raspi-054's return apparently re-opened a large number of service/threshold incidents. The incident crawl paces one
detail call per incident over its 120 s interval, so its first cycle after the 2.12.0 restart was still at 520/526 at
capture. Not a 2.12.0 effect; noted for Thomas.

### PWA 0.14.0 on the production bundle against the live 2.12.0 middleware

`npm run build && npm run preview` (key via the gitignored `.env.local`, removed afterwards), Chrome at 15:40 UTC,
icon colours counted programmatically over the 41 rendered rows:

| check | observed |
|---|---|
| `down` (`rgb(220, 38, 38)`) | **1 — raspi-050**, red icon + red chip 1 + "Host raspi-050" ticker |
| `up` (`rgb(2, 132, 199)`) | **37**, including raspi-054 (back UP, window over) and the Ping-Only pair Miele-T1 / Shelly_MieleW1 |
| `unknown` (`rgb(55, 65, 81)`) | **3** — BHNM-A-SE01, BHNM-A-SE02, bhnm-apns.hurrikap.org (`monitor = 0`) |
| Diagnostics screen, Feeds section | **four rows**: Tactical, Incidents (LIVE — cold at that moment, see above), Thresholds, Maintenance Map; middleware version 2.12.0 |

Screenshots: `2026-09-03-pwa-0.14.0-local-devices-top.jpg`, `2026-09-03-pwa-0.14.0-local-raspi-050-red-icon.jpg`,
`2026-09-03-pwa-0.14.0-local-diagnostics-four-feeds.jpg`.

Not covered: iOS 2.13.0 — next, verified on Thomas's phone with raspi-050 off (red icon) before its commit pushes.
