# Maintenance Window — Design Spec

**Date:** 2026-04-09
**Status:** Approved
**Scope:** iOS, PWA, Middleware

## Overview

Add a "Create Maintenance Window" button to device detail views on both iOS and PWA. The button opens a dialog where the user selects a duration and provides a description. The request flows through the middleware to BHNM's `maint_window_api.php`.

No maintenance status display is included — this is create-only.

## BHNM API Discovery

The BHNM maintenance API was discovered by inspecting the server directly:

**Endpoint:** `POST /api/maint_window_api.php`

**Supported actions:**
- `action=new` — create a maintenance window (params: `name`, `start_time`, `end_time`, `comment`, `password`)
- `action=close` — close all active maintenance windows for a device (params: `name`, `password`)

**Key details:**
- `name` is the device name (string), not a numeric ID
- `start_time` and `end_time` are standard UTC Unix timestamps (seconds)
- `start_time` must be in the future (`> time()`)
- `comment` is stored as the description; `author_name` is hardcoded to `"api_user"` by the API
- Data is stored in the `maintenance_window_log` table
- BHNM's built-in UI schedules maintenance to start 15 minutes in the future; we follow the same pattern

**No query API exists.** Maintenance status is determined internally by BHNM via direct DB query (`start_time <= now AND end_time >= now`). The device list/find endpoints do not include a maintenance status field.

## Architecture

```
iOS / PWA
    → POST /api/proxy/maintenance/create (middleware)
        → POST /api/maint_window_api.php (BHNM)
```

All communication goes through the middleware. Apps never call BHNM directly.

## Middleware Endpoint

### `POST /api/proxy/maintenance/create`

Follows the same pattern as `/api/proxy/incident/acknowledge` and `/api/proxy/incident/unacknowledge`.

**Request body** (form-urlencoded):

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Device name |
| `duration` | integer | yes | Duration in minutes (minimum 1) |
| `comment` | string | yes | Description text |

**Middleware logic:**
1. Validate `X-Proxy-Token`, resolve BHNM target server (same as ACK/UnACK)
2. Calculate `start_time = int(time.time()) + 900` (now + 15 minutes)
3. Calculate `end_time = start_time + (duration * 60)`
4. Forward to BHNM: `POST /api/maint_window_api.php` with `password=<api_key>`, `action=new`, `name`, `start_time`, `end_time`, `comment`
5. Return BHNM's JSON response to the app

No caching, no state — pure proxy with timestamp calculation.

## iOS — Device Detail View

**Button:** "Create Maintenance Window" button in `DeviceDetailView`.

**Dialog:** SwiftUI `.sheet` containing:
- Title: "Create Maintenance Window" + device name subtitle
- Duration picker: chip-style quick picks — 1h, 6h, 12h, 24h, 7d, Custom
- When "Custom" selected: text field for minutes, prefilled with 60
- Description text field, prefilled: `"set by api_user on <yyyy-MM-dd HH:mm>"`
- Cancel / Create buttons
- Loading state on Create, success/error feedback

**API call:** New method in `NetreoAPIService` — `createMaintenanceWindow(deviceName:duration:comment:)` that POSTs to `/api/proxy/maintenance/create`.

## PWA — Device Detail Screen

**Button:** "Create Maintenance Window" button in `DeviceDetailScreen`, below the device info card.

**Dialog:** React modal containing:
- Title + device name
- Duration chip buttons: 1h, 6h, 12h, 24h, 7d, Custom
- Custom minutes input (shown when Custom selected, prefilled 60)
- Description input, prefilled: `"set by api_user on <yyyy-MM-dd HH:mm>"`
- Cancel / Create buttons
- Loading spinner on Create, toast or inline feedback for success/error

**API call:** New function in `pwa/src/lib/api/` that POSTs to `/api/proxy/maintenance/create`.

## Error Handling

- **BHNM returns error** (device not found, API disabled, bad timestamps): surface the `detail` field from BHNM's JSON response to the user
- **Network failure / middleware unreachable**: generic "Could not create maintenance window" error
- **Duration validation**: minimum 1 minute, no upper bound — enforced client-side before sending
- **No confirmation dialog** before creating — the user explicitly tapped Create

## Out of Scope

- Maintenance status display (blue card, "In Maintenance" banner)
- Querying active maintenance windows
- Cancelling/closing maintenance windows early
- Scheduled/recurring maintenance windows
- Timezone configuration (Unix timestamps are UTC; confirmed working via testing)
