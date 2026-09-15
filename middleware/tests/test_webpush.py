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
    # `severity` was removed from the payload; this test kept passing a fourth
    # argument and went red unnoticed because `pytest tests` never collected it.
    payload = build_payload("Server Down", "core-switch-01 unreachable", "42")
    assert payload == {
        "title": "Server Down",
        "body": "core-switch-01 unreachable",
        "incident_id": "42",
    }


def test_build_payload_missing_optional():
    payload = build_payload("Alert", "Something happened", "")
    assert payload == {"title": "Alert", "body": "Something happened", "incident_id": ""}


@pytest.mark.asyncio
async def test_send_web_push_to_all_returns_gone_endpoints():
    subscriptions = [
        {"endpoint": "https://push.example.com/ok", "p256dh": "k1", "auth": "a1"},
        {"endpoint": "https://push.example.com/gone", "p256dh": "k2", "auth": "a2"},
    ]

    def mock_webpush_send(subscription_info, data, **_kwargs):
        # webpush.py also passes `headers=`; pinning the exact signature is how
        # this test broke silently once already.
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
