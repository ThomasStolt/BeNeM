"""C10 — alert_type is learned once from a confirmed call and kept.

[THOMAS 2026-09-19] A host incident is always a host incident; service and
threshold are different things that do not convert. And it cannot be derived
from the title — incident 25076 is titled "Application Service Wordpress" and
its alert_type is `service`, so title parsing gets that one wrong.

Design: docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md C10.
"""

import os
import tempfile

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")

_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name

import database
import incident_cache
from incident_cache import _enrich_incident

database.init_db()


def setup_function():
    incident_cache._types = {}


def test_a_confirmed_type_survives_a_restart():
    incident_cache.remember_type("prod", "25076", "service")
    # The restart: throw the in-memory map away and reload from sqlite.
    incident_cache._types = {}
    incident_cache.load_types()
    assert incident_cache.known_type("prod", "25076") == "service"


def test_the_map_is_keyed_per_server():
    incident_cache.remember_type("prod", "1", "service")
    assert incident_cache.known_type("other", "1") is None


def test_a_failed_detail_uses_the_REMEMBERED_type_not_host():
    """The point of persisting it. Without the map, a failed lookup for a
    `service` incident renders as `host` — the one type known to page — which is
    the strongest possible coverage claim made on no evidence at all.
    """
    enriched = _enrich_incident(
        {"incident_id": "25076", "incident_state": "OPEN"},
        {"alarm_counts": None, "alert_type": "host", "confirmed": False},
        list_at=1000.0,
        remembered="service",
    )
    assert enriched["alert_type"] == "service"
    # Still unconfirmed: a remembered TYPE says nothing about current COUNTS.
    assert enriched["counts_confirmed_at"] is None


def test_a_failed_detail_with_nothing_remembered_still_says_host_for_now():
    """Deliberate, and it is the defect C11 removes at build order step 6 — which
    may not ship before the clients that render UNKNOWN are in the field. This
    test exists so that change is a visible edit here, not a silent drift.
    """
    enriched = _enrich_incident(
        {"incident_id": "99", "incident_state": "OPEN"},
        {"alarm_counts": None, "alert_type": "host", "confirmed": False},
        list_at=1000.0,
        remembered=None,
    )
    assert enriched["alert_type"] == "host"


def test_an_UNCONFIRMED_type_is_never_persisted():
    """A persisted guess is a guess that outlives the process that made it."""
    incident_cache.remember_type("prod", "7", "threshold")
    incident_cache._types = {}
    incident_cache.load_types()
    assert incident_cache.known_type("prod", "7") == "threshold"
    assert incident_cache.known_type("prod", "8") is None, \
        "an incident whose detail call never succeeded must have no remembered type"
