"""An APNs environment outside ("sandbox", "production") is refused, not defaulted.

Written 2026-09-21, from a defect measured on a phone rather than imagined.

An iOS build was changed to read `aps-environment` from the embedded
provisioning profile instead of inferring it from `#if DEBUG`. It read the right
value and sent the entitlement's own word, `development`. `register_token` then
did:

    env = body.environment if body.environment in ("sandbox", "production") else "production"

so a DEVELOPMENT-entitlement token was stored as **production**:

    [APNs]     aps-environment from embedded.mobileprovision: development
    [Register] Token saved: ...10882c55 for iPhone (APNs: production)

which is the exact chain that killed push on the 13 Pro Max on 2026-09-19 —
production host refuses a sandbox token with 400 BadDeviceToken, 2.18.1's
cleanup removes the row, the app re-registers, it flaps.

The silent default was the whole problem. A client sending a value this service
does not understand must fail AT REGISTRATION, loudly, not at the first
incident, invisibly.
"""
import os
import tempfile

_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "test-vapid-public-key")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "mailto:test@test.com")

import pytest
from fastapi.testclient import TestClient

from database import init_db, get_tokens_for_secret
from main import app, INVALID_APNS_ENVIRONMENT

client = TestClient(app)
SECRET = "a" * 64


@pytest.fixture(autouse=True)
def _db():
    init_db()


def _register(token: str, environment):
    body = {"token": token, "device_name": "iPhone"}
    if environment is not None:
        body["environment"] = environment
    return client.post("/register", json=body, headers={"X-Webhook-Token": SECRET})


def _stored_env(token: str):
    """The stored apns_environment for this token, or None if no row exists."""
    for stored, env in get_tokens_for_secret(SECRET):
        if stored == token:
            return env
    return None


def test_development_is_REFUSED_not_silently_stored_as_production():
    """The measured defect. `development` is an entitlement word, not an APNs host."""
    token = "de" * 32
    r = _register(token, "development")
    assert r.status_code == 400, (
        f"expected 400, got {r.status_code} — a development-entitlement token "
        "stored as production is what produces 400 BadDeviceToken from APNs"
    )
    assert r.json()["detail"] == INVALID_APNS_ENVIRONMENT
    assert _stored_env(token) is None, "a refused registration must not write a row"


@pytest.mark.parametrize("bad", ["Development", "prod", "dev", "", "PRODUCTION", "Sandbox"])
def test_every_other_unknown_value_is_refused_too(bad):
    """Including case variants — the comparison is exact and must stay exact."""
    r = _register("ab" * 32, bad)
    assert r.status_code == 400
    assert r.json()["detail"] == INVALID_APNS_ENVIRONMENT


@pytest.mark.parametrize("good", ["sandbox", "production"])
def test_the_two_real_values_are_still_accepted_and_stored_verbatim(good):
    """The guard must be shown capable of a non-400 — otherwise a broken route
    would pass the tests above for the wrong reason."""
    token = ("cd" if good == "sandbox" else "ef") * 32
    r = _register(token, good)
    assert r.status_code == 200, r.text
    assert _stored_env(token) == good, "the accepted value is stored verbatim"


def test_an_absent_environment_still_defaults_to_production():
    """The field's default is unchanged: an older client that sends no
    `environment` at all is not broken by this. Only an UNKNOWN value is
    refused, never a missing one."""
    token = "99" * 32
    r = _register(token, None)
    assert r.status_code == 200, r.text
    assert _stored_env(token) == "production", "the model default is unchanged"


def test_the_refusal_detail_does_not_echo_what_was_sent():
    """A constant detail. The refusal goes into logs and onto screens, and
    echoing client input into either is how injected text gets rendered."""
    r = _register("ab" * 32, "<script>alert(1)</script>")
    assert r.status_code == 400
    assert r.json()["detail"] == INVALID_APNS_ENVIRONMENT
    assert "script" not in r.json()["detail"]
