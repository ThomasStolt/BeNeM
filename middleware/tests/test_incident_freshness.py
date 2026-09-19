"""C9 — every incident states its age, and the cache reports its STALEST member.

The defect this guards: a single `last_updated` stamped once at the end of the
cycle was reported as the age of the whole feed. It was accurate for the last
incident enriched and wrong for every other one — measured 2026-09-16 at 110.5 s
of understatement in a 9-incident lab, and projected at 69 minutes at n=1000.

Design: docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md C9.
"""

import os

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")  # base64("dummy")

from incident_cache import CachedIncidents, _enrich_incident, freshness


def test_a_confirmed_enrichment_carries_both_stamps():
    enriched = _enrich_incident(
        {"incident_id": "1", "incident_state": "OPEN"},
        {"alarm_counts": {"red": 1}, "alert_type": "host", "confirmed": True},
        list_at=1000.0,
    )
    assert enriched["state_confirmed_at"] == 1000.0
    assert enriched["counts_confirmed_at"] is not None


def test_a_FAILED_enrichment_has_NO_counts_timestamp():
    """The whole point. A failed detail call still writes alert_type "host" today
    (C11, build order step 6, deliberately not fixed in this wave) — but it must
    never claim a time at which its counts were confirmed, because there is none.
    """
    enriched = _enrich_incident(
        {"incident_id": "1", "incident_state": "OPEN"},
        {"alarm_counts": None, "alert_type": "host", "confirmed": False},
        list_at=1000.0,
    )
    assert enriched["counts_confirmed_at"] is None
    # State still has a stamp: the LIST call succeeded, only the detail did not.
    assert enriched["state_confirmed_at"] == 1000.0


def test_freshness_reports_the_OLDEST_not_the_newest():
    entry = CachedIncidents(
        active_incidents=[
            {"incident_id": "1", "counts_confirmed_at": 500.0},
            {"incident_id": "2", "counts_confirmed_at": 900.0},
        ],
        closed_incidents=[{"incident_id": "3", "counts_confirmed_at": 100.0}],
    )
    oldest, unconfirmed = freshness(entry)
    assert oldest == 100.0, "a cache is as fresh as its stalest member"
    assert unconfirmed == 0


def test_an_unconfirmed_incident_is_COUNTED_not_aged():
    """"Never confirmed" is a third state. Folding it in as a very large age would
    render unverified as merely stale, which is the doctrine failure.
    """
    entry = CachedIncidents(
        active_incidents=[
            {"incident_id": "1", "counts_confirmed_at": 900.0},
            {"incident_id": "2", "counts_confirmed_at": None},
            {"incident_id": "3"},  # key absent entirely
        ],
    )
    oldest, unconfirmed = freshness(entry)
    assert oldest == 900.0
    assert unconfirmed == 2


def test_freshness_of_an_empty_cache_is_not_zero():
    """Age 0 means "confirmed just now". An empty cache has confirmed nothing, so
    it must report no age at all rather than the freshest possible one.
    """
    oldest, unconfirmed = freshness(CachedIncidents())
    assert oldest is None
    assert unconfirmed == 0
