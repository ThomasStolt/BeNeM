# Tactical Overview Cache — Design Spec

**Date:** 2026-04-09
**Status:** Approved

## Problem

Opening the home screen takes ~10 seconds on the SaaS BHNM instance because the tactical overview data is fetched live on every request. Additionally, the iOS home screen makes an unnecessary paginated device list fetch just to display a "Total Devices" count that can be derived from the tactical overview data.

## Solution

Add a pre-fetching background cache for the tactical overview in the middleware, and a dedicated cached endpoint. Update iOS and PWA to use the new endpoint and remove redundant API calls from the home screen.

## Middleware

### New file: `tactical_cache.py`

Mirrors `incident_cache.py` structure:

- **Storage:** In-memory dict keyed by `(server_id, grouping_type)`, storing the raw JSON response from BHNM.
- **Background loop:** One `asyncio.Task` per cache-enabled server. Each cycle fetches all 3 grouping types (`category`, `site`, `app`) sequentially via `POST /fw/index.php?r=restful/tactical-overview/data`.
- **Configuration:** Shares `cache_enabled` and `cache_refresh_seconds` from `servers.json` (same settings as the incident cache).
- **Lifecycle:** `start_all()` / `stop_server()` / `reload_server()` functions, same pattern as `incident_cache.py`.

### New endpoint: `GET /api/v1/tactical-overview`

In `main.py`:

- **Query param:** `grouping_type` (required, one of `category`, `site`, `app`)
- **Auth:** `X-Proxy-Token` header (same as other endpoints)
- **Server resolution:** Same logic as `/api/v1/incidents` — look up by API key, then by `X-BHNM-Target` header.
- **Cache hit:** Return cached JSON with `cache_age_seconds` metadata.
- **Cache miss / disabled:** Build a proper form-encoded POST to BHNM with `password`, `grouping_type`, and optional `pin` (same pattern as the incident fallthrough fix). Return the raw BHNM response.

### Lifespan changes

Start `tactical_cache.start_all()` alongside `incident_cache.start_all()` in the app lifespan handler. Wire up `reload_server()` in the `/internal/cache/reload` endpoint.

### Health endpoint

Add tactical cache status to `/health` response under a `tactical_cache` key, showing age per server and grouping type.

## iOS

### `NetreoAPIService.swift`

`fetchTacticalOverviewSummaries(groupingType:)` changes from:
- `POST <baseURL>/fw/index.php?r=restful/tactical-overview/data` (form body with `password`, `grouping_type`, `pin`)

To:
- `GET <baseURL>/api/v1/tactical-overview?grouping_type=<type>` (header-only, same as `fetchCachedIncidents`)
- Fallback to the original BHNM path if the cached endpoint returns non-200.

### `DashboardView.swift`

1. **Remove `DeviceListViewModel`** from the dashboard. No more device list fetch on home screen.
2. **"Total Devices" count** derived by summing host status counts (`hostsGreen + hostsBlue + hostsYellow + hostsOrange + hostsRed`) across all categories from `categoryViewModel.groups`.
3. **Connection status** derived from `ha_status` API result instead of device fetch success/failure. Call `POST /api/proxy/ha-status` and set `.connected` / `.disconnected` based on response.

## PWA

### `tactical-overview.ts`

Change `getTacticalSummary()` from:
- `POST <baseUrl>/fw/index.php?r=restful/tactical-overview/data` (form body)

To:
- `GET <baseUrl>/api/v1/tactical-overview?grouping_type=category` (with `X-Proxy-Token` and `X-BHNM-Target` headers)
- Fallback to the original BHNM path on failure.

(PWA already derives device count from tactical data — no change needed.)

## Not in scope

- Device list caching (separate concern, deferred)
- Independent cache toggle for tactical vs. incident cache (shares same settings)
- Caching `ha_status` (it's a live connection test by design)
