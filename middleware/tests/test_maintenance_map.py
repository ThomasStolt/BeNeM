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
    names, down, host_rows = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert names == {"sw-01", "srv-01"}
    assert down == set() and host_rows == 0   # rows without a status literal count for nothing


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
    names, down, host_rows = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert names == set()
    # ...but status has been on host rows since API v1.0.9: host_down works
    # on servers that get no wrenches (documented, not wire-verified < 26.3.01)
    assert down == {"sw-02"} and host_rows == 2


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
    names, _, _ = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
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
    assert cached.down == set()
    assert cached.last_updated > 0


# ── fetch: host_down (Wave B) ────────────────────────────────────────────────


def test_fetch_lists_down_names_only_and_counts_known_literals():
    client = FakeClient(
        categories=[{"id": 1, "name": "Pi"}],
        status_pages={("Pi", 0): {"totalRecords": 6, "statuses": [
            {"deviceName": "raspi-050", "status": "DOWN", "inMaintenance": False},
            {"deviceName": "raspi-054", "status": "DOWN", "inMaintenance": True},   # DOWN and in maintenance
            {"deviceName": "raspi-053", "status": "UP", "inMaintenance": False},
            {"deviceName": "odd-1", "status": "UNREACHABLE"},                       # unknown literal → neither
            {"deviceName": "odd-2", "status": None},                                # null → dropped silently
            {"status": "DOWN"},                                                     # nameless → skipped
        ]}},
    )
    names, down, host_rows = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert down == {"raspi-050", "raspi-054"}
    assert names == {"raspi-054"}
    assert host_rows == 3                       # UP + DOWN + DOWN; UNREACHABLE/null/nameless not counted


def test_fetch_logs_ignored_literals_once_and_never_null(capsys):
    client = FakeClient(
        categories=[{"id": 1, "name": "Pi"}],
        status_pages={("Pi", 0): {"totalRecords": 3, "statuses": [
            {"deviceName": "a", "status": "PENDING"},
            {"deviceName": "b", "status": "pending"},
            {"deviceName": "c", "status": None},
        ]}},
    )
    _, down, host_rows = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert down == set() and host_rows == 0
    out = capsys.readouterr().out
    assert out.count("ignored literals") == 1
    assert "PENDING" in out and "pending" in out and "None" not in out


def test_fetch_all_up_logs_nothing(capsys):
    client = FakeClient(
        categories=[{"id": 1, "name": "Pi"}],
        status_pages={("Pi", 0): {"totalRecords": 1, "statuses": [
            {"deviceName": "a", "status": "UP", "inMaintenance": False}]}},
    )
    _, down, host_rows = run(maintenance_cache._fetch_in_maintenance(client, SERVER))
    assert down == set() and host_rows == 1
    assert "ignored literals" not in capsys.readouterr().out


def test_cycle_failure_keeps_previous_down_set():
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"sw-old"}, down={"raspi-old"}, last_updated=123.0)
    client = FakeClient(categories=[], status_pages={}, fail_categories=True)
    run(maintenance_cache._run_one_cycle(client, SERVER))
    cached = maintenance_cache.get_cached("lab")
    assert cached.down == {"raspi-old"} and cached.names == {"sw-old"}


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
    assert resp.json() == {"cache_age_seconds": None, "in_maintenance": [], "scheduled": [], "host_down": []}


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
    assert body["host_down"] == []


def test_map_route_serves_host_down_sorted_beside_in_maintenance(client_app):
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"raspi-054"}, down={"raspi-054", "raspi-050"}, last_updated=time.time())
    resp = client_app.get(
        "/api/v1/maintenance-map",
        headers={"X-Proxy-Token": "secret-key-123"},
    )
    body = resp.json()
    assert body["host_down"] == ["raspi-050", "raspi-054"]
    assert body["in_maintenance"] == ["raspi-054"]          # the two lists are independent
    assert set(body) == {"cache_age_seconds", "in_maintenance", "scheduled", "host_down"}


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
    assert resp.json() == {"cache_age_seconds": None, "in_maintenance": [], "scheduled": [], "host_down": []}


# ── refresh cadence: fixed 60s, independent of cache_refresh_seconds ─────────


def test_map_refresh_interval_is_fixed_60s():
    # The map drives UI freshness; it does not inherit the per-server
    # cache_refresh_seconds (which can be up to 900s).
    assert maintenance_cache._refresh_interval({"cache_refresh_seconds": 900}) == 60
    assert maintenance_cache._refresh_interval({}) == 60


# ── scheduled-window registry (middleware remembers its own creates) ─────────


@pytest.fixture(autouse=True)
def clean_scheduled():
    maintenance_cache._scheduled.clear()
    yield
    maintenance_cache._scheduled.clear()


def test_scheduled_note_and_serve():
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 240, now + 3840)
    out = maintenance_cache.get_scheduled("lab", active_names=set())
    assert out == [{"name": "sw-01", "start_time": now + 240, "end_time": now + 3840}]
    assert maintenance_cache.get_scheduled("other", active_names=set()) == []


def test_scheduled_last_create_wins_per_device():
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 100, now + 200)
    maintenance_cache.note_scheduled("lab", "sw-01", now + 300, now + 900)
    out = maintenance_cache.get_scheduled("lab", active_names=set())
    assert len(out) == 1 and out[0]["start_time"] == now + 300


def test_scheduled_hidden_once_device_is_active():
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 60, now + 600)
    assert maintenance_cache.get_scheduled("lab", active_names={"sw-01"}) == []


def test_scheduled_expires_past_start_grace():
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now - 300, now + 3600)  # start 5 min ago
    assert maintenance_cache.get_scheduled("lab", active_names=set()) == []
    # and pruned from the registry itself
    assert "sw-01" not in maintenance_cache._scheduled.get("lab", {})


def test_clear_scheduled():
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 240, now + 600)
    maintenance_cache.clear_scheduled("lab", "sw-01")
    assert maintenance_cache.get_scheduled("lab", active_names=set()) == []


def test_map_route_serves_scheduled(client_app):
    now = int(time.time())
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names={"active-1"}, last_updated=time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 240, now + 600)
    maintenance_cache.note_scheduled("lab", "active-1", now - 60, now + 600)  # already active → hidden
    resp = client_app.get("/api/v1/maintenance-map", headers={"X-Proxy-Token": "secret-key-123"})
    body = resp.json()
    assert body["in_maintenance"] == ["active-1"]
    assert body["scheduled"] == [{"name": "sw-01", "start_time": now + 240, "end_time": now + 600}]


def test_map_route_cold_cache_still_serves_scheduled(client_app):
    # A window created moments after middleware start: no cache entry yet,
    # but the scheduled registry must still reach clients.
    now = int(time.time())
    maintenance_cache.note_scheduled("lab", "sw-01", now + 240, now + 600)
    resp = client_app.get("/api/v1/maintenance-map", headers={"X-Proxy-Token": "secret-key-123"})
    body = resp.json()
    assert body["cache_age_seconds"] is None
    assert body["in_maintenance"] == []
    assert body["scheduled"][0]["name"] == "sw-01"
