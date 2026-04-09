# Middleware Incident Cache — Design Spec

**Date:** 2026-04-09  
**Status:** Approved  
**Scope:** middleware, iOS, PWA

## Problem

Loading the Incidents screen triggers 1 + N API calls through the middleware to BHNM:
one `getincidents` call for the list, then one `getincidentdetail` per incident for alarm
color counts. With 119 incidents at ~3-5 seconds each, the screen takes 6-10 minutes to
fully load. The alarm counts never finish appearing. This affects both iOS and PWA.

## Solution

The middleware pre-fetches and caches all incidents with their alarm details for each
configured BHNM server. Clients receive everything in a single response. A background
loop continuously refreshes the cache, pacing API calls evenly over a configurable
interval to avoid overloading BHNM.

## Architecture

```
Admin Portal ──POST /internal/cache/reload──▶ Middleware
                                                │
                                         ┌──────┴──────┐
                                         │ Cache Loop   │ (per server, configurable interval)
                                         │              │
                                         │ 1. getincidents          (1 call)
                                         │ 2. getincidentdetail × N (paced evenly)
                                         │ 3. Store enriched result in memory
                                         └──────┬──────┘
                                                │
iOS / PWA ──GET /api/v1/servers/{id}/incidents──▶ Middleware serves from cache
                                                  (falls through to live proxy if cache cold)
```

## Cache Loop

### One loop per server

Each server with `cache_enabled: true` gets its own independent `asyncio.Task`.
Multiple servers run concurrently without interfering with each other.

Example with 3 servers:
- Server A (119 incidents, 2 min refresh) — ~1 call/second to Server A
- Server B (30 incidents, 5 min refresh) — ~1 call/10 seconds to Server B
- Server C (200 incidents, 2 min refresh) — ~1.7 calls/second to Server C

### Pacing

After `getincidents` returns N incidents, the loop distributes the N
`getincidentdetail` calls evenly across the configured refresh interval.

Formula: `delay = refresh_interval_seconds / (N + 1)`

For 119 incidents over 120 seconds: one detail call roughly every second.

### Cycle behavior

Cycles run continuously. When a full cycle completes, the next one starts
immediately (no idle gap). This means the cache is always being refreshed.

### Error handling

- If a single `getincidentdetail` call fails: skip it, log the error, retain
  the previous cached detail for that incident (if any). Continue the cycle.
- If `getincidents` fails: log the error, keep serving the previous cached
  list. Retry on the next cycle.
- If the BHNM server is unreachable: log once, back off with exponential
  delay (capped at the configured refresh interval), resume normal pacing
  when connectivity returns.

## Cache Storage

In-memory Python dict, keyed by `server_id`. Lost on restart but repopulated
automatically by the background loop within one refresh cycle.

Structure:
```python
_incident_cache: dict[str, CachedIncidents] = {}

@dataclass
class CachedIncidents:
    active_incidents: list[dict]    # enriched with alarm_counts
    closed_incidents: list[dict]    # enriched with alarm_counts
    last_updated: float             # time.time()
```

## New Endpoint

### GET /api/v1/servers/{server_id}/incidents

Returns the cached enriched incident list.

**Response (cache warm):**
```json
{
  "cache_age_seconds": 45,
  "active_incidents": [
    {
      "incident_id": "123",
      "summary": "Host down: router-core-01",
      "severity": "critical",
      "status": "active",
      "device_name": "router-core-01",
      "start_time": "2026-04-09T06:12:00Z",
      "incident_state": "Alarms Active",
      "alarm_counts": {
        "red": 2,
        "orange": 1,
        "yellow": 0,
        "green": 3,
        "blue": 0
      },
      "alert_type": "host"
    }
  ],
  "closed_incidents": []
}
```

**Response (cache cold / caching disabled for this server):**

Fall through to live BHNM proxy: call `getincidents` directly and return the
result without `alarm_counts` (field is `null` per incident). The client
handles `null` alarm_counts by showing a spinner per row, same as today.

Each incident object includes all fields from the BHNM `getincidents` response
(so the client can parse it the same way), plus the added `alarm_counts` and
`alert_type` fields from `getincidentdetail`.

**Authentication:** Same `X-Proxy-Token` header as existing proxy routes.

## servers.json Extension

```json
{
  "id": "prod",
  "name": "Production",
  "url": "https://bhnm.corp.com",
  "api_key": "your-api-key-here",
  "pin": "",
  "cache_enabled": true,
  "cache_refresh_seconds": 120
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `cache_enabled` | bool | `false` | Enable incident caching for this server |
| `cache_refresh_seconds` | int | `120` | Full cache refresh interval. Min 60, max 900. |

Existing servers without these fields default to caching disabled.

## Admin Portal Changes

### Server card

Add a toggle switch labeled "Incident Cache" with an on/off state.
When enabled, show a numeric input for the refresh interval in seconds
(default 120, min 60, max 900).

### Trigger on change

When a server is added, edited, or deleted, the admin portal POSTs to:

```
POST http://benem-middleware:8889/internal/cache/reload
Content-Type: application/json

{ "server_id": "prod" }
```

The middleware responds to this by:
- **Add/edit with caching enabled:** Start or restart the cache loop for that server
- **Edit with caching disabled:** Stop the loop, clear cache for that server
- **Delete:** Stop the loop, clear cache for that server

### Internal endpoint security

`/internal/cache/reload` is not exposed through Caddy. It is only reachable
within the Docker network between the admin and middleware containers.

## Client Changes

### iOS

- New method in `NetreoAPIService` to call `/api/v1/servers/{server_id}/incidents`
- `IncidentListViewModel.loadIncidents()` uses the new endpoint
- Parse `alarm_counts` from the enriched response — no more `loadAlarmCounts()` loop
- If `alarm_counts` is `null` (cold cache fallback), show per-row spinner as today
- `loadAlarmCounts()` remains as fallback but is only called when `alarm_counts` is `null`

### PWA

- Equivalent fetch logic: call the new endpoint, parse enriched incidents
- Same fallback behavior for `null` alarm_counts

## What Stays the Same

- `getincidentdetail` proxy remains available for `IncidentDetailView` (full detail on tap)
- ACK/UnACK endpoints unchanged
- All other proxy routes unchanged (devices, tactical, performance)
- Push notification flow unchanged
- Existing legacy proxy routes continue to work

## Rollout

Caching is opt-in per server (`cache_enabled` defaults to `false`). Enable on
one test server first, verify behavior, then enable on others.
