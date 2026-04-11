"""Background threshold count cache for BHNM servers.

Pre-fetches the threshold CSV (all devices, all thresholds) and
stores per-device counts in memory.  One asyncio.Task per enabled server.

The CSV endpoint returns one row per threshold, so for 10,000 devices
this could be 500K+ rows.  Parsing server-side in Python and serving a
compact JSON dict to PWA clients avoids transferring large CSV payloads
to each browser.
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
class CachedThresholds:
    """Threshold counts per device name for one server."""
    counts: dict[str, int] = field(default_factory=dict)  # deviceName -> count
    last_updated: float = 0.0


_cache: dict[str, CachedThresholds] = {}
_tasks: dict[str, asyncio.Task] = {}


def get_cached(server_id: str) -> CachedThresholds | None:
    entry = _cache.get(server_id)
    if entry and entry.last_updated > 0:
        return entry
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

async def _fetch_threshold_counts(
    client: httpx.AsyncClient,
    server: dict,
) -> dict[str, int]:
    """Fetch list-thresholds-csv, parse it, return {deviceName: count}."""
    url = f"{server['url'].rstrip('/')}/fw/index.php?r=restful/devices/list-thresholds-csv"
    form: dict[str, str] = {"password": server["api_key"]}
    if server.get("pin"):
        form["pin"] = server["pin"]

    resp = await client.post(url, data=form)
    text = resp.text

    counts: dict[str, int] = {}
    lines = text.splitlines()
    # Skip header: Description,Action_Group,Renotify_Interval,Esc_Group,Device_Name,IP,...
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(",")
        if len(parts) >= 5:
            device_name = parts[4].strip()
            if device_name:
                counts[device_name] = counts.get(device_name, 0) + 1

    return counts


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client: httpx.AsyncClient, server: dict) -> None:
    server_id = server["id"]
    try:
        counts = await _fetch_threshold_counts(client, server)
        _cache[server_id] = CachedThresholds(counts=counts, last_updated=time.time())
        print(
            f"[ThresholdCache:{server_id}] Cache updated: "
            f"{len(counts)} devices, {sum(counts.values())} total thresholds"
        )
    except Exception as e:
        print(f"[ThresholdCache:{server_id}] Failed to fetch thresholds: {e}")


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))
    print(f"[ThresholdCache:{server_id}] Background loop started (refresh={refresh}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[ThresholdCache:{server_id}] Cycle failed: {e}")
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
        print(f"[ThresholdCache:{server_id}] Reloaded")
    else:
        print(f"[ThresholdCache:{server_id}] Caching disabled or server removed — stopped")


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
    print(f"[ThresholdCache:{server_id}] Started background loop")
