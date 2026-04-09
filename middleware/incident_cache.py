"""Background incident cache for BHNM servers.

Pre-fetches incidents and their alarm details, stores enriched results
in memory.  One asyncio.Task per enabled server, paced to avoid overload.
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field

import httpx

from config import SERVERS_JSON_PATH, BHNM_TLS_VERIFY, PROXY_TIMEOUT

# -- Cache storage -------------------------------------------------------------

@dataclass
class CachedIncidents:
    active_incidents: list[dict] = field(default_factory=list)
    closed_incidents: list[dict] = field(default_factory=list)
    last_updated: float = 0.0

_cache: dict[str, CachedIncidents] = {}
_tasks: dict[str, asyncio.Task] = {}


def get_cached(server_id: str) -> CachedIncidents | None:
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


def _server_id_for_bhnm_url(bhnm_url: str) -> str:
    """Look up server ID by BHNM URL from servers.json."""
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


# -- BHNM fetch helpers -------------------------------------------------------

async def _fetch_incidents(client: httpx.AsyncClient, server: dict) -> dict:
    url = f"{server['url'].rstrip('/')}/api/incident_api.php"
    form = {"pwd": server["api_key"], "method": "getincidents"}
    if server.get("pin"):
        form["pin"] = server["pin"]
    resp = await client.post(url, data=form)
    raw = resp.json()
    if isinstance(raw, list):
        return raw[0] if raw else {}
    return raw


async def _fetch_incident_detail(client: httpx.AsyncClient, server: dict, incident_id: str) -> dict:
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
        print(f"[Cache] Failed to fetch detail for incident {incident_id}: {e}")
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
            counts["red"] += 1

    return {"alarm_counts": counts, "alert_type": alert_type}


def _enrich_incident(incident: dict, detail: dict) -> dict:
    enriched = dict(incident)
    enriched["alarm_counts"] = detail.get("alarm_counts")
    enriched["alert_type"] = detail.get("alert_type", "host")
    return enriched


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client: httpx.AsyncClient, server: dict) -> None:
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))

    try:
        data = await _fetch_incidents(client, server)
    except Exception as e:
        print(f"[Cache:{server_id}] Failed to fetch incidents: {e}")
        return

    active_raw = data.get("active_incidents", [])
    closed_raw = data.get("closed_incidents", [])
    all_incidents = [(inc, "active") for inc in active_raw] + [(inc, "closed") for inc in closed_raw]

    n = len(all_incidents)
    delay = refresh / (n + 1) if n > 0 else refresh
    print(f"[Cache:{server_id}] Enriching {n} incidents (pacing: {delay:.1f}s between calls)")

    active_enriched = []
    closed_enriched = []

    for i, (incident, bucket) in enumerate(all_incidents):
        inc_id = str(incident.get("incident_id", ""))
        if not inc_id:
            continue
        try:
            detail = await _fetch_incident_detail(client, server, inc_id)
        except Exception as e:
            print(f"[Cache:{server_id}] Error fetching detail for incident {inc_id}: {e}")
            detail = {"alarm_counts": None, "alert_type": "host"}
        enriched = _enrich_incident(incident, detail)
        if bucket == "active":
            active_enriched.append(enriched)
        else:
            closed_enriched.append(enriched)
        if (i + 1) % 20 == 0:
            print(f"[Cache:{server_id}] Progress: {i + 1}/{n}")
        if delay > 0.1:
            await asyncio.sleep(delay)

    _cache[server_id] = CachedIncidents(
        active_incidents=active_enriched,
        closed_incidents=closed_enriched,
        last_updated=time.time(),
    )
    print(f"[Cache:{server_id}] Cache updated: {len(active_enriched)} active, {len(closed_enriched)} closed")


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    print(f"[Cache:{server_id}] Background loop started (refresh={server.get('cache_refresh_seconds', 120)}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[Cache:{server_id}] Cycle failed: {e}")
                await asyncio.sleep(10)


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
        print(f"[Cache:{server_id}] Reloaded")
    else:
        print(f"[Cache:{server_id}] Caching disabled or server removed — stopped")


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
    print(f"[Cache:{server_id}] Started background loop")
