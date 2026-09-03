"""Connection diagnostics — passive telemetry + a background BHNM monitor.

Fully isolated: this module records telemetry that the cache loops feed it, and
runs ONE background probe task per server (shared by all clients) whose cached
result is the authoritative BHNM reachability. It imports NO cache modules (the
caches import *it*, one-way, so there is no cycle) and it never raises into any
other path. The `/api/v1/diagnostics` route assembles the payload from
`bhnm_monitor()` + `get_telemetry()` plus cache freshness — it never awaits a
live probe; secrets never enter the payload (see `scrub`).
"""
from __future__ import annotations

import asyncio
import re
import time
from dataclasses import dataclass

import httpx

from config import DIAG_DOWN_THRESHOLD, DIAG_PROBE_INTERVAL

PROBE_TIMEOUT = 4.0  # seconds — bounded; the probe fails fast, never hangs
FEEDS = ("incidents", "tactical", "thresholds", "maintenance_map")


@dataclass
class FeedTelemetry:
    last_success_ts: float = 0.0
    last_error: str | None = None
    last_error_ts: float = 0.0
    consecutive_failures: int = 0
    last_latency_ms: int | None = None


# registry: {(server_id, feed): FeedTelemetry}
_telemetry: dict[tuple[str, str], FeedTelemetry] = {}


def get_telemetry(server_id: str, feed: str) -> FeedTelemetry:
    key = (server_id, feed)
    t = _telemetry.get(key)
    if t is None:
        t = FeedTelemetry()
        _telemetry[key] = t
    return t


def reset() -> None:  # test helper
    _telemetry.clear()
    for task in _monitor_tasks.values():
        try:
            task.cancel()
        except RuntimeError:
            pass  # task's loop already closed
    _monitor_tasks.clear()


# --- secret scrubbing --------------------------------------------------------
# Drop anything that looks like a credential from an error string before it can
# reach a client. key=value / key: value for common secret-ish keys.
_SECRET_RE = re.compile(r"(?i)\b(password|pwd|api[_-]?key|token|secret)\b\s*[=:]\s*\S+")


def scrub(text: str | None, limit: int = 200) -> str | None:
    if not text:
        return None
    s = _SECRET_RE.sub(r"\1=***", str(text))
    return s[:limit]


# --- recording (called by the cache loops) -----------------------------------
def record_success(server_id: str, feed: str, latency_ms: int | None) -> None:
    t = get_telemetry(server_id, feed)
    t.last_success_ts = time.time()
    t.last_latency_ms = latency_ms
    t.consecutive_failures = 0
    t.last_error = None
    t.last_error_ts = 0.0


def record_failure(server_id: str, feed: str, error: object) -> None:
    t = get_telemetry(server_id, feed)
    t.last_error = scrub(str(error))
    t.last_error_ts = time.time()
    t.consecutive_failures += 1


def _age(ts: float) -> int | None:
    return round(time.time() - ts) if ts else None


# --- payload assembly (read-only) --------------------------------------------
def feed_block(server_id: str, feed: str, *, cached: bool,
               age_seconds: int | None, count: int | None) -> dict:
    t = get_telemetry(server_id, feed)
    return {
        "cached": cached,
        "age_seconds": age_seconds,
        "count": count,
        "consecutive_failures": t.consecutive_failures,
        "last_error": t.last_error,
    }


def bhnm_monitor(server_id: str) -> dict:
    """BHNM-hop status from the background monitor's telemetry — no network call.

    The single authoritative reachability source for every server, cache on or
    off. No result yet (startup window ≤ one probe interval) → reachable:null /
    source:"none" so the client stays in `checking`.

    Flap resistance: down is declared only after DIAG_DOWN_THRESHOLD (default 2)
    consecutive probe failures, so a lone transient blip never flashes the
    banner. A never-succeeded server gets no grace towards "up" — below the
    threshold it stays null (there is no good state to hold).
    """
    t = _telemetry.get((server_id, "probe"))
    no_verdict = {
        "reachable": None, "source": "none", "latency_ms": None,
        "last_success_age_seconds": None, "last_error": None,
        "last_error_age_seconds": None, "consecutive_failures": 0,
    }
    if t is None or (t.last_success_ts == 0 and t.last_error_ts == 0):
        return no_verdict
    if t.last_success_ts == 0 and t.consecutive_failures < DIAG_DOWN_THRESHOLD:
        return no_verdict
    up = t.consecutive_failures < DIAG_DOWN_THRESHOLD
    return {
        "reachable": up,
        "source": "monitor",
        "latency_ms": t.last_latency_ms if up else None,
        "last_success_age_seconds": _age(t.last_success_ts),
        "last_error": t.last_error,
        "last_error_age_seconds": _age(t.last_error_ts),
        "consecutive_failures": t.consecutive_failures,
    }


async def active_probe(target_base: str, api_key: str, pin: str | None,
                       verify: bool) -> dict:
    """One bounded ha_status call. Any HTTP response => reachable (we only care
    that BHNM answered — no role/body check). Timeout/connect error => down.
    Own httpx client + timeout + try/except; never raises."""
    url = f"{target_base.rstrip('/')}/api/ha_status_api.php"
    data = {"password": api_key}
    if pin:
        data["pin"] = pin
    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(verify=verify, timeout=PROBE_TIMEOUT) as client:
            resp = await client.post(url, data=data)
        latency = round((time.perf_counter() - started) * 1000)
        # BHNM sits behind Traefik: a 5xx is a gateway error meaning the BHNM app
        # is down, NOT a valid health response. <500 = BHNM answered (up); a 4xx
        # (e.g. auth/HTTPS complaint) still proves the app is alive.
        up = resp.status_code < 500
        return {
            "reachable": up, "source": "probe",
            "latency_ms": latency if up else None,
            "last_success_age_seconds": 0 if up else None,
            "last_error": None if up else f"HTTP {resp.status_code}",
            "last_error_age_seconds": None if up else 0,
            "consecutive_failures": 0 if up else 1,
        }
    except Exception as e:  # timeout / connect error / DNS / TLS — box unreachable
        return {
            "reachable": False, "source": "probe", "latency_ms": None,
            "last_success_age_seconds": None, "last_error": scrub(str(e)) or "probe failed",
            "last_error_age_seconds": 0, "consecutive_failures": 1,
        }


# --- background BHNM monitor --------------------------------------------------
# ONE probe loop per server, shared by all clients (never per-client). The loop
# records into the "probe" telemetry slot; bhnm_monitor() reads it. Same
# lifecycle shape as the caches: start on lifespan, reload via /internal/cache/
# reload — but for ALL servers (health is independent of cache_enabled).

_monitor_tasks: dict[str, asyncio.Task] = {}


async def _monitor_loop(server: dict, verify: bool) -> None:
    server_id = server["id"]
    print(f"[Monitor:{server_id}] BHNM probe loop started (every {DIAG_PROBE_INTERVAL}s)")
    while True:
        try:
            out = await active_probe(server.get("url", ""), server.get("api_key", ""),
                                     server.get("pin") or None, verify)
            if out["reachable"]:
                record_success(server_id, "probe", out["latency_ms"])
            else:
                record_failure(server_id, "probe", out["last_error"] or "probe failed")
        except asyncio.CancelledError:
            raise
        except Exception as e:  # belt-and-braces: the task must never die
            record_failure(server_id, "probe", e)
        await asyncio.sleep(DIAG_PROBE_INTERVAL)


def start_monitor(server: dict, verify: bool) -> None:
    server_id = server.get("id", "")
    if not server_id:
        return
    if server_id in _monitor_tasks and not _monitor_tasks[server_id].done():
        return
    _monitor_tasks[server_id] = asyncio.create_task(_monitor_loop(server, verify))


def stop_monitor(server_id: str) -> None:
    task = _monitor_tasks.pop(server_id, None)
    if task and not task.done():
        task.cancel()
    _telemetry.pop((server_id, "probe"), None)


def reload_monitor(server_id: str, servers: list[dict], verify: bool) -> None:
    """Restart (or stop, if removed) the probe task for one server."""
    stop_monitor(server_id)
    server = next((s for s in servers if s.get("id") == server_id), None)
    if server:
        start_monitor(server, verify)
        print(f"[Monitor:{server_id}] Reloaded")
    else:
        print(f"[Monitor:{server_id}] Server removed — probe loop stopped")
