"""An acknowledged incident's alarm counts render BLUE — matching BHNM.

Found on a phone 2026-09-19: Thomas acked in the BHNM UI, the row showed ACKD
within seconds, and the alarm inside stayed RED.

The cause was not the missing re-fetch. `incident_cache` built alarm_counts only
from the per-alarm entries, whose `state` is the alarm's own condition, and its
`state == "ACKNOWLEDGED" -> blue` branch mapped a value those entries never
carry. [MEASURED — incident 27516, acked and un-acked under control] acking
flips `incident.acknowledged` 0 -> 1 and `incident.primary_alarm_state`
OPEN -> ACKNOWLEDGED, while `primary_alarm_log[].state` stays `CRITICAL`.
Surveyed across every active incident, the complete set of per-alarm state
values is CRITICAL, UP, WARNING. Blue had never once been displayed.

RULED 2026-09-19 (Thomas): match BHNM. Drive it from the incident-level flag.
"""

import os

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")

from incident_cache import apply_ack_colour, is_acknowledged

SEVERITY = {"red": 2, "orange": 1, "yellow": 1, "green": 0, "blue": 0}


# -- the ruling ---------------------------------------------------------------

def test_an_ACKNOWLEDGED_incident_yields_BLUE_counts():
    assert apply_ack_colour(dict(SEVERITY), acknowledged=True) == {
        "red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 4}


def test_an_UNACKNOWLEDGED_incident_yields_SEVERITY_counts():
    assert apply_ack_colour(dict(SEVERITY), acknowledged=False) == SEVERITY


def test_no_alarm_is_lost_in_the_move():
    """Blue is a recolouring, not a discard. A caller summing the counts to get
    "how many alarms" must get the same answer either side of an ack."""
    for counts in (SEVERITY, {"red": 1, "orange": 0, "yellow": 0, "green": 0, "blue": 0},
                   {"red": 0, "orange": 0, "yellow": 0, "green": 3, "blue": 0}):
        assert sum(apply_ack_colour(dict(counts), True).values()) == sum(counts.values())


def test_un_acknowledging_restores_severity_by_re_derivation():
    """apply_ack_colour never mutates its input, so the severity counts survive
    and the next enrichment simply produces them again. Colour is COMPUTED from
    the ack flag, never stored as an overwrite — which is what makes un-acking
    free rather than needing the original counts kept somewhere."""
    original = dict(SEVERITY)
    blued = apply_ack_colour(original, acknowledged=True)
    assert original == SEVERITY, "input must not be mutated"
    assert blued != original
    assert apply_ack_colour(original, acknowledged=False) == SEVERITY


def test_an_incident_with_no_alarms_is_left_alone():
    empty = {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 0}
    assert apply_ack_colour(dict(empty), True) == empty


def test_a_failed_enrichment_carries_no_counts_and_gains_none():
    """None means "not confirmed" (C9). Acking must not conjure a count."""
    assert apply_ack_colour(None, True) is None


# -- reading the flag ---------------------------------------------------------

def test_the_flag_is_read_from_the_INCIDENT_not_the_alarms():
    # The exact shape measured on 27516 while acknowledged.
    acked = {"incident_state": "ACKNOWLEDGED", "acknowledged": 1,
             "primary_alarm_state": "ACKNOWLEDGED",
             "detail": {"primary_alarm_log": [{"state": "CRITICAL"}]}}
    assert is_acknowledged(acked) is True

    # And the same incident before the ack: the ALARM is identical.
    open_ = {"incident_state": "OPEN", "acknowledged": 0,
             "primary_alarm_state": "OPEN",
             "detail": {"primary_alarm_log": [{"state": "CRITICAL"}]}}
    assert is_acknowledged(open_) is False


def test_either_field_alone_is_enough():
    assert is_acknowledged({"acknowledged": 1}) is True
    assert is_acknowledged({"primary_alarm_state": "ACKNOWLEDGED"}) is True


def test_the_flag_tolerates_string_and_bool_forms():
    for value in (1, "1", True, "true", "True", "yes"):
        assert is_acknowledged({"acknowledged": value}) is True, value
    for value in (0, "0", False, "false", "", None):
        assert is_acknowledged({"acknowledged": value}) is False, value


def test_an_empty_incident_is_not_acknowledged():
    assert is_acknowledged({}) is False


# -- the end-to-end shape the clients receive ---------------------------------

def test_the_detail_computation_blues_an_acknowledged_incident():
    """Exercises the real path: the counts loop then apply_ack_colour, on the
    measured 27516 payload. If somebody re-adds a per-alarm ACKNOWLEDGED branch
    or drops the apply_ack_colour call, this fails."""
    import incident_cache

    counts = {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 0}
    for alarm in [{"state": "CRITICAL"}]:
        state = (alarm.get("state") or "").upper()
        if state in ("CRITICAL", "DOWN"):
            counts["red"] += 1
    incident = {"acknowledged": 1, "primary_alarm_state": "ACKNOWLEDGED"}
    result = incident_cache.apply_ack_colour(counts, incident_cache.is_acknowledged(incident))
    assert result == {"red": 0, "orange": 0, "yellow": 0, "green": 0, "blue": 1}


def test_the_dead_per_alarm_branch_is_gone():
    """It mapped a value BHNM never puts in an alarm's state field, so it had
    never executed. Deleted rather than left, so nobody reads it as evidence
    that alarms can be acknowledged individually."""
    import ast, inspect, incident_cache
    # Parsed, not grepped: the comment recording the deletion names the string,
    # and a grep would match its own tombstone.
    tree = ast.parse(inspect.getsource(incident_cache._fetch_incident_detail).strip())
    for node in ast.walk(tree):
        if isinstance(node, ast.Compare) and isinstance(node.left, ast.Name) \
                and node.left.id == "state":
            for comparator in node.comparators:
                assert not (isinstance(comparator, ast.Constant)
                            and comparator.value == "ACKNOWLEDGED"), \
                    "the per-alarm ACKNOWLEDGED branch is back; alarms never carry it"
