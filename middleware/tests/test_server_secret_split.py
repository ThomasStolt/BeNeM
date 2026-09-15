"""S1 change 1a — per-server accepted-secrets mechanism, with no behavioural change.

1a's whole claim is that it can be deployed on its own: every server's accepted
list is seeded with the current global secret, so the set of devices a webhook
reaches is exactly the set it reached before. The invariant test below is the one
that has to hold — the rest are the mechanism it rests on.
"""
import json
import os
import tempfile

# Test env before imports, as the other endpoint tests do.
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")  # base64("test")

import pytest

import config
import main
from config import server_accepted_secrets
from database import (
    init_db,
    save_token,
    get_conn,
    get_tokens_for_secret,
    get_tokens_for_secrets,
    save_web_push_subscription,
    get_web_push_subscriptions_for_secret,
    get_web_push_subscriptions_for_secrets,
)

GLOBAL_SECRET = "seeded-global-secret-value"  # synthetic; never a real one
NEW_SECRET = "per-server-secret-for-lab"


@pytest.fixture(autouse=True)
def _clean_db():
    init_db()
    with get_conn() as conn:
        conn.execute("DELETE FROM device_tokens")
        conn.execute("DELETE FROM web_push_subscriptions")
    yield


@pytest.fixture
def servers_file(tmp_path, monkeypatch):
    """Point both config and main at a temporary servers.json."""
    def _write(servers):
        path = tmp_path / "servers.json"
        path.write_text(json.dumps(servers))
        monkeypatch.setattr(main, "SERVERS_JSON_PATH", str(path))
        monkeypatch.setattr(config, "SERVERS_JSON_PATH", str(path))
        return str(path)
    return _write


# ── config.server_accepted_secrets ───────────────────────────────────────────

def test_accepted_secrets_reads_the_list():
    assert server_accepted_secrets({"webhook_secrets": [GLOBAL_SECRET, NEW_SECRET]}) == [
        GLOBAL_SECRET, NEW_SECRET
    ]


def test_accepted_secrets_is_empty_when_absent_or_malformed():
    # A servers.json predating 1a, and a hand-edited one with the wrong shape.
    assert server_accepted_secrets({}) == []
    assert server_accepted_secrets({"webhook_secrets": None}) == []
    assert server_accepted_secrets({"webhook_secrets": "not-a-list"}) == []


def test_accepted_secrets_drops_blanks_and_strips():
    assert server_accepted_secrets({"webhook_secrets": ["  a  ", "", "   ", "b"]}) == ["a", "b"]


# ── main.secret_fingerprint ──────────────────────────────────────────────────

def test_fingerprint_is_stable_and_short():
    fp = main.secret_fingerprint(GLOBAL_SECRET)
    assert fp == main.secret_fingerprint(GLOBAL_SECRET)
    assert len(fp) == 8
    int(fp, 16)  # hex, asserted without writing a 16-char hex alphabet the
                 # credential scanner would (correctly) flag as credential-shaped


def test_fingerprint_is_not_a_piece_of_the_secret():
    """The point of the hash. A prefix would leak the secret a character at a time."""
    fp = main.secret_fingerprint(GLOBAL_SECRET)
    assert fp not in GLOBAL_SECRET
    assert not GLOBAL_SECRET.startswith(fp)


def test_fingerprint_distinguishes_two_secrets():
    assert main.secret_fingerprint(GLOBAL_SECRET) != main.secret_fingerprint(NEW_SECRET)


def test_fingerprint_of_nothing_is_a_label_not_a_hash():
    assert main.secret_fingerprint("") == "none"


# ── main._server_for_webhook_secret ──────────────────────────────────────────

def test_resolves_the_server_that_lists_the_secret(servers_file):
    servers_file([
        {"id": "lab", "name": "Lab", "webhook_secrets": [NEW_SECRET]},
        {"id": "prod", "name": "Prod", "webhook_secrets": [GLOBAL_SECRET]},
    ])
    assert main._server_for_webhook_secret(NEW_SECRET)["id"] == "lab"
    assert main._server_for_webhook_secret(GLOBAL_SECRET)["id"] == "prod"


def test_unknown_secret_resolves_to_none(servers_file):
    servers_file([{"id": "lab", "name": "Lab", "webhook_secrets": [NEW_SECRET]}])
    assert main._server_for_webhook_secret("not-listed-anywhere") is None
    assert main._server_for_webhook_secret("") is None


def test_servers_json_predating_1a_resolves_to_none(servers_file):
    """No webhook_secrets key at all — the caller must fall back, not page nobody."""
    servers_file([{"id": "lab", "name": "Lab", "api_key": "k"}])
    assert main._server_for_webhook_secret(GLOBAL_SECRET) is None


# ── the lookup gains a plural without changing the singular ──────────────────

def test_tokens_for_secrets_unions_the_accepted_list():
    save_token("tok-old", "A", GLOBAL_SECRET, "production", "lab")
    save_token("tok-new", "B", NEW_SECRET, "production", "lab")
    found = [t for t, _ in get_tokens_for_secrets([GLOBAL_SECRET, NEW_SECRET])]
    assert found == ["tok-old", "tok-new"]  # ORDER BY id — oldest registration first


def test_tokens_for_secrets_of_an_empty_list_is_empty():
    save_token("tok-old", "A", GLOBAL_SECRET)
    assert get_tokens_for_secrets([]) == []


def test_web_push_subscriptions_union_the_accepted_list():
    save_web_push_subscription("https://push/1", "p", "a", GLOBAL_SECRET, "lab")
    save_web_push_subscription("https://push/2", "p", "a", NEW_SECRET, "lab")
    endpoints = [s["endpoint"] for s in get_web_push_subscriptions_for_secrets([GLOBAL_SECRET, NEW_SECRET])]
    assert endpoints == ["https://push/1", "https://push/2"]


# ── the 1a invariant ─────────────────────────────────────────────────────────

def test_seeded_lists_select_exactly_what_the_single_secret_lookup_selected(servers_file):
    """THE test for 1a being deployable alone.

    Every server seeded with the current global secret, every device registered
    under it: resolving the server and fanning out over its accepted list must
    select the identical device set that the pre-1a single-secret lookup did.
    If this ever fails, 1a has become a behavioural change and must not ship
    without the 1b migration.
    """
    servers_file([
        {"id": "lab", "name": "Lab", "webhook_secrets": [GLOBAL_SECRET]},
        {"id": "prod", "name": "Prod", "webhook_secrets": [GLOBAL_SECRET]},
    ])
    for i in range(3):
        save_token(f"tok-{i}", f"iPhone {i}", GLOBAL_SECRET)
    save_web_push_subscription("https://push/x", "p", "a", GLOBAL_SECRET)

    before_tokens = get_tokens_for_secret(GLOBAL_SECRET)
    before_subs = get_web_push_subscriptions_for_secret(GLOBAL_SECRET)

    server = main._server_for_webhook_secret(GLOBAL_SECRET)
    accepted = server_accepted_secrets(server)
    after_tokens = get_tokens_for_secrets(accepted)
    after_subs = get_web_push_subscriptions_for_secrets(accepted)

    assert after_tokens == before_tokens
    assert after_subs == before_subs
    assert len(after_tokens) == 3


def test_registration_binds_to_a_server_without_changing_who_is_paged(servers_file):
    """A registration records its server; the fan-out still selects it by secret."""
    servers_file([{"id": "lab", "name": "Lab", "webhook_secrets": [GLOBAL_SECRET]}])
    server = main._server_for_webhook_secret(GLOBAL_SECRET)
    save_token("tok-bound", "iPhone", GLOBAL_SECRET, "production", server["id"])

    with get_conn() as conn:
        row = conn.execute(
            "SELECT server_id FROM device_tokens WHERE token = ?", ("tok-bound",)
        ).fetchone()
    assert row[0] == "lab"
    assert [t for t, _ in get_tokens_for_secrets([GLOBAL_SECRET])] == ["tok-bound"]


def test_a_device_on_an_unlisted_secret_is_still_reachable_by_fallback(servers_file):
    """The pre-1a path. An unresolved webhook must page who it pages today."""
    servers_file([{"id": "lab", "name": "Lab", "webhook_secrets": [NEW_SECRET]}])
    save_token("tok-legacy", "iPhone", "some-older-secret")
    assert main._server_for_webhook_secret("some-older-secret") is None
    assert [t for t, _ in get_tokens_for_secret("some-older-secret")] == ["tok-legacy"]
