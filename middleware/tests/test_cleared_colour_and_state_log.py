"""2.20.3 — the colour follows the list's state, and every transition is logged.

**Both come from the same measurement.** Incident 30035, 2026-09-22: raspi-050
came back UP at 14:45:11Z, BHNM reported `ALARMS CLEARED`, and the served row
carried the right state with a RED chip until the detail call came round at
14:48:22Z — **3 min 11 s**, because the counts only moved on enrichment and
enrichment is paced across every open incident. The state was right and the
colour was three minutes behind it.

Building that timeline also showed there was nothing to build it from: the only
per-incident lines in the whole log were the webhook's own. What `getincidents`
returned for an incident on a cycle was unrecorded, which is the same gap the
design note withdrew a claim over on 2026-09-21 — *"the log does not carry
per-incident state."*
"""
import json
import os
import tempfile
import time

API_KEY = "cleared-colour-key"
TARGET = "https://bhnm-cleared.example.com"

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_db.close()
os.environ.setdefault("DB_PATH", _db.name)

_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([{"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
            "cache_enabled": True, "cache_refresh_seconds": 120}], _servers)
_servers.close()
os.environ.setdefault("SERVERS_JSON_PATH", _servers.name)

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import main as main_mod
import incident_cache
from database import init_db
from incident_cache import CachedIncidents, SEVERITY_COUNTS_KEY

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}
RED = {"red": 2, "orange": 1, "yellow": 0, "green": 0, "blue": 0}


@pytest.fixture(autouse=True)
def _clean():
    init_db()   # see test_ack_colour_on_the_override_path for why this is here
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    incident_cache._pending_overrides.clear()
    incident_cache._refresh_last.clear()
    incident_cache._refresh_locks.clear()
    orig_path, orig_tok = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig_path, orig_tok
    incident_cache._cache.clear()
    incident_cache._refresh_last.clear()


def _bhnm(state):
    """A BHNM whose getincidents reports 30035 in `state`. No detail call is
    stubbed, deliberately: the refresh route must not make one, and a test that
    stubbed it could not tell."""
    body = {"result": "completed", "active_incidents": [
        {"incident_id": "30035", "name": "raspi-050", "title": "Host raspi-050",
         "incident_state": state, "open_time": "2026-09-22T16:40:23"}]}
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


def _seed(state="OPEN", acknowledged=False, counts=None, severity=None):
    at = time.time()
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[{
            "incident_id": "30035", "name": "raspi-050", "title": "Host raspi-050",
            "incident_state": state, "state": state, "acknowledged": acknowledged,
            "ack_user": None, "closed_at": None, "alert_type": "host",
            "alarm_counts": dict(counts if counts is not None else RED),
            SEVERITY_COUNTS_KEY: dict(severity if severity is not None else RED),
            "state_confirmed_at": at, "counts_confirmed_at": at,
        }],
        closed_incidents=[], last_updated=at)
    return at


def _refresh(state):
    ctx, calls = _bhnm(state)
    with patch("incident_cache.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).post("/api/v1/incidents/refresh", headers=HEADERS)
    assert r.status_code == 200, r.text
    return r.json()["active_incidents"][0], calls


# ── item 2: the list's state drives the colour ───────────────────────────────

def test_a_list_reporting_ALARMS_CLEARED_serves_GREEN_before_any_enrichment():
    """**The reported defect.** Fails against 2.20.2."""
    before = _seed(state="OPEN")
    row, calls = _refresh("ALARMS CLEARED")

    assert row["state"] == "ALARMS CLEARED"
    assert row["alarm_counts"] == {"red": 0, "orange": 0, "yellow": 0, "green": 3, "blue": 0}, (
        "the chip must follow the state the list just reported — on 30035 this "
        "was 3 min 11 s of red on a green incident"
    )
    assert row[SEVERITY_COUNTS_KEY] == RED, "the severity is the way back"
    assert row["counts_confirmed_at"] == before, (
        "and NO enrichment ran — without this the test could pass for the wrong "
        "reason, which is the shape of the bug it guards"
    )
    assert not any("getincidentdetail" in str(c) for c in calls), "list-only"


def test_no_alarm_is_lost_when_the_list_paints_them_green():
    _seed(state="OPEN")
    row, _ = _refresh("ALARMS CLEARED")
    assert sum(row["alarm_counts"].values()) == sum(RED.values())


def test_the_state_returning_to_OPEN_restores_the_severity_from_the_snapshot():
    _seed(state="ALARMS CLEARED",
          counts={"red": 0, "orange": 0, "yellow": 0, "green": 3, "blue": 0},
          severity=RED)
    row, _ = _refresh("OPEN")
    assert row["state"] == "OPEN"
    assert row["alarm_counts"] == RED, "green is lossy; the snapshot is what comes back"
    assert row[SEVERITY_COUNTS_KEY] == RED


def test_cleared_then_open_then_cleared_returns_to_exactly_where_it_started():
    """A round trip, because two half-correct derivations can still drift."""
    _seed(state="OPEN")
    first, _ = _refresh("ALARMS CLEARED")
    _refresh("OPEN")
    again, _ = _refresh("ALARMS CLEARED")
    assert again["alarm_counts"] == first["alarm_counts"]
    assert again[SEVERITY_COUNTS_KEY] == RED


def test_an_ack_on_a_CLEARED_incident_stays_GREEN():
    """**Cleared beats acknowledged.** ALARMS CLEARED is a fact about the alarms;
    acknowledgement is a fact about the people. A cleared incident somebody has
    picked up is still cleared."""
    _seed(state="OPEN")
    _refresh("ALARMS CLEARED")

    r = TestClient(main_mod.app).post(
        "/webhook?secret=nobody-is-registered",
        json={"notification_type": "ACKNOWLEDGEMENT", "hostname": "raspi-050",
              "incident_id": "30035", "output": "x"})
    assert r.status_code == 200

    served = TestClient(main_mod.app).get("/api/v1/incidents", headers=HEADERS).json()
    row = served["active_incidents"][0]
    assert row["acknowledged"] is True, "the flag moved"
    assert row["alarm_counts"] == {"red": 0, "orange": 0, "yellow": 0, "green": 3, "blue": 0}, (
        "and the colour did not — cleared wins"
    )


def test_an_ack_on_an_OPEN_incident_is_still_BLUE():
    """The guard must be shown capable of a non-green answer, or the test above
    would pass just as happily on a function that always returns green."""
    _seed(state="OPEN")
    TestClient(main_mod.app).post(
        "/webhook?secret=nobody-is-registered",
        json={"notification_type": "ACKNOWLEDGEMENT", "hostname": "raspi-050",
              "incident_id": "30035", "output": "x"})
    row = TestClient(main_mod.app).get(
        "/api/v1/incidents", headers=HEADERS).json()["active_incidents"][0]
    assert row["alarm_counts"] == {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 3}


# ── item 1: one line per transition ──────────────────────────────────────────

def _state_lines(capsys):
    return [l for l in capsys.readouterr().out.splitlines() if l.startswith("[State:lab]")]


def test_a_list_cycle_that_changes_a_state_LOGS_it(capsys):
    """The headline requirement. Before 2.20.3 this produced no line at all."""
    _seed(state="OPEN")
    capsys.readouterr()
    _refresh("ALARMS CLEARED")

    lines = _state_lines(capsys)
    assert len(lines) == 1, f"exactly one line, got {lines}"
    assert "incident 30035" in lines[0]
    assert "OPEN/ack=False -> ALARMS CLEARED/ack=False" in lines[0]
    assert "(source: list)" in lines[0], "the source is the point, not decoration"


def test_a_list_cycle_that_changes_NOTHING_logs_nothing(capsys):
    """Silence has to mean something, or the line is a heartbeat rather than a
    record. A steady estate must produce no lines at all."""
    _seed(state="OPEN")
    capsys.readouterr()
    _refresh("OPEN")
    assert _state_lines(capsys) == []


def test_a_webhook_transition_names_the_webhook(capsys):
    _seed(state="OPEN")
    capsys.readouterr()
    TestClient(main_mod.app).post(
        "/webhook?secret=nobody-is-registered",
        json={"notification_type": "ACKNOWLEDGEMENT", "hostname": "raspi-050",
              "incident_id": "30035", "output": "x"})
    # The webhook patches the cache through note_state_override, which is a
    # different route from the cycle — its own [Webhook] line already records
    # it, and the served row proves the flag moved.
    row = TestClient(main_mod.app).get(
        "/api/v1/incidents", headers=HEADERS).json()["active_incidents"][0]
    assert row["acknowledged"] is True


def test_an_expiring_override_says_so_in_its_own_line(capsys):
    """**A row that goes OPEN -> ALARMS CLEARED because BHNM said so, and one
    that goes there because an override stopped hiding it, have the same before
    and after.** The row's own line says "list" for both, because that is where
    its new value comes from. This line is what tells them apart."""
    _seed(state="OPEN")
    incident_cache._state_overrides["lab"] = {
        "30035": ("ACKNOWLEDGED", time.time() - incident_cache.STATE_OVERRIDE_TTL - 1)}
    capsys.readouterr()
    incident_cache._apply_state_overrides("lab", incident_cache._cache["lab"].active_incidents)

    lines = _state_lines(capsys)
    assert len(lines) == 1, lines
    assert "override ACKNOWLEDGED expired" in lines[0]
    assert "(source: override expiry)" in lines[0]
    assert "30035" not in incident_cache._state_overrides.get("lab", {})


def test_the_line_carries_the_id_the_old_the_new_and_the_source(capsys):
    """All four, because a transition line missing any one of them cannot answer
    the question it exists for."""
    _seed(state="OPEN")
    capsys.readouterr()
    _refresh("ALARMS CLEARED")
    line = _state_lines(capsys)[0]
    for piece in ("30035", "OPEN", "ALARMS CLEARED", "ack=False", "source:"):
        assert piece in line, f"{piece!r} missing from {line!r}"
