import os
import pytest
from unittest.mock import patch, MagicMock

# Ensure config env vars are set for tests
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "")

from webpush import build_payload, send_web_push_to_all


def test_build_payload_all_fields():
    payload = build_payload("Server Down", "core-switch-01 unreachable", "42", "critical")
    assert payload["title"] == "Server Down"
    assert payload["body"] == "core-switch-01 unreachable"
    assert payload["incident_id"] == "42"
    assert payload["severity"] == "critical"


def test_build_payload_missing_optional():
    payload = build_payload("Alert", "Something happened", "", "")
    assert payload["title"] == "Alert"
    assert payload["body"] == "Something happened"
    assert payload["incident_id"] == ""
    assert payload["severity"] == ""


@pytest.mark.asyncio
async def test_send_web_push_to_all_returns_gone_endpoints():
    subscriptions = [
        {"endpoint": "https://push.example.com/ok", "p256dh": "k1", "auth": "a1"},
        {"endpoint": "https://push.example.com/gone", "p256dh": "k2", "auth": "a2"},
    ]

    def mock_webpush_send(subscription_info, data, vapid_private_key, vapid_claims):
        if subscription_info["endpoint"] == "https://push.example.com/gone":
            from pywebpush import WebPushException
            response = MagicMock()
            response.status_code = 410
            raise WebPushException("Gone", response=response)

    with patch("webpush.webpush_send", side_effect=mock_webpush_send), \
         patch("webpush.VAPID_PRIVATE_KEY", "fake-key"):
        gone = await send_web_push_to_all(subscriptions, "Title", "Body", "99")

    assert gone == ["https://push.example.com/gone"]


@pytest.mark.asyncio
async def test_send_web_push_disabled_when_no_vapid_key():
    """When VAPID keys are not configured, send_web_push_to_all should return empty (no-op)."""
    subscriptions = [
        {"endpoint": "https://push.example.com/x", "p256dh": "k", "auth": "a"},
    ]
    # With empty VAPID_PRIVATE_KEY (default in test env), should skip sending
    gone = await send_web_push_to_all(subscriptions, "Title", "Body", "1")
    assert gone == []
