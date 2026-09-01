# Two-Hop Connection Diagnostics — Design Spec

**Date:** 2026-09-01
**Status:** Approved (revised 2026-09-01: background-monitor design — a shared
middleware-side BHNM probe loop replaces the on-demand in-endpoint probe; see
guardrail 2 for why)
**Scope:** iOS (lead) + a small middleware background monitor and
`/api/v1/diagnostics` endpoint
**Criticality:** Non-critical / off the delivery path (reviewer-approved). Must
be **totally isolated** from proxy/cache/push.

## 1. Overview

The single connection badge answers "is my app getting BHNM data?" but can't say
*where* a break is. This feature adds:

1. A **more prominent disconnected state** — a red banner + pulsing top edge, not
   just a faint blinking icon.
2. A **diagnostics screen** (tap the badge) showing the full path
   **📱 App → 🖥 Middleware → 🗄 BHNM** with **per-hop latency**, per-feed
   freshness, a recent-call log, the middleware `/health` readout, and per-server
   error stats.

The app **always** talks to BHNM through the middleware (never directly); the
diagnostics screen visualises exactly that path, one hop at a time.

## 2. Guardrails (baked in — non-negotiable)

1. **No hanging probe.** Any active BHNM probe has its own short timeout (4 s)
   and a catch-all `try/except` → reports `"down"`. The endpoint detects
   down-ness *without hanging on it*.
2. **One shared middleware-side monitor — no per-client probe loops.**
   *(Revised 2026-09-01; supersedes the original "active probe only on-demand,
   never on a loop".)* The original rule was written to stop per-**client** load
   on BHNM, but it cannot meet the ~30 s detection target: the cache loops are
   clamped to a 60 s minimum interval, and a cache-off server emits no telemetry
   at all. The on-demand in-endpoint probe also proved structurally broken:
   Traefik waits ~3 s for a dead backend before returning 502, so the probe
   blocks the diagnostics response; a client cancel (e.g. pull-to-refresh
   superseding the request) then loses the result and misreports App→Middleware
   as down. The revised rule: **no per-client probe loops; ONE shared, bounded
   middleware-side probe loop per server** (~15 s, configurable) is the correct
   design. Clients poll the fast diagnostics endpoint (~30 s, configurable,
   foreground-only) and never probe BHNM themselves. Passive cache telemetry
   remains in the payload for the sheet's **detail** (feed freshness, latency,
   error stats) — it is never the reachability source.
3. **Auth = api_key as `X-Proxy-Token`.** `/api/v1/diagnostics` authenticates via
   `_verify_proxy_token` exactly like the other `/api/v1/*` routes. This depends
   on the **proxy-token fix** (iOS sending `api_key` as `X-Proxy-Token` instead
   of the webhook secret). **Sequence this feature with/after that fix** so the
   screen doesn't 401. See §8.
4. **No secrets, total isolation.** Payload carries counts/booleans/timestamps/
   latency and *truncated* error strings only — never tokens, api_keys, or full
   URLs (host only). The route has its **own** `httpx.AsyncClient` + timeout and
   its **own** `try/except`; it only *reads* cache telemetry and cannot write or
   affect proxy/cache/push state.
5. **Badge is role-free.** Green on *any* valid response — the `role`-field
   requirement that caused the false red is gone (already removed with the
   `ConnectionMonitor` change; §7.1). Reduce-motion is honored on the pulse.

## 3. Architecture & isolation

```
ConnectionMonitor (iOS, ONE global poller — foreground only)
  ├─ every ~30 s (configurable): GET /api/v1/diagnostics (~10 s timeout)
  │     poll fails (no HTTP response)          → middleware DOWN
  │     poll ok, bhnm.reachable == false      → BHNM DOWN (middleware up)
  │     poll ok, bhnm.reachable == true       → connected
  ├─ drives the badge + hop-aware banner; DiagnosticsView (sheet) reads the
  │  poller's cached lastResult; pull-to-refresh = pollNow()
  └─ GET /api/v1/diagnostics  (X-Proxy-Token: api_key, X-BHNM-Target: bhnm url)
        → middleware, ISOLATED route — READS ONLY, never awaits a probe:
            • bhnm hop  = the background monitor's cached probe result
            • feeds     = PASSIVE telemetry from the three caches (detail only)
            • assembles JSON (no secrets) and returns — uniformly fast

Background BHNM monitor (middleware, ONE probe loop per server — shared by all
clients): asyncio.Task per servers.json entry calling active_probe() every
~15 s (configurable), result stored in {server_id: probe_result}.
```

Isolation contract: the monitor and route import the cache modules read-only,
the probe uses its own short-lived `httpx.AsyncClient(verify=…, timeout=4.0)`,
and everything is wrapped in `try/except` so a failure records `down` and
returns a partial payload with HTTP 200 — it never raises into, blocks, or
stalls the caches, proxy, or push paths.

## 4. Middleware: passive telemetry additions

The cache loops currently store only `last_updated`. Add a small per-server
telemetry record (one shared dataclass, updated by each cache loop):

```python
@dataclass
class FeedTelemetry:
    last_success_ts: float = 0.0
    last_error: str | None = None          # truncated to 200 chars, secret-scrubbed
    last_error_ts: float = 0.0
    consecutive_failures: int = 0
    last_latency_ms: int | None = None      # upstream httpx call duration
```

Wire it in each loop (`incident_cache`, `tactical_cache`, `threshold_cache`):
time the upstream call; on success set `last_success_ts`, `last_latency_ms`,
reset `consecutive_failures=0`, clear `last_error`; on exception set
`last_error`/`last_error_ts` and increment `consecutive_failures`. This is the
existing `except … "Cycle failed"` block — it just records instead of only
printing. **Additive and read-only elsewhere** — no behavior change to caching.

`last_latency_ms` from the caches is **detail only** (per-feed rows in the
sheet); the Middleware→BHNM hop latency and reachability come from the
background monitor's probe (§5.1).

## 5. Middleware: background BHNM monitor + `/api/v1/diagnostics` endpoint

### 5.1 Background BHNM monitor (authoritative reachability source)

One `asyncio.Task` per `servers.json` entry (ALL servers, regardless of
`cache_enabled` — health is independent of caching), calling the existing
`active_probe()` every ~15 s (`DIAG_PROBE_INTERVAL` env var, default 15) and
storing the result in a `{server_id: probe_result}` dict. Guardrails it
inherits:

- Each probe is bounded (the 4 s timeout); failures are **recorded, not
  raised** — the task can never crash, stall, or block the middleware or the
  caches.
- Hooks into the existing server reload: `/internal/cache/reload` starts/stops
  a probe task per server exactly like the caches. Server added/removed →
  task started/stopped.
- `active_probe()` keeps treating **an HTTP response with `status_code < 500`
  as "up"** (a Traefik 5xx = BHNM down, not a valid answer). Do not
  reintroduce field/body parsing — the `role`-field requirement caused the
  original false red.
- **Flap resistance:** down is declared only after `DIAG_DOWN_THRESHOLD` (env
  var, default 2) consecutive probe failures, so a lone transient blip never
  flashes the banner. Cost: BHNM-down detection becomes ~2 probe intervals +
  one client poll (~60 s worst, ~40 s typical) — accepted in review over
  single-failure speed. A never-succeeded server gets no grace towards "up":
  below the threshold it stays `reachable:null` (there is no good state to
  hold), then reports down at the threshold.
- Isolated: separate module, own httpx client + timeout, own try/except; no
  secrets in the stored result.

### 5.2 `/api/v1/diagnostics` endpoint

`GET /api/v1/diagnostics` — auth `_verify_proxy_token`; server resolved from
`X-Proxy-Token` (api_key) / `X-BHNM-Target` like the other cached routes.
The route only **reads** the monitor's dict and the passive telemetry — it
never awaits a live probe, so it is uniformly fast. Payload stays lean
(counts/booleans/timestamps; no server-side call logs) so it is cheap to poll.

**Payload (example; no secrets):**

```json
{
  "middleware": {
    "version": "2.6.1",
    "registered_devices": 5,
    "server_time": 1725100000
  },
  "server": {
    "name": "Thomas' Lab Server",
    "host": "bhnm-b.tstolt.com",
    "cache_enabled": true,
    "bhnm": {
      "reachable": true,
      "source": "monitor",
      "latency_ms": 82,
      "last_success_age_seconds": 12,
      "last_error": null,
      "last_error_age_seconds": null,
      "consecutive_failures": 0
    },
    "feeds": {
      "incidents":  {"cached": true, "age_seconds": 15, "count": 10, "consecutive_failures": 0, "last_error": null},
      "tactical":   {"cached": true, "age_seconds": 20, "count": 4,  "consecutive_failures": 0, "last_error": null},
      "thresholds": {"cached": true, "age_seconds": 30, "count": 38, "consecutive_failures": 0, "last_error": null}
    }
  }
}
```

**`bhnm` resolution:** always the background monitor's cached probe result
(`source:"monitor"`), for every server, cache on or off — the monitor is the
single authoritative reachability source. `latency_ms` = the probe's measured
round-trip; `last_success_age_seconds` = seconds since the last successful
probe (≤ the probe interval when healthy — the sheet shows this age so the
number is never misread as live). The block reports `reachable:null` /
`source:"none"` while the monitor has no verdict — no result yet (startup
window), or a never-succeeded server still below `DIAG_DOWN_THRESHOLD`
failures — and the client stays in `checking`. Passive `FeedTelemetry`
appears only in the `feeds` blocks as detail — never as the reachability
source.

**Secret scrubbing:** `last_error` is truncated (≤200 chars) and passed through a
scrubber that drops anything resembling a key/password; `host` is the URL host
only. No `api_key`, `pwd`, `password`, or token ever appears.

## 6. iOS: UI

### 6.1 Disconnected banner + pulsing edge — HOP-AWARE
The banner **names the hop that is actually down**, matching the pipeline. It must
**never** claim "showing cached data" when the **middleware** is the unreachable
hop — the cache lives *in* the middleware, so if we can't reach it there is
nothing to serve. Driven by `ConnectionMonitor`'s down-hop distinction (§7.1):

- **Middleware unreachable** — the app got **no HTTP response at all**
  (transport error), **or a non-2xx status** (a reverse proxy answering
  502/503 for a dead middleware app container is not the middleware):
  **"⚠️ Can't reach the server · showing last known data · retrying…"** —
  "last known data" = the app's own last-fetched data still on screen, **not**
  a middleware-cache claim (the cache lives in the unreachable middleware).
- **BHNM unreachable, middleware up** — the app reached the middleware, which
  reports BHNM down (`bhnm.reachable == false`): **"⚠️ BHNM
  unreachable · showing cached data · retrying…"** — cached Tactical/Incidents
  are genuinely being served here, so the reassurance is correct.

Both render a red banner **under the header** + a **pulsing red top edge**
(2–3 px).
- Hard blink/pulse is reserved for these truly-disconnected states; the brief
  `.checking` state is amber and **static** (no banner).
- **Reduce-motion:** no pulse/blink — **static** red banner + solid red edge; the
  meaning is in the text, not the motion.

Why this matters: a generic "No connection to BHNM · showing cached data" is wrong
on both counts when it's the middleware that's down — it misnames the failing hop
*and* promises a cache that isn't reachable.

### 6.2 DiagnosticsView (tap the badge)
- **Hero pipeline:** `📱 App ──▶ 🖥 Middleware ──▶ 🗄 BHNM`. Each segment shows
  its latency; a **down** hop renders a **broken red link**. Hops:
  - **App → Middleware:** from the poller's last result — up if that poll
    returned; latency = client-measured round-trip of that poll, shown with
    its age (≤ 30 s when healthy; pull-to-refresh makes it "now").
  - **Middleware → BHNM:** from `server.bhnm.reachable` / `latency_ms` (the
    background monitor's probe). **Show the latency's age** (from
    `bhnm.last_success_age_seconds`, e.g. **"82 ms · 9 s ago"**) so the number
    is read as the monitor's last probe, not a live measurement. A stale age is
    itself a signal (monitor wedged or BHNM failing).
  - The **App** node is always up (we're running).
- **Per-feed status** (Tactical / Incidents / Devices→thresholds): last-success
  age, count, and **live vs cached** (from `feeds[*].cached` + `age_seconds`).
- **Recent-call log:** the app's last ~20 API calls — `endpoint · status · ms`
  (client-side ring buffer, §6.3).
- **Middleware /health readout:** version, registered devices, which caches are
  warm (from the payload's `middleware` block + feeds).
- **Per-server error stats:** `consecutive_failures`, last error + age (from
  `bhnm` / `feeds`).
- **Refresh model:** the sheet does **not** fetch for itself — it reads
  `ConnectionMonitor.lastResult` (same truth as the badge, guardrail 2);
  pull-to-refresh calls `pollNow()`. A small App→Middleware **latency
  sparkline** (last ~20 measured round-trips) is Tier-1 and client-side.

### 6.3 iOS plumbing
- `NetreoAPIService.fetchDiagnostics() async -> DiagnosticsResult` — GET
  `/api/v1/diagnostics` with a **~10 s timeout** (NOT URLSession's 60 s
  default, or middleware-down detection balloons), times the round-trip
  (App→Middleware latency), best-effort (transport failure → the poller marks
  the middleware hop down).
- `ConnectionMonitor` (see §7.1) is the **one global poller** — configured
  from `ContentView` on startup and on every server switch
  (`configure(apiService)`); no per-screen polling.
- `ClientCallLog` — a tiny `@MainActor` ring buffer (last ~20) that
  `NetreoAPIService` appends to on each request (`endpoint` with query string
  stripped, `statusCode`, `latencyMs`, `ok`). Read-only for the view. No
  persistence.
- `DiagnosticsView` presented as a **sheet** from the badge tap on every
  screen (tap-to-refresh on the badge is retired; pull-to-refresh + the ring
  remain).

## 7. Badge reconciliation & motion

### 7.1 ConnectionMonitor v2: one global poller (revised)
*(Revised 2026-09-01 — supersedes v1, where the badge derived from data-load
outcomes. v1 failed with caching ON: cached responses masked a BHNM outage for
~5 min, and only the live Devices call could detect it. The badge is now
poller-driven; data calls no longer report to the monitor.)*

`ConnectionMonitor` is a singleton that polls `/api/v1/diagnostics` every
~30 s (configurable, not a compile-time constant) with a ~10 s request
timeout, **foreground-only**: the poll loop pauses when the app is
backgrounded/inactive and resumes (with an immediate `pollNow()`) on
foreground — otherwise every idle phone polls the middleware every 30 s
forever. Derivation per poll:

- poll gets **no HTTP response** (transport error / timeout) **or a non-2xx
  status** (Caddy answering for a dead app container) → `.disconnected`,
  `downHop = .middleware`
- poll ok, payload `bhnm.reachable == false` → `.disconnected`,
  `downHop = .bhnm`
- poll ok, `bhnm.reachable == true` → `.connected`
- unconfigured → `.unknown`; configured but no result yet → `.checking`
  (amber, static)

Badge colour still keys only on connected-vs-not; `downHop` only selects the
banner copy (§6.1). The badge stays role-free — reachability comes from the
middleware monitor's `status_code < 500` rule, never from parsing BHNM fields.
`pollNow()` serves the sheet's pull-to-refresh and the foreground transition.
Detection math: middleware-down ≤ 30 s poll + 10 s timeout; BHNM-down ≤
~2 × 15 s probes (`DIAG_DOWN_THRESHOLD` flap resistance, §5.1) + ≤ 30 s poll
(~60 s worst, ~40 s typical).

### 7.2 Motion
Pulse/blink only on `.disconnected`; amber `.checking` is static. All motion
gated behind `!UIAccessibility.isReduceMotionEnabled` (SwiftUI:
`@Environment(\.accessibilityReduceMotion)`), with a static red fallback.

## 8. Auth sequencing (dependency)

`/api/v1/diagnostics` uses `_verify_proxy_token`, which accepts the api_key as
`X-Proxy-Token`. The prerequisite proxy-token fix (iOS sends `api_key` as
`X-Proxy-Token`, matching the PWA) **landed as `b2ad942`** — diagnostics
authenticates on the api_key path independent of `PROXY_TOKEN`. Dependency
satisfied.

## 9. Testing (TDD when built)

- **Middleware:** telemetry records success/latency and error/consecutive-fail
  on simulated cache cycles; the monitor task records a probe **failure without
  raising**; a probe **timeout** yields `reachable:false` within the 4 s bound;
  **any HTTP response → up** (incl. 4xx), 5xx → down; `/internal/cache/reload`
  **starts/stops** monitor tasks per server; `/api/v1/diagnostics` returns
  **fast from the monitor's dict** (never awaits a probe); payload contains
  **no** secret keys (assert scrubber); missing api_key → 401.
- **iOS:** pipeline renders per-hop up/down from a fixture payload (incl. broken
  Middleware→BHNM link); reduce-motion path shows static banner; `ClientCallLog`
  caps at 20; diagnostics fetch failure → App→Middleware shown down, no crash.
- **Isolation:** a forced exception in the diagnostics route does not touch
  cache/proxy state (unit-level).

## 10. Out of scope / fast-follows

- Historical/persisted latency or uptime %; only in-memory rolling history.
- Push-delivery diagnostics (APNs/WebPush health).
- PWA diagnostics screen (parity fast-follow; the PWA badge already reflects
  real connectivity via the shared `AppHeader`).
- Any *write* or remediation action from the screen (read-only).

## 11. Mockups

Published as an Artifact (see review thread): DiagnosticsView in both states
(all-green two-hop pipeline; BHNM-down with the broken red link), plus the
disconnected banner + pulsing edge on a normal screen. iOS-first.
