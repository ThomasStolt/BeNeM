"""A webhook naming an incident the cache does not hold inserts its row BEFORE the push.

[MEASURED 2026-09-23, raspi-050, incident 30053] The PROBLEM webhook queued delivery
at 14:34:14.068Z and the row did not exist until the next list poll at
14:34:35.937Z — 21.9 s. The phone fetched at 14:34:15.552 and 14:34:24.827, both
before the row existed, and first saw it at 14:35:24.982: 70.9 s after the push.
A user tapping the notification inside that window landed on an incident the
middleware could not serve.

The fix: inside the delivery worker, before the fan-out, one getincidentdetail and
a full row. A failed detail must never cost the push.

The new code is reached through the module, so this file collects against 2.21.0
and fails on behaviour, not on an ImportError.
"""
import json
import os
import tempfile
import time

API_KEY = "row-insert-key"
TARGET = "https://bhnm-row-insert.example.com"
SECRET = "row-insert-secret"

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_db.close()
os.environ.setdefault("DB_PATH", _db.name)

SERVER = {"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
          "cache_enabled": True, "cache_refresh_seconds": 120, "retain_closed": True,
          "webhook_secrets": [SECRET]}
_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([SERVER], _servers)
_servers.close()

import asyncio
import httpx
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

import main as main_mod
import incident_cache
from database import init_db
from incident_cache import CachedIncidents

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}

PROBLEM = {"notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
           "primary_alarm_status": "DOWN", "service_desc": "", "site": "Lab",
           "output": "Ping CRITICAL: Packet Loss 100%", "incident_id": "30053"}

# Trimmed from the live getincidentdetail for 30053, 2026-09-23.
DETAIL_30053 = {"result": "completed", "incident": {
    "title": "Host raspi-050", "incident_state": "OPEN", "incident_id": "30053",
    "name": "raspi-050", "device_category": "23", "device_site": "19", "device_note": "",
    "primary_alarm_state": "DOWN", "incident_open_time": "2026-09-23T16:34:13",
    "acknowledged": 0, "ack_user": "", "alert_type": "Host",
    "detail": {"primary_alarm_log": [{"state": "DOWN"}], "relatedalarms": []}}}


@pytest.fixture(autouse=True)
def _clean():
    init_db()
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    incident_cache._pending_overrides.clear()
    orig = (main_mod.SERVERS_JSON_PATH, incident_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN)
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = ""
    # A cache exists for the server, holding one OTHER incident — the state
    # every running middleware is in when a new incident opens.
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[{"incident_id": "30051", "state": "OPEN", "incident_state": "OPEN",
                           "title": "Other", "name": "UAP", "state_confirmed_at": time.time()}],
        last_updated=time.time(), list_updated=time.time())
    yield
    main_mod.SERVERS_JSON_PATH, incident_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig
    incident_cache._cache.clear()
    incident_cache._pending_overrides.clear()


class FakeBHNM:
    def __init__(self, details, fail=False):
        self.details, self.fail, self.calls = details, fail, []

    async def post(self, url, data=None, **kw):
        form = dict(data or {})
        self.calls.append(form)
        if self.fail:
            raise httpx.ConnectTimeout("BHNM did not answer")
        resp = MagicMock(status_code=200)
        if form.get("method") == "getincidentdetail":
            resp.json.return_value = self.details.get(str(form.get("incident_id")),
                                                      {"result": "completed", "incident": {}})
        else:
            resp.json.return_value = {"result": "completed", "active_incidents": []}
        return resp

    def client(self):
        c = MagicMock()
        c.post = self.post
        ctx = MagicMock()
        ctx.__aenter__ = AsyncMock(return_value=c)
        ctx.__aexit__ = AsyncMock(return_value=False)
        return ctx


def _held(iid):
    entry = incident_cache._cache.get("lab")
    return next((r for r in (*entry.active_incidents, *entry.closed_incidents)
                 if str(r.get("incident_id")) == iid), None) if entry else None


async def _webhook_then_drain(bhnm, payload, at_send):
    """POST the webhook through the real route, drain the real worker, and GET
    the served list — no list poll runs anywhere in this."""
    app_client = httpx.AsyncClient(transport=httpx.ASGITransport(app=main_mod.app),
                                   base_url="http://mw")

    async def send(tokens, title, body, incident_id=""):
        at_send.append(_held(incident_id))
        return []

    main_mod._delivery_queue = asyncio.Queue(maxsize=main_mod.DELIVERY_QUEUE_MAX)
    worker = asyncio.create_task(main_mod._delivery_worker_loop())
    try:
        with patch("incident_cache.httpx.AsyncClient", return_value=bhnm.client()), \
             patch.object(main_mod, "get_tokens_for_secrets", return_value=[("tok", "production")]), \
             patch.object(main_mod, "get_web_push_subscriptions_for_secrets", return_value=[]), \
             patch.object(main_mod, "send_to_all", send):
            r = await app_client.post(f"/webhook?secret={SECRET}", json=payload)
            assert r.status_code == 200, r.text
            await main_mod._delivery_queue.join()
            served = (await app_client.get("/api/v1/incidents", headers=HEADERS)).json()
    finally:
        worker.cancel()
        await app_client.aclose()
    return {str(r["incident_id"]): r
            for r in served["active_incidents"] + served["closed_incidents"]}


def test_a_PROBLEM_for_an_unknown_incident_is_SERVED_before_any_list_poll_and_before_the_push():
    bhnm = FakeBHNM({"30053": DETAIL_30053})
    at_send = []
    served = asyncio.run(_webhook_then_drain(bhnm, PROBLEM, at_send))

    assert not [c for c in bhnm.calls if c.get("method") == "getincidents"], \
        "no list poll may be involved"
    assert "30053" in served, "the row must be served straight after the webhook"
    row = served["30053"]
    assert row["state"] == "OPEN" and row["incident_state"] == "OPEN"
    assert row["title"] == "Host raspi-050" and row["name"] == "raspi-050"
    assert row["open_time"] == "2026-09-23T16:34:13"
    assert row["alarm_counts"]["red"] == 1, "counts come from the detail"
    assert row["counts_confirmed_at"] is not None
    assert time.time() - row["state_confirmed_at"] < 5, "state_confirmed_at is now"
    assert [c.get("incident_id") for c in bhnm.calls] == ["30053"], "exactly one detail call"

    assert len(at_send) == 1, "the push must still go out"
    assert at_send[0] is not None, "the row must exist BEFORE the push is sent"


def test_a_FAILED_detail_still_sends_the_push_and_leaves_the_row_to_the_list_poll(capsys):
    bhnm = FakeBHNM({}, fail=True)
    at_send = []
    served = asyncio.run(_webhook_then_drain(bhnm, PROBLEM, at_send))

    assert len(at_send) == 1, "a failed detail must never cost the push"
    assert "30053" not in served, "no half-row: the next list poll carries it"
    assert "not inserted" in capsys.readouterr().out, "the zero case is logged"


def test_a_KNOWN_incident_is_unchanged_and_costs_no_detail_call():
    before = dict(_held("30051"))
    bhnm = FakeBHNM({})
    at_send = []
    asyncio.run(_webhook_then_drain(bhnm, {**PROBLEM, "incident_id": "30051"}, at_send))

    assert bhnm.calls == [], "a known incident needs no detail call"
    assert _held("30051") == before
    assert len(at_send) == 1


def test_a_detail_for_ANOTHER_host_is_not_inserted():
    """While 4 servers share one secret, the same id can exist on another BHNM.
    The webhook's hostname is what says the detail is about this incident."""
    other = json.loads(json.dumps(DETAIL_30053))
    other["incident"]["name"] = "someone-else"
    bhnm = FakeBHNM({"30053": other})
    at_send = []
    served = asyncio.run(_webhook_then_drain(bhnm, PROBLEM, at_send))

    assert "30053" not in served
    assert len(at_send) == 1
