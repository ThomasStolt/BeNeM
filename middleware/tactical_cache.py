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
