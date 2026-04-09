# BHNM (Netreo) API Reference for Device Dashboards

This document describes how to interact with the BHNM/Netreo API to fetch device
metrics and time series data. It is the result of hands-on discovery against a live
instance and should be treated as ground truth — do not guess endpoint names or
parameter values, use what is documented here.

---

## Two Separate API Surfaces

BHNM exposes two distinct APIs. They have different base paths, different auth
parameter names, and different request encoding. Do not mix them.

|                  | Legacy API                                                   | Open 3.0 API                        |
|------------------|--------------------------------------------------------------|-------------------------------------|
| Base path        | `/fw/index.php?r=restful/`                                   | `/api/{resource}_api.php`           |
| Auth param       | `password=`                                                  | `pwd=`                              |
| Encoding         | `application/x-www-form-urlencoded` or `multipart/form-data` | `application/x-www-form-urlencoded` |
| Routing          | Via `?r=restful/{resource}/{action}`                         | Via `method=` form field            |
| Response wrapper | Array `[{...}]`                                              | Varies                              |

The high-performance time series endpoint (`timeseries-metrics`) lives on the **Legacy API**
and offers significantly better performance than older alternatives. Always use it.

---

## Authentication

### Legacy API
```
password=YOUR_API_PASSWORD
```
Sent as a form field. No username, no Bearer token.

### Open 3.0 API
```
pwd=YOUR_API_PASSWORD
```
Note the different parameter name (`pwd`, not `password`).

### Example — Open 3.0 get all incidents:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/api/incident_api.php' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'pwd=YOUR_PASSWORD&method=getincidents'
```

---

## Device Identification

Devices have multiple identifiers — do not confuse them:

| Field | Example | Used in |
|---|---|---|
| `UID` | `11` | Returned in timeseries response, GUID component |
| `deviceIndex` | `3` | Internal legacy index |
| `GUID` | `netreo-1599587812-11` | Global unique string ID |

**For time series calls, always identify devices by name** using `groupFilterBy=device`
and `groupFilterValue=DEVICE_NAME`. Do not rely on numeric IDs.

### Critical: numeric IDs are not interchangeable

Different endpoints use different numeric ID fields. Confirmed for raspi-054:

| Endpoint | ID parameter | Correct value for raspi-054 |
|---|---|---|
| `devices/find` response | `id` field | `5` |
| `performance-instance-per-category` | `device_id` parameter | `3` (deviceIndex, not find id) |
| `timeseries-metrics` response | `deviceIndex` field | `3` |
| `timeseries-metrics` response | `UID` field | `11` |

`performance-instance-per-category` uses `deviceIndex` (3), NOT the `id` returned
by `devices/find` (5). When in doubt, identify devices by name rather than any numeric ID.

### Look up device by name (Legacy API):
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/find' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&name=raspi-054'
```

### List all devices (Legacy API):
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/list' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&recordStart=0&recordCount=50'
```

---

## Metric Discovery Workflow

When working with a new device, run this two-step discovery process to find valid
metric parameter values. Do not hardcode or guess — the values are device-specific.

### Step 1 — Get performance categories
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/performance-category' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&device_id=NUMERIC_DEVICE_ID'
```

Example response:
```json
[
  { "id": 1,       "category": "CPU" },
  { "id": 9,       "category": "Disk" },
  { "id": 2,       "category": "Memory" },
  { "id": 5,       "category": "Latency" },
  { "id": 20004,   "category": "Logged Messages" },
  { "id": 46000,   "category": "Poll Time" },
  { "id": "interfaces", "cat": "Network" }
]
```

### Step 2 — Get metric instances per category
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/performance-instance-per-category' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&device_id=NUMERIC_DEVICE_ID&id=CATEGORY_ID'
```

Each item in the response contains `title`, `unit`, `key`, `type`, and `description`.
The `unit` field is the exact value to use as `metricFilterUnits` in a time series call.

**Note:** This endpoint may return metrics for multiple devices (not just the one
specified). The response can be large due to per-process metrics (Utilization by
Process repeats once per running process).

---

## Time Series Endpoint

This is the primary endpoint for dashboard data. It is **not in the official OpenAPI
spec** but is the recommended approach for performance.

```
POST /fw/index.php?r=restful/devices/timeseries-metrics
Content-Type: multipart/form-data
```

### Required parameters:

| Parameter | Description | Example |
|---|---|---|
| `password` | API password | `ThisIsAPassword` |
| `metricFilterStatGroup` | Metric category | `CPU` |
| `metricFilterUnits` | Unit of measurement | `%` |
| `groupFilterBy` | Filter type | `device` |
| `groupFilterValue` | Device name | `raspi-054` |
| `timeFrameFilterBy` | Time range type | `time_offset` |
| `timeFrameFilterValue` | Time range value | `Last Hour` |
| `returnFormatFilterBy` | Aggregation method | `average` |

### Working example:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/timeseries-metrics' \
  --header 'Content-Type: multipart/form-data' \
  --form password=YOUR_PASSWORD \
  --form metricFilterStatGroup=CPU \
  --form metricFilterUnits=% \
  --form groupFilterBy=device \
  --form groupFilterValue=raspi-054 \
  --form timeFrameFilterBy=time_offset \
  --form 'timeFrameFilterValue=Last Hour' \
  --form returnFormatFilterBy=average \
  --compressed
```

### Valid `timeFrameFilterValue` options (known):
- `Last Hour`
- `Last 24 Hours` (assumed — verify if needed)

### Valid `returnFormatFilterBy` options (known):
- `average`

---

## Metric Vocabulary — raspi-054

The following table documents the exact parameter values for every metric available
on device raspi-054. Discovered via `performance-category` + `performance-instance-per-category`.

**Critical:** `metricFilterStatGroup` is not always identical to the category name
returned by `performance-category`. Known divergence: category `Disk` → statGroup `Disks`.
Always verify against working examples below.

### CPU (category id: 1)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| CPU Utilization | `CPU` | `%` |
| CPU Cores | `CPU` | `%` |
| Utilization by Process | `CPU` | `%` |
| CPU Voltage | `CPU` | `Volt` |
| Running Processes | `CPU` | `Processes` |
| System Load | `CPU` | `System Load` |

**Important:** When a metric has no real unit (empty string in discovery response),
`metricFilterUnits` takes the metric title as its value instead. This is confirmed
working for System Load (`metricFilterUnits=System Load`). Apply the same pattern
for Running Processes and any other empty-unit metrics.

### Disk (category id: 9)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| Hard Drive Usage | `Disks` | `B` |
| Disk Utilization | `Disks` | `%` |

**Note:** statGroup is `Disks` (plural), not `Disk`.

### Memory (category id: 2)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| Memory Usage | `Memory` | `B` |
| Memory Utilization | `Memory` | `%` |
| Swap Utilization | `Memory` | `%` |
| Utilization by Process | `Memory` | `B` |

### Latency (category id: 5)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| Round-trip Latency | `Latency` | `s` |

### Logged Messages (category id: 20004)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| Rule Matches | `Logged Messages` | `Matches/min` |

### Poll Time (category id: 46000)

| Metric title | `metricFilterStatGroup` | `metricFilterUnits` |
|---|---|---|
| Poll Time | `Poll Time` | `s` |

---

## Response Structure — Time Series

```json
{
  "metrics": [
    {
      "deviceIndex": "3",
      "deviceName": "raspi-054",
      "UID": "11",
      "GUID": "netreo-1599587812-11",
      "instanceDescr": "CPU Utilization for raspi-054 (CPU Utilization)",
      "metricId": "instance_772",
      "pollingInterval": "5-minute polling",
      "datapointLegend": ["All"],
      "datapointCount": 12,
      "datapoints": [
        {
          "1775209800": "2.25",
          "1775210100": "2.25"
        }
      ]
    }
  ],
  "totalMetrics": 5,
  "totalDatapoints": 60
}
```

### Parsing notes — important:

- **`datapoints` is an array containing one object**, where keys are Unix timestamps
  (as strings) and values are metric readings (also as strings, not numbers).
  Iterate with `Object.entries(datapoints[0])` in JS or `datapoints[0].items()` in Python.
- **Values are strings** — always cast before arithmetic. In Swift: `Float(value)`.
  In Python: `float(value)`. In JS: `parseFloat(value)`.
- **Timestamps are Unix epoch seconds** as string keys — convert with
  `Date(timeIntervalSince1970:)` in Swift or `datetime.fromtimestamp()` in Python.
- **One response may contain multiple metrics** matching the filter — e.g. querying
  `CPU` + `%` returns CPU Utilization AND all CPU Cores as separate items in the
  `metrics` array. Use `instanceDescr` or `metricId` to distinguish them.
- **Polling interval is 5 minutes** — "Last Hour" returns 12 datapoints.

---

## Known Working Combinations (Verified)

```bash
# CPU Utilization — verified working
metricFilterStatGroup=CPU  metricFilterUnits=%

# Disk — verified working (note: Disks plural)
metricFilterStatGroup=Disks  metricFilterUnits=%
```

---

## Re-running Discovery for Other Devices

To build the equivalent metric table for a different device:

```bash
# 1. Find numeric device ID
curl -s --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/find' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&name=DEVICE_NAME' | jq

# 2. Get categories
curl -s --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/performance-category' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&device_id=NUMERIC_ID' | jq

# 3. Get instances per category — extract unique title/unit pairs
for id in CATEGORY_IDS_FROM_STEP2; do
  echo "=== Category ID: $id ==="
  curl -s --request POST \
    --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/performance-instance-per-category' \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data "password=YOUR_PASSWORD&device_id=NUMERIC_ID&id=$id" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
seen = set()
for item in data:
    key = (item.get('title',''), item.get('unit',''))
    if key not in seen:
        seen.add(key)
        print(f\"  {item.get('title',''):<35} unit: '{item.get('unit','')}'\")
"
done
```

---

## Maintenance Window API

Creates or closes one-time maintenance windows for a device. Discovered by
inspecting the BHNM server source (`/home/httpd/html/api/maint_window_api.php`).

```
POST https://YOUR_HOST/api/maint_window_api.php
```

Auth: `password=` (same as Legacy API).

### Actions

#### Create a maintenance window (`action=new`)

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API password |
| `action` | yes | `new` |
| `name` | yes | Device name (string, not numeric ID) |
| `start_time` | yes | UTC Unix timestamp. Must be in the future (`> time()`). |
| `end_time` | yes | UTC Unix timestamp. Must be > `start_time`. |
| `comment` | no | Description text (stored in `maintenance_window_log.description`) |

Response:
```json
{"result": "completed", "detail": "Maintenance window setting has been added"}
```

**Note:** `author_name` is hardcoded to `"api_user"` by the endpoint. Use the
`comment` field to record who requested the window.

**Note:** BHNM's built-in UI schedules maintenance windows to start 15 minutes
in the future. BeNeM follows the same convention.

#### Close all maintenance windows (`action=close`)

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API password |
| `action` | yes | `close` |
| `name` | yes | Device name |

Response:
```json
{"result": "completed", "detail": "All maintenance windows for this device are closed"}
```

### Example — create a 1-hour maintenance window:
```bash
START=$(( $(date +%s) + 900 )); END=$(( START + 3600 )); \
curl --request POST \
  --url 'https://YOUR_HOST/api/maint_window_api.php' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data "password=YOUR_PASSWORD&action=new&name=raspi-050&start_time=$START&end_time=$END&comment=Scheduled+via+API"
```

---

---

# Open 3.0 / Officially Documented APIs

These APIs are documented on SwaggerHub at https://app.swaggerhub.com/search?owner=Netreo.

## Important: Base URL Clarification

Despite being called "Open 3.0", these APIs are split across TWO base paths:

| API | Base path | Auth param |
|---|---|---|
| Multi-Device-TimeSeries | `/fw/index.php?r=restful` | `password=` |
| Multi-Device-Status | `/fw/index.php?r=restful` | `password=` |
| Incident Acknowledgement | `/fw/index.php?r=restful` | `password=` |
| New Device API | `/api/new_device_api.php` | `pwd=` |
| Metrics Dictionary | `/api/getPerformanceDataSchema` | `password=` |

The first three share the same base path as the legacy API but use different
endpoint paths and return different response formats.

---

## Multi-Device-TimeSeries API (v1.0.14)

**Legacy version of time series data fetching.**
Use the `timeseries-metrics` endpoint instead for better performance.
Refer to this spec for the complete parameter vocabulary — it is the same.

```
POST https://YOUR_HOST/fw/index.php?r=restful/devices/get-time-series-metrics
```

### All parameters:

| Parameter | Required | Valid values |
|---|---|---|
| `password` | yes | API password |
| `metricFilterStatGroup` | yes | Any valid stat group (see metric vocabulary table) |
| `metricFilterUnits` | yes | Unit matching the stat group (see metric vocabulary table) |
| `groupFilterBy` | yes | `device`, `category`, `site`, `strategicGroup` |
| `groupFilterValue` | yes | Name matching the groupFilterBy type |
| `timeFrameFilterBy` | yes | `time_offset`, `specific_time` |
| `timeFrameFilterValue` | if time_offset | See full list below |
| `timeFrameFilterValueStart` | if specific_time | Unix timestamp |
| `timeFrameFilterValueEnd` | if specific_time | Unix timestamp |
| `returnFormatFilterBy` | yes | `average`, `peak`, `aggregate` |
| `returnFormatFilterValue` | if aggregate | `daily`, `hourly`, `monthly` |
| `returnFormatFilterValueFunction` | if aggregate | `all`, `min`, `avg`, `max` |
| `recordStart` | no | Pagination start (default: 1) |
| `recordCount` | no | Pagination count (default: 500) |

### All valid `timeFrameFilterValue` strings:
```
Last Hour       Last 2 Hours    Last 5 Hours    Last 24 Hours
Last 7 Days     Last Week       Last 30 Days    Last 90 Days
Last Month      Today           Yesterday       This Week
This Month      This Year
```

### Response format — DIFFERENT from timeseries-metrics endpoint:

The official `get-time-series-metrics` returns one object per timestamp,
unlike `timeseries-metrics` which returns a datapoints object keyed by timestamp.

```json
{
  "totalRecords": 100,
  "displayRecords": 12,
  "metrics": [
    {
      "deviceIndex": "463",
      "deviceName": "raspi-054",
      "GUID": "netreo-1599587812-11",
      "instanceDescr": "CPU Utilization for raspi-054",
      "timeStamp": "1775209800",
      "value1": "2.25",
      "value2": "0",
      "speed1": "0",
      "speed2": "0"
    }
  ]
}
```

### Parsing notes:
- `value1` is the primary metric value — always a string, cast before arithmetic
- `value2` is only populated for dual-value metrics (e.g. interface In/Out bandwidth)
- `speed1`/`speed2` are interface speeds in bits — only relevant for bandwidth metrics
- `timeStamp` is a Unix epoch second as a string
- This endpoint returns one object per datapoint — no nested datapoints object

---

## Multi-Device-Status API (v1.0.9)

Fetches current host and service status in bulk. Useful for dashboard status indicators.

```
POST https://YOUR_HOST/fw/index.php?r=restful/devices/get-host-and-service-status
```

### Parameters:

| Parameter | Required | Valid values / notes |
|---|---|---|
| `password` | yes | API password |
| `groupFilterBy` | yes | `device`, `category`, `site`, `strategicGroup` |
| `groupFilterValue` | yes | Name matching the groupFilterBy type |
| `serviceFilter` | yes | `host_only` or `service_desc` (regex supported) |
| `recordStart` | no | Pagination start |
| `recordCount` | no | Pagination count |

### Response:

```json
{
  "totalRecords": 10,
  "displayRecords": 10,
  "statuses": [
    {
      "deviceIndex": "3",
      "deviceName": "raspi-054",
      "incidentID": "457882",
      "status": "UP",
      "stateType": "HARD",
      "message": "PING OK",
      "currentStateDuration": "24d 14h 40m 10s",
      "lastUpdateTime": "2025-01-01T12:00:00Z"
    }
  ]
}
```

### Status values:
- When `serviceFilter=host_only`: `UP` or `DOWN`
- When `serviceFilter=service_desc`: `OK`, `WARNING`, `CRITICAL`, or `UNKNOWN`

### State type values:
- `SOFT` — threshold just crossed, not yet confirmed
- `HARD` — confirmed state after repeated checks

### Example — get status for a single device:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/devices/get-host-and-service-status' \
  --header 'Content-Type: multipart/form-data' \
  --form password=YOUR_PASSWORD \
  --form groupFilterBy=device \
  --form groupFilterValue=raspi-054 \
  --form serviceFilter=host_only \
  --compressed | jq
```

---

## Incident Acknowledgement API (v1.0.2)

Programmatically acknowledge or re-open incidents. Useful for automation and
integration with ticketing systems.

```
POST https://YOUR_HOST/fw/index.php?r=restful/incident/acknowledge
POST https://YOUR_HOST/fw/index.php?r=restful/incident/unacknowledge
```

### Parameters (same for both endpoints):

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API password |
| `incident_id` | yes | Numeric incident ID (integer) |
| `user` | yes | Name to associate with the action. Does not need to match an existing Netreo user. Accepts values like "Automation" or "bhnm-apns". |
| `comment` | no | Comment added to the incident record. Max 255 characters. |

### Response — acknowledge:
```json
{
  "result": "completed",
  "detail": "This incident has been ACKNOWLEDGED. Acked from RESTful API"
}
```

### Response — unacknowledge:
```json
{
  "result": "completed",
  "detail": "This incident has been RE-OPEN. De-Acked from RESTful API"
}
```

### Example:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/fw/index.php?r=restful/incident/acknowledge' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD&incident_id=457882&user=bhnm-apns&comment=Auto-acknowledged+via+API'
```

---

## New Device API (v1.0.14)

Adds a new device to Netreo or updates an existing one if the IP address already exists.

```
GET  https://YOUR_HOST/api/new_device_api.php
POST https://YOUR_HOST/api/new_device_api.php
```

Auth: `pwd=` (not `password=`)

### Required parameters:

| Parameter | Notes |
|---|---|
| `pwd` | API password |
| `ip` | IP address of the device |
| `poll` | Polling/monitoring status. Valid values: `on` or `off` |

### Key optional parameters:

| Parameter | Notes |
|---|---|
| `device_name` | Display name in Netreo. No special characters. |
| `snmp_pub` | SNMP public community string. Max 32 chars. |
| `type` | Device type title (must match a valid type in Netreo) |
| `subtype` | Device subtype (must be related to the chosen type) |
| `category` | Category name. Created if it doesn't exist. |
| `site` | Site name. Max 32 chars. Created if it doesn't exist. |
| `strategic_groups` | List of strategic group names |
| `rediscover` | Set to `1` to force a discovery poll immediately |
| `enabled` | `1` to add enabled (default), `0` to add disabled |
| `basicInterfaceFilter` | PERL5 regex to filter SNMP interfaces during discovery |
| `patch_management` | `1` to enable, `0` to disable |

### Device attribute arrays (repeat for multiple attributes):
```
name[]=DAX+number&value[]=dax12345
name[]=Location&value[]=Berlin
```

### Contact arrays (repeat for multiple contacts):
```
contact_name[]=John+Doe&contact_email[]=john@example.com&contact_number[]=+49123456
```

### Example — add a device:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/api/new_device_api.php' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'pwd=YOUR_PASSWORD&ip=192.168.1.100&device_name=my-device&poll=on&category=Servers&rediscover=1'
```

**Note:** If the IP already exists in Netreo, the device is updated, not duplicated.

---

## Metrics Dictionary API (v1.0.1)

Returns schema information for performance metrics published on the Kafka message bus.
Describes the structure of available metrics per device — useful for understanding
what data is available before querying time series.

```
POST https://YOUR_HOST/api/getPerformanceDataSchema
```

**Note:** This endpoint returned 302 redirects in testing against the VPN proxy on
port 8888. It may not be accessible via that proxy — test directly against the BHNM
host if needed.

### Parameters:

| Parameter | Where | Notes |
|---|---|---|
| `password` | query string | API password |
| `RecordStart` | JSON body | Pagination start |
| `RecordCount` | JSON body | Pagination count |
| `DeviceID` | JSON body | Numeric device ID |
| `PerformanceDataKey` | JSON body | e.g. `leaf_23` or `instances_123` — filter to specific metric |
| `AttributeFilter` | JSON body | Array of `{AttributeName, AttributeValue}` objects |

### Example:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/api/getPerformanceDataSchema?password=YOUR_PASSWORD' \
  --header 'Content-Type: application/json' \
  --data '{
    "DeviceID": "5",
    "RecordStart": 0,
    "RecordCount": 50
  }' | jq
```

### Response structure:
```json
[
  {
    "OmniCenterID": "1085490000",
    "PerformanceDataDescriptionList": [
      {
        "PerformanceDataKey": "leaf_23",
        "deviceID": "5",
        "deviceName": "raspi-054",
        "InstanceDescription": "CPU Utilization",
        "DS0Description": "CPU Utilization for raspi-054 In",
        "DS1Description": "CPU Utilization for raspi-054 Out",
        "unit": "%",
        "metricsGroup": "CPU",
        "thresholdStatus": "0",
        "lastDiscoveryPoll": "1612492358",
        "factor": 1,
        "dataType": "Gauge"
      }
    ]
  }
]
```

### Parsing notes:
- `metricsGroup` maps to `metricFilterStatGroup` in time series calls
- `unit` maps to `metricFilterUnits` in time series calls
- `PerformanceDataKey` can be used to query a specific metric directly
- `dataType` is either `Counter` (cumulative) or `Gauge` (point-in-time)
- `factor` is a conversion multiplier (e.g. `8` to convert bytes to bits)

---

## High Availability Status API (v0.3)

Retrieves the HA role and status of the BHNM appliance. Lightweight endpoint —
ideal for connection tests (no device enumeration, tiny response).

```
POST https://YOUR_HOST/api/ha_status_api.php
```

**Auth note:** Despite living under `/api/`, this endpoint uses `password=`
(not `pwd=`). This is consistent with the official OpenAPI spec on SwaggerHub.

### Parameters:

| Parameter | Required | Notes |
|---|---|---|
| `password` | yes | API key (case-sensitive) |

### Response:

```json
[{"role": "master", "status": "1"}]
```

Response is array-wrapped (consistent with BHNM convention).

### Role values:

| Role | Meaning |
|---|---|
| `standalone` | Not configured as an HA node |
| `primary` / `master` | Primary HA node |
| `slave` | Arbitrator or replica HA node |

### Status codes by role:

| Role | Status | Meaning |
|---|---|---|
| Primary | `1` | Active |
| Primary | `2` | Inactive |
| Slave | `1` | Active |
| Slave | `2` | Takeover |
| Slave | `3` | Inactive |

### Example:
```bash
curl --request POST \
  --url 'https://YOUR_HOST/api/ha_status_api.php' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data 'password=YOUR_PASSWORD'
```

### Use as connection test:

A successful 200 with a valid JSON response proves:
1. BHNM host is reachable
2. API key is valid
3. The appliance is operational

Used by BeNeM iOS and PWA Settings screens as the test-connection endpoint
(replaces the previous `devices/list` approach which was expensive in large
environments).

---

## Open 3.0 API — Quick Reference

| Purpose | Endpoint | Auth |
|---|---|---|
| Get time series data | `POST /fw/index.php?r=restful/devices/get-time-series-metrics` | `password=` |
| Get device/service status | `POST /fw/index.php?r=restful/devices/get-host-and-service-status` | `password=` |
| Acknowledge incident | `POST /fw/index.php?r=restful/incident/acknowledge` | `password=` |
| Unacknowledge incident | `POST /fw/index.php?r=restful/incident/unacknowledge` | `password=` |
| Add / update device | `POST /api/new_device_api.php` | `pwd=` |
| Get metric schema | `POST /api/getPerformanceDataSchema` | `password=` |
| Get HA status | `POST /api/ha_status_api.php` | `password=` |
| Create maintenance window | `POST /api/maint_window_api.php` | `password=` |
