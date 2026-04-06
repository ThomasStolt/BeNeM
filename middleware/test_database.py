import os
import tempfile
import pytest

# Point DB at a temp file before importing database module
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()

from database import (
    init_db,
    save_web_push_subscription,
    get_web_push_subscriptions_for_secret,
    delete_web_push_subscription,
)


@pytest.fixture(autouse=True)
def _setup_db():
    """Re-init DB and clear subscriptions before each test."""
    init_db()
    from database import get_conn
    with get_conn() as conn:
        conn.execute("DELETE FROM web_push_subscriptions")
    yield


def test_save_and_get_subscription():
    save_web_push_subscription(
        endpoint="https://push.example.com/abc",
        p256dh="test-p256dh-key",
        auth="test-auth-secret",
        webhook_secret="secret-123",
    )
    subs = get_web_push_subscriptions_for_secret("secret-123")
    assert len(subs) == 1
    assert subs[0]["endpoint"] == "https://push.example.com/abc"
    assert subs[0]["p256dh"] == "test-p256dh-key"
    assert subs[0]["auth"] == "test-auth-secret"


def test_upsert_replaces_keys():
    save_web_push_subscription("https://push.example.com/abc", "old-p256dh", "old-auth", "secret-1")
    save_web_push_subscription("https://push.example.com/abc", "new-p256dh", "new-auth", "secret-1")
    subs = get_web_push_subscriptions_for_secret("secret-1")
    assert len(subs) == 1
    assert subs[0]["p256dh"] == "new-p256dh"
    assert subs[0]["auth"] == "new-auth"


def test_different_secrets_isolated():
    save_web_push_subscription("https://push.example.com/a", "k1", "a1", "secret-A")
    save_web_push_subscription("https://push.example.com/b", "k2", "a2", "secret-B")
    assert len(get_web_push_subscriptions_for_secret("secret-A")) == 1
    assert len(get_web_push_subscriptions_for_secret("secret-B")) == 1
    assert len(get_web_push_subscriptions_for_secret("secret-C")) == 0


def test_delete_subscription():
    save_web_push_subscription("https://push.example.com/del", "k", "a", "secret-1")
    assert len(get_web_push_subscriptions_for_secret("secret-1")) == 1
    delete_web_push_subscription("https://push.example.com/del")
    assert len(get_web_push_subscriptions_for_secret("secret-1")) == 0
