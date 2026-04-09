# Middleware Incident Cache — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pre-cache BHNM incidents with alarm details in the middleware so clients get enriched incidents in a single fast response instead of N+1 sequential API calls.

**Architecture:** A background `asyncio.Task` per enabled server fetches incidents and their alarm details from BHNM, pacing calls evenly over a configurable interval. Results are stored in an in-memory dict. A new `/api/v1/incidents` endpoint serves cached data; falls through to live BHNM proxy when cache is cold. The admin portal triggers cache reload on server changes.

**Tech Stack:** Python/FastAPI (middleware), HTMX (admin), Swift/SwiftUI (iOS)

**Spec deviation:** The spec defined the endpoint as `/api/v1/servers/{server_id}/incidents`, but the iOS app has no concept of `server_id` — it identifies servers by `api_key` (sent as `X-Proxy-Token`) and `bhnmURL` (sent as `X-BHNM-Target`). The endpoint is changed to `/api/v1/incidents` using the same auth/routing pattern as existing proxy routes.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `middleware/incident_cache.py` | Create | Cache storage, background loop, BHNM fetch logic |
| `middleware/main.py` | Modify | Start cache on lifespan, new endpoint, reload endpoint |
| `middleware/benem-admin/servers.py` | Modify | Add `cache_enabled`, `cache_refresh_seconds` to Server dataclass |
| `middleware/benem-admin/main.py` | Modify | Trigger cache reload on server add/edit/delete |
| `middleware/benem-admin/templates/_server_card.html` | Modify | Show cache status toggle |
| `middleware/benem-admin/templates/_server_form.html` | Modify | Add cache toggle + interval input |
| `middleware/tests/test_incident_cache.py` | Create | Unit tests for cache module |
| `ios/BeNeM/Services/NetreoAPIService.swift` | Modify | New `fetchCachedIncidents` method |
| `ios/BeNeM/ViewModels/IncidentListViewModel.swift` | Modify | Use cached endpoint, parse alarm_counts inline |

**Note:** PWA changes are deferred — the PWA is still a stub. Once the middleware endpoint is live, PWA can consume it the same way iOS does.

---

### Task 1: Create incident_cache.py — cache storage and BHNM fetch helpers

**Files:**
- Create: `middleware/incident_cache.py`
- Create: `middleware/tests/test_incident_cache.py`

- [ ] **Step 1: Write test for `_resolve_server_for_request` helper**

```python
# middleware/tests/test_incident_cache.py
import pytest
from incident_cache import _server_id_for_api_key

def test_server_id_for_api_key_found(tmp_path):
    import json, os
    servers_path = tmp_path / "servers.json"
    servers_path.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com",
         "api_key": "key123", "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120}
    ]))
    os.environ["SERVERS_JSON_PATH"] = str(servers_path)
    assert _server_id_for_api_key("key123") == "prod"

def test_server_id_for_api_key_not_found(tmp_path):
    import json, os
    servers_path = tmp_path / "servers.json"
    servers_path.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com",
         "api_key": "key123", "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120}
    ]))
    os.environ["SERVERS_JSON_PATH"] = str(servers_path)
    assert _server_id_for_api_key("wrong") == ""
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd middleware && python -m pytest tests/test_incident_cache.py -v
```

Expected: FAIL — `incident_cache` module does not exist.

- [ ] **Step 3: Write the cache module skeleton with storage, server lookup, and BHNM fetch helpers**

```python
# middleware/incident_cache.py
"""Background incident cache for BHNM servers.

Pre-fetches incidents and their alarm details, stores enriched results
in memory.  One asyncio.Task per enabled server, paced to avoid overload.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from urllib.parse import parse_qs

import httpx

from config import SERVERS_JSON_PATH, BHNM_TLS_VERIFY, PROXY_TIMEOUT

logger = logging.getLogger("incident_cache")

# ── Cache storage ────────────────────────────────────────────────────────────

@dataclass
class CachedIncidents:
    active_incidents: list[dict] = field(default_factory=list)
    closed_incidents: list[dict] = field(default_factory=list)
    last_updated: float = 0.0

_cache: dict[str, CachedIncidents] = {}
_tasks: dict[str, asyncio.Task] = {}


def get_cached(server_id: str) -> CachedIncidents | None:
    """Return cached incidents for a server, or None if not cached."""
    entry = _cache.get(server_id)
    if entry and entry.last_updated > 0:
        return entry
    return None


def _server_id_for_api_key(api_key: str) -> str:
    """Look up server ID by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s.get("id", "")
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return ""


def _load_enabled_servers() -> list[dict]:
    """Return servers from servers.json where cache_enabled is true."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            return [s for s in json.load(f) if s.get("cache_enabled")]
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        return []


# ── BHNM fetch helpers ──────────────────────────────────────────────────────

async def _fetch_incidents(client: httpx.AsyncClient, server: dict) -> dict:
    """Call getincidents on the BHNM server. Returns parsed JSON dict."""
    url = f"{server['url'].rstrip('/')}/api/incident_api.php"
    form = {"pwd": server["api_key"], "method": "getincidents"}
    if server.get("pin"):
        form["pin"] = server["pin"]
    resp = await client.post(url, data=form)
    raw = resp.json()
    # BHNM may wrap response in an outer array
    if isinstance(raw, list):
        return raw[0] if raw else {}
    return raw


async def _fetch_incident_detail(client: httpx.AsyncClient, server: dict, incident_id: str) -> dict:
    """Call getincidentdetail for one incident. Returns alarm_counts + alert_type."""
    url = f"{server['url'].rstrip('/')}/api/incident_api.php"
    form = {"pwd": server["api_key"], "method": "getincidentdetail", "incident_id": incident_id}
    if server.get("pin"):
        form["pin"] = server["pin"]
    try:
        resp = await client.post(url, data=form)
        data = resp.json()
        if isinstance(data, list):
            data = data[0] if data else {}
    except Exception as e:
        logger.warning("Failed to fetch detail for incident %s: %s", incident_id, e)
        return {"alarm_counts": None, "alert_type": "host"}

    incident = data.get("incident", {})
    detail = incident.get("detail", {})
    alert_type = (incident.get("alert_type") or "host").lower()

    alarm_entries = []
    for key in ("primary_alarm_log", "relatedalarms"):
        entries = detail.get(key)
        if isinstance(entries, list):
            alarm_entries.extend(entries)

    counts = {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 0}
    for alarm in alarm_entries:
        state = (alarm.get("state") or "").upper()
        if state in ("CRITICAL", "DOWN"):
            counts["red"] += 1
        elif state in ("MAJOR", "UNREACHABLE"):
            counts["orange"] += 1
        elif state in ("WARNING", "MINOR"):
            counts["yellow"] += 1
        elif state in ("OK", "RESOLVED", "CLOSED", "UP", "NORMAL", "RECOVERY", "CLEARED", "ALARMS CLEARED"):
            counts["green"] += 1
        elif state == "ACKNOWLEDGED":
            counts["blue"] += 1
        else:
            counts["red"] += 1  # unknown = worst case

    return {"alarm_counts": counts, "alert_type": alert_type}


# ── Enrichment: merge alarm details into incident list ───────────────────────

def _enrich_incident(incident: dict, detail: dict) -> dict:
    """Return a copy of the incident dict with alarm_counts and alert_type added."""
    enriched = dict(incident)
    enriched["alarm_counts"] = detail.get("alarm_counts")
    enriched["alert_type"] = detail.get("alert_type", "host")
    return enriched
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd middleware && python -m pytest tests/test_incident_cache.py -v
```

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd middleware && git add incident_cache.py tests/test_incident_cache.py
git commit -m "feat(middleware): add incident_cache module with storage and BHNM fetch helpers"
```

---

### Task 2: Add the background cache loop to incident_cache.py

**Files:**
- Modify: `middleware/incident_cache.py`
- Modify: `middleware/tests/test_incident_cache.py`

- [ ] **Step 1: Write test for cache loop cycle**

```python
# Append to middleware/tests/test_incident_cache.py
import asyncio
from unittest.mock import AsyncMock, patch

@pytest.mark.asyncio
async def test_cache_loop_populates_cache():
    """A single cycle should populate the cache with enriched incidents."""
    from incident_cache import _run_one_cycle, _cache, CachedIncidents

    server = {
        "id": "test", "url": "https://bhnm.test", "api_key": "k",
        "pin": "", "cache_refresh_seconds": 120,
    }

    mock_incidents_resp = {
        "active_incidents": [
            {"incident_id": "1", "title": "Down", "name": "router1",
             "incident_state": "OPEN", "open_time": "2026-04-09T06:00:00"}
        ],
        "closed_incidents": [],
    }
    mock_detail_resp = {
        "incident": {
            "alert_type": "Host",
            "detail": {
                "primary_alarm_log": [{"state": "CRITICAL"}],
                "relatedalarms": [{"state": "WARNING"}],
            },
        }
    }

    async def mock_post(url, data=None, **kw):
        resp = AsyncMock()
        if data.get("method") == "getincidents":
            resp.json.return_value = mock_incidents_resp
        else:
            resp.json.return_value = mock_detail_resp
        return resp

    mock_client = AsyncMock()
    mock_client.post = mock_post

    await _run_one_cycle(mock_client, server)

    cached = _cache.get("test")
    assert cached is not None
    assert len(cached.active_incidents) == 1
    enriched = cached.active_incidents[0]
    assert enriched["alarm_counts"] == {"red": 1, "orange": 0, "yellow": 1, "green": 0, "blue": 0}
    assert enriched["alert_type"] == "host"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd middleware && python -m pytest tests/test_incident_cache.py::test_cache_loop_populates_cache -v
```

Expected: FAIL — `_run_one_cycle` not defined.

- [ ] **Step 3: Implement `_run_one_cycle` and `_cache_loop`**

Append to `middleware/incident_cache.py`:

```python
# ── Cache loop ───────────────────────────────────────────────────────────────

async def _run_one_cycle(client: httpx.AsyncClient, server: dict) -> None:
    """Fetch all incidents for a server, enrich with alarm details, store in cache."""
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))

    try:
        data = await _fetch_incidents(client, server)
    except Exception as e:
        logger.error("[Cache:%s] Failed to fetch incidents: %s", server_id, e)
        return

    active_raw = data.get("active_incidents", [])
    closed_raw = data.get("closed_incidents", [])
    all_incidents = [(inc, "active") for inc in active_raw] + [(inc, "closed") for inc in closed_raw]

    n = len(all_incidents)
    delay = refresh / (n + 1) if n > 0 else refresh
    logger.info("[Cache:%s] Enriching %d incidents (pacing: %.1fs between calls)", server_id, n, delay)

    active_enriched = []
    closed_enriched = []

    for incident, bucket in all_incidents:
        inc_id = str(incident.get("incident_id", ""))
        if not inc_id:
            continue
        detail = await _fetch_incident_detail(client, server, inc_id)
        enriched = _enrich_incident(incident, detail)
        if bucket == "active":
            active_enriched.append(enriched)
        else:
            closed_enriched.append(enriched)
        if delay > 0.1:
            await asyncio.sleep(delay)

    _cache[server_id] = CachedIncidents(
        active_incidents=active_enriched,
        closed_incidents=closed_enriched,
        last_updated=time.time(),
    )
    logger.info("[Cache:%s] Cache updated: %d active, %d closed",
                server_id, len(active_enriched), len(closed_enriched))


async def _cache_loop(server: dict) -> None:
    """Continuous loop: run cycles back-to-back for one server."""
    server_id = server["id"]
    logger.info("[Cache:%s] Background loop started (refresh=%ds)", server_id, server.get("cache_refresh_seconds", 120))
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error("[Cache:%s] Cycle failed: %s", server_id, e)
                await asyncio.sleep(10)
```

- [ ] **Step 4: Run tests**

```bash
cd middleware && python -m pytest tests/test_incident_cache.py -v
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add middleware/incident_cache.py middleware/tests/test_incident_cache.py
git commit -m "feat(middleware): add background cache loop with paced BHNM fetching"
```

---

### Task 3: Add cache lifecycle management to incident_cache.py

**Files:**
- Modify: `middleware/incident_cache.py`

- [ ] **Step 1: Add `start_all`, `reload_server`, and `stop_server` functions**

Append to `middleware/incident_cache.py`:

```python
# ── Lifecycle ────────────────────────────────────────────────────────────────

def start_all() -> None:
    """Start cache loops for all enabled servers. Call from FastAPI lifespan."""
    for server in _load_enabled_servers():
        _start_server(server)


def reload_server(server_id: str) -> None:
    """Restart or stop the cache loop for a server based on current servers.json."""
    stop_server(server_id)
    servers = _load_enabled_servers()
    server = next((s for s in servers if s["id"] == server_id), None)
    if server:
        _start_server(server)
        logger.info("[Cache:%s] Reloaded", server_id)
    else:
        logger.info("[Cache:%s] Caching disabled or server removed — stopped", server_id)


def stop_server(server_id: str) -> None:
    """Stop the cache loop for a server and clear its cache."""
    task = _tasks.pop(server_id, None)
    if task and not task.done():
        task.cancel()
    _cache.pop(server_id, None)


def _start_server(server: dict) -> None:
    """Start a background cache loop for one server."""
    server_id = server["id"]
    if server_id in _tasks and not _tasks[server_id].done():
        return  # already running
    _tasks[server_id] = asyncio.create_task(_cache_loop(server))
    logger.info("[Cache:%s] Started background loop", server_id)
```

- [ ] **Step 2: Run all tests**

```bash
cd middleware && python -m pytest tests/test_incident_cache.py -v
```

Expected: all tests PASS (lifecycle functions don't need their own tests — they're thin wrappers tested via integration).

- [ ] **Step 3: Commit**

```bash
git add middleware/incident_cache.py
git commit -m "feat(middleware): add cache lifecycle management (start/stop/reload)"
```

---

### Task 4: Integrate cache into middleware main.py

**Files:**
- Modify: `middleware/main.py`

- [ ] **Step 1: Add import and start cache loops in lifespan**

At the top of `main.py`, add import:

```python
import incident_cache
```

Modify the lifespan handler (lines 128-132):

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    incident_cache.start_all()
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — dynamic multi-server routing enabled")
    yield
```

- [ ] **Step 2: Add the `/api/v1/incidents` endpoint**

Insert before the "BHNM Proxy — Dedicated Routes" section (before line 283):

```python
# ── Cached Incidents Endpoint ────────────────────────────────────────────────

@app.get("/api/v1/incidents")
@app.post("/api/v1/incidents")
async def cached_incidents(request: Request):
    """Return enriched incidents from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)

    # Resolve server: api_key from X-Proxy-Token → server_id → cache
    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = incident_cache._server_id_for_api_key(api_key)

    if server_id:
        cached = incident_cache.get_cached(server_id)
        if cached:
            return {
                "cache_age_seconds": round(time.time() - cached.last_updated),
                "active_incidents": cached.active_incidents,
                "closed_incidents": cached.closed_incidents,
            }

    # Cache cold or server not found — fall through to live BHNM
    return await _proxy_to_bhnm(request, "/api/incident_api.php")
```

Add `import time` to the imports at the top of `main.py`.

- [ ] **Step 3: Add the `/internal/cache/reload` endpoint**

Insert after the cached incidents endpoint:

```python
@app.post("/internal/cache/reload")
async def cache_reload(request: Request):
    """Trigger cache reload for a server. Called by admin portal."""
    try:
        body = await request.json()
    except Exception:
        body = {}
    server_id = body.get("server_id", "")
    if not server_id:
        raise HTTPException(status_code=400, detail="server_id is required")
    incident_cache.reload_server(server_id)
    return {"status": "ok", "server_id": server_id}
```

- [ ] **Step 4: Run tests and verify the server starts**

```bash
cd middleware && python -m pytest tests/ -v
```

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py
git commit -m "feat(middleware): integrate incident cache — new /api/v1/incidents and /internal/cache/reload endpoints"
```

---

### Task 5: Update Server dataclass and servers.py

**Files:**
- Modify: `middleware/benem-admin/servers.py`

- [ ] **Step 1: Add `cache_enabled` and `cache_refresh_seconds` to the Server dataclass**

Replace the current `Server` dataclass and `save_servers` function:

```python
@dataclass
class Server:
    id: str
    name: str
    url: str
    api_key: str
    pin: str = ""
    cache_enabled: bool = False
    cache_refresh_seconds: int = 120
```

Update `save_servers` to include the new fields:

```python
def save_servers(servers: list[Server]) -> None:
    """Write servers list to servers.json with file locking."""
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    data = [
        {"id": s.id, "name": s.name, "url": s.url, "api_key": s.api_key, "pin": s.pin,
         "cache_enabled": s.cache_enabled, "cache_refresh_seconds": s.cache_refresh_seconds}
        for s in servers
    ]
    with open(path, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            f.seek(0)
            json.dump(data, f, indent=2)
            f.write("\n")
            f.truncate()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
```

- [ ] **Step 2: Update `load_servers` to handle missing fields gracefully**

The existing `load_servers` uses `Server(**s)` which will work because the new fields have defaults. But servers.json files without these fields would fail if extra keys exist. Actually `Server(**s)` will raise `TypeError` if `s` contains unknown keys from old format — but since old format has no extra keys this is fine. The new fields just get defaults.

No change needed — the defaults handle backward compatibility.

- [ ] **Step 3: Run existing admin tests (if any) and verify**

```bash
cd middleware/benem-admin && python -c "from servers import load_servers, Server; print(Server(id='t', name='t', url='t', api_key='t'))"
```

Expected: prints `Server(id='t', name='t', url='t', api_key='t', pin='', cache_enabled=False, cache_refresh_seconds=120)`

- [ ] **Step 4: Commit**

```bash
git add middleware/benem-admin/servers.py
git commit -m "feat(admin): add cache_enabled and cache_refresh_seconds to Server dataclass"
```

---

### Task 6: Update admin portal — server form with cache toggle

**Files:**
- Modify: `middleware/benem-admin/templates/_server_form.html`
- Modify: `middleware/benem-admin/templates/_server_card.html`
- Modify: `middleware/benem-admin/main.py`

- [ ] **Step 1: Add cache fields to the server form template**

In `_server_form.html`, insert before the `<div style="display:flex;gap:8px;">` (save/cancel buttons), after the PIN field:

```html
    <div class="form-group" style="display:flex;align-items:center;gap:10px;">
      <label style="margin:0;">Incident Cache</label>
      <label class="switch">
        <input type="checkbox" name="cache_enabled" value="1"
               {% if s.cache_enabled %}checked{% endif %}
               onchange="document.getElementById('cache-interval-{{ s.id or 'new' }}').style.display = this.checked ? 'flex' : 'none'">
        <span class="slider"></span>
      </label>
    </div>
    <div class="form-group" id="cache-interval-{{ s.id or 'new' }}"
         style="display:{{ 'flex' if s.cache_enabled else 'none' }};align-items:center;gap:10px;">
      <label style="margin:0;">Refresh interval</label>
      <input type="number" name="cache_refresh_seconds" value="{{ s.cache_refresh_seconds }}"
             min="60" max="900" step="10" style="width:80px;" class="mono">
      <span style="color:var(--text-dim);font-size:12px;">seconds (60–900)</span>
    </div>
```

- [ ] **Step 2: Add cache info to the server card template**

In `_server_card.html`, add a line to the `<dl class="info">` section, after the PIN row:

```html
    <div>
      <dt>Cache</dt>
      <dd>{{ 'Enabled (' + s.cache_refresh_seconds|string + 's)' if s.cache_enabled else 'Disabled' }}</dd>
    </div>
```

- [ ] **Step 3: Update admin `server_add` and `server_edit` routes to accept cache fields**

In `benem-admin/main.py`, update `server_add` (line 418):

Add parameters:
```python
    cache_enabled: str = Form(""),
    cache_refresh_seconds: int = Form(120),
```

Update the `Server` construction:
```python
    cache_on = cache_enabled == "1"
    refresh = max(60, min(900, cache_refresh_seconds))
    new_server = Server(id=id, name=name, url=url, api_key=api_key, pin=pin,
                        cache_enabled=cache_on, cache_refresh_seconds=refresh)
```

Similarly update `server_edit` (line 461) — add the same parameters and update:
```python
    cache_on = cache_enabled == "1"
    refresh = max(60, min(900, cache_refresh_seconds))
    servers[idx] = Server(id=id, name=name, url=url, api_key=api_key, pin=pin,
                          cache_enabled=cache_on, cache_refresh_seconds=refresh)
```

- [ ] **Step 4: Verify by starting admin portal locally (visual check)**

```bash
cd middleware/benem-admin && python -c "from servers import Server; s=Server(id='t',name='T',url='u',api_key='k',cache_enabled=True,cache_refresh_seconds=120); print(s)"
```

- [ ] **Step 5: Commit**

```bash
git add middleware/benem-admin/templates/_server_form.html middleware/benem-admin/templates/_server_card.html middleware/benem-admin/main.py
git commit -m "feat(admin): add incident cache toggle and refresh interval to server management"
```

---

### Task 7: Admin portal — trigger middleware cache reload

**Files:**
- Modify: `middleware/benem-admin/main.py`

- [ ] **Step 1: Add helper function to notify middleware**

Add near the top of `benem-admin/main.py`, after the existing constants (around line 39):

```python
MIDDLEWARE_INTERNAL_URL = os.environ.get("MIDDLEWARE_INTERNAL_URL", "http://benem-middleware:8889")


async def _notify_cache_reload(server_id: str) -> None:
    """Tell the middleware to reload the cache for a server. Best-effort."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(
                f"{MIDDLEWARE_INTERNAL_URL}/internal/cache/reload",
                json={"server_id": server_id},
            )
    except Exception as e:
        print(f"[Admin] Failed to notify middleware cache reload for {server_id}: {e}")
```

- [ ] **Step 2: Call `_notify_cache_reload` in server_add**

After `save_servers(servers)` in `server_add` (around line 455), add:

```python
    await _notify_cache_reload(id)
```

Also make the route handler `async`:

```python
@app.post("/admin/settings/servers/add", response_class=HTMLResponse)
async def server_add(
```

- [ ] **Step 3: Call `_notify_cache_reload` in server_edit**

After `save_servers(servers)` in `server_edit` (around line 504), add:

```python
    await _notify_cache_reload(id)
```

Make it async:

```python
@app.post("/admin/settings/servers/edit", response_class=HTMLResponse)
async def server_edit(
```

- [ ] **Step 4: Call `_notify_cache_reload` in server_delete**

After `save_servers(servers)` in `server_delete` (around line 519), add:

```python
    await _notify_cache_reload(server_id)
```

Make it async:

```python
@app.post("/admin/settings/servers/delete", response_class=HTMLResponse)
async def server_delete(request: Request, server_id: str = Form(...)):
```

- [ ] **Step 5: Commit**

```bash
git add middleware/benem-admin/main.py
git commit -m "feat(admin): notify middleware to reload cache on server add/edit/delete"
```

---

### Task 8: iOS — add cached incidents fetch method

**Files:**
- Modify: `ios/BeNeM/Services/NetreoAPIService.swift`

- [ ] **Step 1: Add `fetchCachedIncidents` method**

Insert after the existing `fetchIncidents()` method (after line 786):

```swift
    /// Fetches enriched incidents from the middleware cache endpoint.
    /// Returns (incidents, alarmCounts) — alarm_counts may be nil per incident if cache is cold.
    func fetchCachedIncidents() async throws -> ([NetreoIncident], [String: [AlarmColor: Int]]) {
        guard let url = URL(string: "\(configuration.baseURL)/api/v1/incidents") else {
            throw APIError.configurationError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addProxyToken(&request)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            // Fall back to legacy if middleware doesn't support cached endpoint
            let incidents = try await fetchIncidents()
            return (incidents, [:])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        // If response is a proxied BHNM response (cache cold), it has no cache_age_seconds
        let isCached = json["cache_age_seconds"] != nil

        var incidents: [NetreoIncident] = []
        var alarmCounts: [String: [AlarmColor: Int]] = [:]

        if let activeArray = json["active_incidents"] as? [[String: Any]] {
            let parsed = try parseIncidentsFromNetreoFormat(from: activeArray, defaultStatus: nil)
            incidents.append(contentsOf: parsed)

            if isCached {
                for (i, raw) in activeArray.enumerated() where i < parsed.count {
                    if let counts = raw["alarm_counts"] as? [String: Int] {
                        alarmCounts[parsed[i].incidentID] = parseAlarmCounts(counts)
                    }
                }
            }
        }
        if let closedArray = json["closed_incidents"] as? [[String: Any]] {
            let parsed = try parseIncidentsFromNetreoFormat(from: closedArray, defaultStatus: .resolved)
            incidents.append(contentsOf: parsed)

            if isCached {
                for (i, raw) in closedArray.enumerated() where i < parsed.count {
                    if let counts = raw["alarm_counts"] as? [String: Int] {
                        alarmCounts[parsed[i].incidentID] = parseAlarmCounts(counts)
                    }
                }
            }
        }

        return (incidents, alarmCounts)
    }

    /// Convert {"red": 2, "orange": 1, ...} dict to [AlarmColor: Int]
    private func parseAlarmCounts(_ raw: [String: Int]) -> [AlarmColor: Int] {
        var result: [AlarmColor: Int] = [:]
        for (key, value) in raw {
            if let color = AlarmColor(rawValue: key) {
                result[color] = value
            }
        }
        return result
    }
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/Services/NetreoAPIService.swift
git commit -m "feat(ios): add fetchCachedIncidents method for enriched middleware response"
```

---

### Task 9: iOS — update IncidentListViewModel to use cached endpoint

**Files:**
- Modify: `ios/BeNeM/ViewModels/IncidentListViewModel.swift`

- [ ] **Step 1: Update `loadIncidents()` to use the cached endpoint**

Replace the `loadIncidents()` method (lines 101-144):

```swift
    func loadIncidents() async {
        #if DEBUG
        print("IncidentListViewModel: Starting to load incidents")
        #endif

        if await MainActor.run(body: { isLoading }) {
            #if DEBUG
            print("IncidentListViewModel: Already loading, skipping")
            #endif
            return
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let (fetchedIncidents, cachedAlarmCounts) = try await apiService.fetchCachedIncidents()
            #if DEBUG
            print("IncidentListViewModel: Received \(fetchedIncidents.count) incidents, \(cachedAlarmCounts.count) cached alarm counts")
            #endif

            await MainActor.run {
                let newIDs = Set(fetchedIncidents.map(\.incidentID))
                alarmCounts = alarmCounts.filter { newIDs.contains($0.key) }
                // Merge cached alarm counts
                for (id, counts) in cachedAlarmCounts {
                    alarmCounts[id] = counts
                }
                incidents = fetchedIncidents
                isLoading = false
            }
            // Only fetch individual alarm counts for incidents missing from cache
            let missingIDs = fetchedIncidents.filter { cachedAlarmCounts[$0.incidentID] == nil }.map(\.incidentID)
            if !missingIDs.isEmpty {
                #if DEBUG
                print("IncidentListViewModel: Fetching alarm counts for \(missingIDs.count) uncached incidents")
                #endif
                await loadAlarmCounts(for: missingIDs)
            }
        } catch {
            #if DEBUG
            let detail = "\(error)"
            print("IncidentListViewModel: Error loading incidents: \(detail)")
            #endif
            UserDefaults.standard.set("\(error)", forKey: "debug_incident_error")
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
```

- [ ] **Step 2: Update `loadAlarmCounts` to accept a filtered list of IDs**

Replace the `loadAlarmCounts()` method (lines 150-156):

```swift
    func loadAlarmCounts(for incidentIDs: [String]? = nil) async {
        let currentIncidents = await MainActor.run { incidents }
        let toFetch = incidentIDs.map { ids in currentIncidents.filter { ids.contains($0.incidentID) } } ?? currentIncidents
        for incident in toFetch {
            let counts = (try? await apiService.fetchIncidentAlarmCounts(incidentID: incident.incidentID)) ?? [:]
            await MainActor.run { alarmCounts[incident.incidentID] = counts }
        }
    }
```

- [ ] **Step 3: Build and deploy**

```bash
cd ios && bash build_and_deploy.sh 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED` and `App installed.`

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/ViewModels/IncidentListViewModel.swift
git commit -m "feat(ios): use cached incidents endpoint, fall back to per-incident fetch for uncached"
```

---

### Task 10: CSS for the toggle switch in admin portal

**Files:**
- Modify: `middleware/benem-admin/static/style.css` (or equivalent)

- [ ] **Step 1: Check if a toggle switch CSS already exists**

```bash
grep -r "switch\|slider\|toggle" middleware/benem-admin/static/ 2>/dev/null || echo "No toggle CSS found"
```

- [ ] **Step 2: If no toggle CSS exists, add it**

Add to the admin stylesheet:

```css
/* Toggle switch */
.switch { position:relative; display:inline-block; width:40px; height:22px; }
.switch input { opacity:0; width:0; height:0; }
.switch .slider {
    position:absolute; cursor:pointer; inset:0;
    background:var(--border); border-radius:22px; transition:0.2s;
}
.switch .slider::before {
    content:""; position:absolute; height:16px; width:16px;
    left:3px; bottom:3px; background:white; border-radius:50%; transition:0.2s;
}
.switch input:checked + .slider { background:var(--accent); }
.switch input:checked + .slider::before { transform:translateX(18px); }
```

- [ ] **Step 3: Commit**

```bash
git add middleware/benem-admin/static/
git commit -m "feat(admin): add toggle switch CSS for cache enable/disable"
```

---

### Task 11: End-to-end verification

**Files:** None (testing only)

- [ ] **Step 1: Deploy middleware and admin**

```bash
cd middleware && docker compose build && docker compose up -d
```

- [ ] **Step 2: Enable caching for the test server via admin portal**

Open admin portal → Settings → Edit the test server → Enable "Incident Cache" with 120s interval → Save.

- [ ] **Step 3: Verify middleware logs show cache loop starting**

```bash
docker logs benem-middleware 2>&1 | grep -i cache | tail -20
```

Expected: logs showing `[Cache:test] Background loop started` and `[Cache:test] Enriching N incidents`.

- [ ] **Step 4: Test the cached endpoint directly**

```bash
curl -s -H "X-Proxy-Token: <api_key>" https://bhnm-apns.hurrikap.org/api/v1/incidents | python3 -m json.tool | head -30
```

Expected: JSON with `cache_age_seconds`, `active_incidents` containing `alarm_counts` per incident.

- [ ] **Step 5: Verify on iOS app**

Open the Incidents screen on the test device. Incidents and alarm badges should load almost instantly.

- [ ] **Step 6: Commit all remaining changes and bump versions**

```bash
# Bump middleware version
cd middleware && sed -i '' 's/VERSION = "2.4.0"/VERSION = "2.5.0"/' main.py

# Bump admin version
cd benem-admin && sed -i '' 's/VERSION = "1.5.0"/VERSION = "1.6.0"/' main.py

git add -A && git commit -m "feat: middleware incident cache — enriched incidents in a single response

Pre-caches BHNM incidents with alarm details server-side.
Clients get everything in one fast response instead of N+1 API calls.
Configurable per server via admin portal toggle."
```
