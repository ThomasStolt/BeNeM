"""Background maintenance map cache for BHNM servers.

Twin of threshold_cache.py. Pre-fetches which devices are currently in a
maintenance window by iterating categories (the only bulk path — see
docs/superpowers/specs/2026-09-02-maintenance-list-badges-design.md) and
stores the in-maintenance device NAMES per server. One asyncio.Task per
enabled server.

Only names are stored: the UI renders "in the set" and nothing else — a
device absent from the set (unmonitored, unknown, or on BHNM < 26.3.01
where the inMaintenance field doesn't exist) shows no state, never a wrong
one.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field

import httpx
import diagnostics

from config import BHNM_TLS_VERIFY, PROXY_TIMEOUT
from threshold_cache import (
    _load_enabled_servers,
    _server_id_for_api_key,
    _server_id_for_bhnm_url,
)

# re-exported for main.py's server resolution symmetry
__all__ = [
    "CachedMaintenance", "get_cached", "start_all", "reload_server",
    "stop_server", "_server_id_for_api_key", "_server_id_for_bhnm_url",
]

PAGE_SIZE = 500  # per-category status page size


# -- Cache storage -------------------------------------------------------------

@dataclass
class CachedMaintenance:
    """In-maintenance device names for one server."""
    names: set[str] = field(default_factory=set)
    last_updated: float = 0.0


_cache: dict[str, CachedMaintenance] = {}
_tasks: dict[str, asyncio.Task] = {}


def get_cached(server_id: str) -> CachedMaintenance | None:
    entry = _cache.get(server_id)
    if entry and entry.last_updated > 0:
        return entry
    return None


# -- BHNM fetch ---------------------------------------------------------------

async def _fetch_in_maintenance(client, server: dict) -> set[str]:
    """Iterate categories → one bulk host-status call each (paged) →
    the set of device names whose host row carries inMaintenance == True."""
    base = server["url"].rstrip("/")
    password = server["api_key"]
    pin = server.get("pin")

    form: dict[str, str] = {"password": password}
    if pin:
        form["pin"] = pin
    resp = await client.post(f"{base}/fw/index.php?r=restful/category/list", data=form)
    categories = resp.json() or []

    names: set[str] = set()
    for cat in categories:
        cat_name = cat.get("name", "")
        if not cat_name:
            continue
        start = 0
        while True:
            page_form: dict[str, str] = {
                "password": password,
                "groupFilterBy": "category",
                # Category NAME, not id — ids give "Bad input parameter"
                "groupFilterValue": cat_name,
                "serviceFilter": "host_only",
                "recordCount": str(PAGE_SIZE),
                "recordStart": str(start),
            }
            if pin:
                page_form["pin"] = pin
            resp = await client.post(
                f"{base}/fw/index.php?r=restful/devices/get-host-and-service-status",
                data=page_form,
            )
            data = resp.json() or {}
            rows = data.get("statuses", []) or []
            for row in rows:
                # Version gate: only rows that actually carry the field count
                if row.get("inMaintenance") is True and row.get("deviceName"):
                    names.add(row["deviceName"])
            start += len(rows)
            total = int(data.get("totalRecords", 0) or 0)
            if not rows or start >= total:
                break
    return names


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client, server: dict) -> None:
    """Record-don't-raise: a failed cycle keeps the previous set."""
    server_id = server["id"]
    started = time.perf_counter()
    try:
        names = await _fetch_in_maintenance(client, server)
        _cache[server_id] = CachedMaintenance(names=names, last_updated=time.time())
        diagnostics.record_success(server_id, "maintenance_map",
                                   round((time.perf_counter() - started) * 1000))
        print(f"[MaintenanceCache:{server_id}] Cache updated: {len(names)} in maintenance")
    except Exception as e:
        diagnostics.record_failure(server_id, "maintenance_map", e)
        print(f"[MaintenanceCache:{server_id}] Fetch failed (previous set kept): {e}")


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))
    print(f"[MaintenanceCache:{server_id}] Background loop started (refresh={refresh}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[MaintenanceCache:{server_id}] Cycle failed: {e}")
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
        print(f"[MaintenanceCache:{server_id}] Reloaded")
    else:
        print(f"[MaintenanceCache:{server_id}] Caching disabled or server removed — stopped")


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
    print(f"[MaintenanceCache:{server_id}] Started background loop")
