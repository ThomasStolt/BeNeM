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

from config import (SERVERS_JSON_PATH, BHNM_TLS_VERIFY, PROXY_TIMEOUT, RETENTION_SECONDS,
                    server_cache_enabled, server_retain_closed)

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
        else:
            counts["red"] += 1
    # The `state == "ACKNOWLEDGED" -> blue` branch that used to sit here is
    # DELETED, not left. Measured 2026-09-19: across every active incident in
    # the lab the complete set of per-alarm state values is CRITICAL, UP and
    # WARNING. Alarms never carry ACKNOWLEDGED, so that branch had never once
    # executed and blue had never once been displayed.

    acknowledged = is_acknowledged(incident)
    counts = apply_ack_colour(counts, acknowledged)
    # M1 — the flag was already being computed here and then thrown away. It is
    # now carried out so _enrich_incident can serve it beside the state instead
    # of the two sharing one field.
    return {"alarm_counts": counts, "alert_type": alert_type, "confirmed": True,
            "acknowledged": acknowledged,
            "ack_user": (incident.get("ack_user") or None)}


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


def is_acknowledged(incident: dict) -> bool:
    """Is this incident acknowledged, per BHNM?

    **BHNM records acknowledgement at the INCIDENT level and never on the
    alarms.** [MEASURED 2026-09-19, incident 27516 acked and un-acked under
    control] Acking flips `incident.acknowledged` 0 -> 1 and
    `incident.primary_alarm_state` OPEN -> ACKNOWLEDGED, while every entry in
    `primary_alarm_log` keeps its own condition (`CRITICAL` stayed `CRITICAL`).
    So the only place to read this is here.

    Both fields are checked because either alone is one BHNM quirk away from
    being wrong, and they agreed in the measurement.
    """
    ack = incident.get("acknowledged")
    if ack in (1, True) or str(ack).strip().lower() in ("1", "true", "yes"):
        return True
    return str(incident.get("primary_alarm_state") or "").strip().upper() == "ACKNOWLEDGED"


def apply_ack_colour(counts: dict | None, acknowledged: bool) -> dict | None:
    """An acknowledged incident's alarms render BLUE. Match BHNM.

    RULED 2026-09-19 (Thomas): BeNeM is a BHNM companion and its users already
    read blue as "someone has this". Do not invent a second visual language for
    a fact BHNM already has a colour for.

    The total is preserved — every alarm moves to blue, none is lost — so a
    caller summing the counts still gets the alarm count. Un-acknowledging
    restores severity by simple re-derivation on the next enrichment, which is
    why this is computed and never stored as a mutation.

    ponytail: all alarms, not just the primary. If BHNM turns out to colour only
    the primary alarm, this is the one function to change.
    """
    if not acknowledged or not counts:
        return counts
    total = sum(counts.values())
    if not total:
        return counts
    return {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": total}


# -- M1: the state and the flag are two facts ------------------------------------
# BHNM has THREE incident states — OPEN, ALARMS CLEARED, CLOSED — and
# acknowledgement is a FLAG on an OPEN incident, not a fourth state. Today the
# webhook writes "ACKNOWLEDGED" into incident_state, so "acknowledged" and
# "alarms cleared" occupy the same field and cannot both be true.
#
# incident_state KEEPS TODAY'S BEHAVIOUR EXACTLY, ACKNOWLEDGED and all: both
# released clients (iOS build 53, PWA 0.18.1) derive their entire notion of
# acknowledgement from it, so removing the value is a breaking change with no
# field removed. It goes at M1-drop, once no BeNeM/53 remains in the proxy log —
# Thomas's word, never an inference from elapsed time.

BHNM_STATES = ("OPEN", "ALARMS CLEARED", "CLOSED")


def state_of(incident: dict) -> str:
    """BHNM's own state for a row, with the ack flag taken back out of it.

    An unrecognised value becomes OPEN rather than passing through: TOTL is
    OPEN + CLRD + CLSD, so a state in none of the three would drop the incident
    out of every pill on the client and vanish it from the list entirely. Loud
    beats gone.
    """
    raw = str(incident.get("state") or incident.get("incident_state") or "").strip().upper()
    if raw in BHNM_STATES:
        return raw
    return "OPEN"


def _apply_override_fields(inc: dict, state: str, at: float) -> None:
    """Turn one override string into fields — the ONLY place that mapping lives.

    Both the legacy write and the M1 split happen here, so a webhook, a proxied
    ACK and a re-applied override can never disagree about what an override means.
    """
    inc["incident_state"] = state          # unchanged from today, on purpose
    if state == "ACKNOWLEDGED":
        inc["acknowledged"] = True         # state is untouched: ACKD is a SUBSET of OPEN
    elif state == "CLOSED":
        inc["state"] = "CLOSED"
        if inc.get("closed_at") is None:
            inc["closed_at"] = at          # first close wins; a re-delivery must not move it
    else:                                  # OPEN — an unacknowledgement
        inc["acknowledged"] = False
        # state deliberately NOT forced to OPEN: un-acking an ALARMS CLEARED
        # incident clears the flag, it does not re-open the alarms.


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

    # M1 — additive. incident_state above is untouched; these are the fields the
    # pills read. The detail call is the only place BHNM exposes the incident-level
    # ack flag, so a FAILED detail falls back to whatever the list row carried
    # rather than asserting False — "not confirmed acknowledged" is not "confirmed
    # not acknowledged", and False is the healthy-looking one.
    enriched["state"] = state_of(incident)
    if detail.get("confirmed"):
        enriched["acknowledged"] = bool(detail.get("acknowledged"))
        enriched["ack_user"] = detail.get("ack_user") or None
    else:
        enriched["acknowledged"] = is_acknowledged(incident)
        enriched["ack_user"] = incident.get("ack_user") or None
    enriched["closed_at"] = incident.get("closed_at")
    if enriched["state"] == "CLOSED" and enriched["closed_at"] is None:
        enriched["closed_at"] = list_at
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
    at = time.time()
    _state_overrides.setdefault(server_id, {})[str(incident_id)] = (state, at)
    entry = _cache.get(server_id)
    if entry:
        for bucket in (entry.active_incidents, entry.closed_incidents):
            for inc in bucket:
                if str(inc.get("incident_id")) == str(incident_id):
                    _apply_override_fields(inc, state, at)


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
            _apply_override_fields(inc, override[0], override[1])
            continue
        pending = _pending_overrides.get(iid)
        if pending:
            # First sighting of an incident that was acked before it was ever
            # cached. Promote it to a normal per-server override so it survives
            # subsequent cycles for the rest of the TTL, and say so — this is the
            # branch whose silence was the defect.
            _apply_override_fields(inc, pending[0], pending[1])
            _state_overrides.setdefault(server_id, {})[iid] = pending
            del _pending_overrides[iid]
            print(f"[Cache:{server_id}] Pending state override applied on first "
                  f"sighting: incident {iid} -> {pending[0]}")


# -- Single-incident merge ------------------------------------------------------

def normalise_incident_id(incident_id: str) -> str:
    """Strip a leading `<prefix>-` and return the bare numeric id.

    Three identifiers are in play and they are not reliably the same string: the
    push payload carries `29570`, the cache may carry `NetreoCloudDemo-24090`,
    and BHNM's getincidentdetail wants `24090`. Tolerant in, strict out — and
    normalised at EXACTLY ONE PLACE, which is here. Rejecting the prefixed form
    would break shipped clients for no gain.
    (2026-09-15 design, "The ID question", decision 4.)
    """
    text = str(incident_id).strip()
    if "-" in text:
        tail = text.rsplit("-", 1)[1]
        if tail.isdigit():
            return tail
    return text


def merge_incident(server_id: str, enriched: dict) -> bool:
    """Insert or replace one incident in the cache, in the bucket its state says.

    Returns True if a cache existed to merge into. **Moving between buckets is
    part of this, not a separate step**: BHNM moves a recovered incident out of
    the active set, so leaving a CLOSED row in the active bucket would leave the
    active COUNT counting something that is not active — a number asserting a
    state nothing has confirmed.
    """
    entry = _cache.get(server_id)
    if entry is None:
        return False
    iid = normalise_incident_id(enriched.get("incident_id", ""))
    closed = state_of(enriched) == "CLOSED"
    target = entry.closed_incidents if closed else entry.active_incidents
    other = entry.active_incidents if closed else entry.closed_incidents
    for bucket in (target, other):
        for i, inc in enumerate(list(bucket)):
            if normalise_incident_id(inc.get("incident_id", "")) == iid:
                del bucket[i]
                break
    target.append(enriched)
    return True


# -- M3: CLSD retention, and C15's 24-hour ceiling -------------------------------

def _retain_closed(server_id: str, active: list[dict], closed: list[dict],
                   at: float) -> list[dict]:
    """Rows the cache held and the list call no longer returns are CLOSED.

    **Disappearance IS a close, and for some incidents it is the only signal
    there is.** [MEASURED 2026-09-21, BHNM-B] incident 30014 produced zero
    webhook lines in the entire log and is simply absent from getincidents now;
    a rule that waited for a RECOVERY would let it vanish with no CLSD row at
    all. So this must not require one.

    `closed_at` for a disappearance is the middleware's OWN clock at the moment
    it noticed — ruled 2026-09-21, open question 2. It is the only time this
    code can honestly claim: BHNM never told it when.
    """
    entry = _cache.get(server_id)
    if entry is None:
        return closed
    seen = {normalise_incident_id(i.get("incident_id", "")) for i in (*active, *closed)}
    carried = []
    for inc in (*entry.active_incidents, *entry.closed_incidents):
        if normalise_incident_id(inc.get("incident_id", "")) in seen:
            continue
        row = dict(inc)
        _apply_override_fields(row, "CLOSED", at)
        carried.append(row)
    if carried:
        print(f"[Cache:{server_id}] Retained {len(carried)} incident(s) as CLOSED — "
              f"gone from the list, no RECOVERY seen")
    return closed + carried


def _prune_aged(server_id: str, rows: list[dict], now: float) -> list[dict]:
    """C15 — nothing older than the retention window is held, in any state.

    Only a row carrying a `closed_at` is retained on the middleware's own
    initiative; everything else is replaced wholesale by each list call and
    cannot age. So one sweep over both buckets is the whole of C15.
    `incident_types` is NOT incident data and is exempt — dropping it would
    re-open C11's UNKNOWN on every aged incident.
    """
    kept = [r for r in rows
            if r.get("closed_at") is None or now - r["closed_at"] < RETENTION_SECONDS]
    dropped = len(rows) - len(kept)
    if dropped:
        print(f"[Cache:{server_id}] Dropped {dropped} incident(s) closed over "
              f"{round(RETENTION_SECONDS / 3600)}h ago")
    return kept


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

    if server_retain_closed(server):
        closed_enriched = _retain_closed(server_id, active_enriched, closed_enriched, list_at)
        closed_enriched = _prune_aged(server_id, closed_enriched, list_at)
        active_enriched = _prune_aged(server_id, active_enriched, list_at)

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


# -- M2 / C7: the refresh — ONE list call, no detail calls ----------------------

REFRESH_WINDOW = 30.0  # C7: one per server per 30 s, enforced server-side only

_refresh_locks: dict[str, asyncio.Lock] = {}
_refresh_last: dict[str, tuple[float, dict]] = {}  # server_id -> (finished_at, payload)


def ack_flag(incident: dict) -> bool | None:
    """The ack flag if this row SAYS anything about it, else None.

    **None is not False.** [MEASURED 2026-09-21, from the served-row key list in
    the filter design §3] a `getincidents` row carries incident_id,
    incident_state, name, title, open_time, device_category, device_site and
    device_note — and no ack field at all. `is_acknowledged()` on such a row
    returns False, which would un-acknowledge every incident on every refresh.
    So a row that does not say must be allowed to say nothing.

    The consequence, stated rather than hidden: **a refresh cannot learn about
    an acknowledgement made in the BHNM UI.** That arrives by ACKNOWLEDGEMENT
    webhook or by the next enrichment, which is the webhook-first premise doing
    its job rather than a gap in this function.
    """
    if "acknowledged" in incident or "primary_alarm_state" in incident:
        return is_acknowledged(incident)
    return None


def _list_only_row(raw: dict, known: dict | None, server_id: str, list_at: float) -> dict:
    """One incident as a list call alone can know it. Counts are exactly what
    this does not refresh, so a known row keeps its own — and an unknown one gets
    NO counts and NO counts_confirmed_at rather than a confident zero."""
    row = dict(known or {})
    row.update(raw)
    iid = normalise_incident_id(raw.get("incident_id", ""))
    row["alarm_counts"] = (known or {}).get("alarm_counts")
    row["alert_type"] = (known or {}).get("alert_type") or known_type(server_id, iid) or "host"
    row["counts_confirmed_at"] = (known or {}).get("counts_confirmed_at")
    row["state_confirmed_at"] = list_at
    row["state"] = state_of(raw)
    flag = ack_flag(raw)
    row["acknowledged"] = flag if flag is not None else bool((known or {}).get("acknowledged"))
    row["ack_user"] = raw.get("ack_user") or (known or {}).get("ack_user") or None
    row["closed_at"] = (known or {}).get("closed_at")
    if row["state"] == "CLOSED" and row["closed_at"] is None:
        row["closed_at"] = list_at
    return row


async def _run_list_only(client: httpx.AsyncClient, server: dict) -> None:
    server_id = server["id"]
    data = await _fetch_incidents(client, server)
    list_at = time.time()

    prev = _cache.get(server_id)
    known = {normalise_incident_id(i.get("incident_id", "")): i
             for i in (*(prev.active_incidents if prev else []),
                       *(prev.closed_incidents if prev else []))}

    active, closed = [], []
    for raw, bucket in ([(i, active) for i in data.get("active_incidents", [])]
                        + [(i, closed) for i in data.get("closed_incidents", [])]):
        iid = normalise_incident_id(raw.get("incident_id", ""))
        if not iid:
            continue
        bucket.append(_list_only_row(raw, known.get(iid), server_id, list_at))

    if server_retain_closed(server):
        closed = _retain_closed(server_id, active, closed, list_at)
        closed = _prune_aged(server_id, closed, list_at)
        active = _prune_aged(server_id, active, list_at)

    _apply_state_overrides(server_id, active)
    _apply_state_overrides(server_id, closed)
    _cache[server_id] = CachedIncidents(
        active_incidents=active,
        closed_incidents=closed,
        # last_updated says the cache was updated, and it was. It is NOT a claim
        # about the counts — that claim is per-incident, in counts_confirmed_at,
        # which this call deliberately leaves alone. C9 exists because one number
        # for two facts is what lied in the first place.
        last_updated=list_at,
        list_updated=list_at,
    )
    print(f"[Refresh:{server_id}] List refreshed: {len(active)} active, {len(closed)} closed, "
          f"no detail calls")


async def refresh_server(server: dict) -> dict:
    """C7's refresh endpoint, in M2's list-only form.

    Single-flight, at most one upstream call per server per 30 s, **independent
    of the polling switch** — under webhook mode there is no poll to carry the
    ALARMS CLEARED transition, and [MEASURED 2026-09-21, BHNM-B] BHNM sends no
    webhook for it, so a list call is the only way it can ever arrive.

    The lock and the window together give C7 both behaviours from one mechanism:
    a caller arriving while a refresh is running WAITS and then finds that
    caller's fresh result inside the window — *"a tap inside the window returns
    the running one's result"*, a single-flight and not a 429. Two clients each
    implementing their own coalescing is the thing this avoids.

    List-only is the point. `_fetch_incidents` is ONE request; enrichment is one
    per incident paced over ~110 s ([MEASURED] `Enriching 10 incidents (pacing:
    10.9s between calls)`). A refresh that waits for enrichment is not a refresh.
    """
    server_id = server["id"]
    lock = _refresh_locks.setdefault(server_id, asyncio.Lock())
    async with lock:
        prev = _refresh_last.get(server_id)
        if prev and time.time() - prev[0] < REFRESH_WINDOW:
            return {**prev[1], "coalesced": True}
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            await _run_list_only(client, server)
        entry = _cache[server_id]
        payload = {
            "cache_age_seconds": round(time.time() - entry.last_updated),
            "active_incidents": entry.active_incidents,
            "closed_incidents": entry.closed_incidents,
        }
        _refresh_last[server_id] = (time.time(), payload)
        return {**payload, "coalesced": False}


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
    # The coalesced payload is a snapshot of a cache that no longer exists.
    # Serving it after a reload would answer a refresh with the old server's list.
    _refresh_last.pop(server_id, None)


def _start_server(server: dict) -> None:
    server_id = server["id"]
    if server_id in _tasks and not _tasks[server_id].done():
        return
    _tasks[server_id] = asyncio.create_task(_cache_loop(server))
    print(f"[Cache:{server_id}] Started background loop")
