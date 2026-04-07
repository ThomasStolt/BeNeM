import os
import tempfile

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
    resp = client.post(
        "/register-webpush",
        json={
            "endpoint": "https://fcm.googleapis.com/fcm/send/abc123",
            "p256dh": "test-public-key",
            "auth": "test-auth-secret",
        },
        headers={"X-Webhook-Token": "my-webhook-secret"},
    )
    assert resp.status_code == 201
    subs = get_web_push_subscriptions_for_secret("my-webhook-secret")
    assert len(subs) >= 1
    assert any(s["endpoint"] == "https://fcm.googleapis.com/fcm/send/abc123" for s in subs)


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


def test_webhook_rejects_non_json():
    resp = client.post("/webhook?secret=testsecret", content=b"not json",
                       headers={"Content-Type": "application/json"})
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
