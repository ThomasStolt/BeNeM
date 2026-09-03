import os
import tempfile
import uuid

# Set up test env before imports
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")  # base64("test")
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "test-vapid-public-key")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "mailto:test@test.com")

import pytest
from fastapi.testclient import TestClient
from database import init_db, get_web_push_subscriptions_for_secret
from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _setup_db():
    init_db()
    yield


def test_register_webpush_creates_subscription():
    # Unique endpoint per run: the suite's DB_PATH is decided by whichever test
    # module imports `database` first, and those /tmp files persist across runs,
    # so a fixed endpoint would already exist and the route would answer 200.
    endpoint = f"https://fcm.googleapis.com/fcm/send/{uuid.uuid4().hex}"
    resp = client.post(
        "/register-webpush",
        json={
            "endpoint": endpoint,
            "p256dh": "test-public-key",
            "auth": "test-auth-secret",
        },
        headers={"X-Webhook-Token": "my-webhook-secret"},
    )
    assert resp.status_code == 201
    subs = get_web_push_subscriptions_for_secret("my-webhook-secret")
    assert len(subs) >= 1
    assert any(s["endpoint"] == endpoint for s in subs)


def test_register_webpush_upsert_returns_200():
    client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k1", "auth": "a1"},
        headers={"X-Webhook-Token": "secret"},
    )
    resp = client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k2", "auth": "a2"},
        headers={"X-Webhook-Token": "secret"},
    )
    assert resp.status_code == 200


def test_register_webpush_requires_webhook_token():
    resp = client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k", "auth": "a"},
    )
    assert resp.status_code == 400


def test_vapid_key_endpoint():
    # config is imported once per pytest session; whichever test module loads
    # first decides VAPID_PUBLIC_KEY. Pin it here so the test does not depend
    # on collection order (it passed before only because this file was
    # collected first from the middleware root).
    with patch("config.VAPID_PUBLIC_KEY", "test-vapid-public-key"):
        resp = client.get("/vapid-key")
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicKey"] == "test-vapid-public-key"


def test_vapid_key_returns_404_when_not_configured():
    """When VAPID_PUBLIC_KEY is empty, /vapid-key should return 404."""
    import config
    original = config.VAPID_PUBLIC_KEY
    config.VAPID_PUBLIC_KEY = ""
    try:
        resp = client.get("/vapid-key")
        assert resp.status_code == 404
    finally:
        config.VAPID_PUBLIC_KEY = original


# ── Webhook Pydantic validation and no-device behaviour ──────────────────────

from unittest.mock import patch, AsyncMock


def test_webhook_form_encoded_body_is_accepted():
    """Deliberate BHNM fallback: a non-JSON body that form-decodes to a valid
    payload is processed exactly like JSON (BHNM may send without the JSON
    content-type). Pinned against the running route, 2026-09-03."""
    client.post("/register", json={"token": "55667788" * 8},
                headers={"X-Webhook-Token": "formsecret"})
    with patch("main.send_to_all", new_callable=AsyncMock, return_value=[]) as send:
        resp = client.post(
            "/webhook?secret=formsecret",
            content=b"notification_type=PROBLEM&hostname=raspi-050&host_state=DOWN&incident_id=1",
            headers={"Content-Type": "application/x-www-form-urlencoded"})
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok", "notified": 1}
    assert "raspi-050" in send.await_args.args[1]   # title built from the form fields


def test_webhook_garbage_body_is_rejected_and_not_pushed():
    """2.11.1 contract: a body that is neither JSON nor a form decodes to {}
    (no hostname) and used to be pushed as an "Unknown device" PROBLEM.
    Now 422, and nothing is sent. The ?secret= gate is unchanged."""
    client.post("/register", json={"token": "99aabbcc" * 8},
                headers={"X-Webhook-Token": "garbagesecret"})
    with patch("main.send_to_all", new_callable=AsyncMock, return_value=[]) as send:
        resp = client.post("/webhook?secret=garbagesecret", content=b"not json",
                           headers={"Content-Type": "application/json"})
    assert resp.status_code == 422
    send.assert_not_awaited()


def test_webhook_empty_body_is_rejected():
    resp = client.post("/webhook?secret=anysecret", content=b"")
    assert resp.status_code == 422


@pytest.mark.parametrize("scalar_or_array", [b"123", b"[]", b'["hostname"]', b"null"])
def test_webhook_json_non_object_is_422_not_500(scalar_or_array):
    """A JSON scalar or array used to reach data.get() and raise → 500."""
    resp = client.post("/webhook?secret=anysecret", content=scalar_or_array,
                       headers={"Content-Type": "application/json"})
    assert resp.status_code == 422


@pytest.mark.parametrize("payload", [{"notification_type": "PROBLEM", "host_state": "DOWN"},
                                     {"hostname": ""}, {"hostname": "   "}])
def test_webhook_json_without_hostname_is_rejected(payload):
    """hostname is the one field every BHNM webhook template carries ($HOSTNAME);
    without it there is nothing to notify about."""
    resp = client.post("/webhook?secret=anysecret", json=payload)
    assert resp.status_code == 422


def test_webhook_accepts_valid_payload():
    client.post("/register",
                json={"token": "aabbccdd" * 8},
                headers={"X-Webhook-Token": "testsecret"})
    with patch("main.send_to_all", new_callable=AsyncMock, return_value=[]):
        resp = client.post("/webhook?secret=testsecret",
                           json={
                               "notification_type": "PROBLEM",
                               "hostname": "switch-01",
                               "host_state": "DOWN",
                               "site": "HQ",
                               "output": "unreachable",
                               "incident_id": "42"
                           })
    assert resp.status_code == 200


def test_webhook_accepts_minimal_payload():
    client.post("/register",
                json={"token": "11223344" * 8},
                headers={"X-Webhook-Token": "testsecret2"})
    with patch("main.send_to_all", new_callable=AsyncMock, return_value=[]):
        resp = client.post("/webhook?secret=testsecret2",
                           json={"hostname": "router-01"})
    assert resp.status_code == 200


def test_webhook_returns_200_for_unknown_secret():
    """A valid-shaped secret with no registered devices should return 200, not 403."""
    resp = client.post("/webhook?secret=no-devices-yet",
                       json={"hostname": "switch-01", "host_state": "DOWN"})
    assert resp.status_code == 200
    assert resp.json()["notified"] == 0


# ── Input validation ───────────────────────────────────────────────────────────

def test_register_rejects_empty_token():
    resp = client.post("/register",
                       json={"token": ""},
                       headers={"X-Webhook-Token": "secret"})
    assert resp.status_code == 422


def test_register_rejects_whitespace_token():
    resp = client.post("/register",
                       json={"token": "   "},
                       headers={"X-Webhook-Token": "secret"})
    assert resp.status_code == 422


def test_webpush_rejects_empty_endpoint():
    resp = client.post("/register-webpush",
                       json={"endpoint": "", "p256dh": "key", "auth": "auth"},
                       headers={"X-Webhook-Token": "secret"})
    assert resp.status_code == 422
