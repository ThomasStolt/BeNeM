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
import database
import diagnostics

from config import SERVERS_JSON_PATH, BHNM_TLS_VERIFY, PROXY_TIMEOUT, server_cache_enabled

# -- Cache storage -------------------------------------------------------------

@dataclass
class CachedIncidents:
    active_incidents: list[dict] = field(default_factory=list)
    closed_incidents: list[dict] = field(default_factory=list)
    last_updated: float = 0.0
    # C9 — the list call and the enrichment are DIFFERENT FACTS with different
    # costs, and merging them into one stamp is what let diagnostics report
    # "age 0" for data a whole cycle old (2026-09-16 measurement: 110.5 s of
    # understatement in a 9-incident lab). getincidents is one request whatever
    # the estate size; enrichment is one request per incident. So this is the
    # time of the last successful LIST call, and every incident carries its own
    # counts_confirmed_at beside it.
    list_updated: float = 0.0

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
            return [s for s in json.load(f) if server_cache_enabled(s)]
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
        # confirmed=False is what C9 reads. The "host" default is a KNOWN DEFECT
        # (C11) and is deliberately left in place until the clients that render
        # UNKNOWN are in the field — build order step 6, after the store release.
        # Until then the row lies about its type and tells the truth about its age.
        return {"alarm_counts": None, "alert_type": "host", "confirmed": False}

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

    return {"alarm_counts": counts, "alert_type": alert_type, "confirmed": True}


# -- C10: the incident type map -------------------------------------------------
# alert_type is immutable per incident [THOMAS 2026-09-19] and cannot be derived
# from the title, so it is learned once from a confirmed detail call and kept.
# The working copy is in memory; sqlite is what survives a restart.
#
# ponytail: a plain dict, loaded once. Known ceiling: it is per-process, so two
# middleware replicas would each learn independently — which is harmless, they
# would converge on the same values. Revisit only if this ever runs replicated.

_types: dict[tuple[str, str], str] = {}
_types_loaded = False


def load_types() -> None:
    """Read the persisted map into memory. Called once at startup; a failure is
    logged and degrades to an empty map, never to a crash — a cold type map costs
    detail calls, a dead cache costs the product."""
    global _types, _types_loaded
    try:
        _types = database.load_incident_types()
        print(f"[Cache] Type map loaded: {len(_types)} incidents")
    except Exception as e:
        print(f"[Cache] Type map load FAILED, starting cold: {e}")
        _types = {}
    _types_loaded = True


def known_type(server_id: str, incident_id: str) -> str | None:
    return _types.get((server_id, str(incident_id)))


def remember_type(server_id: str, incident_id: str, alert_type: str) -> None:
    """Only ever called with a type from a CONFIRMED detail call. A persisted
    guess is a guess that outlives the process that made it."""
    key = (server_id, str(incident_id))
    if _types.get(key) == alert_type:
        return  # no write, no churn — the common case by far
    _types[key] = alert_type
    try:
        database.save_incident_type(server_id, str(incident_id), alert_type)
    except Exception as e:
        print(f"[Cache:{server_id}] Type map write failed for incident {incident_id}: {e}")


def _enrich_incident(incident: dict, detail: dict, list_at: float,
                     remembered: str | None = None) -> dict:
    enriched = dict(incident)
    enriched["alarm_counts"] = detail.get("alarm_counts")
    if detail.get("confirmed"):
        enriched["alert_type"] = detail.get("alert_type", "host")
    else:
        # C10 — a type learned earlier from a confirmed call is a FACT, and using
        # it beats re-guessing "host". If nothing was ever learned, today's "host"
        # default stands: it is a known defect (C11) and it may not become UNKNOWN
        # until the clients that render UNKNOWN are in the field (step 6).
        enriched["alert_type"] = remembered or detail.get("alert_type", "host")
    # C9 — two facts, two stamps. State came from the list call at list_at.
    # Counts came from the detail call, which may have failed or may not have
    # run at all, in which case there is NO time at which they were confirmed
    # and null says exactly that. Never substitute list_at here: that would be
    # the whole defect back again, a confirmed stamp on an unconfirmed value.
    enriched["state_confirmed_at"] = list_at
    enriched["counts_confirmed_at"] = time.time() if detail.get("confirmed") else None
    return enriched


def freshness(entry: CachedIncidents) -> tuple[float | None, int]:
    """(oldest counts_confirmed_at, how many incidents have none).

    A cache is as fresh as its STALEST member, so this is what diagnostics
    reports — never the newest. An incident that has never been enriched has no
    age at all: it is counted separately rather than folded in, because "not yet
    confirmed" is a third state and must not be rendered as a large-but-finite
    age. Root CLAUDE.md doctrine, applied to a number instead of an icon.
    """
    oldest = None
    unconfirmed = 0
    for inc in (*entry.active_incidents, *entry.closed_incidents):
        ts = inc.get("counts_confirmed_at")
        if ts is None:
            unconfirmed += 1
        elif oldest is None or ts < oldest:
            oldest = ts
    return oldest, unconfirmed


# -- Ack state overrides --------------------------------------------------------
# The cached list is a snapshot up to ~2 cache cycles old, so a successful
# ACK/UnACK through the proxy patches the cache immediately (clients see it on
# their next fetch) and the override shields the patch from being reverted by
# an in-flight cycle whose getincidents snapshot predates the ack.

STATE_OVERRIDE_TTL = 300  # BHNM reflects acks in getincidents instantly; 5 min covers two cycles

_state_overrides: dict[str, dict[str, tuple[str, float]]] = {}  # server -> incident_id -> (state, ts)

# Overrides for incidents no cache has seen yet, keyed by incident id alone.
# An incident acknowledged before its first cache cycle — someone woken, looking,
# and acking inside two minutes, which is the normal case for a paging product —
# used to be dropped on the floor: note_state_override_any_server() found nothing
# to patch, returned 0, and main.py logged only `if n:`. Measured 2026-09-15:
# incident 29586 raised 22:05:23Z, acked 93 s later, inside the 120 s refresh
# window; in the whole persisted log `Cache patched` had appeared three times and
# every one was `-> CLOSED`, never once `-> ACKNOWLEDGED`.
#
# ponytail: one flat dict rather than per-server pending buckets — the webhook
# cannot name its server while every server shares one secret (S1 1a). Known
# ceiling: two servers holding the same incident id would both be patched. S1 1b
# makes secrets unique, at which point this can be keyed by server like the rest.
_pending_overrides: dict[str, tuple[str, float]] = {}  # incident_id -> (state, ts)


def note_state_override(server_id: str, incident_id: str, state: str) -> None:
    _state_overrides.setdefault(server_id, {})[str(incident_id)] = (state, time.time())
    entry = _cache.get(server_id)
    if entry:
        for bucket in (entry.active_incidents, entry.closed_incidents):
            for inc in bucket:
                if str(inc.get("incident_id")) == str(incident_id):
                    inc["incident_state"] = state


def note_state_override_any_server(incident_id: str, state: str) -> int:
    """Same patch as note_state_override, for callers that know the incident but
    not the server. Webhooks are routed by shared secret, not by server id, so the
    incident id is the only handle they have.

    Returns the number of servers patched. **Zero is not a failure and is not a
    no-op**: the override is recorded as pending and applied the first time the
    incident appears in any cycle, within the same TTL. The caller must still log
    the zero case — a silent zero is how this defect stayed invisible.
    """
    patched = 0
    for server_id, entry in _cache.items():
        for bucket in (entry.active_incidents, entry.closed_incidents):
            if any(str(inc.get("incident_id")) == str(incident_id) for inc in bucket):
                note_state_override(server_id, incident_id, state)
                patched += 1
                break
    if patched == 0:
        _pending_overrides[str(incident_id)] = (state, time.time())
    return patched


def _apply_state_overrides(server_id: str, incidents: list[dict]) -> None:
    now = time.time()
    overrides = _state_overrides.get(server_id, {})
    for iid in [k for k, (_, ts) in overrides.items() if now - ts > STATE_OVERRIDE_TTL]:
        del overrides[iid]
    for iid in [k for k, (_, ts) in _pending_overrides.items() if now - ts > STATE_OVERRIDE_TTL]:
        del _pending_overrides[iid]
    if not overrides and not _pending_overrides:
        return
    for inc in incidents:
        iid = str(inc.get("incident_id"))
        override = overrides.get(iid)
        if override:
            inc["incident_state"] = override[0]
            continue
        pending = _pending_overrides.get(iid)
        if pending:
            # First sighting of an incident that was acked before it was ever
            # cached. Promote it to a normal per-server override so it survives
            # subsequent cycles for the rest of the TTL, and say so — this is the
            # branch whose silence was the defect.
            inc["incident_state"] = pending[0]
            _state_overrides.setdefault(server_id, {})[iid] = pending
            del _pending_overrides[iid]
            print(f"[Cache:{server_id}] Pending state override applied on first "
                  f"sighting: incident {iid} -> {pending[0]}")


# -- Cache loop ----------------------------------------------------------------

async def _run_one_cycle(client: httpx.AsyncClient, server: dict) -> None:
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))

    try:
        data = await _fetch_incidents(client, server)
    except Exception as e:
        print(f"[Cache:{server_id}] Failed to fetch incidents: {e}")
        raise  # propagate so the loop records a telemetry failure (not a false success)

    # C9 — stamp the LIST result the moment it lands, not at the end of the
    # cycle. Every incident's state is confirmed as of this instant.
    list_at = time.time()

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
            detail = {"alarm_counts": None, "alert_type": "host", "confirmed": False}
        if detail.get("confirmed") and detail.get("alert_type"):
            remember_type(server_id, inc_id, detail["alert_type"])
        enriched = _enrich_incident(incident, detail, list_at,
                                    remembered=known_type(server_id, inc_id))
        if bucket == "active":
            active_enriched.append(enriched)
        else:
            closed_enriched.append(enriched)
        if (i + 1) % 20 == 0:
            print(f"[Cache:{server_id}] Progress: {i + 1}/{n}")
        if delay > 0.1:
            await asyncio.sleep(delay)

    _apply_state_overrides(server_id, active_enriched)
    _apply_state_overrides(server_id, closed_enriched)
    _cache[server_id] = CachedIncidents(
        active_incidents=active_enriched,
        closed_incidents=closed_enriched,
        last_updated=time.time(),
        list_updated=list_at,
    )
    oldest, unconfirmed = freshness(_cache[server_id])
    age = f"{round(time.time() - oldest)}s" if oldest is not None else "n/a"
    print(f"[Cache:{server_id}] Cache updated: {len(active_enriched)} active, "
          f"{len(closed_enriched)} closed, oldest enrichment {age}, "
          f"{unconfirmed} unconfirmed")


async def _cache_loop(server: dict) -> None:
    server_id = server["id"]
    print(f"[Cache:{server_id}] Background loop started (refresh={server.get('cache_refresh_seconds', 120)}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_one_cycle(client, server)
                # incidents cycle is paced over the refresh interval, so its
                # duration isn't a meaningful upstream latency → record None.
                diagnostics.record_success(server_id, "incidents", None)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[Cache:{server_id}] Cycle failed: {e}")
                diagnostics.record_failure(server_id, "incidents", e)
                await asyncio.sleep(10)


# -- Lifecycle -----------------------------------------------------------------

def start_all() -> None:
    if not _types_loaded:
        load_types()
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
