"""Background maintenance map cache for BHNM servers.

Twin of threshold_cache.py. Pre-fetches which devices are currently in a
maintenance window by iterating categories (the only bulk path — see
docs/superpowers/specs/2026-09-02-maintenance-list-badges-design.md) and
stores two NAME lists per server: devices in maintenance, and devices whose
host row BHNM reports as DOWN (Wave B, spec 2026-09-03-host-status-overlay).
One asyncio.Task per enabled server.

Only names are stored — never a full map. For maintenance the UI renders
"in the set" and nothing else; for host state it renders "in the DOWN set"
as red and falls back to its own rule otherwise (UP is never served: the
fallback already paints monitored devices green). A device absent from
both sets (unmonitored, unknown literal, or on BHNM < 26.3.01 where the
inMaintenance field doesn't exist) shows no state, never a wrong one.
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

# Documented host_only domain (API v1.0.9), wire-confirmed 2026-09-03 (see
# docs/evidence/2026-09-03-bhnm-host-status-down-row.md). Exact literal or
# nothing — an unknown literal is neither counted nor listed, never coerced.
HOST_STATUS_LITERALS = frozenset({"UP", "DOWN"})


# -- Cache storage -------------------------------------------------------------

@dataclass
class CachedMaintenance:
    """Per-server snapshot: in-maintenance names + names whose host row is DOWN."""
    names: set[str] = field(default_factory=set)
    down: set[str] = field(default_factory=set)      # deviceName with host status "DOWN"
    host_rows: int = 0                               # rows classified UP/DOWN by the last crawl (diagnostics count)
    last_updated: float = 0.0


_cache: dict[str, CachedMaintenance] = {}
_tasks: dict[str, asyncio.Task] = {}

# -- Scheduled-window registry --------------------------------------------------
# BHNM has no list-scheduled API (action=list is active-only), but every app
# create flows through this middleware — so it remembers its own creates and
# serves them to ALL clients, keeping every user's "scheduled" blink in sync.
# In-memory on purpose: the snapped start is at most ~5 min out, so a restart
# merely degrades one window to creator-only visibility. Windows created
# directly in the BHNM UI stay invisible until active (no API for them).

SCHEDULED_GRACE = 4 * 60  # keep past start until the active set takes over

_scheduled: dict[str, dict[str, dict]] = {}  # server_id -> name -> {start_time, end_time}


def note_scheduled(server_id: str, name: str, start_time: int, end_time: int) -> None:
    _scheduled.setdefault(server_id, {})[name] = {
        "start_time": start_time, "end_time": end_time,
    }


def clear_scheduled(server_id: str, name: str) -> None:
    _scheduled.get(server_id, {}).pop(name, None)


def get_scheduled(server_id: str, active_names: set[str]) -> list[dict]:
    """Pending windows for one server, pruned: gone once active or once the
    start is more than SCHEDULED_GRACE in the past."""
    entries = _scheduled.get(server_id, {})
    now = time.time()
    for name in [n for n, e in entries.items() if e["start_time"] + SCHEDULED_GRACE < now]:
        del entries[name]
    return [
        {"name": name, **e}
        for name, e in sorted(entries.items())
        if name not in active_names
    ]


def get_cached(server_id: str) -> CachedMaintenance | None:
    entry = _cache.get(server_id)
    if entry and entry.last_updated > 0:
        return entry
    return None


# -- BHNM fetch ---------------------------------------------------------------

async def _fetch_in_maintenance(client, server: dict) -> tuple[set[str], set[str], int]:
    """Iterate categories → one bulk host-status call each (paged) →
    (names with inMaintenance == True, names with status == "DOWN",
    number of host rows whose status was a known literal)."""
    base = server["url"].rstrip("/")
    password = server["api_key"]
    pin = server.get("pin")

    form: dict[str, str] = {"password": password}
    if pin:
        form["pin"] = pin
    resp = await client.post(f"{base}/fw/index.php?r=restful/category/list", data=form)
    categories = resp.json() or []

    names: set[str] = set()
    down: set[str] = set()
    ignored: set[str] = set()   # status literals that are neither UP nor DOWN
    host_rows = 0
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
                name = row.get("deviceName")
                if not isinstance(name, str) or not name:
                    continue   # nameless or non-string names can never match a client row
                # Version gate: only rows that actually carry the field count
                if row.get("inMaintenance") is True:
                    names.add(name)
                status = row.get("status")
                if isinstance(status, str) and status in HOST_STATUS_LITERALS:
                    host_rows += 1
                    if status == "DOWN":
                        down.add(name)
                elif status is not None:
                    ignored.add(str(status))   # null is dropped silently
            start += len(rows)
            total = int(data.get("totalRecords", 0) or 0)
            if not rows or start >= total:
                break
    if ignored:
        # One line per cycle, only when something unknown showed up — the
        # signal that BHNM has a host state this code does not know.
        print(f"[MaintenanceCache:{server['id']}] host rows: ignored literals {sorted(ignored)}")
    return names, down, host_rows


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client, server: dict) -> None:
    """Record-don't-raise: a failed cycle keeps the previous set."""
    server_id = server["id"]
    started = time.perf_counter()
    try:
        names, down, host_rows = await _fetch_in_maintenance(client, server)
        _cache[server_id] = CachedMaintenance(names=names, down=down, host_rows=host_rows,
                                              last_updated=time.time())
        diagnostics.record_success(server_id, "maintenance_map",
                                   round((time.perf_counter() - started) * 1000))
        # host_rows is on-call visibility: a crawl that suddenly sees 0 host
        # rows (permission/filter change) would otherwise look healthy.
        print(f"[MaintenanceCache:{server_id}] Cache updated: {len(names)} in maintenance, "
              f"{host_rows} host rows, {len(down)} down")
    except Exception as e:
        diagnostics.record_failure(server_id, "maintenance_map", e)
        print(f"[MaintenanceCache:{server_id}] Fetch failed (previous set kept): {e}")


def _refresh_interval(server: dict) -> int:
    """Fixed 60s: the map drives visible UI freshness (list wrenches), so it
    does not inherit the per-server cache_refresh_seconds (up to 900s).
    Cost is bounded: 1 + #categories cheap calls per minute per server."""
    return 60


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    refresh = _refresh_interval(server)
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
