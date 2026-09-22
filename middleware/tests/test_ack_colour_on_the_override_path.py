"""The alarm chip must move with the flag, in the same instant.

**The field defect, reported 2026-09-22 on iOS 54:** after an ACKNOWLEDGEMENT
webhook the row reads ACKD and the alarm chip stays red.

**Measured on the live lab before anything was changed**, on incident 30032 —
the only lab incident with a BHNM Action, so the only one whose ack produces a
webhook at all (30031 and 25482 were acked in BHNM and produced no webhook; the
log was checked, not assumed):

    baseline, unacknowledged      counts={'green': 1}  ccat=1790084632.9871218
    ACKNOWLEDGEMENT webhook
    +5.94s, acknowledged=True     counts={'green': 1}  ccat=1790084632.9871218

`counts_confirmed_at` byte-identical either side proves no enrichment ran, so
that IS the override window — and `alarm_counts` came back unchanged. The
reverse was measured too: after a DEACKNOWLEDGEMENT the served row read
`acknowledged: false` while still carrying `blue: 1`.

The cause is one line long. `_apply_override_fields` wrote `incident_state`,
`acknowledged`, `state` and `closed_at`, and never touched `alarm_counts` —
which was survivable while only enrichment applied the colour, because
enrichment re-derives from BHNM every cycle. Under webhook mode that cycle is
~100 s in this lab and longer in a real estate, and it is the whole window the
user sits in.

These tests drive the REAL webhook route and read the REAL served payload. A
test calling `apply_ack_colour` directly would have passed throughout: that
function was always correct, and was simply never called on this path.
"""
import json
import os
import tempfile
import time

API_KEY = "ack-colour-key"
TARGET = "https://bhnm-ack-colour.example.com"

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
# setdefault, never a hard set: `database.py` reads DB_PATH into a module global
# at import, so a hard set here points this module's init_db() at a file the
# already-imported connection is not using — `no such table: device_tokens`, but
# only when the whole suite runs and another module imported first. Measured.
_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_db.close()
os.environ.setdefault("DB_PATH", _db.name)

_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([{"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
            "cache_enabled": True, "cache_refresh_seconds": 120}], _servers)
_servers.close()
# Same rule. The fixture below sets the module globals, which is what actually
# decides where the app looks at runtime.
os.environ.setdefault("SERVERS_JSON_PATH", _servers.name)

import pytest
from fastapi.testclient import TestClient

import main as main_mod
import incident_cache
from database import init_db
from incident_cache import SEVERITY_COUNTS_KEY, apply_ack_colour, derive_counts

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}
RED = {"red": 2, "orange": 1, "yellow": 0, "green": 0, "blue": 0}
GREEN = {"red": 0, "orange": 0, "yellow": 0, "green": 3, "blue": 0}


@pytest.fixture(autouse=True)
def _clean():
    # init_db HERE, not at import. `database.py` resolves DB_PATH from the
    # environment per CONNECTION (`database.py:87`), and six other test modules
    # hard-set DB_PATH at import — so whichever imported last decides where the
    # app actually reads, and a table created at this module's import time can
    # end up in a file nothing opens. The webhook route touches device_tokens
    # even with nobody registered, so it has to exist wherever the env points
    # at the moment these tests run. Measured: `no such table: device_tokens`,
    # nine failures, only when the whole suite runs together.
    init_db()
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    incident_cache._pending_overrides.clear()
    orig_path, orig_tok = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig_path, orig_tok
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()


def _seed(counts, acknowledged=False, state="OPEN"):
    """One enriched row, exactly as _enrich_incident leaves it — including the
    severity counts, which is what makes the un-ack reversible."""
    confirmed = time.time()
    incident_cache._cache["lab"] = incident_cache.CachedIncidents(
        active_incidents=[{
            "incident_id": "30032", "name": "raspi-050", "title": "Host raspi-050",
            "incident_state": "ACKNOWLEDGED" if acknowledged else state,
            "state": state, "acknowledged": acknowledged, "ack_user": None,
            "closed_at": None, "alert_type": "host",
            "alarm_counts": apply_ack_colour(dict(counts), acknowledged),
            SEVERITY_COUNTS_KEY: dict(counts),
            "state_confirmed_at": confirmed, "counts_confirmed_at": confirmed,
        }],
        closed_incidents=[],
        last_updated=confirmed,
    )
    return confirmed


def _webhook(notification_type):
    return TestClient(main_mod.app).post(
        "/webhook?secret=nobody-is-registered",
        json={"notification_type": notification_type, "hostname": "raspi-050",
              "incident_id": "30032", "output": "x"})


def _served():
    """The row as GET /api/v1/incidents actually serves it — not the cache dict.
    The defect was reported from a screen, so the assertion belongs on the
    payload a screen receives."""
    r = TestClient(main_mod.app).get("/api/v1/incidents", headers=HEADERS)
    assert r.status_code == 200, r.text
    body = r.json()
    for row in body["active_incidents"] + body["closed_incidents"]:
        if str(row["incident_id"]) == "30032":
            return row
    raise AssertionError("30032 is in neither bucket")


# ── 1. the ack ───────────────────────────────────────────────────────────────

def test_an_ack_webhook_turns_the_SERVED_counts_blue_BEFORE_any_enrichment():
    """**The reported defect.** Fails against 2.20.1."""
    confirmed = _seed(RED)
    assert _served()["alarm_counts"] == RED

    assert _webhook("ACKNOWLEDGEMENT").status_code == 200

    row = _served()
    assert row["acknowledged"] is True, "the flag moved"
    assert row["alarm_counts"] == {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 3}, (
        "the chip must move with the flag — this is the field defect: the row "
        "read ACKD with a red chip until the next enrichment came round"
    )
    assert row["counts_confirmed_at"] == confirmed, (
        "and NO enrichment has run — without this the test could pass for the "
        "wrong reason, which is the whole shape of the bug it is guarding"
    )


def test_no_alarm_is_lost_when_the_override_paints_them_blue():
    _seed(RED)
    _webhook("ACKNOWLEDGEMENT")
    assert sum(_served()["alarm_counts"].values()) == sum(RED.values())


# ── 2. the un-ack ────────────────────────────────────────────────────────────

def test_an_unack_webhook_turns_the_SERVED_counts_BACK_to_severity():
    """The reverse, and the reason the severity counts are stored at all.

    Blue says "three alarms, someone has this" and not which three, so nothing
    can be recovered from it. Measured on the live lab: after a
    DEACKNOWLEDGEMENT the served row read `acknowledged: false` and still
    carried `blue: 1`.
    """
    confirmed = _seed(RED, acknowledged=True)
    assert _served()["alarm_counts"]["blue"] == 3, "starts blue"

    assert _webhook("DEACKNOWLEDGEMENT").status_code == 200

    row = _served()
    assert row["acknowledged"] is False
    assert row["alarm_counts"] == RED, "the severity must come back, not stay blue"
    assert row["counts_confirmed_at"] == confirmed, "no enrichment ran"


def test_ack_then_unack_returns_the_row_to_exactly_where_it_started():
    """A round trip, because two half-correct derivations can still drift."""
    _seed(RED)
    before = dict(_served()["alarm_counts"])
    _webhook("ACKNOWLEDGEMENT")
    _webhook("DEACKNOWLEDGEMENT")
    assert _served()["alarm_counts"] == before


# ── 3. cleared stays green ───────────────────────────────────────────────────

def test_cleared_alarms_stay_GREEN_either_way():
    """Green is a fact about the ALARM, not about whether anybody has picked the
    incident up. An acknowledged incident whose alarms have cleared is still
    cleared.

    Until 2.20.2 `apply_ack_colour` moved green too, and it was measured doing
    so on 2026-09-22: incident 30032, host back UP, enrichment turned
    `{'green': 1}` into `{'blue': 1}` while acknowledged.
    """
    _seed(GREEN, state="ALARMS CLEARED")
    _webhook("ACKNOWLEDGEMENT")
    row = _served()
    assert row["acknowledged"] is True
    assert row["alarm_counts"] == GREEN, "cleared alarms are not repainted"
    assert row["state"] == "ALARMS CLEARED", "and ACKD is a flag, not a state"

    _webhook("DEACKNOWLEDGEMENT")
    assert _served()["alarm_counts"] == GREEN


def test_a_mixed_row_blues_only_the_uncleared_alarms():
    mixed = {"red": 1, "orange": 0, "yellow": 1, "green": 2, "blue": 0}
    _seed(mixed)
    _webhook("ACKNOWLEDGEMENT")
    assert _served()["alarm_counts"] == {
        "red": 0, "orange": 0, "yellow": 0, "green": 2, "blue": 2}


# ── 4. the things the fix must not break ─────────────────────────────────────

def test_a_row_with_no_counts_gains_none():
    """None means "not confirmed" (C9). An ack must not conjure a count."""
    confirmed = time.time()
    incident_cache._cache["lab"] = incident_cache.CachedIncidents(
        active_incidents=[{
            "incident_id": "30032", "name": "raspi-050", "title": "Host raspi-050",
            "incident_state": "OPEN", "state": "OPEN", "acknowledged": False,
            "ack_user": None, "closed_at": None, "alert_type": "host",
            "alarm_counts": None, SEVERITY_COUNTS_KEY: None,
            "state_confirmed_at": confirmed, "counts_confirmed_at": None,
        }],
        closed_incidents=[], last_updated=confirmed)
    _webhook("ACKNOWLEDGEMENT")
    row = _served()
    assert row["acknowledged"] is True
    assert row["alarm_counts"] is None
    assert row["counts_confirmed_at"] is None


def test_a_row_cached_before_this_release_still_acks_correctly():
    """The deploy window, stated rather than hidden. A row already in the cache
    when 2.20.2 starts has no severity key, because nothing was writing one. For
    an ACK its current counts ARE the severity counts, so the answer is exactly
    right; only an un-ack in that window cannot come back, and the next
    enrichment fixes it."""
    confirmed = time.time()
    incident_cache._cache["lab"] = incident_cache.CachedIncidents(
        active_incidents=[{
            "incident_id": "30032", "name": "raspi-050", "title": "Host raspi-050",
            "incident_state": "OPEN", "state": "OPEN", "acknowledged": False,
            "ack_user": None, "closed_at": None, "alert_type": "host",
            "alarm_counts": dict(RED),          # no SEVERITY_COUNTS_KEY at all
            "state_confirmed_at": confirmed, "counts_confirmed_at": confirmed,
        }],
        closed_incidents=[], last_updated=confirmed)
    _webhook("ACKNOWLEDGEMENT")
    assert _served()["alarm_counts"] == {
        "red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 3}


def test_a_recovery_webhook_does_not_repaint_anything():
    """CLOSED is not an ack. The colour rule must not leak into the close path."""
    _seed(RED)
    _webhook("RECOVERY")
    row = _served()
    assert row["state"] == "CLOSED"
    assert row["alarm_counts"] == RED, "closing an incident is not acknowledging it"


def test_ONE_derivation_function_serves_EVERY_path():
    """Not three copies. The list path, the webhook path and enrichment all
    reach the colour rule through `recolour`, which reads the row's own state
    and flag rather than taking them as arguments — so a caller cannot derive a
    colour from a fact the row does not actually carry.

    Before 2.20.3 the ack rule lived in two places and the cleared rule in none.
    """
    import inspect
    for fn in (incident_cache._apply_override_fields,
               incident_cache._list_only_row,
               incident_cache._enrich_incident):
        assert "recolour(" in inspect.getsource(fn), \
            f"{fn.__name__} must go through the shared rule"
    assert "derive_counts" in inspect.getsource(incident_cache.recolour)

    # And they agree on actual values, which the greps above cannot show.
    row = {"state": "OPEN", "acknowledged": True,
           "alarm_counts": dict(RED), SEVERITY_COUNTS_KEY: dict(RED)}
    incident_cache.recolour(row)
    assert row["alarm_counts"] == derive_counts(dict(RED), cleared=False, acknowledged=True)
    assert row["alarm_counts"] == apply_ack_colour(dict(RED), True)
