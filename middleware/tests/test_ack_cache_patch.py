import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_ack_patch.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_ack_patch.json")

import json
import time
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import incident_cache
from main import app


@pytest.fixture(autouse=True)
def setup(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com", "api_key": "secret-key-123"}
    ]))
    import main as main_mod
    import threshold_cache
    old = (main_mod.SERVERS_JSON_PATH, threshold_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN)
    main_mod.SERVERS_JSON_PATH = str(servers_file)
    threshold_cache.SERVERS_JSON_PATH = str(servers_file)
    main_mod.PROXY_TOKEN = ""
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    yield
    main_mod.SERVERS_JSON_PATH, threshold_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = old
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()


@pytest.fixture
def client():
    return TestClient(app)


def _seed_cache():
    incident_cache._cache["prod"] = incident_cache.CachedIncidents(
        active_incidents=[
            {"incident_id": "100", "incident_state": "OPEN", "title": "t1"},
            {"incident_id": "200", "incident_state": "ACKNOWLEDGED", "title": "t2"},
        ],
        closed_incidents=[],
        last_updated=time.time(),
    )


# ── override store + live patch ──────────────────────────────────────────────


def test_note_override_patches_live_cache():
    _seed_cache()
    incident_cache.note_state_override("prod", "100", "ACKNOWLEDGED")
    states = {i["incident_id"]: i["incident_state"]
              for i in incident_cache._cache["prod"].active_incidents}
    assert states["100"] == "ACKNOWLEDGED"


def test_store_applies_fresh_overrides_to_stale_snapshot():
    # A cycle that started BEFORE the ack must not revert it at store time
    incident_cache.note_state_override("prod", "100", "ACKNOWLEDGED")
    stale = [{"incident_id": "100", "incident_state": "OPEN"}]
    incident_cache._apply_state_overrides("prod", stale)
    assert stale[0]["incident_state"] == "ACKNOWLEDGED"


def test_expired_override_not_applied():
    incident_cache._state_overrides["prod"] = {"100": ("ACKNOWLEDGED", time.time() - 600)}
    stale = [{"incident_id": "100", "incident_state": "OPEN"}]
    incident_cache._apply_state_overrides("prod", stale)
    assert stale[0]["incident_state"] == "OPEN"
    assert "100" not in incident_cache._state_overrides["prod"]


# ── route wiring ─────────────────────────────────────────────────────────────


def _bhnm_ok(detail=b'{"result": "completed", "detail": "This incident has been ACKNOWLEDGED."}'):
    mock_response = MagicMock()
    mock_response.content = detail
    mock_response.status_code = 200
    mock_response.headers = {}
    inst = AsyncMock()

    async def mock_request(*args, **kwargs):
        return mock_response
    inst.request = mock_request
    inst.__aenter__ = AsyncMock(return_value=inst)
    inst.__aexit__ = AsyncMock(return_value=False)
    return inst


HDRS = {"X-Proxy-Token": "secret-key-123", "X-BHNM-Target": "https://bhnm.example.com"}


def test_dedicated_ack_route_patches_cache(client):
    _seed_cache()
    with patch("httpx.AsyncClient", return_value=_bhnm_ok()):
        resp = client.post("/api/proxy/incident/acknowledge",
                           data={"password": "secret-key-123", "incident_id": "100", "user": "tom"},
                           headers=HDRS)
    assert resp.status_code == 200
    states = {i["incident_id"]: i["incident_state"]
              for i in incident_cache._cache["prod"].active_incidents}
    assert states["100"] == "ACKNOWLEDGED"


def test_dedicated_unack_route_patches_cache(client):
    _seed_cache()
    with patch("httpx.AsyncClient", return_value=_bhnm_ok(b'{"result": "completed", "detail": "UNACKNOWLEDGED"}')):
        client.post("/api/proxy/incident/unacknowledge",
                    data={"password": "secret-key-123", "incident_id": "200", "user": "tom"},
                    headers=HDRS)
    states = {i["incident_id"]: i["incident_state"]
              for i in incident_cache._cache["prod"].active_incidents}
    assert states["200"] == "OPEN"


def test_catchall_restful_ack_patches_cache(client):
    # iOS calls /fw/index.php?r=restful/incident/acknowledge via the catch-all
    _seed_cache()
    with patch("httpx.AsyncClient", return_value=_bhnm_ok()):
        resp = client.post("/fw/index.php?r=restful/incident/acknowledge",
                           data={"password": "secret-key-123", "incident_id": "100", "user": "tom"},
                           headers={"X-Proxy-Token": "secret-key-123"})
    assert resp.status_code == 200
    states = {i["incident_id"]: i["incident_state"]
              for i in incident_cache._cache["prod"].active_incidents}
    assert states["100"] == "ACKNOWLEDGED"


def test_no_patch_on_bhnm_error(client):
    _seed_cache()
    with patch("httpx.AsyncClient", return_value=_bhnm_ok(b'{"result": "error", "detail": "no"}')):
        client.post("/api/proxy/incident/acknowledge",
                    data={"password": "secret-key-123", "incident_id": "100", "user": "tom"},
                    headers=HDRS)
    states = {i["incident_id"]: i["incident_state"]
              for i in incident_cache._cache["prod"].active_incidents}
    assert states["100"] == "OPEN"
