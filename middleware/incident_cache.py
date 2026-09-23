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
                    server_cache_enabled, server_retain_closed,
                    server_list_poll_seconds)

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
_tasks: dict[str, list[asyncio.Task]] = {}   # C19: one list loop + one enrichment loop per server


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
    try:
        raw = resp.json()
    except ValueError as e:
        # PHP's "API require HTTPS" and friends are not JSON at all.
        raise ValueError(f"getincidents returned non-JSON from {server.get('id') or url}") from e
    if isinstance(raw, list):
        raw = raw[0] if raw else {}

    # **The body must SAY it completed before anything is derived from what it
    # does not contain.** An error answer — a wrong api_key, an HTTPS refusal, a
    # BHNM fault — has no `active_incidents` key, and an unchecked body reads as
    # ZERO incidents. Before CLSD retention that blanked one cycle and the next
    # one repaired it. With retention, zero incidents means every cached incident
    # disappeared from the list, which _retain_closed correctly treats as a close:
    # the whole estate marked CLOSED with a closed_at, and served as CLSD for the
    # next 24 hours. So this raises, the cycle fails, and NO retention pass runs.
    #
    # `result: "completed"` with no `active_incidents` key is a different thing
    # and is a legitimate answer meaning none — [MEASURED 2026-09-19] BHNM says
    # {"result":"completed","detail":"No active incident."}. It is not guarded
    # against, and the caller's `.get("active_incidents", [])` handles it.
    if not isinstance(raw, dict):
        raise ValueError(f"getincidents returned a {type(raw).__name__}, not an object, "
                         f"from {server.get('id') or url}")
    if str(raw.get("result", "")).strip().lower() != "completed":
        # result and the key names, never the body: an error string is the one
        # place BHNM might echo something it was sent.
        raise ValueError(f"getincidents did not complete on {server.get('id') or url} "
                         f"(HTTP {resp.status_code}, result={raw.get('result')!r}, "
                         f"keys={sorted(raw)})")
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
        return {"alarm_counts": None, "alert_type": "host", "confirmed": False,
                "bhnm_state": None}

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
    # The UNCOLOURED counts travel beside the coloured ones so the override path
    # can re-derive in either direction without a BHNM call. See
    # SEVERITY_COUNTS_KEY for why blue alone is not enough to come back from.
    severity = dict(counts)
    counts = apply_ack_colour(counts, acknowledged)
    # M1 — the flag was already being computed here and then thrown away. It is
    # now carried out so _enrich_incident can serve it beside the state instead
    # of the two sharing one field.
    return {"alarm_counts": counts, SEVERITY_COUNTS_KEY: severity,
            "alert_type": alert_type, "confirmed": True,
            "acknowledged": acknowledged,
            # C17 — BHNM's own word on the state, carried out so the absence
            # check can read it without a second call. `None` when the body
            # carried no incident at all, which is "not found".
            "bhnm_state": (incident.get("incident_state") or None),
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


#: The key carrying the UNCOLOURED counts — what the alarms actually are,
#: before acknowledgement is painted over them. Served, because rows are served
#: verbatim; additive, so no shipped client notices (the GAIN rule).
#:
#: **It exists because the ack colour is lossy and the un-ack has to come back.**
#: Blue says "three alarms, someone has this" and not which three, so nothing
#: can be recovered from it. Before 2.20.2 that was survivable: only enrichment
#: applied the colour, and enrichment re-derived severity from BHNM every cycle.
#: Now the OVERRIDE applies it too, within a second of the webhook and with no
#: BHNM call available, so the severity has to have been kept.
SEVERITY_COUNTS_KEY = "alarm_counts_severity"


def apply_ack_colour(counts: dict | None, acknowledged: bool) -> dict | None:
    """The ONE derivation: acknowledged alarms render BLUE, cleared ones stay GREEN.

    RULED 2026-09-19 (Thomas): BeNeM is a BHNM companion and its users already
    read blue as "someone has this". Do not invent a second visual language for
    a fact BHNM already has a colour for.

    **Every non-cleared alarm becomes blue; green is left alone.** Green means
    the alarm has cleared, which is a fact about the alarm and not about whether
    anybody has picked the incident up — an acknowledged incident whose alarms
    have cleared is still cleared. Until 2.20.2 this moved green too, and it was
    measured doing so on 2026-09-22: incident 30032, host back UP, enrichment
    turned `{green: 1}` into `{blue: 1}` while acknowledged.
    `test_cleared_alarms_stay_green_either_way` is the guard.

    The non-green total is preserved — every non-cleared alarm moves to blue,
    none is lost — so a caller summing the counts still gets the alarm count.

    **Called from BOTH paths, which is the point of this release.** Enrichment
    calls it through `_parse_alarm_counts`; the webhook override calls it through
    `_apply_override_fields`. Two copies of this rule would be two things to keep
    in step, and the second copy is exactly what was missing — the override set
    the flag and left the colour alone, so a row read ACKD with a red chip for as
    long as it took the next enrichment to come round, which is ~100 s in the lab
    and longer in a real estate.

    Takes the UNCOLOURED counts and is therefore reversible: pass
    `acknowledged=False` and the severity comes back untouched. That is why the
    severity is stored under `SEVERITY_COUNTS_KEY` rather than recomputed.

    ponytail: all alarms, not just the primary. If BHNM turns out to colour only
    the primary alarm, this is the one function to change.
    """
    if not acknowledged or not counts:
        return counts
    cleared = counts.get("green", 0)
    total = sum(counts.values()) - cleared
    if not total:
        return counts
    return {"red": 0, "orange": 0, "yellow": 0, "green": cleared, "blue": total}


def derive_counts(severity: dict | None, *, cleared: bool, acknowledged: bool) -> dict | None:
    """The ONE rule turning the severity counts into what a row serves.

    **Cleared beats acknowledged.** An incident whose alarms have cleared is
    green whether or not anybody has picked it up — `ALARMS CLEARED` is a fact
    about the alarms, and acknowledgement is a fact about the people. Asserted
    as `test_an_ack_on_a_cleared_incident_stays_green`.

    `apply_ack_colour` already leaves green alone, so the two rules compose
    rather than fight: a fully-cleared row handed to it has nothing left to
    paint blue and comes back unchanged. The explicit branch here is still
    written, because "it happens to work out" is not a rule anybody can read.

    The total is preserved in both directions, so a caller summing the counts
    still gets the alarm count.
    """
    if not severity:
        return severity
    if cleared:
        total = sum(severity.values())
        if not total:
            return severity
        return {"red": 0, "orange": 0, "yellow": 0, "green": total, "blue": 0}
    return apply_ack_colour(severity, acknowledged)


def recolour(inc: dict) -> None:
    """Re-derive one row's `alarm_counts` from its stored severity and its OWN
    current `state` and `acknowledged`, in place.

    **One function, every path.** The list path calls it when `getincidents`
    reports a new state, the webhook path calls it from `_apply_override_fields`,
    and enrichment calls it once it has written BHNM's fresh severity. Before
    2.20.3 the ack rule lived in two places and the cleared rule in none; two
    copies of a colour rule are two things to keep in step, and the drift is
    invisible because each copy looks right on its own.

    It reads the row rather than taking the flags as arguments, so a caller
    cannot pass a state the row does not actually have — the bug that shape
    invites is a colour derived from a fact that was never written.

    **The severity is the way back and is never overwritten here.** Blue says
    "three alarms, someone has this" and green says "they have cleared"; neither
    says which three, so nothing can be recovered from the derived counts. Only
    enrichment replaces the severity, with BHNM's own answer.

    The fallback for a row cached before the severity key existed is stated in
    `SEVERITY_COUNTS_KEY`: its current counts are used as the severity, which is
    exactly right on the way in and cannot restore on the way back out. The next
    enrichment fixes it.
    """
    severity = inc.get(SEVERITY_COUNTS_KEY) or inc.get("alarm_counts")
    if severity is None:
        return
    inc[SEVERITY_COUNTS_KEY] = severity
    inc["alarm_counts"] = derive_counts(
        dict(severity),
        cleared=str(inc.get("state") or "") == "ALARMS CLEARED",
        acknowledged=bool(inc.get("acknowledged")),
    )


# -- One line per state or acknowledged transition ------------------------------

def state_pair(inc: dict | None) -> tuple[str | None, bool | None]:
    """The two facts a transition is about. `None` for a row that did not exist."""
    if inc is None:
        return (None, None)
    return (inc.get("state"), bool(inc.get("acknowledged")))


def log_transition(server_id: str, incident_id: str,
                   before: tuple, after: tuple,
                   *, state_source: str, ack_source: str,
                   raw: tuple | None = None) -> None:
    """**One line per incident whose state or ack flag moved, naming WHERE the
    new value came from.**

    Written 2026-09-22 because the log could not answer an ordinary question.
    Asked to build a timeline for incident 30035 — green in BHNM, red on the
    phone — the only per-incident lines in the whole log were the webhook's
    own. What `getincidents` returned for that incident on each cycle, and what
    `getincidentdetail` said about its alarms, were **unrecorded**, so the
    timeline had to be inferred from `state_confirmed_at` and the aggregate
    `Cache updated` counts. The design note had already withdrawn one claim for
    exactly this reason on 2026-09-21: *"the log does not carry per-incident
    state."*

    The source is not decoration. A row that goes OPEN -> ALARMS CLEARED because
    BHNM said so on a list call, and one that goes there because an override
    expired and stopped hiding it, are different events with the same before and
    after — and telling them apart afterwards is the whole reason to write a log
    line rather than a metric.

    Silent when nothing changed, so a steady estate produces no lines at all and
    an absence means something.
    """
    if before == after:
        return
    sources = []
    if before[0] != after[0]:
        sources.append(state_source)
    if before[1] != after[1]:
        sources.append(ack_source)
    src = "+".join(dict.fromkeys(sources))
    # C20 — when an override is holding a different value from the one the list
    # reported, say BOTH. The served value is the headline, because that is what
    # anybody reading this line is trying to explain; the list value is what
    # tells them an override is why it differs.
    aside = ""
    if raw is not None and raw != after:
        aside = f"  [list said: {raw[0]}/ack={raw[1]}]"
    print(f"[State:{server_id}] incident {incident_id}: "
          f"{before[0]}/ack={before[1]} -> {after[0]}/ack={after[1]} (source: {src}){aside}")


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


def _apply_override_fields(inc: dict, state: str, at: float,
                           source: str = "webhook") -> None:
    """Turn one override string into fields — the ONLY place that mapping lives.

    Both the legacy write and the M1 split happen here, so a webhook, a proxied
    ACK and a re-applied override can never disagree about what an override means.
    """
    inc["incident_state"] = state          # unchanged from today, on purpose
    if state == "ACKNOWLEDGED":
        inc["acknowledged"] = True         # state is untouched: ACKD is a SUBSET of OPEN
        recolour(inc)
    elif state == "CLOSED":
        inc["state"] = "CLOSED"
        if inc.get("closed_at") is None:
            inc["closed_at"] = at          # first close wins; a re-delivery must not move it
    else:                                  # OPEN — an unacknowledgement
        inc["acknowledged"] = False
        # state deliberately NOT forced to OPEN: un-acking an ALARMS CLEARED
        # incident clears the flag, it does not re-open the alarms.
        recolour(inc)
    # **The colour moves with the flag, in the same function, or it does not
    # move at all.** Measured 2026-09-22 on the live lab: in the window between
    # an ACKNOWLEDGEMENT webhook and the next enrichment — `counts_confirmed_at`
    # byte-identical either side, so provably no enrichment — the served row
    # flipped to `acknowledged: true` in ~6 s and `alarm_counts` came back
    # unchanged. The row read ACKD and the chip kept its severity colour until
    # enrichment came round ~100 s later. The reverse was measured too: after a
    # DEACKNOWLEDGEMENT the row served `acknowledged: false` with `blue: 1`.


def _enrich_incident(incident: dict, detail: dict, list_at: float,
                     remembered: str | None = None) -> dict:
    enriched = dict(incident)
    enriched["alarm_counts"] = detail.get("alarm_counts")
    enriched[SEVERITY_COUNTS_KEY] = detail.get(SEVERITY_COUNTS_KEY)
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
    # BHNM's fresh severity is now in place; the DISPLAY colour is derived from
    # it by the same function the list and webhook paths use, so enrichment
    # cannot disagree with them about what acknowledged or cleared looks like.
    if enriched.get(SEVERITY_COUNTS_KEY) is not None:
        recolour(enriched)
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
    # **Expiry gets its own line.** A row that goes OPEN -> ALARMS CLEARED because
    # BHNM said so, and one that goes there because an override stopped hiding it,
    # have the same before and after — and the row's own transition line will say
    # "list" for both, because that IS where its new value comes from. This line
    # is what tells them apart afterwards.
    for iid in [k for k, (_, ts) in overrides.items() if now - ts > STATE_OVERRIDE_TTL]:
        print(f"[State:{server_id}] incident {iid}: override {overrides[iid][0]} "
              f"expired after {STATE_OVERRIDE_TTL}s (source: override expiry)")
        del overrides[iid]
    for iid in [k for k, (_, ts) in _pending_overrides.items() if now - ts > STATE_OVERRIDE_TTL]:
        print(f"[State:{server_id}] incident {iid}: PENDING override "
              f"{_pending_overrides[iid][0]} expired after {STATE_OVERRIDE_TTL}s "
              f"having never been applied (source: override expiry)")
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
        _apply_override_fields(row, "CLOSED", at, source="disappearance")
        log_transition(server_id, str(inc.get("incident_id")),
                       state_pair(inc), state_pair(row),
                       state_source="disappearance", ack_source="disappearance")
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

async def _run_list_and_publish(client: httpx.AsyncClient, server: dict) -> None:
    """C19's list cadence: one `getincidents`, published at once.

    This is the whole of what used to be the top of `_run_one_cycle`, minus the
    enrichment that used to hold its answer hostage. One request per server per
    `list_poll_seconds`, whatever the incident count.
    """
    data = await _fetch_incidents(client, server)
    await publish_list(client, server, data, time.time(), origin="Cache")


def _apply_detail_to_cached_row(server_id: str, incident_id: str, detail: dict,
                                remembered: str | None = None) -> None:
    """C18 — ONE row's counts, published the moment its detail call lands.

    The cache is mutated in place rather than swapped, which is what makes the
    publish per-row. A failed detail leaves the row's state and its existing
    counts alone: C11 says a failed enrichment is never cached, and under C18
    that gains a second meaning — it must not roll back a state the LIST already
    confirmed.
    """
    entry = _cache.get(server_id)
    if entry is None:
        return
    iid = normalise_incident_id(incident_id)
    for row in (*entry.active_incidents, *entry.closed_incidents):
        if normalise_incident_id(row.get("incident_id", "")) != iid:
            continue
        if not detail.get("confirmed"):
            # C10 — a type learned earlier from a confirmed call is a FACT.
            row["alert_type"] = row.get("alert_type") or remembered or "host"
            return
        row[SEVERITY_COUNTS_KEY] = detail.get(SEVERITY_COUNTS_KEY)
        row["alert_type"] = detail.get("alert_type", "host")
        row["acknowledged"] = bool(detail.get("acknowledged"))
        row["ack_user"] = detail.get("ack_user") or None
        # The display colour is derived from the fresh severity by the one
        # function the list and webhook paths use (2.20.3).
        recolour(row)
        row["counts_confirmed_at"] = time.time()
        _apply_state_overrides(server_id, [row])
        entry.last_updated = time.time()
        return


async def _run_enrichment_sweep(client: httpx.AsyncClient, server: dict) -> None:
    """C19's enrichment cadence: one `getincidentdetail` per cached incident,
    paced over `cache_refresh_seconds`, each published as it lands.

    It no longer takes a list of its own. The list loop owns state; this owns
    `alarm_counts` and `counts_confirmed_at`. That is C9's two stamps finally
    having two writers, instead of one write at the end of a cycle re-coupling
    what C9 separated.
    """
    server_id = server["id"]
    refresh = max(60, min(900, server.get("cache_refresh_seconds", 120)))
    entry = _cache.get(server_id)
    if entry is None:
        return
    ids = [str(i.get("incident_id")) for i in (*entry.active_incidents, *entry.closed_incidents)
           if i.get("incident_id")]
    n = len(ids)
    if not n:
        return
    delay = refresh / (n + 1)
    print(f"[Cache:{server_id}] Enriching {n} incidents (pacing: {delay:.1f}s between calls)")
    for i, inc_id in enumerate(ids):
        try:
            detail = await _fetch_incident_detail(client, server, inc_id)
        except Exception as e:
            print(f"[Cache:{server_id}] Error fetching detail for incident {inc_id}: {e}")
            detail = {"alarm_counts": None, "alert_type": "host", "confirmed": False,
                      "bhnm_state": None}
        if detail.get("confirmed") and detail.get("alert_type"):
            remember_type(server_id, inc_id, detail["alert_type"])
        _apply_detail_to_cached_row(server_id, inc_id, detail,
                                    remembered=known_type(server_id, inc_id))
        if (i + 1) % 20 == 0:
            print(f"[Cache:{server_id}] Progress: {i + 1}/{n}")
        if delay > 0.1:
            await asyncio.sleep(delay)
    oldest, unconfirmed = freshness(_cache[server_id])
    age = f"{round(time.time() - oldest)}s" if oldest is not None else "n/a"
    print(f"[Cache:{server_id}] Enrichment sweep done: oldest enrichment {age}, "
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
    # Counts are exactly what a list call does not refresh, so the severity
    # travels with them — dropping it here would make the NEXT override's
    # un-ack unable to come back.
    row[SEVERITY_COUNTS_KEY] = (known or {}).get(SEVERITY_COUNTS_KEY)
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
    # **The colour follows the state the list just reported, without waiting for
    # an enrichment.** Measured 2026-09-22 on incident 30035: raspi-050 came back
    # UP at 14:45:11Z, the list call had the incident as ALARMS CLEARED, and the
    # chip stayed red until the detail call came round at 14:48:22Z — 3 min 11 s,
    # because the counts only moved on enrichment and enrichment is paced across
    # every open incident. The state was right and the colour was three minutes
    # behind it. The severity snapshot is the way back if the state returns to
    # OPEN before the next detail call lands.
    recolour(row)
    return row


async def _confirm_absence(client: httpx.AsyncClient, server: dict,
                           row: dict) -> tuple[str, str | None]:
    """C17 — a row absent from the list is CHECKED, not assumed closed.

    Returns `(verdict, state)`:

    * `("closed", state)` — BHNM says CLOSED, or has no such incident. Retain.
    * `("active", state)` — BHNM says OPEN or ALARMS CLEARED. Keep it active
      with that state.
    * `("unknown", None)` — **the check could not be made.** Keep the row
      exactly as it is, touch nothing, and let the next list poll try again.

    **[MEASURED 2026-09-23] The defect this removes:** incident 30045 was served
    CLOSED at 07:00:55Z while BHNM's own `incident_log` had it `OPEN` — opened
    07:00:12, not closed until 07:10:29. Absence from a list was read as a
    close, and nothing asked.

    Absence is still a real close signal and must stay one. [MEASURED
    2026-09-21] incident 30014 produced zero webhook lines and simply vanished;
    without the disappearance rule it would have had no CLSD row at all. What
    C17 changes is that the middleware now asks before asserting.

    **"Not found" retains.** BHNM has forgotten the incident, which is a close
    by another name, and the alternative is a row that never ages out.

    **A FAILED check does not retain, and that is the correction this rule got
    in review.** A transport error is not evidence of a close any more than it
    is evidence of an open — and the two mistakes are not symmetric in cost.
    Retaining on failure turns one timeout into a CLOSED row served for the
    whole 24-hour window (C15), on an incident somebody may be paged for.
    Keeping it active costs one extra `getincidentdetail` on the next poll.

    **Nothing lives for ever on the strength of this.** The row keeps its old
    `state_confirmed_at` — the check did not happen, so no confirmation is
    dated — which means C16 leaves it eligible and the very next list poll picks
    it up again. It ages out the moment ONE check succeeds, in whichever
    direction that check answers.
    """
    iid = str(row.get("incident_id"))
    try:
        detail = await _fetch_incident_detail(client, server, iid)
    except Exception as e:
        # Belt and braces: _fetch_incident_detail swallows its own transport
        # errors today, so this branch should be unreachable. It is kept so a
        # future raise cannot silently become a close.
        print(f"[Cache:{server['id']}] Absence check raised for incident {iid}: {e} "
              f"— keeping it active with its last state, will retry")
        return ("unknown", None)
    # **`confirmed` is what separates a failed call from a real "not found".**
    # `_fetch_incident_detail` returns `confirmed: False` when the call or the
    # parse failed, and `confirmed: True` with no incident when BHNM answered
    # and has no such incident. Both leave `bhnm_state` None, so reading the
    # state alone cannot tell them apart — which is how the first cut of this
    # function retained on a transport error while believing it did not.
    if not detail.get("confirmed"):
        print(f"[Cache:{server['id']}] Absence check failed for incident {iid} "
              f"— keeping it active with its last state, will retry")
        return ("unknown", None)
    state = detail.get("bhnm_state")
    if state in ("OPEN", "ALARMS CLEARED"):
        return ("active", state)
    return ("closed", state)


async def publish_list(client: httpx.AsyncClient, server: dict,
                       data: dict, list_at: float, *, origin: str) -> None:
    """C16 + C17 + C18 — merge one list result into the cache, IMMEDIATELY.

    The single path by which a `getincidents` answer reaches the cache. The
    background list loop calls it and so does the Refresh endpoint; before
    2.21.0 those were two code paths and the slower one won by finishing last.

    **C18 — this publishes state and `acknowledged` the moment the list lands,
    with no enrichment in between.** [MEASURED 2026-09-23] The old cycle held
    30046's `ALARMS CLEARED` from 07:07:36.490Z until 07:09:17.555Z: **101
    seconds in which the middleware had the right answer and served the old
    one**, because the cache was written once, at the end of the loop.

    **C16 — a publish from a list taken at `list_at` may not overwrite a row
    whose `state_confirmed_at` is NEWER than `list_at`, and may not treat such a
    row as disappeared.** `state_confirmed_at` already records every row's
    vintage and nothing compared them, so the older writer won by arriving
    later. The comparison is per ROW, not per publish: a cycle carrying one
    stale row still publishes the other four.
    """
    server_id = server["id"]
    prev = _cache.get(server_id)
    known = {normalise_incident_id(i.get("incident_id", "")): i
             for i in (*(prev.active_incidents if prev else []),
                       *(prev.closed_incidents if prev else []))}

    active, closed = [], []
    raw_pairs: dict[str, tuple] = {}
    befores: dict[str, tuple] = {}
    seen: set[str] = set()
    protected = 0

    def place(row):
        (closed if row.get("state") == "CLOSED" else active).append(row)

    for raw, from_closed in ([(i, False) for i in data.get("active_incidents", [])]
                             + [(i, True) for i in data.get("closed_incidents", [])]):
        iid = normalise_incident_id(raw.get("incident_id", ""))
        if not iid:
            continue
        seen.add(iid)
        k = known.get(iid)
        befores[iid] = state_pair(k)
        # C16 — this row has been confirmed since the list was taken. The list
        # is not wrong, it is OLD, and old must not win.
        if k is not None and (k.get("state_confirmed_at") or 0) > list_at:
            protected += 1
            place(k)
            continue
        row = _list_only_row(raw, k, server_id, list_at)
        raw_pairs[iid] = state_pair(row)
        place(row)

    # Rows the list did not mention.
    for iid, k in known.items():
        if iid in seen:
            continue
        befores[iid] = state_pair(k)
        # C16 again — a row confirmed AFTER the list was taken could not have
        # been in it. Absence from a list that predates the row is not absence.
        if (k.get("state_confirmed_at") or 0) > list_at:
            protected += 1
            place(k)
            continue
        # Already been through C17 on an earlier poll. Re-asking every interval
        # would have been six calls a poll on the measured estate.
        if k.get("state") == "CLOSED" and k.get("closed_at") is not None:
            place(k)
            continue
        if not server_retain_closed(server):
            # Retention is off, so there is nothing to retain — but an incident
            # BHNM still has OPEN must not be dropped on an absence either.
            verdict, state = await _confirm_absence(client, server, k)
            if verdict == "unknown":
                # The check could not be made, so nothing is known and nothing
                # is written — not even the stamp. C16 then leaves the row
                # eligible and the next poll re-checks it.
                place(k)
            elif verdict == "active":
                row = dict(k)
                row["state"] = state
                row["incident_state"] = state
                row["state_confirmed_at"] = list_at
                recolour(row)
                place(row)
            continue
        verdict, state = await _confirm_absence(client, server, k)
        if verdict == "unknown":
            # Untouched, stamp included. A failed check must not close a row,
            # and must not date a confirmation that did not happen.
            place(k)
            continue
        row = dict(k)
        if verdict == "active":
            row["state"] = state
            row["incident_state"] = state
            row["state_confirmed_at"] = list_at
            recolour(row)
        else:
            _apply_override_fields(row, "CLOSED", list_at, source="disappearance")
            recolour(row)
        place(row)

    if server_retain_closed(server):
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

    # C20 — the transition lines are written HERE, after the overrides, so they
    # report what is SERVED. Until 2.21.0 they were emitted inside the row loop
    # and described the list instead: [MEASURED 2026-09-23T07:11:59.949Z] the
    # line read `30046: CLOSED -> ALARMS CLEARED (source: list)` while the
    # served row was CLOSED under a live RECOVERY override. A log line that
    # disagrees with the payload is worse than no line, because it is believed.
    for row in (*active, *closed):
        iid = normalise_incident_id(row.get("incident_id", ""))
        before = befores.get(iid, (None, None))
        log_transition(server_id, iid, before, state_pair(row),
                       state_source="list", ack_source="list",
                       raw=raw_pairs.get(iid))

    retained = sum(1 for r in closed if r.get("closed_at") is not None)
    extra = f", {protected} newer than this list" if protected else ""
    print(f"[{origin}:{server_id}] List published: {len(active)} active, "
          f"{len(closed)} closed, {retained} retained{extra}")


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
            data = await _fetch_incidents(client, server)
            await publish_list(client, server, data, time.time(), origin="Refresh")
        entry = _cache[server_id]
        payload = {
            "cache_age_seconds": round(time.time() - entry.last_updated),
            "active_incidents": entry.active_incidents,
            "closed_incidents": entry.closed_incidents,
        }
        _refresh_last[server_id] = (time.time(), payload)
        return {**payload, "coalesced": False}


async def _list_loop(server: dict) -> None:
    """C19 — the list cadence. One `getincidents` per `list_poll_seconds`."""
    server_id = server["id"]
    every = server_list_poll_seconds(server)
    print(f"[Cache:{server_id}] List loop started (list_poll={every}s)")
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                await _run_list_and_publish(client, server)
                diagnostics.record_success(server_id, "incidents", None)
                await asyncio.sleep(every)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[Cache:{server_id}] List poll failed: {e}")
                diagnostics.record_failure(server_id, "incidents", e)
                await asyncio.sleep(10)


async def _enrichment_loop(server: dict) -> None:
    """C19 — the enrichment cadence, unchanged in interval and renamed in
    nothing. `cache_refresh_seconds` still means exactly what it meant."""
    server_id = server["id"]
    every = max(60, min(900, server.get("cache_refresh_seconds", 120)))
    print(f"[Cache:{server_id}] Enrichment loop started (cache_refresh={every}s)")
    # Let the list loop publish first, so the sweep has rows to work on rather
    # than finding an empty cache and sleeping a full interval.
    await asyncio.sleep(2)
    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        while True:
            try:
                started = time.time()
                await _run_enrichment_sweep(client, server)
                # The sweep paces itself across the interval, so what is left is
                # whatever the pacing did not consume — usually nothing.
                await asyncio.sleep(max(1.0, every - (time.time() - started)))
            except asyncio.CancelledError:
                raise
            except Exception as e:
                print(f"[Cache:{server_id}] Enrichment sweep failed: {e}")
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
    for task in _tasks.pop(server_id, []) or []:
        if not task.done():
            task.cancel()
    _cache.pop(server_id, None)
    # The coalesced payload is a snapshot of a cache that no longer exists.
    # Serving it after a reload would answer a refresh with the old server's list.
    _refresh_last.pop(server_id, None)


def _start_server(server: dict) -> None:
    """C19 — TWO tasks per server now, one per cadence.

    They are started together and cancelled together; a server with a live list
    loop and a dead enrichment loop would serve states that never gained counts,
    which is worse than serving neither.
    """
    server_id = server["id"]
    running = _tasks.get(server_id) or []
    if any(not t.done() for t in running):
        return
    _tasks[server_id] = [asyncio.create_task(_list_loop(server)),
                         asyncio.create_task(_enrichment_loop(server))]
    print(f"[Cache:{server_id}] Started background loops")
