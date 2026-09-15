"""Concurrent webhooks must reach every device.

This is the regression test for the defect measured on 2026-09-15 (evidence §3.9):
2.13.4 made sends sequential *inside* one fan-out, but two webhooks arriving in the
same second each started their own fan-out and raced on the shared HTTP/2 client.
Both stalled after ~3 sends and were abandoned; the two newest devices got nothing.

It was found by an accidental duplicate request, which means the same defect could
just as easily have shipped looking fixed. So the concurrent case is exercised
deliberately here, against a stub APNs transport rather than a mocked send_to_all —
the bug lived below send_to_all, in the shared client.
"""
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_delivery_queue.db")

import asyncio
from unittest.mock import patch

import httpx
import pytest

import apns as apns_mod
import main as main_mod


def _stub_apns(recorder, delay=0.01):
    """An APNs that records every device token and, crucially, watches for
    overlapping requests.

    Apple documents that APNs caps HTTP/2 stream concurrency per connection and
    that with token authentication it "allows only one stream until you post a
    request with a valid authentication token". Overlapping sends are what wedged
    the real connection, so `state["max_in_flight"]` is the property under test —
    asserting only "every device was served" would pass against the broken code,
    because a mock transport never actually stalls.
    """
    state = {"in_flight": 0, "max_in_flight": 0}

    async def handler(request: httpx.Request) -> httpx.Response:
        state["in_flight"] += 1
        state["max_in_flight"] = max(state["max_in_flight"], state["in_flight"])
        try:
            await asyncio.sleep(delay)
            recorder.append(request.url.path.rsplit("/", 1)[-1])
            return httpx.Response(200)
        finally:
            state["in_flight"] -= 1

    return httpx.AsyncClient(transport=httpx.MockTransport(handler)), state


async def _drive(jobs, tokens, recorder):
    main_mod._delivery_queue = asyncio.Queue(maxsize=main_mod.DELIVERY_QUEUE_MAX)
    worker = asyncio.create_task(main_mod._delivery_worker_loop())
    try:
        for i in range(jobs):
            assert main_mod._enqueue_delivery(tokens, [], "t", "b", str(i))
        await main_mod._delivery_queue.join()
    finally:
        worker.cancel()


def test_several_webhooks_in_the_same_second_reach_every_device():
    recorder = []
    tokens = [(f"tok{i:02d}" * 8, "production") for i in range(5)]
    jobs = 4

    seen_state = {}

    async def run():
        client, state = _stub_apns(recorder)
        seen_state.update(state)
        with patch.object(apns_mod, "_get_client", lambda: client), \
             patch.object(apns_mod, "_get_jwt", lambda: "stub-jwt"):
            await _drive(jobs, tokens, recorder)
        seen_state.update(state)
        await client.aclose()

    asyncio.run(run())

    expected = [t for _ in range(jobs) for t, _env in tokens]
    assert recorder == expected, (
        f"expected {len(expected)} sends ({jobs} webhooks x {len(tokens)} devices), "
        f"got {len(recorder)}"
    )
    assert seen_state["max_in_flight"] == 1, (
        "two APNs requests were in flight at once — this is the shape that wedged "
        "the real HTTP/2 connection")


def test_every_device_is_served_even_when_jobs_overlap_the_worker():
    """Enqueue while the worker is mid-job — the case the accidental duplicate hit."""
    recorder = []
    tokens = [(f"dev{i:02d}" * 8, "production") for i in range(3)]

    seen_state = {}

    async def run():
        client, state = _stub_apns(recorder, delay=0.02)
        seen_state.update(state)
        with patch.object(apns_mod, "_get_client", lambda: client), \
             patch.object(apns_mod, "_get_jwt", lambda: "stub-jwt"):
            main_mod._delivery_queue = asyncio.Queue(maxsize=main_mod.DELIVERY_QUEUE_MAX)
            worker = asyncio.create_task(main_mod._delivery_worker_loop())
            try:
                main_mod._enqueue_delivery(tokens, [], "t", "b", "first")
                await asyncio.sleep(0.03)          # worker is now mid fan-out
                main_mod._enqueue_delivery(tokens, [], "t", "b", "second")
                await main_mod._delivery_queue.join()
            finally:
                worker.cancel()
        seen_state.update(state)
        await client.aclose()

    asyncio.run(run())

    assert len(recorder) == 6, f"both fan-outs must complete in full, got {recorder}"
    assert seen_state["max_in_flight"] == 1, "fan-outs overlapped on the shared client"
    assert recorder[:3] == [t for t, _ in tokens], "ordering within a fan-out"
    assert recorder[3:] == [t for t, _ in tokens], "second fan-out served too"


def test_a_full_queue_drops_loudly_and_never_silently(capsys):
    """A dropped page is survivable. A dropped page nobody hears about is not."""
    async def run():
        main_mod._delivery_queue = asyncio.Queue(maxsize=2)   # no worker draining
        accepted = [main_mod._enqueue_delivery([("t", "production")], [], "t", "b", str(i))
                    for i in range(4)]
        return accepted

    accepted = asyncio.run(run())

    assert accepted == [True, True, False, False]
    out = capsys.readouterr().out
    assert out.count("[Deliver] QUEUE FULL") == 2
    assert "Nobody was paged for it" in out


def test_enqueue_before_the_worker_exists_is_not_silent(capsys):
    main_mod._delivery_queue = None
    assert main_mod._enqueue_delivery([("t", "production")], [], "t", "b", "7") is False
    assert "[Deliver] DROPPED" in capsys.readouterr().out


def test_a_growing_backlog_is_reported(capsys):
    async def run():
        main_mod._delivery_queue = asyncio.Queue(maxsize=main_mod.DELIVERY_QUEUE_MAX)
        for i in range(main_mod.DELIVERY_QUEUE_WARN + 1):
            main_mod._enqueue_delivery([("t", "production")], [], "t", "b", str(i))

    asyncio.run(run())
    assert "[Deliver] BACKLOG" in capsys.readouterr().out


def test_the_detector_would_have_caught_the_old_code():
    """Teeth check. Before the worker, `/webhook` spawned an independent
    BackgroundTask per request, so two webhooks ran two fan-outs concurrently on
    the shared client. Reproduce exactly that and assert the stub notices — without
    this, the tests above would pass against the broken code, because a mock
    transport never stalls the way the real HTTP/2 connection did."""
    recorder = []
    tokens = [(f"old{i:02d}" * 8, "production") for i in range(3)]
    seen_state = {}

    async def run():
        client, state = _stub_apns(recorder, delay=0.02)
        seen_state.update(state)
        with patch.object(apns_mod, "_get_client", lambda: client), \
             patch.object(apns_mod, "_get_jwt", lambda: "stub-jwt"):
            # the pre-2.14 shape: two fan-outs, nothing serialising them
            await asyncio.gather(
                main_mod._fan_out(tokens, [], "t", "b", "a"),
                main_mod._fan_out(tokens, [], "t", "b", "b"),
            )
        seen_state.update(state)
        await client.aclose()

    asyncio.run(run())

    assert seen_state["max_in_flight"] > 1, (
        "the overlap detector did not fire on the old concurrent shape — it would "
        "not have caught the bug it exists for")
