import json
import os
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

# Set dummy env vars that config.py requires at import time
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")  # base64("dummy")

from incident_cache import (_server_id_for_api_key, _run_list_and_publish,
                            _run_enrichment_sweep, _cache, CachedIncidents)


def test_server_id_for_api_key_found(tmp_path):
    servers_path = tmp_path / "servers.json"
    servers_path.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com",
         "api_key": "key123", "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120}
    ]))
    with patch("incident_cache.SERVERS_JSON_PATH", str(servers_path)):
        assert _server_id_for_api_key("key123") == "prod"


def test_server_id_for_api_key_not_found(tmp_path):
    servers_path = tmp_path / "servers.json"
    servers_path.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com",
         "api_key": "key123", "pin": "", "cache_enabled": True, "cache_refresh_seconds": 120}
    ]))
    with patch("incident_cache.SERVERS_JSON_PATH", str(servers_path)):
        assert _server_id_for_api_key("wrong") == ""


@pytest.mark.asyncio
async def test_cache_loop_populates_cache():
    server = {
        "id": "test", "url": "https://bhnm.test", "api_key": "k",
        "pin": "", "cache_refresh_seconds": 120,
    }

    mock_incidents_resp = {
        # `result` is required, and is the real wire shape: a body that does not
        # say it completed is an error answer, and reading it as zero incidents
        # is what _fetch_incidents now refuses to do.
        "result": "completed",
        "active_incidents": [
            {"incident_id": "1", "title": "Down", "name": "router1",
             "incident_state": "OPEN", "open_time": "2026-04-09T06:00:00"}
        ],
        "closed_incidents": [],
    }
    mock_detail_resp = {
        "incident": {
            "alert_type": "Host",
            "detail": {
                "primary_alarm_log": [{"state": "CRITICAL"}],
                "relatedalarms": [{"state": "WARNING"}],
            },
        }
    }

    async def mock_post(url, data=None, **kw):
        resp = MagicMock()
        if data.get("method") == "getincidents":
            resp.json.return_value = mock_incidents_resp
        else:
            resp.json.return_value = mock_detail_resp
        return resp

    mock_client = AsyncMock()
    mock_client.post = mock_post

    # C18 (2.21.0) — the cycle is TWO loops now. The list publishes state the
    # moment it lands; the enrichment sweep fills in alarm_counts row by row as
    # each detail call returns. This test is about the enriched result, so it
    # drives both — which is also the smallest demonstration that the two
    # compose into what the single cycle used to produce.
    await _run_list_and_publish(mock_client, server)
    await _run_enrichment_sweep(mock_client, server)

    cached = _cache.get("test")
    assert cached is not None
    assert len(cached.active_incidents) == 1
    enriched = cached.active_incidents[0]
    assert enriched["alarm_counts"] == {"red": 1, "orange": 0, "yellow": 1, "green": 0, "blue": 0}
    assert enriched["alert_type"] == "host"
