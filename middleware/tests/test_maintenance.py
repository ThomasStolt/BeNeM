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

    # start_time should be ~now+900
    assert before + 900 <= start_time <= after + 900 + 2

    # end_time should be start_time + duration*60
    expected_end = start_time + duration_minutes * 60
    assert end_time == expected_end

    # Verify the target URL
    assert captured_kwargs.get("url", "").endswith("/api/maint_window_api.php")
