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
