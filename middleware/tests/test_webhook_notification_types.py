"""Every notification literal observed on the wire from BHNM 26.3.

Payloads here are trimmed copies of real captures recorded in
docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md — including the
quirks: DEACKNOWLEDGEMENT (not UNACKNOWLEDGEMENT), host_state carrying the literal
"ACKNOWLEDGEMENT" on ack notifications, and service_* empty on host alerts.
"""
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_webhook_types.db")

import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient

import incident_cache
from main import app

SECRET = "types-secret"


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture(autouse=True)
def clear_cache():
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    yield
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()


def post(client, payload):
    """Send a webhook with one registered device and return (title, body)."""
    with patch("main.get_tokens_for_secret", return_value=["tok"]), \
         patch("main.get_web_push_subscriptions_for_secret", return_value=[]), \
         patch("main.send_to_all", new_callable=AsyncMock) as send:
        send.return_value = []
        resp = client.post(f"/webhook?secret={SECRET}", json=payload)
        assert resp.status_code == 200, resp.text
        assert send.await_count == 1, "expected exactly one push"
        _tokens, title, body, incident_id = send.await_args.args
        return title, body, incident_id


# ── PROBLEM ───────────────────────────────────────────────────────────────────

def test_problem_host_down(client):
    title, body, iid = post(client, {
        "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
        "primary_alarm_status": "DOWN", "service_state": "", "service_desc": "",
        "output": "<br />Ping CRITICAL: Packet Loss 100%", "site": "New_York",
        "incident_id": "29483", "notification_number": "1",
    })
    assert title == "🔴 raspi-050 — DOWN"
    assert "Ping CRITICAL" in body and "Site: New_York" in body
    assert iid == "29483"


def test_problem_without_notification_number_is_first_notice(client):
    title, _body, _iid = post(client, {
        "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
    })
    assert title == "🔴 raspi-050 — DOWN"
    assert "notice" not in title


@pytest.mark.parametrize("n,expected", [("2", 2), ("7", 7)])
def test_renotification_says_still(client, n, expected):
    title, _body, _iid = post(client, {
        "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
        "notification_number": n, "incident_id": "29483",
    })
    assert title == f"🔴 raspi-050 — still DOWN (notice {expected})"


def test_unparseable_notification_number_falls_back_to_first_notice(client):
    title, _body, _iid = post(client, {
        "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
        "notification_number": "",
    })
    assert title == "🔴 raspi-050 — DOWN"


def test_warning_state_uses_warning_emoji(client):
    title, _body, _iid = post(client, {
        "notification_type": "WARNING", "hostname": "sw-01", "host_state": "UP",
    })
    assert title.startswith("⚠️")


# ── ACKNOWLEDGEMENT ───────────────────────────────────────────────────────────

def test_acknowledgement_host_state_carries_the_literal_type(client):
    """BHNM puts "ACKNOWLEDGEMENT" in host_state here, not a host state."""
    title, body, _iid = post(client, {
        "notification_type": "ACKNOWLEDGEMENT", "hostname": "raspi-050",
        "host_state": "ACKNOWLEDGEMENT", "primary_alarm_status": "DOWN",
        "output": "Acknowledged by admin: No comment.", "incident_id": "29483",
    })
    assert title == "Acknowledged: raspi-050"
    assert body == "Acknowledged by admin: No comment."


# ── DEACKNOWLEDGEMENT ─────────────────────────────────────────────────────────

@pytest.mark.parametrize("literal", ["DEACKNOWLEDGEMENT", "UNACKNOWLEDGEMENT"])
def test_unacknowledgement_both_spellings(client, literal):
    """The wire sends DEACKNOWLEDGEMENT; BHNM's docs say UNACKNOWLEDGEMENT."""
    title, body, _iid = post(client, {
        "notification_type": literal, "hostname": "raspi-050", "host_state": "DOWN",
        "primary_alarm_status": "DOWN", "output": "Deacknowledged by admin: No comment.",
        "incident_id": "29483",
    })
    assert title == "Unacknowledged: raspi-050"
    assert body == "Deacknowledged by admin: No comment."


def test_unacknowledgement_never_looks_like_a_fresh_outage(client):
    """host_state is DOWN on this notification — the problem branch would render
    "🔴 raspi-050 — DOWN", indistinguishable from a new alarm."""
    title, _body, _iid = post(client, {
        "notification_type": "DEACKNOWLEDGEMENT", "hostname": "raspi-050",
        "host_state": "DOWN", "primary_alarm_status": "DOWN",
    })
    assert "🔴" not in title
    assert title == "Unacknowledged: raspi-050"


def test_unacknowledgement_body_falls_back_to_primary_alarm_status(client):
    _title, body, _iid = post(client, {
        "notification_type": "DEACKNOWLEDGEMENT", "hostname": "raspi-050",
        "host_state": "DOWN", "primary_alarm_status": "DOWN", "output": "",
    })
    assert body == "DOWN"


# ── RECOVERY ──────────────────────────────────────────────────────────────────

def test_recovery_host_reads_as_english(client):
    """service_desc is empty on host alerts, so the subject must be "Host"."""
    title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "raspi-050", "host_state": "UP",
        "primary_alarm_status": "UP", "service_desc": "", "service_state": "",
        "output": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%",
        "incident_id": "29483",
    })
    assert title == "Resolved: raspi-050"
    assert body.startswith("Host recovered.")
    assert "UP recovered." not in body


def test_recovery_service_uses_the_service_description(client):
    _title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "web-01", "host_state": "UP",
        "service_desc": "Main Website", "output": "HTTP OK",
    })
    assert body == "Main Website recovered. HTTP OK"


# ── Cache patch ───────────────────────────────────────────────────────────────

def _seed_cache(state="OPEN"):
    entry = incident_cache.CachedIncidents()
    entry.active_incidents = [{"incident_id": "29483", "incident_state": state}]
    entry.closed_incidents = []
    incident_cache._cache["prod"] = entry
    return entry


@pytest.mark.parametrize("ntype,expected", [
    ("ACKNOWLEDGEMENT", "ACKNOWLEDGED"),
    ("DEACKNOWLEDGEMENT", "OPEN"),
    ("UNACKNOWLEDGEMENT", "OPEN"),
    ("RECOVERY", "CLOSED"),
])
def test_webhook_patches_the_cached_incident(client, ntype, expected):
    entry = _seed_cache("ACKNOWLEDGED" if expected == "OPEN" else "OPEN")
    post(client, {"notification_type": ntype, "hostname": "raspi-050",
                  "host_state": "DOWN", "incident_id": "29483"})
    assert entry.active_incidents[0]["incident_state"] == expected


def test_problem_does_not_patch_the_cache(client):
    entry = _seed_cache("OPEN")
    post(client, {"notification_type": "PROBLEM", "hostname": "raspi-050",
                  "host_state": "DOWN", "incident_id": "29483"})
    assert entry.active_incidents[0]["incident_state"] == "OPEN"
    assert not incident_cache._state_overrides


def test_cache_patch_is_a_noop_for_an_unknown_incident(client):
    entry = _seed_cache("OPEN")
    post(client, {"notification_type": "RECOVERY", "hostname": "other-host",
                  "host_state": "UP", "incident_id": "99999"})
    assert entry.active_incidents[0]["incident_state"] == "OPEN"
