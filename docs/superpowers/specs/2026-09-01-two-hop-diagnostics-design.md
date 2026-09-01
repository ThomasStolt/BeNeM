# Two-Hop Connection Diagnostics — Design Spec

**Date:** 2026-09-01
**Status:** Proposed — awaiting review (do not build until approved)
**Scope:** iOS (lead) + a small middleware `/api/v1/diagnostics` endpoint
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
2. **Passive first.** Prefer telemetry the caches already gather while running
   (last-success time, last error + timestamp, consecutive-failure count, last
   measured upstream latency, cache-refresh age). An **active** probe (the cheap
   `ha_status` call) runs **only** when caching is off for that server, and
   **only on demand** (screen open + pull-to-refresh) — **never** on the 120 s
   dashboard loop. The 120 s loop is client-side and does not call diagnostics.
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
DiagnosticsView (iOS)
  ├─ measures App→Middleware latency itself (round-trip to /api/v1/diagnostics)
  └─ GET /api/v1/diagnostics  (X-Proxy-Token: api_key, X-BHNM-Target: bhnm url)
        → middleware, ISOLATED route:
            • reads PASSIVE telemetry from incident/tactical/threshold caches
            • if that server has caching OFF → ONE active ha_status probe
              (own httpx client, 4s timeout, try/except → up/down + latency)
            • assembles JSON (no secrets) and returns
```

Isolation contract: the route imports the cache modules read-only, opens its own
short-lived `httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=4.0)` for the
optional probe, and wraps everything in `try/except` so a failure returns a
partial/`down` payload with HTTP 200 — it never raises into, or blocks, any other
path.

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

`last_latency_ms` from the caches **is** the Middleware→BHNM hop latency for
cache-enabled servers (measured continuously, for free, no probe).

## 5. Middleware: `/api/v1/diagnostics` endpoint

`GET /api/v1/diagnostics` — auth `_verify_proxy_token`; server resolved from
`X-Proxy-Token` (api_key) / `X-BHNM-Target` like the other cached routes.

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
      "source": "passive",
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

**`bhnm` resolution:**
- **cache_enabled = true** → `source:"passive"`; fields come from the
  `FeedTelemetry` (latency = most recent feed's `last_latency_ms`; `reachable` =
  `consecutive_failures == 0` on the freshest feed). No network call.
- **cache_enabled = false** → `source:"probe"`; fire **one** `ha_status` call
  (own client, 4 s timeout). `reachable = true` on **any** HTTP response
  (2xx/4xx/5xx alike — we only care that BHNM answered; drop role/body checks,
  guardrail 5); `latency_ms` = measured round-trip; on timeout/connect error →
  `reachable:false`, `latency_ms:null`, `last_error:"probe timeout"`.

**Secret scrubbing:** `last_error` is truncated (≤200 chars) and passed through a
scrubber that drops anything resembling a key/password; `host` is the URL host
only. No `api_key`, `pwd`, `password`, or token ever appears.

## 6. iOS: UI

### 6.1 Disconnected banner + pulsing edge — HOP-AWARE
The banner **names the hop that is actually down**, matching the pipeline. It must
**never** claim "showing cached data" when the **middleware** is the unreachable
hop — the cache lives *in* the middleware, so if we can't reach it there is
nothing to serve. Driven by `ConnectionMonitor`'s down-hop distinction (§7.1):

- **Middleware unreachable** — the app got **no HTTP response at all** (transport
  error): **"⚠️ Can't reach the server · retrying…"** — **no** "cached data"
  claim.
- **BHNM unreachable, middleware up** — the app reached the middleware, which
  reports BHNM down (proxy 5xx / `bhnm.reachable == false`): **"⚠️ BHNM
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
  - **App → Middleware:** up if the diagnostics call returned; latency =
    client-measured round-trip to `/api/v1/diagnostics` — always **live** (this
    open), so it carries no age label.
  - **Middleware → BHNM:** from `server.bhnm.reachable` / `latency_ms`. **Show the
    latency's age** so a *passive* (possibly minutes-old) number isn't misread as
    live: `source:"passive"` → e.g. **"82 ms · 2m ago"** (from
    `bhnm.last_success_age_seconds`); `source:"probe"` (just measured on demand)
    → **"82 ms · now"**. A stale age is itself a signal.
  - The **App** node is always up (we're running).
- **Per-feed status** (Tactical / Incidents / Devices→thresholds): last-success
  age, count, and **live vs cached** (from `feeds[*].cached` + `age_seconds`).
- **Recent-call log:** the app's last ~20 API calls — `endpoint · status · ms`
  (client-side ring buffer, §7.2).
- **Middleware /health readout:** version, registered devices, which caches are
  warm (from the payload's `middleware` block + feeds).
- **Per-server error stats:** `consecutive_failures`, last error + age (from
  `bhnm` / `feeds`).
- **Refresh triggers:** screen open + pull-to-refresh only (guardrail 2). A small
  App→Middleware **latency sparkline** (last ~20 measured round-trips) is Tier-1
  and client-side.

### 6.3 iOS plumbing
- `NetreoAPIService.fetchDiagnostics() async -> Diagnostics?` — GET
  `/api/v1/diagnostics`, times the round-trip (App→Middleware latency),
  best-effort (nil on failure → screen shows App→Middleware as down).
- `ClientCallLog` — a tiny `@MainActor` ring buffer (last ~20) that
  `NetreoAPIService` appends to on each request (`endpoint`, `statusCode`,
  `latencyMs`, `ok`). Read-only for the view. No persistence.
- `DiagnosticsView` presented from the badge tap on every screen (the badge's
  existing `onRetry`/tap becomes "open diagnostics"; a retry button lives inside).

## 7. Badge reconciliation & motion

### 7.1 The badge already dropped the role requirement
The connectivity badge no longer uses `checkHAStatus()`; it reads the shared
`ConnectionMonitor`, fed by real middleware data calls (incidents/tactical/
devices). "Green on any valid response" is satisfied — any successful
middleware call is green; a thrown network error is red. Guardrail 5's *badge*
half is already done by that change; this spec keeps it and adds the banner/edge.

**Extension for the hop-aware banner (built in step c, on the committed base):**
`ConnectionMonitor` gains a `downHop` distinction so the banner (§6.1) can name
the failure while the badge stays role-free:
- data call throws a **transport** error (no HTTP response) → `.middlewareDown`
- data call gets an HTTP response but signals BHNM failure (proxy 5xx, or a
  diagnostics payload with `bhnm.reachable == false`) → `.bhnmDown`
- otherwise `.connected` / `.unknown`

The reporting methods therefore pass *why* they failed (reached the middleware or
not), not just success/failure. Badge colour still keys only on connected-vs-not;
`downHop` only selects the banner copy.

### 7.2 Motion
Pulse/blink only on `.disconnected`; amber `.checking` is static. All motion
gated behind `!UIAccessibility.isReduceMotionEnabled` (SwiftUI:
`@Environment(\.accessibilityReduceMotion)`), with a static red fallback.

## 8. Auth sequencing (dependency)

`/api/v1/diagnostics` uses `_verify_proxy_token`, which accepts the api_key as
`X-Proxy-Token`. iOS currently sends the **webhook secret** there
(`ContentView.swift:183`), which only passes because `PROXY_TOKEN == webhook
secret` today. **Land the proxy-token fix first** (iOS → send `api_key` as
`X-Proxy-Token`, matching the PWA), so diagnostics authenticates on the api_key
path independent of `PROXY_TOKEN`. Until then, diagnostics would ride the same
coincidence. This spec assumes that fix ships with or before it.

## 9. Testing (TDD when built)

- **Middleware:** telemetry records success/latency and error/consecutive-fail
  on simulated cache cycles; `/api/v1/diagnostics` returns passive data when
  cache on; fires exactly one probe (mocked) when cache off; a probe **timeout**
  yields `reachable:false` within the 4 s bound and never raises; payload
  contains **no** secret keys (assert scrubber); missing api_key → 401.
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
