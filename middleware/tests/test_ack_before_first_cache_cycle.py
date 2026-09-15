"""An incident acknowledged before its first cache cycle must still show ACKNOWLEDGED.

Reproduces the defect measured on 2026-09-15 (evidence §8.9), with that night's exact
timing: incident 29586 raised at 22:05:23Z, acknowledged 93 seconds later, inside the
120 s refresh window, so it had never been cached. `note_state_override_any_server()`
found nothing to patch, returned 0, and `main.py` logged only `if n:` — no patch, no
log, no error.

The strong version of the finding: in the whole persisted log `Cache patched` appeared
three times and every one was `-> CLOSED`. Never once `-> ACKNOWLEDGED`. A feature that
works only on incidents older than two minutes, in a product about the first two minutes.
"""
import os
import time

# Test env before imports — incident_cache pulls in diagnostics, which pulls in config.
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")  # base64("test")

import pytest

import incident_cache


@pytest.fixture(autouse=True)
def _clean_cache():
    # getattr, not attribute access: this file must FAIL on the pre-fix code with a
    # behavioural assertion, not error out in setup on a missing private name.
    def reset():
        incident_cache._cache.clear()
        incident_cache._state_overrides.clear()
        getattr(incident_cache, "_pending_overrides", {}).clear()
    reset()
    yield
    reset()


def _incident(iid: str, state: str = "OPEN") -> dict:
    return {"incident_id": iid, "incident_state": state, "name": "raspi-050", "alert_type": "host"}


# ── the defect, reproduced ───────────────────────────────────────────────────

def test_ack_before_the_first_cache_cycle_is_applied_on_first_sighting():
    """Tonight's exact sequence, asserted through behaviour only.

    Deliberately touches no private state, so against the pre-fix code this fails on
    the last line with OPEN != ACKNOWLEDGED — the defect itself — rather than erroring
    on a name that did not exist yet.
    """
    # 22:05:23 — the incident exists in BHNM. No cache cycle has run for it.
    # 22:06:56 — 93 seconds later, the ACK webhook arrives. Nothing is cached to patch.
    incident_cache.note_state_override_any_server("29586", "ACKNOWLEDGED")

    # The next cache cycle is the first one to see the incident at all.
    incidents = [_incident("29586"), _incident("29546")]
    incident_cache._apply_state_overrides("ThomasLabServer", incidents)

    assert incidents[0]["incident_state"] == "ACKNOWLEDGED"
    assert incidents[1]["incident_state"] == "OPEN", "only the acked incident is touched"


def test_the_override_survives_later_cycles_within_the_ttl():
    """Promoted to a normal per-server override, so cycle two does not revert it."""
    incident_cache.note_state_override_any_server("29586", "ACKNOWLEDGED")
    first = [_incident("29586")]
    incident_cache._apply_state_overrides("ThomasLabServer", first)
    assert first[0]["incident_state"] == "ACKNOWLEDGED"

    # A later cycle brings a fresh snapshot from BHNM, still saying OPEN.
    second = [_incident("29586")]
    incident_cache._apply_state_overrides("ThomasLabServer", second)
    assert second[0]["incident_state"] == "ACKNOWLEDGED"


def test_a_pending_override_expires_with_the_same_ttl():
    """It must not resurrect an incident state five minutes later."""
    incident_cache.note_state_override_any_server("29586", "ACKNOWLEDGED")
    incident_cache._pending_overrides["29586"] = (
        "ACKNOWLEDGED",
        time.time() - incident_cache.STATE_OVERRIDE_TTL - 1,
    )
    incidents = [_incident("29586")]
    incident_cache._apply_state_overrides("ThomasLabServer", incidents)
    assert incidents[0]["incident_state"] == "OPEN"
    assert "29586" not in incident_cache._pending_overrides


def test_recovery_before_the_first_cycle_works_the_same_way():
    """RECOVERY is the path with three prior observations of working; it must not
    regress, and it takes the same route when the incident is not yet cached."""
    assert incident_cache.note_state_override_any_server("29999", "CLOSED") == 0
    incidents = [_incident("29999")]
    incident_cache._apply_state_overrides("ThomasLabServer", incidents)
    assert incidents[0]["incident_state"] == "CLOSED"


# ── the pre-existing path must still behave ─────────────────────────────────

def test_an_incident_already_cached_is_patched_immediately_and_counted():
    """The path that always worked. It must keep working, and must NOT go pending."""
    inc = _incident("29570")
    incident_cache._cache["ThomasLabServer"] = incident_cache.CachedIncidents(
        active_incidents=[inc], closed_incidents=[], last_updated=time.time()
    )
    assert incident_cache.note_state_override_any_server("29570", "CLOSED") == 1
    assert inc["incident_state"] == "CLOSED", "patched in place, visible on the next fetch"
    # getattr: this test is the regression guard for the path that always worked, so
    # it must pass against the pre-fix code too.
    assert "29570" not in getattr(incident_cache, "_pending_overrides", {})


def test_zero_return_no_longer_means_the_override_was_dropped():
    """The contract change. Zero used to mean 'nothing happened'; it now means
    'nothing was patched *yet*'. The caller logs it either way — a silent zero is
    how this stayed invisible."""
    n = incident_cache.note_state_override_any_server("30001", "ACKNOWLEDGED")
    assert n == 0
    assert incident_cache._pending_overrides["30001"][0] == "ACKNOWLEDGED"
