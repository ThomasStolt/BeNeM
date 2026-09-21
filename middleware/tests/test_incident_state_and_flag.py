"""M1 / M2 / M3 — the state and the flag are two facts, and CLSD is retained.

Each definition in the filter design gets a test that fails if the definition
changes. Not one suite over the five: separate assertions, because that is what
makes a later edit visible.

Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §2, §5.
"""

import json
import os
import tempfile
import time

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")

_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ.setdefault("DB_PATH", _tmp.name)

API_KEY = "state-and-flag-key"
TARGET = "https://bhnm-state.example.com"
# A second server with caching OFF: "the polling switch" in its shipped form.
# The refresh must work for it anyway — under webhook mode there is no poll to
# carry ALARMS CLEARED, so a list call is the only way that state can arrive.
NOPOLL_KEY = "state-and-flag-nopoll-key"
NOPOLL_TARGET = "https://bhnm-nopoll.example.com"
# A third with CLSD retention ON, which is what turns a misread body from one
# blanked cycle into 24 hours of false CLSD.
RETAIN_KEY = "state-and-flag-retain-key"
RETAIN_TARGET = "https://bhnm-retain.example.com"

_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([
    {"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
     "cache_enabled": True, "cache_refresh_seconds": 120},
    {"id": "nopoll", "name": "No poll", "url": NOPOLL_TARGET, "api_key": NOPOLL_KEY,
     "pin": "", "cache_enabled": False, "cache_refresh_seconds": 120},
    {"id": "retain", "name": "Retain", "url": RETAIN_TARGET, "api_key": RETAIN_KEY,
     "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120, "retain_closed": True},
], _servers)
_servers.close()
os.environ.setdefault("SERVERS_JSON_PATH", _servers.name)

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import main as main_mod
import incident_cache
from database import init_db
from config import RETENTION_SECONDS

init_db()  # the webhook route reaches device_tokens even when nobody is registered
from incident_cache import (CachedIncidents, _apply_override_fields, _prune_aged,
                            _retain_closed, ack_flag, state_of)

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}
NOPOLL_HEADERS = {"X-Proxy-Token": NOPOLL_KEY, "X-BHNM-Target": NOPOLL_TARGET}
RETAIN_HEADERS = {"X-Proxy-Token": RETAIN_KEY, "X-BHNM-Target": RETAIN_TARGET}


def _row(iid, state="OPEN", **kw):
    """An enriched row as _enrich_incident would leave it."""
    row = {"incident_id": iid, "name": "raspi-050", "title": f"Host {iid}",
           "incident_state": state, "state": state, "acknowledged": False,
           "ack_user": None, "closed_at": None, "alert_type": "host",
           "alarm_counts": {"red": 1, "orange": 0, "yellow": 0, "green": 0, "blue": 0},
           "state_confirmed_at": time.time(), "counts_confirmed_at": time.time()}
    row.update(kw)
    return row


@pytest.fixture(autouse=True)
def _clean():
    """Plain TestClient, never the context-manager form: that runs the app
    lifespan, which starts four real cache loops against a fake BHNM URL."""
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    incident_cache._pending_overrides.clear()
    incident_cache._refresh_last.clear()
    incident_cache._refresh_locks.clear()
    incident_cache._types = {}
    orig_path, orig_tok = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = "operator-token-not-used-by-these-tests"
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig_path, orig_tok
    incident_cache._cache.clear()
    incident_cache._refresh_last.clear()


def _bhnm(body):
    """A stand-in BHNM that records every form it was posted. `calls` is the
    evidence for "exactly one getincidents and no getincidentdetail" — asserting
    on the answer alone would pass just as happily with a detail call beside it.
    """
    calls = []

    async def post(url, data=None, **kw):
        calls.append(dict(data or {}))
        resp = MagicMock(status_code=200)
        resp.json.return_value = body
        return resp

    client = MagicMock()
    client.post = post
    ctx = MagicMock()
    ctx.__aenter__ = AsyncMock(return_value=client)
    ctx.__aexit__ = AsyncMock(return_value=False)
    return ctx, calls


def _webhook(notification_type, incident_id):
    return TestClient(main_mod.app).post(
        "/webhook?secret=irrelevant-no-devices-registered",
        json={"notification_type": notification_type, "hostname": "raspi-050",
              "incident_id": str(incident_id), "output": "x"})


def _cached(iid):
    entry = incident_cache._cache["lab"]
    for inc in (*entry.active_incidents, *entry.closed_incidents):
        if str(inc["incident_id"]) == str(iid):
            return inc
    raise AssertionError(f"incident {iid} is in neither bucket")


# -- M1: the flag is not a state ------------------------------------------------

def test_an_acknowledgement_webhook_sets_the_FLAG_and_leaves_state_OPEN():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30005")], last_updated=time.time())
    assert _webhook("ACKNOWLEDGEMENT", 30005).status_code == 200
    inc = _cached(30005)
    assert inc["acknowledged"] is True
    assert inc["state"] == "OPEN", "ACKD is a SUBSET of OPEN, not a peer of it"


def test_acking_an_alarms_cleared_incident_does_not_reopen_its_alarms():
    """The defect M1 removes, in its sharpest form: with one field, an
    acknowledged incident whose alarms then clear can only be shown as one or
    the other."""
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30014", state="ALARMS CLEARED")], last_updated=time.time())
    _webhook("ACKNOWLEDGEMENT", 30014)
    inc = _cached(30014)
    assert inc["acknowledged"] is True
    assert inc["state"] == "ALARMS CLEARED", "both facts must survive together"


def test_an_acknowledgement_webhook_still_writes_ACKNOWLEDGED_into_incident_state():
    """The transition guarantee build 53 depends on.

    iOS 2.13.6 (NetreoAPIService.swift:1300-1308) and PWA 0.18.1
    (incidents.ts:101-104) derive their ENTIRE notion of acknowledgement from
    incident_state == "ACKNOWLEDGED". Dropping the value is a breaking change
    with no field removed at all.

    DELETED AT M1-drop, NOT BEFORE — once no BeNeM/53 remains in the proxy log,
    which is Thomas's word and never an inference from elapsed time.
    """
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30005")], last_updated=time.time())
    _webhook("ACKNOWLEDGEMENT", 30005)
    assert _cached(30005)["incident_state"] == "ACKNOWLEDGED"


def test_an_unacknowledgement_clears_the_flag_without_touching_the_state():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30014", state="ALARMS CLEARED", acknowledged=True)],
        last_updated=time.time())
    _webhook("DEACKNOWLEDGEMENT", 30014)
    inc = _cached(30014)
    assert inc["acknowledged"] is False
    assert inc["state"] == "ALARMS CLEARED"


def test_a_recovery_webhook_sets_state_CLOSED_and_stamps_closed_at():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30007")], last_updated=time.time())
    before = time.time()
    _webhook("RECOVERY", 30007)
    inc = _cached(30007)
    assert inc["state"] == "CLOSED"
    assert inc["incident_state"] == "CLOSED"
    assert before <= inc["closed_at"] <= time.time()


def test_a_second_recovery_does_not_move_closed_at():
    """A BHNM retry is a duplicate webhook, and it must not restart the 24-hour
    window on an incident that closed an hour ago."""
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30007")], last_updated=time.time())
    _webhook("RECOVERY", 30007)
    first = _cached(30007)["closed_at"]
    _webhook("RECOVERY", 30007)
    assert _cached(30007)["closed_at"] == first


def test_state_of_takes_the_ack_flag_back_OUT_of_the_state_field():
    assert state_of({"incident_state": "ACKNOWLEDGED"}) == "OPEN"
    assert state_of({"incident_state": "ALARMS CLEARED"}) == "ALARMS CLEARED"
    assert state_of({"incident_state": "CLOSED"}) == "CLOSED"
    # Unrecognised must not vanish: TOTL is OPEN + CLRD + CLSD, so a state in
    # none of the three would drop the row out of every pill on the client.
    assert state_of({"incident_state": "SOMETHING NEW"}) == "OPEN"
    assert state_of({}) == "OPEN"


def test_a_row_that_says_nothing_about_the_flag_says_None_not_False():
    """None is not False. [MEASURED] a getincidents row carries no ack field at
    all, and reading it as False would un-acknowledge every incident on every
    refresh."""
    assert ack_flag({"incident_id": "1", "incident_state": "OPEN"}) is None
    assert ack_flag({"acknowledged": 1}) is True
    assert ack_flag({"acknowledged": 0}) is False
    assert ack_flag({"primary_alarm_state": "ACKNOWLEDGED"}) is True


# -- M2: the refresh ------------------------------------------------------------

LIST_CLEARED = {"result": "completed", "active_incidents": [
    {"incident_id": "30014", "incident_state": "ALARMS CLEARED", "name": "UAP_AC_M",
     "title": "Anomaly Bandwidth on UAP_AC_M", "open_time": "2026-09-21T17:55:09"},
]}


def test_alarms_cleared_arrives_only_from_the_list_call():
    """[MEASURED 2026-09-21, BHNM-B] BHNM sends NO webhook for the ALARMS
    CLEARED transition — 30008-30011 went WARNING at 15:40Z and RECOVERY at
    16:16Z with nothing between, while BHNM's own list showed them cleared. So
    the list call is the only path this state has.
    """
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30014", state="OPEN")], last_updated=time.time())
    ctx, calls = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=HEADERS)
    assert r.status_code == 200
    assert r.json()["active_incidents"][0]["state"] == "ALARMS CLEARED"
    assert [c["method"] for c in calls] == ["getincidents"]


def test_the_refresh_endpoint_makes_exactly_one_getincidents_and_no_detail_call():
    """List-only is the point: `_fetch_incidents` is ONE request whatever the
    estate size, enrichment is one per incident paced over ~110 s. A refresh
    that waits for enrichment is not a refresh."""
    ctx, calls = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=HEADERS)
    assert r.status_code == 200
    assert len(calls) == 1
    assert calls[0]["method"] == "getincidents"
    assert not any(c["method"] == "getincidentdetail" for c in calls)
    # Counts are exactly what this call does not refresh, and the row says so
    # rather than claiming a time at which they were confirmed.
    assert r.json()["active_incidents"][0]["counts_confirmed_at"] is None
    assert r.json()["active_incidents"][0]["state_confirmed_at"] is not None


def test_two_refreshes_inside_30s_produce_ONE_upstream_call_and_the_same_answer():
    """C7: a tap inside the window returns the running one's result. A
    single-flight, not a 429 — a rejection would push the coalescing into two
    clients that would each implement it differently."""
    ctx, calls = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        client = TestClient(main_mod.app)
        first = client.post("/api/v1/incidents/refresh", headers=HEADERS)
        second = client.post("/api/v1/incidents/refresh", headers=HEADERS)
    assert len(calls) == 1, "one user's refresh serves everyone on that server"
    assert first.json()["coalesced"] is False
    assert second.json()["coalesced"] is True, "the response must say which it is"
    assert second.json()["active_incidents"] == first.json()["active_incidents"]


def test_a_refresh_after_the_window_goes_upstream_again():
    ctx, calls = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        client = TestClient(main_mod.app)
        client.post("/api/v1/incidents/refresh", headers=HEADERS)
        # Age the window rather than sleeping 30 s in a test suite.
        at, payload = incident_cache._refresh_last["lab"]
        incident_cache._refresh_last["lab"] = (at - incident_cache.REFRESH_WINDOW - 1, payload)
        client.post("/api/v1/incidents/refresh", headers=HEADERS)
    assert len(calls) == 2


def test_refresh_works_with_incident_polling_OFF():
    """The polling switch in its shipped form is `cache_enabled: false` — no
    background loop, so nothing else on this server ever calls getincidents.
    The refresh must still work, and must populate a cache that was never warm.
    """
    assert incident_cache.get_cached("nopoll") is None
    ctx, calls = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=NOPOLL_HEADERS)
    assert r.status_code == 200
    assert len(calls) == 1
    assert incident_cache.get_cached("nopoll") is not None


def test_a_refresh_keeps_the_counts_it_already_had():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30014", state="OPEN", acknowledged=True,
                               ack_user="Thomas iPhone 13 ProMax")],
        last_updated=time.time())
    ctx, _ = _bhnm(LIST_CLEARED)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=HEADERS)
    row = r.json()["active_incidents"][0]
    assert row["alarm_counts"] == {"red": 1, "orange": 0, "yellow": 0, "green": 0, "blue": 0}
    assert row["counts_confirmed_at"] is not None, "a KNOWN row keeps its own stamp"
    # The list row says nothing about the flag, so the refresh must not answer
    # for it — least of all with the healthy-looking value.
    assert row["acknowledged"] is True
    assert row["ack_user"] == "Thomas iPhone 13 ProMax"


def test_refresh_is_refused_without_a_proxy_token():
    assert TestClient(main_mod.app).post(
        "/api/v1/incidents/refresh", headers={"X-BHNM-Target": TARGET}).status_code == 401


# -- M3: CLSD retention ----------------------------------------------------------

def test_an_incident_that_disappears_from_the_list_is_retained_as_CLOSED():
    """The 30014 case. [MEASURED 2026-09-21] it produced ZERO webhook lines in
    the entire log and is simply absent from getincidents now — a rule that
    waited for a RECOVERY would let it vanish with no CLSD row at all."""
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[_row("30014"), _row("30015")], last_updated=time.time())
    now = time.time()
    closed = _retain_closed("lab", [_row("30015")], [], now)
    assert [c["incident_id"] for c in closed] == ["30014"]
    assert closed[0]["state"] == "CLOSED"
    assert closed[0]["closed_at"] == now, "the middleware's own clock — BHNM never said"


def test_retention_is_OFF_by_default_so_build_53_sees_no_closed_rows():
    """A purely additive payload producing a visible behaviour change on a
    released client: build 53's list applies NO status filter at all
    (IncidentListViewModel.filteredIncidents:69-102), so a retained closed row
    would simply appear in it with no pill to hide it."""
    from config import server_retain_closed
    assert server_retain_closed({"id": "lab"}) is False
    assert server_retain_closed({"id": "lab", "retain_closed": True}) is True


def test_a_closed_row_is_served_for_24h_from_closed_at_and_dropped_after():
    now = time.time()
    rows = [_row("1", state="CLOSED", closed_at=now - RETENTION_SECONDS + 60),
            _row("2", state="CLOSED", closed_at=now - RETENTION_SECONDS - 60)]
    kept = _prune_aged("lab", rows, now)
    assert [r["incident_id"] for r in kept] == ["1"]


def test_the_24h_window_runs_from_closed_at_not_open_time():
    """RULED 2026-09-21, open question 1. An incident open for three days and
    closed ten minutes ago is CLSD."""
    now = time.time()
    row = _row("1", state="CLOSED", closed_at=now - 600,
               open_time="2026-09-18T10:00:00")
    assert _prune_aged("lab", [row], now) == [row]


def test_nothing_older_than_24h_is_held_in_any_state():
    """C15's other half. The sweep is over both buckets, not just the closed one."""
    now = time.time()
    aged = _row("9", state="CLOSED", closed_at=now - RETENTION_SECONDS - 1)
    assert _prune_aged("lab", [aged], now) == []
    # An OPEN row carries no closed_at and is replaced wholesale by every list
    # call, so it cannot age — but it must also not be swept.
    old_open = _row("10", state="OPEN", open_time="2026-09-01T00:00:00")
    assert _prune_aged("lab", [old_open], now) == [old_open]


def test_incident_types_is_NOT_dropped_by_the_24h_rule():
    """C15's exemption. incident_types is an id->type map, not incident data,
    and dropping it would re-open C11's UNKNOWN on every aged incident."""
    incident_cache._types = {("lab", "1"): "service"}
    now = time.time()
    _prune_aged("lab", [_row("1", state="CLOSED",
                             closed_at=now - RETENTION_SECONDS - 1)], now)
    assert incident_cache.known_type("lab", "1") == "service"


def test_override_fields_are_applied_in_exactly_one_place():
    """A webhook, a proxied ACK and a re-applied override must never disagree
    about what an override means."""
    row = _row("1", state="ALARMS CLEARED")
    _apply_override_fields(row, "ACKNOWLEDGED", 1000.0)
    assert (row["incident_state"], row["state"], row["acknowledged"]) == \
        ("ACKNOWLEDGED", "ALARMS CLEARED", True)
    _apply_override_fields(row, "CLOSED", 2000.0)
    assert (row["incident_state"], row["state"], row["closed_at"]) == ("CLOSED", "CLOSED", 2000.0)


# -- The body must say it completed before anything is derived from it ----------
# Retention is what raises the stakes here. An error answer has no
# active_incidents key, and an unchecked body reads as ZERO incidents. Before
# CLSD retention that blanked one cycle and the next one repaired it. With
# retention, zero incidents means every cached incident vanished from the list,
# which _retain_closed correctly treats as a close — the whole estate marked
# CLOSED with a closed_at and served as CLSD for the next 24 hours.

RETAIN_SERVER = {"id": "retain", "url": RETAIN_TARGET, "api_key": RETAIN_KEY,
                 "pin": "", "cache_refresh_seconds": 120, "retain_closed": True}

# A wrong api_key, an HTTPS refusal, a BHNM fault: whatever the wording, the
# shape is the same — it does not say `completed` and it has no incident list.
ERROR_BODY = {"result": "error", "detail": "Invalid password."}


@pytest.mark.asyncio
async def test_an_error_body_RAISES_and_the_cache_is_untouched():
    """The cycle must FAIL, so that no retention pass runs at all. A cycle that
    succeeds on an error answer is the doctrine failure in its operational form:
    the positive result is real and measures something other than the thing that
    mattered."""
    before = CachedIncidents(active_incidents=[_row("30005"), _row("30006")],
                             closed_incidents=[], last_updated=time.time())
    incident_cache._cache["retain"] = before

    async def post(url, data=None, **kw):
        resp = MagicMock(status_code=200)
        resp.json.return_value = ERROR_BODY
        return resp

    client = MagicMock()
    client.post = post
    with pytest.raises(ValueError):
        await incident_cache._run_one_cycle(client, RETAIN_SERVER)

    assert incident_cache._cache["retain"] is before, "the cache entry was replaced"
    assert [i["state"] for i in before.active_incidents] == ["OPEN", "OPEN"]
    assert before.closed_incidents == []
    assert all(i["closed_at"] is None for i in before.active_incidents)


@pytest.mark.asyncio
async def test_a_completed_body_with_no_active_incidents_key_closes_everything():
    """The legitimate zero, and it must still work. [MEASURED 2026-09-19] BHNM's
    own "none" answer is {"result":"completed","detail":"No active incident."} —
    it completed, it simply has nothing to list, and every cached incident really
    has gone."""
    incident_cache._cache["retain"] = CachedIncidents(
        active_incidents=[_row("30005")], closed_incidents=[], last_updated=time.time())

    async def post(url, data=None, **kw):
        resp = MagicMock(status_code=200)
        resp.json.return_value = {"result": "completed", "detail": "No active incident."}
        return resp

    client = MagicMock()
    client.post = post
    await incident_cache._run_one_cycle(client, RETAIN_SERVER)

    entry = incident_cache._cache["retain"]
    assert entry.active_incidents == []
    assert [i["incident_id"] for i in entry.closed_incidents] == ["30005"]
    assert entry.closed_incidents[0]["state"] == "CLOSED"
    assert entry.closed_incidents[0]["closed_at"] is not None


def test_the_refresh_path_refuses_an_error_body_too():
    """Same guard, same function — the refresh reaches BHNM through
    _fetch_incidents, so fixing it in one place fixes both callers."""
    before = CachedIncidents(active_incidents=[_row("30005")], closed_incidents=[],
                             last_updated=time.time())
    incident_cache._cache["retain"] = before
    ctx, calls = _bhnm(ERROR_BODY)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=RETAIN_HEADERS)
    assert r.status_code == 502
    assert incident_cache._cache["retain"] is before
    assert before.active_incidents[0]["state"] == "OPEN"
    # And a failed refresh must not be coalesced: the next tap has to try again
    # rather than be handed a 30-second-old failure as an answer.
    assert "retain" not in incident_cache._refresh_last


@pytest.mark.asyncio
async def test_a_non_json_body_raises_rather_than_reading_as_zero_incidents():
    """PHP's "API require HTTPS" is not JSON at all."""
    async def post(url, data=None, **kw):
        resp = MagicMock(status_code=200)
        resp.json.side_effect = ValueError("no json")
        return resp

    client = MagicMock()
    client.post = post
    with pytest.raises(ValueError):
        await incident_cache._fetch_incidents(client, RETAIN_SERVER)
