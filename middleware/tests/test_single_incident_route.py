"""GET /api/v1/incidents/{id} — 404 and 502 kept DISTINCT.

Designed 2026-09-15 (Part 2), unbuilt until now. The point of the route is the
distinction: one is a terminal fact, the other is "ask again later", and
collapsing them is what produces `Incident not found.` said to someone whose
network was simply down.

[MEASURED 2026-09-19 against the lab] BHNM answers a missing incident with
HTTP 200 and no `incident` key: {"result":"completed","detail":"No active incident."}
So the 404 signal is structural, not a status code.

Design: docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md
build order step 3.
"""

import json
import os
import tempfile

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")

_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ.setdefault("DB_PATH", _tmp.name)
_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
API_KEY = "single-incident-key"
TARGET = "https://bhnm.example.com"
json.dump([{"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY,
            "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120}], _servers)
_servers.close()
os.environ.setdefault("SERVERS_JSON_PATH", _servers.name)

import httpx
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import main as main_mod
import incident_cache
from incident_cache import CachedIncidents, normalise_incident_id, merge_incident

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}

FOUND_BODY = {
    "result": "completed",
    "incident": {
        "incident_id": "25076", "incident_state": "OPEN",
        "title": "Application Service Wordpress", "name": "Wordpress Admin",
        "device_category": "", "device_site": "", "device_note": "",
        "incident_open_time": "2026-05-26T02:20:42",
        "acknowledged": 0, "ack_time": "", "ack_user": "", "ack_comment": "",
        "alert_type": "Service",
        "detail": {"primary_alarm_log": [{"state": "CRITICAL"}], "relatedalarms": None},
    },
}
# The real shape, copied from the lab probe of a nonexistent id.
MISSING_BODY = {"result": "completed", "detail": "No active incident."}


@pytest.fixture(autouse=True)
def _clean():
    """No `with TestClient(...)` anywhere below: the context-manager form runs the
    app lifespan, which starts four real cache loops against a fake BHNM URL and
    hangs the suite. The rest of the suite uses the plain form for the same reason.
    """
    incident_cache._cache.clear()
    incident_cache._types = {}
    orig_path, orig_tok = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = "operator-token-not-used-by-these-tests"
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig_path, orig_tok
    incident_cache._cache.clear()


def _client_returning(body, status=200):
    resp = MagicMock(status_code=status)
    resp.json.return_value = body
    client = MagicMock()
    client.post = AsyncMock(return_value=resp)
    ctx = MagicMock()
    ctx.__aenter__ = AsyncMock(return_value=client)
    ctx.__aexit__ = AsyncMock(return_value=False)
    return ctx


def test_a_missing_incident_is_404_not_502():
    with patch("main.httpx.AsyncClient", return_value=_client_returning(MISSING_BODY)):
        r = TestClient(main_mod.app).get("/api/v1/incidents/99999999", headers=HEADERS)
    assert r.status_code == 404
    assert r.json() == {"error": "incident_not_found"}


def test_an_unreachable_bhnm_is_502_not_404():
    """The whole reason the route exists. A client that cannot reach BHNM must
    never be told the incident does not exist."""
    ctx = MagicMock()
    ctx.__aenter__ = AsyncMock(side_effect=httpx.ConnectError("boom"))
    ctx.__aexit__ = AsyncMock(return_value=False)
    with patch("main.httpx.AsyncClient", return_value=ctx):
        r = TestClient(main_mod.app).get("/api/v1/incidents/25076", headers=HEADERS)
    assert r.status_code == 502
    assert r.json() == {"error": "upstream_unavailable"}


def test_a_5xx_from_bhnm_is_502_not_404():
    with patch("main.httpx.AsyncClient", return_value=_client_returning({}, status=503)):
        r = TestClient(main_mod.app).get("/api/v1/incidents/25076", headers=HEADERS)
    assert r.status_code == 502


def test_a_found_incident_returns_a_list_shaped_row_with_C9_stamps():
    with patch("main.httpx.AsyncClient", return_value=_client_returning(FOUND_BODY)):
        r = TestClient(main_mod.app).get("/api/v1/incidents/25076", headers=HEADERS)
    assert r.status_code == 200
    body = r.json()
    assert body["incident_id"] == "25076"
    assert body["incident_state"] == "OPEN"
    # open_time is the one rename between the list and the detail shape.
    assert body["open_time"] == "2026-05-26T02:20:42"
    assert body["alert_type"] == "service"
    assert body["ack_user"] == ""
    assert body["state_confirmed_at"] is not None
    assert body["counts_confirmed_at"] is not None


def test_an_unauthenticated_request_is_refused():
    r = TestClient(main_mod.app).get("/api/v1/incidents/25076", headers={"X-BHNM-Target": TARGET})
    assert r.status_code == 401


def test_a_non_numeric_id_is_refused_before_any_upstream_call():
    r = TestClient(main_mod.app).get("/api/v1/incidents/not-an-id", headers=HEADERS)
    assert r.status_code == 400


# -- id normalisation and the bucket move ------------------------------------

def test_normalise_strips_a_server_prefix_but_keeps_a_bare_id():
    assert normalise_incident_id("NetreoCloudDemo-24090") == "24090"
    assert normalise_incident_id("29570") == "29570"
    assert normalise_incident_id(29570) == "29570"


def test_normalise_leaves_a_non_numeric_tail_alone():
    """Tolerant in, strict out — but not so tolerant it invents an id."""
    assert normalise_incident_id("weird-name") == "weird-name"


def test_a_recovered_incident_MOVES_buckets_it_does_not_just_relabel():
    """BHNM moves a recovered incident out of the active set, so BeNeM must. A
    CLOSED row left in the active bucket leaves the active COUNT counting
    something that is not active.
    """
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[{"incident_id": "25076", "incident_state": "OPEN"}],
        closed_incidents=[],
    )
    merged = merge_incident("lab", {"incident_id": "25076", "incident_state": "CLOSED"})
    entry = incident_cache._cache["lab"]
    assert merged is True
    assert entry.active_incidents == []
    assert len(entry.closed_incidents) == 1


def test_merge_replaces_rather_than_duplicates():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[{"incident_id": "25076", "incident_state": "OPEN"}])
    merge_incident("lab", {"incident_id": "25076", "incident_state": "ACKNOWLEDGED"})
    entry = incident_cache._cache["lab"]
    assert len(entry.active_incidents) == 1
    assert entry.active_incidents[0]["incident_state"] == "ACKNOWLEDGED"


def test_merge_matches_across_the_prefixed_and_bare_forms():
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[{"incident_id": "NetreoCloudDemo-24090", "incident_state": "OPEN"}])
    merge_incident("lab", {"incident_id": "24090", "incident_state": "CLOSED"})
    entry = incident_cache._cache["lab"]
    assert entry.active_incidents == [], "the prefixed row must not survive as a duplicate"
    assert len(entry.closed_incidents) == 1


def test_a_cold_cache_reports_that_it_could_not_merge():
    """Not an error — the caller still gets its answer — but it must not look
    like a successful merge."""
    assert merge_incident("lab", {"incident_id": "1", "incident_state": "OPEN"}) is False
