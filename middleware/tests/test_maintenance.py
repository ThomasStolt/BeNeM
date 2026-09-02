import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_maintenance.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_maintenance.json")

import json
import time
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from urllib.parse import parse_qs, urlencode
from fastapi.testclient import TestClient
from main import app


@pytest.fixture(autouse=True)
def setup_servers(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com", "api_key": "secret-key-123"}
    ]))
    import main as main_mod
    original_path = main_mod.SERVERS_JSON_PATH
    original_proxy_token = main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = str(servers_file)
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH = original_path
    main_mod.PROXY_TOKEN = original_proxy_token


@pytest.fixture
def client():
    return TestClient(app)


# ── snap_start boundary math (§3a) ──────────────────────────────────────────
# Epochs relative to an exact hour H (any multiple of 3600 works; use 36000 = 10:00:00 UTC).

H = 36000  # 10:00:00


def test_snap_start_exact_boundary_goes_to_next():
    from main import snap_start
    assert snap_start(H) == H + 300           # 10:00:00 → 10:05:00


def test_snap_start_one_second_past_boundary():
    from main import snap_start
    assert snap_start(H + 301) == H + 600     # 10:05:01 → 10:10:00


def test_snap_start_inside_margin_skips_to_following_boundary():
    from main import snap_start
    assert snap_start(H + 299) == H + 600     # 10:04:59 → 10:10:00


def test_snap_start_exactly_at_margin_is_allowed():
    from main import snap_start
    assert snap_start(H + 240) == H + 300     # 10:04:00 → 10:05:00 (60 s lead ok; < is strict)


def test_maintenance_create_rejects_missing_token(client):
    resp = client.post(
        "/api/proxy/maintenance/create",
        data={"name": "Router 1", "duration": "60"},
        headers={"X-BHNM-Target": "https://bhnm.example.com"},
    )
    assert resp.status_code == 401


def test_maintenance_create_rejects_missing_name(client):
    resp = client.post(
        "/api/proxy/maintenance/create",
        data={"duration": "60"},
        headers={
            "X-Proxy-Token": "secret-key-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
    )
    assert resp.status_code == 400
    assert "name" in resp.json()["detail"].lower()


def test_maintenance_create_rejects_missing_duration(client):
    resp = client.post(
        "/api/proxy/maintenance/create",
        data={"name": "Router 1"},
        headers={
            "X-Proxy-Token": "secret-key-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
    )
    assert resp.status_code == 400
    assert "duration" in resp.json()["detail"].lower()


def test_maintenance_create_rejects_duration_less_than_1(client):
    resp = client.post(
        "/api/proxy/maintenance/create",
        data={"name": "Router 1", "duration": "0"},
        headers={
            "X-Proxy-Token": "secret-key-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
    )
    assert resp.status_code == 400


def test_maintenance_create_rejects_non_numeric_duration(client):
    resp = client.post(
        "/api/proxy/maintenance/create",
        data={"name": "Router 1", "duration": "abc"},
        headers={
            "X-Proxy-Token": "secret-key-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
    )
    assert resp.status_code == 400


def test_maintenance_create_forwards_correctly_to_bhnm(client):
    duration_minutes = 30
    before = int(time.time())

    mock_response = MagicMock()
    mock_response.content = b'{"status": "ok"}'
    mock_response.status_code = 200
    mock_response.headers = {}

    captured_kwargs = {}

    async def mock_request(*args, **kwargs):
        captured_kwargs.update(kwargs)
        return mock_response

    mock_client_instance = AsyncMock()
    mock_client_instance.request = mock_request
    mock_client_instance.__aenter__ = AsyncMock(return_value=mock_client_instance)
    mock_client_instance.__aexit__ = AsyncMock(return_value=False)

    with patch("httpx.AsyncClient", return_value=mock_client_instance):
        resp = client.post(
            "/api/proxy/maintenance/create",
            data={"name": "core-router-01", "duration": str(duration_minutes), "comment": "Patching"},
            headers={
                "X-Proxy-Token": "secret-key-123",
                "X-BHNM-Target": "https://bhnm.example.com",
            },
        )

    after = int(time.time())

    assert resp.status_code == 200

    # Decode the forwarded body
    forwarded_body = captured_kwargs.get("content", b"")
    if isinstance(forwarded_body, bytes):
        forwarded_body = forwarded_body.decode("utf-8")
    parsed = parse_qs(forwarded_body)

    assert parsed.get("action", [""])[0] == "new"
    assert parsed.get("name", [""])[0] == "core-router-01"
    assert parsed.get("comment", [""])[0] == "Patching"
    assert parsed.get("password", [""])[0] == "secret-key-123"

    start_time = int(parsed.get("start_time", ["0"])[0])
    end_time = int(parsed.get("end_time", ["0"])[0])

    # start_time snaps to the next 5-min boundary, >=60s ahead (§3a)
    from main import snap_start
    assert start_time in (snap_start(before), snap_start(after))
    assert start_time % 300 == 0
    assert start_time - before >= 60

    # end_time should be start_time + duration*60
    expected_end = start_time + duration_minutes * 60
    assert end_time == expected_end

    # The snapped start is echoed to the client; the body stays a verbatim passthrough
    assert resp.headers.get("X-Maintenance-Start") == str(start_time)
    assert resp.content == b'{"status": "ok"}'

    # Verify the target URL
    assert captured_kwargs.get("url", "").endswith("/api/maint_window_api.php")


# ── /api/proxy/maintenance/close (§3b) ──────────────────────────────────────


def test_maintenance_close_rejects_missing_token(client):
    resp = client.post(
        "/api/proxy/maintenance/close",
        data={"name": "Router 1"},
        headers={"X-BHNM-Target": "https://bhnm.example.com"},
    )
    assert resp.status_code == 401


def test_maintenance_close_rejects_missing_name(client):
    resp = client.post(
        "/api/proxy/maintenance/close",
        data={},
        headers={
            "X-Proxy-Token": "secret-key-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
    )
    assert resp.status_code == 400
    assert "name" in resp.json()["detail"].lower()


def test_maintenance_close_forwards_correctly_to_bhnm(client):
    mock_response = MagicMock()
    mock_response.content = b'{"result": "completed", "detail": "All maintenance windows for this device are closed"}'
    mock_response.status_code = 200
    mock_response.headers = {}

    captured_kwargs = {}

    async def mock_request(*args, **kwargs):
        captured_kwargs.update(kwargs)
        return mock_response

    mock_client_instance = AsyncMock()
    mock_client_instance.request = mock_request
    mock_client_instance.__aenter__ = AsyncMock(return_value=mock_client_instance)
    mock_client_instance.__aexit__ = AsyncMock(return_value=False)

    with patch("httpx.AsyncClient", return_value=mock_client_instance):
        resp = client.post(
            "/api/proxy/maintenance/close",
            data={"name": "core-router-01"},
            headers={
                "X-Proxy-Token": "secret-key-123",
                "X-BHNM-Target": "https://bhnm.example.com",
            },
        )

    assert resp.status_code == 200
    # Response body passes through verbatim
    assert resp.content == mock_response.content

    forwarded_body = captured_kwargs.get("content", b"")
    if isinstance(forwarded_body, bytes):
        forwarded_body = forwarded_body.decode("utf-8")
    parsed = parse_qs(forwarded_body)

    assert parsed.get("action", [""])[0] == "close"
    assert parsed.get("name", [""])[0] == "core-router-01"
    # api_key resolved server-side, never taken from the client
    assert parsed.get("password", [""])[0] == "secret-key-123"
    assert captured_kwargs.get("url", "").endswith("/api/maint_window_api.php")


# ── /api/proxy/maintenance/status (D2 merged route) ─────────────────────────


def _status_client_mock(host_status_result, list_result):
    """Mock httpx.AsyncClient dispatching by URL; results may be Exceptions.
    Returns (mock_client_instance, captured) where captured maps url→kwargs."""
    captured = {}

    async def mock_request(*args, **kwargs):
        url = kwargs.get("url", "")
        captured[url] = kwargs
        if "get-host-and-service-status" in url:
            result = host_status_result
        else:
            result = list_result
        if isinstance(result, Exception):
            raise result
        mock_response = MagicMock()
        mock_response.content = json.dumps(result).encode()
        mock_response.status_code = 200
        mock_response.headers = {}
        mock_response.json = MagicMock(return_value=result)
        return mock_response

    inst = AsyncMock()
    inst.request = mock_request
    inst.post = mock_request
    inst.__aenter__ = AsyncMock(return_value=inst)
    inst.__aexit__ = AsyncMock(return_value=False)
    return inst, captured


STATUS_HEADERS = {
    "X-Proxy-Token": "secret-key-123",
    "X-BHNM-Target": "https://bhnm.example.com",
}


def test_maintenance_status_rejects_missing_token(client):
    resp = client.post(
        "/api/proxy/maintenance/status",
        data={"name": "Router 1"},
        headers={"X-BHNM-Target": "https://bhnm.example.com"},
    )
    assert resp.status_code == 401


def test_maintenance_status_rejects_missing_name(client):
    resp = client.post("/api/proxy/maintenance/status", data={}, headers=STATUS_HEADERS)
    assert resp.status_code == 400
    assert "name" in resp.json()["detail"].lower()


def test_maintenance_status_merges_both_bhnm_calls(client):
    import httpx as _httpx
    inst, captured = _status_client_mock(
        {"totalRecords": 1, "displayRecords": 1,
         "statuses": [{"deviceName": "core-router-01", "status": "UP", "inMaintenance": True}]},
        {"result": "completed",
         "windows": [{"start_time": 1000, "end_time": 2000, "comment": "patching"}]},
    )
    with patch("httpx.AsyncClient", return_value=inst):
        resp = client.post("/api/proxy/maintenance/status",
                           data={"name": "core-router-01"}, headers=STATUS_HEADERS)

    assert resp.status_code == 200
    assert resp.json() == {
        "inMaintenance": True,
        "windows": [{"start_time": 1000, "end_time": 2000, "comment": "patching"}],
    }

    # Host-status call carries the probed-quirk params and the server-side key
    hs_url = next(u for u in captured if "get-host-and-service-status" in u)
    hs_body = parse_qs(captured[hs_url]["content"].decode())
    assert hs_body["groupFilterBy"] == ["device"]
    assert hs_body["groupFilterValue"] == ["core-router-01"]
    assert hs_body["serviceFilter"] == ["host_only"]
    assert int(hs_body["recordCount"][0]) >= 1
    assert hs_body["password"] == ["secret-key-123"]

    # List call is action=list for the same device
    lw_url = next(u for u in captured if "maint_window_api.php" in u)
    lw_body = parse_qs(captured[lw_url]["content"].decode())
    assert lw_body["action"] == ["list"]
    assert lw_body["name"] == ["core-router-01"]
    assert lw_body["password"] == ["secret-key-123"]


def test_maintenance_status_empty_statuses_is_false(client):
    inst, _ = _status_client_mock(
        {"totalRecords": 1, "displayRecords": 0, "statuses": []},
        {"result": "completed", "windows": []},
    )
    with patch("httpx.AsyncClient", return_value=inst):
        resp = client.post("/api/proxy/maintenance/status",
                           data={"name": "core-router-01"}, headers=STATUS_HEADERS)
    assert resp.status_code == 200
    assert resp.json() == {"inMaintenance": False, "windows": []}


def test_maintenance_status_missing_field_is_false(client):
    # BHNM < 26.3.01: host row has no inMaintenance key → version gate → false
    inst, _ = _status_client_mock(
        {"totalRecords": 1, "displayRecords": 1,
         "statuses": [{"deviceName": "core-router-01", "status": "UP"}]},
        {"result": "completed", "windows": []},
    )
    with patch("httpx.AsyncClient", return_value=inst):
        resp = client.post("/api/proxy/maintenance/status",
                           data={"name": "core-router-01"}, headers=STATUS_HEADERS)
    assert resp.status_code == 200
    assert resp.json()["inMaintenance"] is False


def test_maintenance_status_list_failure_keeps_bool_and_empties_windows(client):
    import httpx as _httpx
    inst, _ = _status_client_mock(
        {"totalRecords": 1, "displayRecords": 1,
         "statuses": [{"deviceName": "core-router-01", "status": "UP", "inMaintenance": True}]},
        _httpx.ConnectError("boom"),
    )
    with patch("httpx.AsyncClient", return_value=inst):
        resp = client.post("/api/proxy/maintenance/status",
                           data={"name": "core-router-01"}, headers=STATUS_HEADERS)
    assert resp.status_code == 200
    assert resp.json() == {"inMaintenance": True, "windows": []}


def test_maintenance_status_host_call_failure_is_false(client):
    import httpx as _httpx
    inst, _ = _status_client_mock(
        _httpx.ConnectError("boom"),
        {"result": "completed",
         "windows": [{"start_time": 1000, "end_time": 2000, "comment": "x"}]},
    )
    with patch("httpx.AsyncClient", return_value=inst):
        resp = client.post("/api/proxy/maintenance/status",
                           data={"name": "core-router-01"}, headers=STATUS_HEADERS)
    assert resp.status_code == 200
    body = resp.json()
    # Fail safe: never claim maintenance we can't confirm; windows still best-effort
    assert body["inMaintenance"] is False
    assert body["windows"] == [{"start_time": 1000, "end_time": 2000, "comment": "x"}]
