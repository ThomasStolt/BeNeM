import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_proxy_auth.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers.json")

import json
import pytest
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


def test_proxy_rejects_missing_token(client):
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code == 401


def test_proxy_rejects_wrong_token(client):
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "wrong", "X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code == 401


def test_proxy_accepts_matching_api_key(client):
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "secret-key-123", "X-BHNM-Target": "https://bhnm.example.com"})
    # Will fail to connect to upstream, but should NOT be 401
    assert resp.status_code != 401


def test_proxy_accepts_env_proxy_token(client):
    import main as main_mod
    main_mod.PROXY_TOKEN = "env-token-456"
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "env-token-456", "X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code != 401


def test_dedicated_proxy_rejects_missing_token(client):
    """The dedicated proxy routes (/api/proxy/*) should also require auth."""
    resp = client.post("/api/proxy/incident/acknowledge",
                       headers={"X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code == 401
