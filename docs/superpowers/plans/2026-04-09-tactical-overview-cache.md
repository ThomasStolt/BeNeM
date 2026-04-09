# Tactical Overview Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pre-fetch and cache tactical overview data in the middleware so the home screen loads instantly instead of waiting ~10 seconds for live BHNM calls.

**Architecture:** New `tactical_cache.py` mirrors `incident_cache.py` — one background asyncio task per cache-enabled server fetches all 3 grouping types. New `GET /api/v1/tactical-overview` endpoint serves cached data. iOS and PWA switch to the new endpoint. iOS dashboard drops the device list fetch (derives count from tactical data) and uses `ha_status` for connection checks.

**Tech Stack:** Python/FastAPI (middleware), Swift/SwiftUI (iOS), React/TypeScript (PWA)

**Spec:** `docs/superpowers/specs/2026-04-09-tactical-overview-cache-design.md`

---

### Task 1: Middleware — `tactical_cache.py`

**Files:**
- Create: `middleware/tactical_cache.py`

- [ ] **Step 1: Create `tactical_cache.py`**

```python
"""Background tactical overview cache for BHNM servers.

Pre-fetches tactical overview data (category/site/app grouping types),
stores raw JSON in memory.  One asyncio.Task per enabled server.
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field

import httpx

from config import SERVERS_JSON_PATH, BHNM_TLS_VERIFY, PROXY_TIMEOUT

GROUPING_TYPES = ("category", "site", "app")


# -- Cache storage -------------------------------------------------------------

@dataclass
class CachedTactical:
    """Cached tactical overview data for one server."""
    data: dict[str, dict] = field(default_factory=dict)   # grouping_type -> raw JSON
    last_updated: dict[str, float] = field(default_factory=dict)  # grouping_type -> epoch

_cache: dict[str, CachedTactical] = {}
_tasks: dict[str, asyncio.Task] = {}


def get_cached(server_id: str, grouping_type: str) -> tuple[dict, float] | None:
    entry = _cache.get(server_id)
    if not entry:
        return None
    data = entry.data.get(grouping_type)
    ts = entry.last_updated.get(grouping_type, 0.0)
    if data is not None and ts > 0:
        return (data, ts)
    return None


def _server_id_for_api_key(api_key: str) -> str:
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s.get("id", "")
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return ""


def _server_id_for_bhnm_url(bhnm_url: str) -> str:
    normalized = bhnm_url.rstrip("/")
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("url", "").rstrip("/") == normalized:
                    return s.get("id", "")
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return ""


def _load_enabled_servers() -> list[dict]:
    try:
        with open(SERVERS_JSON_PATH) as f:
            return [s for s in json.load(f) if s.get("cache_enabled")]
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        return []


# -- BHNM fetch ---------------------------------------------------------------

async def _fetch_tactical(client: httpx.AsyncClient, server: dict, grouping_type: str) -> dict:
    url = f"{server['url'].rstrip('/')}/fw/index.php?r=restful/tactical-overview/data"
    form: dict[str, str] = {
        "password": server["api_key"],
        "grouping_type": grouping_type,
    }
    if server.get("pin"):
        form["pin"] = server["pin"]
    resp = await client.post(url, data=form)
    raw = resp.json()
    if isinstance(raw, list):
        return raw[0] if raw else {}
    return raw


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client: httpx.AsyncClient, server: dict) -> None:
    server_id = server["id"]
    if server_id not in _cache:
        _cache[server_id] = CachedTactical()

    for gt in GROUPING_TYPES:
        try:
            data = await _fetch_tactical(client, server, gt)
            _cache[server_id].data[gt] = data
            _cache[server_id].last_updated[gt] = time.time()
        except Exception as e:
            print(f"[TacticalCache:{server_id}] Failed to fetch {gt}: {e}")

    print(f"[TacticalCache:{server_id}] Cache updated: {', '.join(f'{gt}={len(_cache[server_id].data.get(gt, {}))} groups' for gt in GROUPING_TYPES)}")


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))
    print(f"[TacticalCache:{server_id}] Background loop started (refresh={refresh}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[TacticalCache:{server_id}] Cycle failed: {e}")
            await asyncio.sleep(refresh)


# -- Lifecycle -----------------------------------------------------------------

def start_all() -> None:
    for server in _load_enabled_servers():
        _start_server(server)


def reload_server(server_id: str) -> None:
    stop_server(server_id)
    servers = _load_enabled_servers()
    server = next((s for s in servers if s["id"] == server_id), None)
    if server:
        _start_server(server)
        print(f"[TacticalCache:{server_id}] Reloaded")
    else:
        print(f"[TacticalCache:{server_id}] Caching disabled or server removed — stopped")


def stop_server(server_id: str) -> None:
    task = _tasks.pop(server_id, None)
    if task and not task.done():
        task.cancel()
    _cache.pop(server_id, None)


def _start_server(server: dict) -> None:
    server_id = server["id"]
    if server_id in _tasks and not _tasks[server_id].done():
        return
    _tasks[server_id] = asyncio.create_task(_cache_loop(server))
    print(f"[TacticalCache:{server_id}] Started background loop")
```

- [ ] **Step 2: Commit**

```bash
git add middleware/tactical_cache.py
git commit -m "feat(middleware): add tactical overview background cache"
```

---

### Task 2: Middleware — New endpoint and wiring

**Files:**
- Modify: `middleware/main.py`

- [ ] **Step 1: Add import**

At `middleware/main.py:19`, after `import incident_cache`, add:

```python
import tactical_cache
```

- [ ] **Step 2: Start tactical cache in lifespan**

At `middleware/main.py:143-147`, change the lifespan handler from:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    incident_cache.start_all()
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — dynamic multi-server routing enabled")
    yield
```

To:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    incident_cache.start_all()
    tactical_cache.start_all()
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — dynamic multi-server routing enabled")
    yield
```

- [ ] **Step 3: Add tactical cache to health endpoint**

At `middleware/main.py:287-303`, change the health function to include tactical cache status. After the incident cache loop (line 296), add:

```python
    tactical_status = {}
    for sid, cached in tactical_cache._cache.items():
        tactical_status[sid] = {
            gt: {
                "groups": len(cached.data.get(gt, {})),
                "age_seconds": round(time.time() - cached.last_updated.get(gt, 0)) if cached.last_updated.get(gt) else None,
            }
            for gt in tactical_cache.GROUPING_TYPES
        }
```

And add `"tactical_cache": tactical_status` to the return dict alongside `"cache": cache_status`.

- [ ] **Step 4: Wire tactical cache into `/internal/cache/reload`**

At `middleware/main.py:375` (the `cache_reload` function), after `incident_cache.reload_server(server_id)`, add:

```python
    tactical_cache.reload_server(server_id)
```

- [ ] **Step 5: Add the cached tactical overview endpoint**

Insert the following after the `/internal/cache/reload` endpoint (before the `# ── BHNM Proxy — Dedicated Routes` comment):

```python
# ── Cached Tactical Overview Endpoint ──────────────────────────────────────

@app.get("/api/v1/tactical-overview")
async def cached_tactical_overview(request: Request, grouping_type: str = "category"):
    """Return tactical overview from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)

    if grouping_type not in ("category", "site", "app"):
        raise HTTPException(status_code=400, detail="grouping_type must be category, site, or app")

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = tactical_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = tactical_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = tactical_cache.get_cached(server_id, grouping_type)
        if cached:
            data, ts = cached
            return {
                "cache_age_seconds": round(time.time() - ts),
                "grouping_type": grouping_type,
                "data": data,
            }

    # Cache cold or server not found — fetch live from BHNM.
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    server_cfg = _server_config_for_api_key(api_key)
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base)

    form = {"password": api_key, "grouping_type": grouping_type}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/fw/index.php?r=restful/tactical-overview/data"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    return Response(content=resp.content, status_code=resp.status_code,
                    headers={k: v for k, v in resp.headers.items()
                             if k.lower() not in HOP_BY_HOP_RESPONSE})
```

- [ ] **Step 6: Commit**

```bash
git add middleware/main.py
git commit -m "feat(middleware): add /api/v1/tactical-overview endpoint with cache"
```

---

### Task 3: iOS — Switch tactical overview to cached endpoint

**Files:**
- Modify: `ios/BeNeM/Services/NetreoAPIService.swift:626-676`

- [ ] **Step 1: Update `fetchTacticalOverviewSummaries`**

Replace the current implementation at lines 626-676 with a new version that calls the middleware cached endpoint first, falling back to the direct BHNM call:

```swift
    func fetchTacticalOverviewSummaries(groupingType: String) async throws -> [GroupSummary] {
        // Try cached endpoint first
        let cachedURL = "\(configuration.baseURL)/api/v1/tactical-overview?grouping_type=\(groupingType)"
        if let url = URL(string: cachedURL) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addProxyToken(&request)

            if let (data, response) = try? await urlSession.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Cached response wraps the BHNM data in a "data" key
                let tacticalData: [String: Any]
                if let wrapped = json["data"] as? [String: Any] {
                    tacticalData = wrapped
                } else {
                    // Fallthrough response is raw BHNM format
                    tacticalData = json
                }
                return parseTacticalOverview(tacticalData, groupingType: groupingType)
            }
        }

        // Fallback to direct BHNM call
        return try await fetchTacticalOverviewDirect(groupingType: groupingType)
    }

    private func fetchTacticalOverviewDirect(groupingType: String) async throws -> [GroupSummary] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/tactical-overview/data") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password",      value: configuration.apiKey),
            URLQueryItem(name: "grouping_type", value: groupingType)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return parseTacticalOverview(json, groupingType: groupingType)
    }

    private func parseTacticalOverview(_ json: [String: Any], groupingType: String) -> [GroupSummary] {
        func statusCounts(_ status: [String: Any], prefix: String)
            -> (green: Int, blue: Int, yellow: Int, orange: Int, red: Int)
        {
            let ok   = status["\(prefix)ok_count"]   as? Int ?? 0
            let ack  = status["\(prefix)ack_count"]  as? Int ?? 0
            let warn = status["\(prefix)warn_count"] as? Int ?? 0
            let un   = status["\(prefix)un_count"]   as? Int ?? 0
            let crit = status["\(prefix)crit_count"] as? Int ?? 0
            return (ok, ack, warn, un, crit)
        }

        var result: [GroupSummary] = []
        for (name, value) in json {
            guard let group  = value as? [String: Any],
                  let status = group["Status"] as? [String: Any] else { continue }
            let h = statusCounts(status, prefix: "host_")
            let s = statusCounts(status, prefix: "service_")
            let t = statusCounts(status, prefix: "threshold_")
            let a = statusCounts(status, prefix: "anom_threshold_")
            let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : name
            result.append(GroupSummary(
                id: name, name: displayName,
                hostsGreen:       h.green,  hostsBlue:       h.blue,  hostsYellow:       h.yellow,
                hostsOrange:      h.orange, hostsRed:        h.red,
                servicesGreen:    s.green,  servicesBlue:    s.blue,  servicesYellow:    s.yellow,
                servicesOrange:   s.orange, servicesRed:     s.red,
                thresholdsGreen:  t.green,  thresholdsBlue:  t.blue,  thresholdsYellow:  t.yellow,
                thresholdsOrange: t.orange, thresholdsRed:   t.red,
                anomaliesGreen:   a.green,  anomaliesBlue:   a.blue,  anomaliesYellow:   a.yellow,
                anomaliesOrange:  a.orange, anomaliesRed:    a.red
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
```

- [ ] **Step 2: Commit**

```bash
git add ios/BeNeM/Services/NetreoAPIService.swift
git commit -m "feat(ios): use cached tactical overview endpoint with fallback"
```

---

### Task 4: iOS — Remove device list from dashboard, use ha_status for connection

**Files:**
- Modify: `ios/BeNeM/Views/DashboardView.swift`
- Modify: `ios/BeNeM/Services/NetreoAPIService.swift` (add `checkHAStatus` method)

- [ ] **Step 1: Add `checkHAStatus()` to `NetreoAPIService`**

Add after the `fetchTacticalOverviewSummaries` method:

```swift
    /// Lightweight connection check via the HA status endpoint.
    /// Returns true if the server responds with a valid HA status JSON.
    func checkHAStatus() async -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/api/proxy/ha-status") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)

        guard let (data, response) = try? await urlSession.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode,
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        // ha_status returns [{"role":"master","status":"1"}] or {"role":"standalone","status":"1"}
        let obj: [String: Any]?
        if let dict = raw as? [String: Any] { obj = dict }
        else if let arr = raw as? [[String: Any]] { obj = arr.first }
        else { obj = nil }
        return obj?["role"] as? String != nil
    }
```

- [ ] **Step 2: Update `DashboardView` — remove `DeviceListViewModel`, derive device count, use ha_status**

In `DashboardView.swift`, make these changes:

**a) Remove `deviceViewModel` property** (line 17):

Delete:
```swift
    @StateObject private var deviceViewModel: DeviceListViewModel
```

**b) Remove `deviceViewModel` from init** (line 34):

Delete:
```swift
        self._deviceViewModel    = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
```

**c) Update loading condition** (lines 44-46):

Change from:
```swift
                    if (incidentViewModel.isLoading || deviceViewModel.isLoading)
                        && incidentViewModel.incidents.isEmpty
                        && deviceViewModel.devices.isEmpty {
```

To:
```swift
                    if (incidentViewModel.isLoading || categoryViewModel.isLoading)
                        && incidentViewModel.incidents.isEmpty
                        && categoryViewModel.groups.isEmpty {
```

**d) Update AutoRefreshButton isLoading** (line 85):

Change from:
```swift
                        isLoading: incidentViewModel.isLoading || deviceViewModel.isLoading || categoryViewModel.isLoading,
```

To:
```swift
                        isLoading: incidentViewModel.isLoading || categoryViewModel.isLoading,
```

**e) Update .task condition** (line 92):

Change from:
```swift
                if incidentViewModel.incidents.isEmpty && deviceViewModel.devices.isEmpty {
```

To:
```swift
                if incidentViewModel.incidents.isEmpty && categoryViewModel.groups.isEmpty {
```

**f) Remove `deviceViewModel.updateAPIService` from onChange** (line 118):

Delete:
```swift
            deviceViewModel.updateAPIService(apiService)
```

**g) Update "Total Devices" StatusCard** (lines 139-144):

Change from:
```swift
            StatusCard(
                title: "Total Devices",
                count: deviceViewModel.devices.count,
                color: .blue,
                icon: "network"
            )
```

To:
```swift
            StatusCard(
                title: "Total Devices",
                count: totalDeviceCount,
                color: .blue,
                icon: "network"
            )
```

**h) Add computed property** for `totalDeviceCount` near the other computed properties (after `hostTotals`):

```swift
    private var totalDeviceCount: Int {
        let h = hostTotals
        return h.green + h.blue + h.yellow + h.orange + h.red
    }
```

**i) Update `loadData()`** (lines 335-345):

Change from:
```swift
    private func loadData() async {
        // Load incidents, devices, and category data concurrently.
        // Category is needed for the Dashboard stat boxes (H/S/T/A).
        // Sites and Business Workflows load on demand when the user navigates there.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await incidentViewModel.loadIncidents() }
            group.addTask { await deviceViewModel.loadDevices() }
            group.addTask { await categoryViewModel.load() }
        }
        connectionStatus = deviceViewModel.errorMessage == nil ? .connected : .disconnected
    }
```

To:
```swift
    private func loadData() async {
        // Load incidents and category data concurrently.
        // Category is needed for the Dashboard stat boxes (H/S/T/A) and Total Devices count.
        // Sites and Business Workflows load on demand when the user navigates there.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await incidentViewModel.loadIncidents() }
            group.addTask { await categoryViewModel.load() }
        }
        connectionStatus = await apiService.checkHAStatus() ? .connected : .disconnected
    }
```

- [ ] **Step 3: Build iOS**

```bash
cd ios && xcodebuild -scheme BeNeM -destination 'platform=iOS,name=TomiPhone13' build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/Views/DashboardView.swift ios/BeNeM/Services/NetreoAPIService.swift
git commit -m "feat(ios): derive device count from tactical data, use ha_status for connection check"
```

---

### Task 5: PWA — Switch tactical overview to cached endpoint

**Files:**
- Modify: `pwa/src/lib/api/tactical-overview.ts:100-116`

- [ ] **Step 1: Update `fetchTacticalOverview` to use cached endpoint with fallback**

Replace the `fetchTacticalOverview` function (lines 100-116) with:

```typescript
export async function fetchTacticalOverview(
  config: BhnmConfig,
  groupingType: GroupingType = 'category',
): Promise<TacticalGroup[]> {
  // Try cached endpoint first
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;
  try {
    const raw = await fetchJson(
      config.baseUrl,
      `/api/v1/tactical-overview?grouping_type=${groupingType}`,
      headers,
    );
    // Cached response wraps BHNM data in a "data" key
    const obj = (typeof raw === 'object' && raw !== null) ? raw as Record<string, unknown> : {};
    const tacticalData = obj.data ?? raw;
    return parseTacticalResponse(tacticalData);
  } catch {
    // Fall back to direct BHNM call through proxy
    const params: Record<string, string> = {
      password: config.apiKey,
      grouping_type: groupingType,
    };
    if (config.pin) params.pin = config.pin;
    const raw = await postForm(
      config.baseUrl,
      '/fw/index.php?r=restful/tactical-overview/data',
      params,
      config.apiKey,
    );
    return parseTacticalResponse(raw);
  }
}
```

- [ ] **Step 2: Add `fetchJson` import**

At the top of `pwa/src/lib/api/tactical-overview.ts` (line 1), change:

```typescript
import { postForm } from './client';
```

To:

```typescript
import { fetchJson, postForm } from './client';
```

- [ ] **Step 3: Commit**

```bash
git add pwa/src/lib/api/tactical-overview.ts
git commit -m "feat(pwa): use cached tactical overview endpoint with fallback"
```

---

### Task 6: Deploy and verify

**Files:** None (deployment only)

- [ ] **Step 1: Deploy middleware + PWA to production**

```bash
./deploy.sh
```

- [ ] **Step 2: Verify health endpoint shows tactical cache**

```bash
curl -s https://bhnm-apns.hurrikap.org/health | python3 -m json.tool
```

Expected: `tactical_cache` key present with data for AENA server showing `category`, `site`, `app` entries.

- [ ] **Step 3: Verify cached tactical endpoint works**

```bash
curl -s -X GET 'https://bhnm-apns.hurrikap.org/api/v1/tactical-overview?grouping_type=category' \
  -H "X-Proxy-Token: ThisIsAPassword" \
  -H "X-BHNM-Target: https://vpn.hurrikap.org:8888" | python3 -m json.tool | head -20
```

Expected: JSON with tactical overview data (cache miss falls through to live BHNM since lab server caching is disabled).

- [ ] **Step 4: Build and deploy iOS to device**

```bash
cd ios && ./build_and_deploy.sh
```

- [ ] **Step 5: Manual verification**

Open the app and verify:
- Home screen loads fast (cached data for AENA server)
- "Total Devices" count matches previous value
- Connection status indicator works
- Drill down to Categories/Sites/Business Workflows still works
- PWA dashboard at https://bhnm-apns.hurrikap.org also loads fast

---

### Task 7: Update middleware CLAUDE.md

**Files:**
- Modify: `middleware/CLAUDE.md`

- [ ] **Step 1: Add tactical cache documentation**

In the `## Project Structure` table, add after the `incident_cache.py` row:

```markdown
| `tactical_cache.py` | Background tactical overview cache: pre-fetches category/site/app grouping data from BHNM, stores raw JSON in memory. Same lifecycle as `incident_cache.py`. |
```

In the `## Endpoints` table, add after the `/internal/cache/reload` row:

```markdown
| `GET /api/v1/tactical-overview` | Cached tactical overview data by grouping type; falls through to live BHNM if cache is cold | iOS app, PWA |
```

In the `### Incident Cache` section, add a new `### Tactical Overview Cache` section:

```markdown
### Tactical Overview Cache
`tactical_cache.py` pre-fetches tactical overview data (category, site, app grouping types) from each BHNM server with caching enabled. One `asyncio.Task` per server runs a continuous loop:

1. Calls `POST /fw/index.php?r=restful/tactical-overview/data` for each grouping type (3 API calls)
2. Stores the raw JSON response in an in-memory dict keyed by `(server_id, grouping_type)`

Clients call `GET /api/v1/tactical-overview?grouping_type=category` and receive the data instantly. If the cache is cold, the endpoint falls through to a live BHNM request (building the proper form-encoded POST from the proxy token).

Configuration shares `cache_enabled` and `cache_refresh_seconds` with the incident cache. Admin portal reload (`/internal/cache/reload`) restarts both caches.
```

- [ ] **Step 2: Commit**

```bash
git add middleware/CLAUDE.md
git commit -m "docs: add tactical overview cache to middleware CLAUDE.md"
```
