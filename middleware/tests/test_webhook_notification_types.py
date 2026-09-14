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


# ── BHNM text cleaning (2.13.1) ───────────────────────────────────────────────

from main import clean_bhnm_text


def test_clean_strips_the_captured_html_string():
    assert clean_bhnm_text("<br />Ping CRITICAL: Packet Loss 100%") == "Ping CRITICAL: Packet Loss 100%"


def test_clean_decodes_entities():
    assert clean_bhnm_text("Ping &amp; check &lt;ok&gt;") == "Ping & check <ok>"


def test_clean_collapses_whitespace():
    assert clean_bhnm_text(" (Host check triggered from Service PING)<br />Ping OK:  Packet Loss 0%") == \
        "(Host check triggered from Service PING) Ping OK: Packet Loss 0%"


def test_clean_handles_empty_and_none():
    assert clean_bhnm_text("") == ""
    assert clean_bhnm_text(None) == ""


def test_problem_body_has_no_markup(client):
    _title, body, _iid = post(client, {
        "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
        "output": "<br />Ping CRITICAL: Packet Loss 100%", "site": "New_York",
    })
    assert "<br" not in body
    assert body == "Ping CRITICAL: Packet Loss 100% | Site: New_York"


def test_recovery_body_has_no_double_space(client):
    """"Host recovered.  (Host check..." — the captured output starts with a space."""
    _title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "raspi-050", "host_state": "UP",
        "output": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%",
    })
    assert "  " not in body
    assert body == "Host recovered. (Host check triggered from Service PING) Ping OK: Packet Loss 0%"


def test_retry_wording_from_bhnm_survives_cleaning(client):
    """BHNM stamps its own retry label into {OUTPUT}; it is text, not markup."""
    _title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "raspi-050", "host_state": "UP",
        "output": "Retry action by system 1 of 3.  (Host check triggered from Service PING)",
    })
    assert body == "Host recovered. Retry action by system 1 of 3. (Host check triggered from Service PING)"


# ── Fast acknowledgement (2.13.1) ─────────────────────────────────────────────

def test_webhook_responds_without_awaiting_delivery(client):
    """The response must not wait on APNs: BHNM times out at ~30s and retries 3x."""
    import main as main_mod
    started, released = [], []

    async def slow_send(tokens, title, body, incident_id=""):
        started.append(True)
        return []

    with patch("main.get_tokens_for_secret", return_value=["tok"]), \
         patch("main.get_web_push_subscriptions_for_secret", return_value=[]), \
         patch("main.send_to_all", side_effect=slow_send):
        resp = client.post("/webhook?secret=fastack", json={
            "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN"})
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "notified": 1}
    released.append(True)
    # TestClient drains background tasks after the response, so delivery still ran
    assert started == [True]


def test_stale_token_cleanup_still_happens_in_the_background(client):
    with patch("main.get_tokens_for_secret", return_value=["tok-stale"]), \
         patch("main.get_web_push_subscriptions_for_secret", return_value=[]), \
         patch("main.send_to_all", new_callable=AsyncMock) as send, \
         patch("main.delete_token") as delete:
        send.return_value = ["tok-stale"]
        resp = client.post("/webhook?secret=cleanup", json={
            "notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN"})
    assert resp.status_code == 200
    delete.assert_called_once_with("tok-stale")


# ── Secret redaction in logs (2.13.2) ─────────────────────────────────────────

from main import _redact


def test_redact_removes_the_webhook_secret_from_an_access_line():
    line = 'POST /webhook?secret=76acf51fc3952b0312b000140e23b40cc HTTP/1.1" 200 OK'
    out = _redact(line)
    assert "76acf51f" not in out
    assert "secret=<redacted>" in out


@pytest.mark.parametrize("key", ["secret", "token", "password", "pwd", "key"])
def test_redact_covers_every_credential_parameter(key):
    assert "abc123" not in _redact(f"/x?{key}=abc123&other=1")


def test_redact_keeps_the_rest_of_the_line():
    out = _redact("POST /webhook?secret=deadbeef HTTP/1.1 200 OK")
    assert out.startswith("POST /webhook?secret=<redacted>")
    assert out.endswith("200 OK")
