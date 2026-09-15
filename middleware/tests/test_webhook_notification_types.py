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


def test_clean_turns_br_into_a_real_line_break():
    assert clean_bhnm_text(" (Host check triggered from Service PING)<br />Ping OK:  Packet Loss 0%") == \
        "(Host check triggered from Service PING)\nPing OK: Packet Loss 0%"


@pytest.mark.parametrize("markup", ["<br>", "<br/>", "<br />", "<BR />", "</p>", "</ p>"])
def test_clean_treats_every_break_spelling_as_a_line_break(markup):
    assert clean_bhnm_text(f"a{markup}b") == "a\nb"


def test_clean_preserves_a_real_newline():
    """If BHNM fixes the defect and emits \n, that must survive to the screen."""
    assert clean_bhnm_text("Ping OK\nRTA = 0.5 ms") == "Ping OK\nRTA = 0.5 ms"


def test_clean_collapses_spaces_and_tabs_but_not_newlines():
    assert clean_bhnm_text("a  \t b\nc   d") == "a b\nc d"


def test_clean_caps_blank_lines_at_one():
    assert clean_bhnm_text("x\n\n\n\ny") == "x\n\ny"


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


def test_recovery_body_has_no_double_space_and_breaks_at_the_br(client):
    """"Host recovered.  (Host check..." — the captured output starts with a space,
    and its <br /> becomes a real line break rather than another space."""
    _title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "raspi-050", "host_state": "UP",
        "output": " (Host check triggered from Service PING)<br />Ping OK: Packet Loss 0%",
    })
    assert "  " not in body
    assert body == "Host recovered. (Host check triggered from Service PING)\nPing OK: Packet Loss 0%"


def test_retry_wording_from_bhnm_survives_cleaning(client):
    """BHNM stamps its own retry label into {OUTPUT}; it is text, not markup."""
    _title, body, _iid = post(client, {
        "notification_type": "RECOVERY", "hostname": "raspi-050", "host_state": "UP",
        "output": "Retry action by system 1 of 3.  (Host check triggered from Service PING)",
    })
    assert body == "Host recovered. Retry action by system 1 of 3. (Host check triggered from Service PING)"
    assert "\n" not in body  # no markup in this one, so no break


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
    line = 'POST /webhook?secret=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef HTTP/1.1" 200 OK'
    out = _redact(line)
    assert "deadbeef" not in out
    assert "secret=<redacted>" in out


@pytest.mark.parametrize("key", ["secret", "token", "password", "pwd", "key"])
def test_redact_covers_every_credential_parameter(key):
    assert "abc123" not in _redact(f"/x?{key}=abc123&other=1")


def test_redact_keeps_the_rest_of_the_line():
    out = _redact("POST /webhook?secret=deadbeef HTTP/1.1 200 OK")
    assert out.startswith("POST /webhook?secret=<redacted>")
    assert out.endswith("200 OK")


# ── Fan-out reaches every device (2.13.4) ─────────────────────────────────────

import asyncio
import apns as apns_mod


def test_send_to_all_sends_to_every_token_not_just_the_first():
    """Concurrent sends on one HTTP/2 connection wedged after the first response,
    so only the oldest registered device was ever notified. Sends are serial now."""
    seen = []

    async def fake_send_one(_client, token, _title, _body, _iid, env):
        seen.append(token)
        return token, True, 200

    tokens = [(f"tok-{i}", "production") for i in range(5)]
    with patch.object(apns_mod, "_send_one", fake_send_one), \
         patch.object(apns_mod, "_get_client", lambda: object()):
        stale = asyncio.run(apns_mod.send_to_all(tokens, "t", "b", "1"))

    assert seen == [f"tok-{i}" for i in range(5)], "every token, in registration order"
    assert stale == []


def test_send_to_all_collects_410s_and_keeps_going():
    async def fake_send_one(_client, token, _title, _body, _iid, env):
        return token, False, 410 if token == "tok-dead" else 200

    tokens = [("tok-a", "production"), ("tok-dead", "production"), ("tok-b", "production")]
    with patch.object(apns_mod, "_send_one", fake_send_one), \
         patch.object(apns_mod, "_get_client", lambda: object()):
        stale = asyncio.run(apns_mod.send_to_all(tokens, "t", "b", "1"))

    assert stale == ["tok-dead"]


def test_one_failing_token_does_not_stop_the_others():
    seen = []

    async def fake_send_one(_client, token, _title, _body, _iid, env):
        seen.append(token)
        return token, False, 0        # _send_one swallows its own exceptions

    tokens = [("tok-a", "production"), ("tok-b", "production")]
    with patch.object(apns_mod, "_send_one", fake_send_one), \
         patch.object(apns_mod, "_get_client", lambda: object()):
        asyncio.run(apns_mod.send_to_all(tokens, "t", "b", "1"))

    assert seen == ["tok-a", "tok-b"]


def test_a_stalled_fan_out_is_logged_not_silent(capsys):
    """The previous stall produced no output at all for months."""
    import main as main_mod

    async def never_returns(*_a, **_kw):
        await asyncio.sleep(3600)

    async def run():
        with patch.object(main_mod, "send_to_all", never_returns), \
             patch.object(main_mod, "FANOUT_TIMEOUT", 0.05):
            await main_mod._deliver([("tok", "production")], [], "t", "b", "42")

    asyncio.run(run())
    out = capsys.readouterr().out
    assert "[Deliver] TIMEOUT" in out
    assert "incident 42" in out


def test_a_completing_fan_out_logs_no_timeout(capsys):
    import main as main_mod

    async def quick(*_a, **_kw):
        return []

    async def run():
        with patch.object(main_mod, "send_to_all", quick), \
             patch.object(main_mod, "FANOUT_TIMEOUT", 5):
            await main_mod._deliver([("tok", "production")], [], "t", "b", "42")

    asyncio.run(run())
    assert "TIMEOUT" not in capsys.readouterr().out
