"""C16 to C20 — when the cache publishes, and what it is allowed to overwrite.

Design: docs/superpowers/specs/2026-09-23-cache-publish-and-cadence.md

Three defects measured on the live lab on 2026-09-23, all in the same place —
the cycle that takes a list, enriches every row, and writes the whole cache at
the end:

  30045  served CLOSED while BHNM had it OPEN. A cycle published a list taken
         at 06:59:24, 48 s before the incident existed at 07:00:12, over a
         refresh at 07:00:37.783 that had already found it. BHNM did not close
         it until 07:10:29.
  30046  BHNM cleared at 07:06:27, the phone saw green at 07:09:38 — of which
         101 s was the cache holding the right answer and serving the old one,
         because the write happens at the end of the cycle.

Nothing here is about colour. 2.20.2 and 2.20.3 were.

**The new names are reached through the module, not imported at the top**, so
this file still COLLECTS against the pre-2.21.0 code and the three headline
tests fail on behaviour rather than on an ImportError. An import error is
weaker evidence: it says the function is missing, not that the old code is
wrong.
"""
import json
import os
import tempfile
import time

API_KEY = "publish-cadence-key"
TARGET = "https://bhnm-publish.example.com"

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_db.close()
os.environ.setdefault("DB_PATH", _db.name)

_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([{"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
            "cache_enabled": True, "cache_refresh_seconds": 120,
            "retain_closed": True}], _servers)
_servers.close()
os.environ.setdefault("SERVERS_JSON_PATH", _servers.name)

import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi.testclient import TestClient

import main as main_mod
import incident_cache
from database import init_db
from incident_cache import CachedIncidents, SEVERITY_COUNTS_KEY

HEADERS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": TARGET}
SERVER = {"id": "lab", "name": "Lab", "url": TARGET, "api_key": API_KEY, "pin": "",
          "cache_enabled": True, "cache_refresh_seconds": 120, "retain_closed": True}
RED = {"red": 1, "orange": 0, "yellow": 0, "green": 0, "blue": 0}


@pytest.fixture(autouse=True)
def _clean():
    init_db()
    incident_cache._cache.clear()
    incident_cache._state_overrides.clear()
    incident_cache._pending_overrides.clear()
    incident_cache._refresh_last.clear()
    incident_cache._refresh_locks.clear()
    orig = (main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN)
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig
    incident_cache._cache.clear()
    incident_cache._refresh_last.clear()


# ── a BHNM that records every call and answers per method ───────────────────

class FakeBHNM:
    """Records every form posted. `detail_calls` is the evidence for C17's cost
    claim — asserting on the answer alone would pass just as happily with a
    detail call per row beside it.

    `detail_gate`, when set, blocks inside getincidentdetail. That is how C18 is
    tested: the list must publish while a detail call is still in flight.
    """

    def __init__(self, listing, details=None):
        self.listing = listing
        self.details = details or {}
        self.calls = []
        self.detail_gate: asyncio.Event | None = None

    @property
    def detail_calls(self):
        return [c for c in self.calls if c.get("method") == "getincidentdetail"]

    @property
    def list_calls(self):
        return [c for c in self.calls if c.get("method") == "getincidents"]

    async def post(self, url, data=None, **kw):
        form = dict(data or {})
        self.calls.append(form)
        resp = MagicMock(status_code=200)
        if form.get("method") == "getincidentdetail":
            if self.detail_gate is not None:
                await self.detail_gate.wait()
            iid = str(form.get("incident_id"))
            resp.json.return_value = self.details.get(
                iid, {"result": "completed", "incident": {}})
        else:
            resp.json.return_value = self.listing
        return resp

    def client(self):
        c = MagicMock()
        c.post = self.post
        ctx = MagicMock()
        ctx.__aenter__ = AsyncMock(return_value=c)
        ctx.__aexit__ = AsyncMock(return_value=False)
        return ctx


def listing(*rows):
    return {"result": "completed",
            "active_incidents": [dict(r) for r in rows]}


def raw(iid, state="OPEN"):
    return {"incident_id": iid, "name": "raspi-050", "title": f"Host {iid}",
            "incident_state": state, "open_time": "2026-09-23T09:00:12"}


def detail(state="OPEN", alarm="CRITICAL", found=True):
    if not found:
        return {"result": "completed", "detail": "No such incident."}
    return {"result": "completed", "incident": {
        "incident_state": state, "acknowledged": 0, "alert_type": "host",
        "detail": {"primary_alarm_log": [{"state": alarm}]}}}


def cached(iid, *, state="OPEN", confirmed_at, counts_at=None, closed_at=None,
           acknowledged=False):
    return {"incident_id": iid, "name": "raspi-050", "title": f"Host {iid}",
            "incident_state": state, "state": state, "acknowledged": acknowledged,
            "ack_user": None, "closed_at": closed_at, "alert_type": "host",
            "alarm_counts": dict(RED), SEVERITY_COUNTS_KEY: dict(RED),
            "state_confirmed_at": confirmed_at,
            "counts_confirmed_at": confirmed_at if counts_at is None else counts_at}


def seed(*rows):
    active = [r for r in rows if r.get("state") != "CLOSED"]
    closed = [r for r in rows if r.get("state") == "CLOSED"]
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=active, closed_incidents=closed, last_updated=time.time())


def served(iid=None):
    r = TestClient(main_mod.app).get("/api/v1/incidents", headers=HEADERS)
    assert r.status_code == 200, r.text
    body = r.json()
    rows = body["active_incidents"] + body["closed_incidents"]
    if iid is None:
        return {str(x["incident_id"]): x for x in rows}
    return next((x for x in rows if str(x["incident_id"]) == str(iid)), None)


def run_cycle(bhnm):
    """One full pass of whatever the current code calls a cycle."""
    with patch("incident_cache.httpx.AsyncClient", return_value=bhnm.client()):
        asyncio.run(_one_pass(bhnm))


async def _one_pass(bhnm):
    fn = getattr(incident_cache, "_run_list_and_publish", None) or incident_cache._run_one_cycle
    async with __import__("httpx").AsyncClient() as _:
        pass
    c = MagicMock()
    c.post = bhnm.post
    await fn(c, SERVER)


def refresh(bhnm):
    with patch("incident_cache.httpx.AsyncClient", return_value=bhnm.client()):
        return asyncio.run(incident_cache.refresh_server(SERVER))


# ══ C16 — newest confirmation wins ═══════════════════════════════════════════

def test_a_cycle_may_not_overwrite_a_row_a_refresh_confirmed_later():
    """**The headline C16 test. Fails against 2.20.3.**

    A cycle takes its list at T and publishes it later. A refresh confirms the
    same row at T+10. The cycle must not put its older answer back.
    """
    now = time.time()
    seed(cached("30045", state="ALARMS CLEARED", confirmed_at=now + 10))
    bhnm = FakeBHNM(listing(raw("30045", "OPEN")),
                    {"30045": detail("OPEN")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row["state"] == "ALARMS CLEARED", (
        "a list taken at T must not overwrite a row confirmed at T+10 — this is "
        "the refresh-then-cycle regression of state"
    )
    assert row["state_confirmed_at"] == now + 10, "and its stamp must not move backwards"


def test_a_row_confirmed_after_the_list_was_taken_is_NOT_a_disappearance():
    """**The 30045 case exactly.** The incident opened 48 s after the cycle's
    list was taken, so it could not have been in it. Absence from a list that
    predates the row is not absence."""
    now = time.time()
    seed(cached("30045", state="OPEN", confirmed_at=now + 10))
    bhnm = FakeBHNM(listing())                       # the cycle's list has nothing
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row is not None, "the row must survive"
    assert row["state"] == "OPEN", "and must NOT have been retained as CLOSED"
    assert row["closed_at"] is None
    assert bhnm.detail_calls == [], "and no C17 check is needed — it is not absent"


def test_a_cycle_DOES_overwrite_a_row_older_than_its_list():
    """The guard shown capable of the other answer. Without this, a function
    that never publishes anything would pass the two tests above."""
    now = time.time()
    seed(cached("30045", state="OPEN", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(raw("30045", "ALARMS CLEARED")),
                    {"30045": detail("ALARMS CLEARED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    assert served("30045")["state"] == "ALARMS CLEARED"


def test_the_comparison_is_per_row_not_per_publish():
    """One protected row must not block the other four. The rule is about
    vintages of rows, not vintages of publishes."""
    now = time.time()
    seed(cached("1", confirmed_at=now + 10, state="ALARMS CLEARED"),
         cached("2", confirmed_at=now - 300),
         cached("3", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(raw("1", "OPEN"), raw("2", "ALARMS CLEARED"),
                            raw("3", "ALARMS CLEARED")),
                    {i: detail("ALARMS CLEARED", alarm="OK") for i in ("1", "2", "3")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    rows = served()
    assert rows["1"]["state"] == "ALARMS CLEARED", "protected, keeps its own newer value"
    assert rows["2"]["state"] == "ALARMS CLEARED", "older, takes the list's"
    assert rows["3"]["state"] == "ALARMS CLEARED"
    assert rows["1"]["state_confirmed_at"] == now + 10
    assert rows["2"]["state_confirmed_at"] == now


# ══ C17 — disappearance is confirmed ═════════════════════════════════════════

def test_an_absent_row_is_CHECKED_with_one_getincidentdetail_before_retention():
    """**The headline C17 test. Fails against 2.20.3**, which retains on the
    absence alone and makes no call at all."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": detail("CLOSED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    ids = [c.get("incident_id") for c in bhnm.detail_calls]
    assert ids == ["30045"], (
        f"exactly one check for the absent row before retention, got {ids}"
    )


def test_BHNM_saying_CLOSED_retains_the_row():
    """The 30014 path — an incident that vanishes with no RECOVERY — still
    works. C17 makes the close checked, not optional."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": detail("CLOSED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row["state"] == "CLOSED"
    assert row["closed_at"] is not None, "closed_at is still the middleware's own clock"


def test_BHNM_saying_OPEN_keeps_the_row_ACTIVE_with_that_state():
    """The false-CLOSED defect closed off at its second cause."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": detail("OPEN")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row["state"] == "OPEN", "BHNM still has it open; it is not closed"
    assert row["closed_at"] is None
    assert str(row["incident_id"]) in {
        str(x["incident_id"]) for x in
        TestClient(main_mod.app).get("/api/v1/incidents", headers=HEADERS)
        .json()["active_incidents"]}, "and it is in the ACTIVE bucket"


def test_BHNM_saying_ALARMS_CLEARED_keeps_the_row_active_and_GREEN():
    """C17 composes with 2.20.3's recolour: the state it learns drives the
    colour through the one derivation, not a second copy of the rule."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": detail("ALARMS CLEARED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row["state"] == "ALARMS CLEARED"
    assert row["closed_at"] is None
    assert row["alarm_counts"]["green"] == sum(RED.values())
    assert row["alarm_counts"]["red"] == 0


def test_BHNM_not_finding_it_retains_the_row():
    """BHNM has forgotten the incident, which is a close by another name. The
    alternative is a row that never ages out."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": detail(found=False)})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    row = served("30045")
    assert row["state"] == "CLOSED"
    assert row["closed_at"] is not None


def test_a_FAILED_absence_check_keeps_the_row_ACTIVE_and_retries():
    """**Corrected in review before 2.21.0 shipped.** The first cut retained on
    a failed check, on the reasoning that a check which could not be made is not
    evidence the incident is still open. True — and it is not evidence of a
    close either, and the two mistakes cost differently: retaining turns one
    timeout into a CLOSED row served for the whole 24-hour C15 window, on an
    incident somebody may be paged for. Keeping it active costs one extra
    detail call on the next poll.
    """
    now = time.time()
    seed(cached("30045", state="OPEN", confirmed_at=now - 300))

    bhnm = FakeBHNM(listing())

    async def boom(url, data=None, **kw):
        form = dict(data or {})
        bhnm.calls.append(form)
        if form.get("method") == "getincidentdetail":
            raise RuntimeError("BHNM detail exploded")
        resp = MagicMock(status_code=200)
        resp.json.return_value = bhnm.listing
        return resp

    bhnm.post = boom
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)

    row = served("30045")
    assert row is not None, "a failed check must not delete the row"
    assert row["state"] == "OPEN", "it keeps its last known state"
    assert row["closed_at"] is None, "and is NOT retained as closed"
    assert row["state_confirmed_at"] == now - 300, (
        "the stamp must NOT move — the check did not happen, so no confirmation "
        "is dated, which is what leaves C16 willing to re-check it next poll"
    )
    assert len(bhnm.detail_calls) == 1, "one attempt was made"


def test_the_row_AGES_OUT_as_soon_as_one_absence_check_SUCCEEDS():
    """**Nothing lives for ever on the strength of a failed check.** The retry
    is bounded by the next successful answer, in whichever direction it goes."""
    now = time.time()
    seed(cached("30045", state="OPEN", confirmed_at=now - 300))

    failing = FakeBHNM(listing())

    async def boom(url, data=None, **kw):
        form = dict(data or {})
        failing.calls.append(form)
        if form.get("method") == "getincidentdetail":
            raise RuntimeError("BHNM detail exploded")
        resp = MagicMock(status_code=200)
        resp.json.return_value = failing.listing
        return resp

    failing.post = boom
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(failing)
    assert served("30045")["state"] == "OPEN", "still active after the failure"

    # The next poll, with BHNM answering.
    working = FakeBHNM(listing(), {"30045": detail("CLOSED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(working)
    row = served("30045")
    assert row["state"] == "CLOSED", "one successful check resolves it"
    assert row["closed_at"] is not None
    assert len(working.detail_calls) == 1, "and it was re-checked, exactly once"


@pytest.mark.parametrize("answer,verdict", [
    (detail("CLOSED", alarm="OK"), "CLOSED -> retained"),
    (detail("OPEN"), "OPEN -> kept active"),
    (detail("ALARMS CLEARED", alarm="OK"), "ALARMS CLEARED -> kept active"),
    (detail(found=False), "not found -> retained"),
])
def test_every_absence_check_logs_ONE_line_with_the_id_and_the_verdict(capsys, answer, verdict):
    """[MEASURED 2026-09-23] 30051 and 30052 were retained after checks that left
    no line at all; the only evidence was `retained` stepping in the publish line,
    and the [State:] line said `source: list`. A check the log cannot show is a
    check nobody can prove ran."""
    now = time.time()
    seed(cached("30045", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(), {"30045": answer})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    lines = [l for l in capsys.readouterr().out.splitlines() if "Absence check" in l]
    assert lines == [f"[Cache:lab] Absence check incident 30045: BHNM says {verdict}"], lines


def test_the_check_is_one_call_per_ABSENT_row_not_per_row():
    """**The cost claim.** Five rows, one absent — one extra call, not five.
    Absence is rare; the bound has to be how often incidents leave the list,
    not how many there are."""
    now = time.time()
    seed(*[cached(str(i), confirmed_at=now - 300) for i in range(1, 6)])
    bhnm = FakeBHNM(listing(*[raw(str(i)) for i in range(1, 5)]),
                    {"5": detail("CLOSED", alarm="OK")})
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    ids = sorted(c.get("incident_id") for c in bhnm.detail_calls)
    assert ids == ["5"], f"only the absent row is checked, got {ids}"


def test_an_ALREADY_retained_row_is_not_re_checked_every_poll():
    """The other half of the cost claim, and the one a naive C17 gets wrong: a
    row already carrying CLOSED and a closed_at has been through this check, and
    re-asking every 30 s would be six calls a poll on the measured estate."""
    now = time.time()
    seed(cached("30045", state="CLOSED", confirmed_at=now - 300, closed_at=now - 200))
    bhnm = FakeBHNM(listing())
    with patch("incident_cache.time.time", side_effect=lambda: now):
        run_cycle(bhnm)
    assert bhnm.detail_calls == [], "already retained — nothing left to confirm"
    assert served("30045")["closed_at"] == now - 200, "and its close time does not move"


# ══ C18 — publish the list immediately ═══════════════════════════════════════

def test_state_is_SERVED_before_any_detail_call_is_made():
    """**The headline C18 test. Fails against 2.20.3**, which publishes nothing
    until every detail call in the cycle has returned.

    The detail stub blocks. The served state must have moved anyway.
    """
    now = time.time()
    seed(cached("30046", state="OPEN", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(raw("30046", "ALARMS CLEARED")),
                    {"30046": detail("ALARMS CLEARED", alarm="OK")})

    async def drive():
        bhnm.detail_gate = asyncio.Event()          # every detail call hangs
        c = MagicMock()
        c.post = bhnm.post
        fn = getattr(incident_cache, "_run_list_and_publish", None) \
            or incident_cache._run_one_cycle
        task = asyncio.create_task(fn(c, SERVER))
        for _ in range(50):                          # let the list land
            await asyncio.sleep(0.01)
            if (incident_cache._cache.get("lab")
                    and any(r.get("state") == "ALARMS CLEARED"
                            for r in incident_cache._cache["lab"].active_incidents)):
                break
        state = next((r.get("state") for r in incident_cache._cache["lab"].active_incidents
                      if str(r["incident_id"]) == "30046"), None)
        bhnm.detail_gate.set()
        try:
            await asyncio.wait_for(task, timeout=5)
        except Exception:
            task.cancel()
        return state

    with patch("incident_cache.time.time", side_effect=lambda: now):
        state = asyncio.run(drive())
    assert state == "ALARMS CLEARED", (
        "the list's state must be served the moment the list lands — 30046 cost "
        "101 s of holding the right answer and serving the old one"
    )


def test_counts_are_published_row_by_row_as_each_detail_lands():
    """After the first detail call returns, THAT row's counts_confirmed_at has
    moved and the others' have not. One write at the end cannot do this."""
    now = time.time()
    seed(cached("1", confirmed_at=now - 300, counts_at=now - 300),
         cached("2", confirmed_at=now - 300, counts_at=now - 300))
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[cached("1", confirmed_at=now - 300, counts_at=now - 300),
                          cached("2", confirmed_at=now - 300, counts_at=now - 300)],
        closed_incidents=[], last_updated=now)
    bhnm = FakeBHNM(listing(raw("1"), raw("2")),
                    {"1": detail("OPEN"), "2": detail("OPEN")})
    sweep = getattr(incident_cache, "_run_enrichment_sweep", None)
    assert sweep is not None, "C18 needs an enrichment sweep separate from the list"

    async def drive():
        c = MagicMock()
        c.post = bhnm.post
        task = asyncio.create_task(sweep(c, {**SERVER, "cache_refresh_seconds": 60}))
        for _ in range(200):
            await asyncio.sleep(0.01)
            rows = {str(r["incident_id"]): r for r in incident_cache._cache["lab"].active_incidents}
            if rows["1"].get("counts_confirmed_at") != now - 300:
                task.cancel()
                return dict(rows["1"]), dict(rows["2"])
        task.cancel()
        return None, None

    with patch("incident_cache.time.time", side_effect=lambda: now):
        one, two = asyncio.run(drive())
    assert one is not None, "the first row's counts never published on their own"
    assert two["counts_confirmed_at"] == now - 300, (
        "the second row must still be waiting — otherwise this is one write at the end"
    )


def test_the_30046_shape_costs_under_a_second_not_101_seconds():
    """The measurement as a regression test. The list lands carrying ALARMS
    CLEARED; the gap between that and the state being served is the 101 s that
    C18 removes."""
    now = time.time()
    seed(cached("30046", state="OPEN", confirmed_at=now - 300))
    bhnm = FakeBHNM(listing(raw("30046", "ALARMS CLEARED")),
                    {"30046": detail("ALARMS CLEARED", alarm="OK")})
    started = time.monotonic()
    with patch("incident_cache.time.time", side_effect=lambda: now):
        refresh(bhnm)
    elapsed = time.monotonic() - started
    assert served("30046")["state"] == "ALARMS CLEARED"
    assert elapsed < 1.0, f"the list publish took {elapsed:.2f}s"


def test_a_failed_detail_call_does_not_unpublish_the_state():
    """C11 — a failed enrichment is never cached. With C18 that gains a second
    meaning: it must not roll back a state the LIST already confirmed."""
    now = time.time()
    incident_cache._cache["lab"] = CachedIncidents(
        active_incidents=[cached("30046", state="ALARMS CLEARED", confirmed_at=now)],
        closed_incidents=[], last_updated=now)
    bhnm = FakeBHNM(listing(raw("30046", "ALARMS CLEARED")))

    async def boom(*a, **kw):
        bhnm.calls.append({"method": "getincidentdetail"})
        raise RuntimeError("BHNM detail exploded")

    sweep = getattr(incident_cache, "_run_enrichment_sweep", None)
    assert sweep is not None
    c = MagicMock()
    c.post = boom
    with patch("incident_cache.time.time", side_effect=lambda: now):
        asyncio.run(sweep(c, SERVER))
    row = served("30046")
    assert row["state"] == "ALARMS CLEARED", "the confirmed state survives a failed detail"
    assert row["counts_confirmed_at"] is not None or row["alarm_counts"] is not None
