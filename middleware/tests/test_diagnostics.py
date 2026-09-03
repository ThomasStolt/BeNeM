import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_diagnostics.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_diagnostics.json")

import asyncio
import json
import time
import pytest
import httpx
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import main as main_mod
import diagnostics
import incident_cache
from incident_cache import CachedIncidents
from database import init_db
from main import app

init_db()  # create the device_tokens table in the test DB

API_KEY = "key-abc-123"
TARGET = "https://bhnm.example.com"


@pytest.fixture(autouse=True)
def _reset():
    diagnostics.reset()
    incident_cache._cache.clear()
    orig_path, orig_tok = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig_path, orig_tok
    diagnostics.reset()
    incident_cache._cache.clear()


@pytest.fixture
def servers(tmp_path):
    def write(cache_enabled=True):
        f = tmp_path / "servers.json"
        f.write_text(json.dumps([{
            "id": "lab", "name": "Lab", "url": TARGET,
            "api_key": API_KEY, "pin": "", "cache_enabled": cache_enabled,
        }]))
        main_mod.SERVERS_JSON_PATH = str(f)
    return write


@pytest.fixture
def client():
    return TestClient(app)


def _auth():
    return {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}


# --- auth --------------------------------------------------------------------
def test_requires_proxy_token(client, servers):
    servers()
    assert client.get("/api/v1/diagnostics").status_code == 401


def test_wrong_token_401(client, servers):
    servers()
    r = client.get("/api/v1/diagnostics", headers={"X-Proxy-Token": "nope", "X-BHNM-Target": TARGET})
    assert r.status_code == 401


# --- BHNM hop = background monitor's cached result; feeds = passive telemetry
PROBE_UP = {
    "reachable": True, "source": "probe", "latency_ms": 12,
    "last_success_age_seconds": 0, "last_error": None,
    "last_error_age_seconds": None, "consecutive_failures": 0,
}
PROBE_DOWN = {
    "reachable": False, "source": "probe", "latency_ms": None,
    "last_success_age_seconds": None, "last_error": "HTTP 502",
    "last_error_age_seconds": 0, "consecutive_failures": 1,
}
SERVER = {"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": ""}


def test_bhnm_from_monitor_feeds_from_telemetry(client, servers):
    servers(cache_enabled=True)
    diagnostics.record_success("lab", "tactical", 42)
    diagnostics.record_success("lab", "probe", 12)      # the monitor's last probe
    incident_cache._cache["lab"] = CachedIncidents(active_incidents=[{}, {}], last_updated=time.time())
    with patch.object(diagnostics, "active_probe", AsyncMock(return_value=PROBE_UP)) as probe:
        r = client.get("/api/v1/diagnostics", headers=_auth())
    assert r.status_code == 200
    body = r.json()
    probe.assert_not_awaited()             # endpoint READS the dict — never probes
    bhnm = body["server"]["bhnm"]
    assert bhnm["source"] == "monitor" and bhnm["reachable"] is True
    assert bhnm["latency_ms"] == 12
    feeds = body["server"]["feeds"]
    assert feeds["incidents"]["cached"] is True and feeds["incidents"]["count"] == 2
    # all four crawlers report — the maintenance map was recorded but unlisted before 2.11.0
    assert set(feeds) == {"incidents", "tactical", "thresholds", "maintenance_map"}
    assert feeds["maintenance_map"]["cached"] is False    # no cycle yet → cold, not an error
    assert body["server"]["host"] == "bhnm.example.com"   # host only, never full URL


def test_maintenance_map_feed_count_is_host_rows(client, servers):
    import maintenance_cache
    servers(cache_enabled=True)
    diagnostics.record_success("lab", "probe", 12)
    maintenance_cache._cache["lab"] = maintenance_cache.CachedMaintenance(
        names=set(), down={"raspi-050"}, host_rows=38, last_updated=time.time())
    with patch.object(diagnostics, "active_probe", AsyncMock(return_value=PROBE_UP)):
        r = client.get("/api/v1/diagnostics", headers=_auth())
    f = r.json()["server"]["feeds"]["maintenance_map"]
    assert f["cached"] is True and f["count"] == 38      # host rows, not the in-maintenance count
    maintenance_cache._cache.clear()


def test_bhnm_down_when_monitor_recorded_failures(client, servers):
    # BHNM app down behind Traefik (monitor recorded threshold 5xx failures) →
    # hop down, even though the cache still has warm data (feeds stay cached).
    servers(cache_enabled=True)
    diagnostics.record_success("lab", "tactical", 42)
    diagnostics.record_success("lab", "probe", 12)
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    r = client.get("/api/v1/diagnostics", headers=_auth())
    assert r.status_code == 200
    bhnm = r.json()["server"]["bhnm"]
    assert bhnm["reachable"] is False
    assert bhnm["last_error"] == "HTTP 502"
    assert bhnm["consecutive_failures"] == 2


def test_flap_resistance_two_strikes():
    # Down is declared only after DIAG_DOWN_THRESHOLD (default 2) consecutive
    # failures; a lone transient blip never flashes the banner.
    diagnostics.record_success("lab", "probe", 12)
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    assert diagnostics.bhnm_monitor("lab")["reachable"] is True    # 1 → still up
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    assert diagnostics.bhnm_monitor("lab")["reachable"] is False   # 2 → down
    diagnostics.record_success("lab", "probe", 10)
    assert diagnostics.bhnm_monitor("lab")["reachable"] is True    # success resets


def test_startup_failure_below_threshold_stays_null():
    # Never-succeeded server: a below-threshold failure must not report "up"
    # (there is no good state to hold) — stay null/checking until definitive.
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    assert diagnostics.bhnm_monitor("lab")["reachable"] is None
    diagnostics.record_failure("lab", "probe", "HTTP 502")
    assert diagnostics.bhnm_monitor("lab")["reachable"] is False


def test_bhnm_unknown_before_first_probe(client, servers):
    # Startup window (≤ one probe interval): no monitor result yet → null/none,
    # so the client stays in `checking` instead of showing a false state.
    servers(cache_enabled=False)
    r = client.get("/api/v1/diagnostics", headers=_auth())
    bhnm = r.json()["server"]["bhnm"]
    assert bhnm["reachable"] is None
    assert bhnm["source"] == "none"


# --- background monitor lifecycle --------------------------------------------
@pytest.mark.asyncio
async def test_monitor_loop_records_probe_success():
    with patch.object(diagnostics, "active_probe", AsyncMock(return_value=PROBE_UP)), \
         patch.object(diagnostics, "DIAG_PROBE_INTERVAL", 0.01):
        diagnostics.start_monitor(SERVER, True)
        await asyncio.sleep(0.03)
    t = diagnostics.get_telemetry("lab", "probe")
    assert t.last_success_ts > 0 and t.last_latency_ms == 12
    assert t.consecutive_failures == 0


@pytest.mark.asyncio
async def test_monitor_task_records_failure_without_raising():
    # Even if the probe itself blows up, the task records the failure and lives on.
    with patch.object(diagnostics, "active_probe", AsyncMock(side_effect=RuntimeError("kaboom"))), \
         patch.object(diagnostics, "DIAG_PROBE_INTERVAL", 0.01):
        diagnostics.start_monitor(SERVER, True)
        await asyncio.sleep(0.05)
        task = diagnostics._monitor_tasks["lab"]
        assert not task.done()                          # never crashed
    t = diagnostics.get_telemetry("lab", "probe")
    assert t.consecutive_failures >= 1
    assert "kaboom" in (t.last_error or "")


@pytest.mark.asyncio
async def test_reload_starts_and_stops_monitor_tasks():
    with patch.object(diagnostics, "active_probe", AsyncMock(return_value=PROBE_UP)), \
         patch.object(diagnostics, "DIAG_PROBE_INTERVAL", 60):
        diagnostics.reload_monitor("lab", [SERVER], True)
        assert "lab" in diagnostics._monitor_tasks
        diagnostics.reload_monitor("lab", [], True)     # server removed → stopped
        assert "lab" not in diagnostics._monitor_tasks


@pytest.mark.asyncio
async def test_active_probe_timeout_is_bounded_and_down():
    class _Boom:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, *a, **k): raise httpx.TimeoutException("timed out")
    with patch.object(diagnostics.httpx, "AsyncClient", lambda *a, **k: _Boom()):
        out = await diagnostics.active_probe(TARGET, API_KEY, None, True)
    assert out["reachable"] is False
    assert out["source"] == "probe"
    assert out["latency_ms"] is None


@pytest.mark.asyncio
async def test_active_probe_4xx_is_up():
    # A 4xx means the BHNM app answered (auth/HTTPS complaint) — it's alive.
    class _OK:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, *a, **k): return MagicMock(status_code=400)
    with patch.object(diagnostics.httpx, "AsyncClient", lambda *a, **k: _OK()):
        out = await diagnostics.active_probe(TARGET, API_KEY, None, True)
    assert out["reachable"] is True
    assert isinstance(out["latency_ms"], int)


@pytest.mark.asyncio
async def test_active_probe_5xx_gateway_is_down():
    # A 5xx is Traefik's gateway error when the BHNM app is down — NOT reachable.
    class _502:
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def post(self, *a, **k): return MagicMock(status_code=502)
    with patch.object(diagnostics.httpx, "AsyncClient", lambda *a, **k: _502()):
        out = await diagnostics.active_probe(TARGET, API_KEY, None, True)
    assert out["reachable"] is False
    assert out["latency_ms"] is None
    assert out["last_error"] == "HTTP 502"


# --- no secrets in payload ---------------------------------------------------
def test_no_secrets_in_payload(client, servers):
    servers(cache_enabled=True)
    diagnostics.record_failure("lab", "tactical",
                               "HTTP 500 password=hunter2 api_key=SEKRET token: xyz")
    diagnostics.record_success("lab", "probe", 12)
    r = client.get("/api/v1/diagnostics", headers=_auth())
    text = r.text
    assert "hunter2" not in text
    assert "SEKRET" not in text
    assert "xyz" not in text
    assert API_KEY not in text            # the proxy token never echoed
    assert "password=***" in text         # scrubbed form present


def test_scrub_strips_credentials():
    s = diagnostics.scrub("err password=abc api_key: def token=ghi secret=jkl and more")
    for leak in ("abc", "def", "ghi", "jkl"):
        assert leak not in s
    assert diagnostics.scrub(None) is None
    assert len(diagnostics.scrub("x" * 500)) <= 200


# --- isolation: never 500 into the app ---------------------------------------
def test_isolation_returns_payload_on_internal_error(client, servers):
    servers(cache_enabled=True)
    with patch.object(diagnostics, "bhnm_monitor", MagicMock(side_effect=RuntimeError("kaboom"))):
        r = client.get("/api/v1/diagnostics", headers=_auth())
    assert r.status_code == 200                     # degraded, not a 500
    assert r.json()["server"]["bhnm"]["reachable"] is False
    assert r.json()["server"]["bhnm"]["source"] == "error"
