import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_maintenance_map.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_maintenance_map.json")

import asyncio
import json
import time
import pytest
from fastapi.testclient import TestClient

import maintenance_cache
from main import app

SERVER = {"id": "lab", "url": "https://bhnm.example.com", "api_key": "secret-key-123"}


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def json(self):
        return self._payload


class FakeClient:
    """Dispatches POSTs by URL + form data; scripted per test."""

    def __init__(self, categories, status_pages, fail_status=False, fail_categories=False):
        self.categories = categories          # list of {id, name}
        self.status_pages = status_pages      # {(cat_name, recordStart): payload}
        self.fail_status = fail_status
        self.fail_categories = fail_categories
        self.calls = []

    async def post(self, url, data=None):
        self.calls.append((url, dict(data or {})))
        if "category/list" in url:
            if self.fail_categories:
                raise RuntimeError("category list down")
            return FakeResponse(self.categories)
        if "get-host-and-service-status" in url:
            if self.fail_status:
                raise RuntimeError("status down")
            key = (data["groupFilterValue"], int(data.get("recordStart", 0)))
            return FakeResponse(self.status_pages[key])
        raise AssertionError(f"unexpected url {url}")


def run(coro):
    return asyncio.run(coro)


@pytest.fixture(autouse=True)
def clean_cache():
    maintenance_cache._cache.clear()
    yield
    maintenance_cache._cache.clear()


# ── fetch: map building ──────────────────────────────────────────────────────


def test_fetch_collects_true_names_across_categories():
    client = FakeClient(
        categories=[{"id": 1, "name": "Net"}, {"id": 2, "name": "Servers"}],
        status_pages={
            ("Net", 0): {"totalRecords": 2, "statuses": [
                {"deviceName": "sw-01", "inMaintenance": True},
                {"deviceName": "sw-02", "inMaintenance": False},
            ]},
            ("Servers", 0): {"totalRecords": 1, "statuses": [
                {"deviceName": "srv-01", "inMaintenance": True},
            ]},
        },
    )
    names = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert names == {"sw-01", "srv-01"}


def test_fetch_version_gate_field_absent_yields_empty():
    # BHNM < 26.3.01: rows carry no inMaintenance key at all
    client = FakeClient(
        categories=[{"id": 1, "name": "Net"}],
        status_pages={
            ("Net", 0): {"totalRecords": 2, "statuses": [
                {"deviceName": "sw-01", "status": "UP"},
                {"deviceName": "sw-02", "status": "DOWN"},
            ]},
        },
    )
    names = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert names == set()


def test_fetch_paginates_past_page_size(monkeypatch):
    monkeypatch.setattr(maintenance_cache, "PAGE_SIZE", 2)
    client = FakeClient(
        categories=[{"id": 1, "name": "Net"}],
        status_pages={
            ("Net", 0): {"totalRecords": 5, "statuses": [
                {"deviceName": "a", "inMaintenance": True},
                {"deviceName": "b", "inMaintenance": False},
            ]},
            ("Net", 2): {"totalRecords": 5, "statuses": [
                {"deviceName": "c", "inMaintenance": False},
                {"deviceName": "d", "inMaintenance": True},
            ]},
            ("Net", 4): {"totalRecords": 5, "statuses": [
                {"deviceName": "e", "inMaintenance": True},
            ]},
        },
    )
    names = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert names == {"a", "d", "e"}
    status_calls = [c for c in client.calls if "get-host-and-service-status" in c[0]]
    assert len(status_calls) == 3
    # server-side key + probed-quirk params on every page
    for _, form in status_calls:
        assert form["password"] == "secret-key-123"
        assert form["groupFilterBy"] == "category"
        assert form["serviceFilter"] == "host_only"


# ── cycle: record-don't-raise, keeps previous ────────────────────────────────


def test_cycle_success_replaces_set():
    client = FakeClient(
        categories=[{"id": 1, "name": "Net"}],
        status_pages={("Net", 0): {"totalRecords": 1, "statuses": [
            {"deviceName": "sw-01", "inMaintenance": True}]}},
    )
    run(maintenance_cache._run_one_cycle(client, SERVER))
    cached = maintenance_cache.get_cached("lab")
    assert cached is not None
    assert cached.names == {"sw-01"}
    assert cached.last_updated > 0


def test_cycle_failure_keeps_previous_set_and_does_not_raise():
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"sw-old"}, last_updated=123.0)
    client = FakeClient(categories=[], status_pages={}, fail_categories=True)
    run(maintenance_cache._run_one_cycle(client, SERVER))  # must not raise
    cached = maintenance_cache.get_cached("lab")
    assert cached.names == {"sw-old"}
    assert cached.last_updated == 123.0


def test_partial_category_failure_keeps_previous_set():
    # One category call failing fails the cycle; the previous set survives
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"sw-old"}, last_updated=123.0)
    client = FakeClient(
        categories=[{"id": 1, "name": "Net"}],
        status_pages={}, fail_status=True,
    )
    run(maintenance_cache._run_one_cycle(client, SERVER))
    assert maintenance_cache.get_cached("lab").names == {"sw-old"}


# ── lifecycle ────────────────────────────────────────────────────────────────


def test_reload_and_stop_lifecycle(tmp_path, monkeypatch):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([dict(SERVER, cache_enabled=True)]))
    import threshold_cache
    monkeypatch.setattr("config.SERVERS_JSON_PATH", str(servers_file), raising=False)
    monkeypatch.setattr(threshold_cache, "SERVERS_JSON_PATH", str(servers_file), raising=False)

    async def scenario():
        maintenance_cache.reload_server("lab")
        assert "lab" in maintenance_cache._tasks
        assert not maintenance_cache._tasks["lab"].done()
        maintenance_cache.stop_server("lab")
        await asyncio.sleep(0)
        assert "lab" not in maintenance_cache._tasks

    run(scenario())


# ── route ────────────────────────────────────────────────────────────────────


@pytest.fixture
def client_app(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([SERVER]))
    import main as main_mod
    orig_path, orig_token = main_mod.PROXY_TOKEN, None
    import threshold_cache
    old_sjp_main = getattr(main_mod, "SERVERS_JSON_PATH")
    old_sjp_th = threshold_cache.SERVERS_JSON_PATH
    old_token = main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = str(servers_file)
    threshold_cache.SERVERS_JSON_PATH = str(servers_file)
    maintenance_cache.SERVERS_JSON_PATH = str(servers_file)
    main_mod.PROXY_TOKEN = ""
    yield TestClient(app)
    main_mod.SERVERS_JSON_PATH = old_sjp_main
    threshold_cache.SERVERS_JSON_PATH = old_sjp_th
    maintenance_cache.SERVERS_JSON_PATH = old_sjp_th
    main_mod.PROXY_TOKEN = old_token


def test_map_route_rejects_missing_token(client_app):
    import main as main_mod
    main_mod.PROXY_TOKEN = "required-token"
    resp = client_app.get("/api/v1/maintenance-map")
    assert resp.status_code == 401
    main_mod.PROXY_TOKEN = ""


def test_map_route_cold_cache_returns_empty_no_fallthrough(client_app):
    resp = client_app.get(
        "/api/v1/maintenance-map",
        headers={"X-Proxy-Token": "secret-key-123"},
    )
    assert resp.status_code == 200
    assert resp.json() == {"cache_age_seconds": None, "in_maintenance": []}


def test_map_route_serves_cached_names_with_age(client_app):
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"sw-01", "srv-09"}, last_updated=time.time() - 30)
    resp = client_app.get(
        "/api/v1/maintenance-map",
        headers={"X-Proxy-Token": "secret-key-123"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert sorted(body["in_maintenance"]) == ["srv-09", "sw-01"]
    assert 28 <= body["cache_age_seconds"] <= 33


def test_map_route_unresolvable_server_returns_empty(client_app):
    # Authenticated via the global proxy token, but the token maps to no
    # servers.json entry → no server_id → empty map, never someone else's.
    import main as main_mod
    main_mod.PROXY_TOKEN = "global-token"
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"sw-01"}, last_updated=time.time())
    resp = client_app.get(
        "/api/v1/maintenance-map",
        headers={"X-Proxy-Token": "global-token"},
    )
    main_mod.PROXY_TOKEN = ""
    assert resp.status_code == 200
    assert resp.json() == {"cache_age_seconds": None, "in_maintenance": []}


# ── refresh cadence: fixed 60s, independent of cache_refresh_seconds ─────────


def test_map_refresh_interval_is_fixed_60s():
    # The map drives UI freshness; it does not inherit the per-server
    # cache_refresh_seconds (which can be up to 900s).
    assert maintenance_cache._refresh_interval({"cache_refresh_seconds": 900}) == 60
    assert maintenance_cache._refresh_interval({}) == 60
