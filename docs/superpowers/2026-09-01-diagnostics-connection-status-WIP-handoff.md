# Connection Status + Diagnostics — WIP Handoff

**Date:** 2026-09-01
**Status:** PAUSED mid-redesign of the connection-status indicator. Fresh session
+ model change intended, to **restart the design-discussion approach**. iOS
working tree **does not currently compile** (see "WIP / broken bits").

---

## What we're building
1. **Connection status indicator** — the top-left chain badge (`ConnectionBadgeButton`)
   + a hop-aware disconnected **banner** — answering "can the app reach BHNM,
   **always through the middleware**?"
2. **Diagnostics screen** (tap the badge → sheet) — the 📱 App → 🖥 Middleware →
   🗄 BHNM pipeline with per-hop latency, per-feed status, recent-call log,
   `/health` readout, per-server error stats.

Approved spec: `docs/superpowers/specs/2026-09-01-two-hop-diagnostics-design.md`
(now partly superseded by the design journey below — the spec still says the
badge derives from data calls and the probe runs client-side only when cache
off; both have since evolved).

## Committed & known-good (builds, on device)
- `16efb22` **fix(middleware): strip client Accept-Encoding** — the *real* cause
  of the iOS empty-Devices outage (Brotli passthrough via Traefik). Deployed to
  prod. NOT proxy-token (reviewer over-called that).
- `4b86c84` **fix(ios): unified connection badge via ConnectionMonitor (v1)** —
  badge derived from data-load outcomes; all 4 screens; removed `checkHAStatus()`.
- `b2ad942` **fix(ios): send api_key as X-Proxy-Token** (proxy-token hardening).
  **← last commit that builds + runs on device.**
- `143d058` **docs**: maintenance-read + two-hop-diagnostics specs.

## Uncommitted WIP
### Middleware — deployed to prod via FILE-COPY (uncommitted on server too)
- NEW `middleware/diagnostics.py`: telemetry registry + `scrub()` + `active_probe()`.
  Probe reachability = **`status_code < 500`** (Traefik 502 = BHNM down; <500 = alive).
- `main.py`: `GET /api/v1/diagnostics` (isolated: own try/except, own httpx,
  no secrets, host-only). Currently bhnm block = **live on-demand `active_probe`**
  (this is the part being replaced — see direction below); feeds = passive telemetry.
- `incident_cache.py` / `tactical_cache.py` / `threshold_cache.py`: record
  telemetry in the loops; **incident cycle now `raise`s** on fetch-fail so the
  failure is recorded (was swallowed → false "success").
- `middleware/tests/test_diagnostics.py`: **11/11 pass** in the venv
  (`scratchpad/mwtest-venv`; global python3.14 has broken pydantic-core).
- **Deploy note:** the server's `/root/BeNeM/middleware` has these files copied
  in (uncommitted). For the real deploy: `git checkout` those files on the
  server first, then git pull the committed versions + `docker compose up -d
  --build bhnm-apns`.

### iOS — MID-REFACTOR, DOES NOT COMPILE
- NEW: `Models/Diagnostics.swift`, `Services/ClientCallLog.swift`,
  `Views/DiagnosticsView.swift`, `Views/DisconnectedBanner.swift`
  (+ `.connectionBanner()` modifier). Added to `project.pbxproj` (xcodeproj gem).
- `AutoRefreshButton.swift`: `ConnectionMonitor` rewritten as a **30 s poller**
  that calls `fetchDiagnostics()`; `DiagnosticsPresenter`; badge tap → sheet;
  reduce-motion blink.
- Banner applied under each screen's header via `.connectionBanner()` (fixed the
  earlier overlap where it covered the toolbar).
- **BROKEN / half-done:**
  - `TacticalViewModel` + `IncidentListViewModel` still call the removed
    `ConnectionMonitor.report*` / `isTransport` → **compile errors**.
    (`DeviceListViewModel` + `fetchDevices` already cleaned.)
  - `DiagnosticsView` still fetches itself; should read `ConnectionMonitor.lastResult`
    and pull-to-refresh → `pollNow()`.
  - `ContentView` does **not** yet call `ConnectionMonitor.shared.configure(apiService)`
    on config/server-switch.

## Design journey (WHY the churn — don't re-derive)
The **status indicator** evolved as the vision clarified:
1. (pre-session) HA-status, green iff a `role` field present → **false red** bug.
2. **v1 (committed `4b86c84`):** badge from the real data-load outcomes
   (incidents/tactical/devices). Problem: with caching **on**, only the live
   Devices call detects BHNM-down → banner lagged **~5 min**; badge green on
   Home/Incidents (cached) while BHNM down.
3. **Sheet option (c):** `/api/v1/diagnostics` does a **live on-demand probe**
   for the BHNM hop. Problem: the probe **blocks ~3.3 s** (Traefik waits ~3 s for
   the dead backend before returning 502); on pull-to-refresh the slow request is
   cancelled → App→Middleware wrongly shown down (**unreliable**).
4. **CURRENT AGREED DIRECTION (Thomas, mid-build):** a dedicated checker,
   independent of any screen:
   - **BHNM health poll runs ON THE MIDDLEWARE** — one lightweight `ha_status`
     poll **per server** every ~15–30 s, cached (so BHNM isn't hit once *per
     client*).
   - **Client polls a FAST middleware endpoint every 30 s.** Reaching it =
     middleware up; response `bhnm.reachable` = BHNM up/down; client poll fails =
     **middleware down**. → middleware-down ≤30 s; BHNM-down ~30–60 s (poll BHNM
     on the middleware ~15 s to keep it near 30 s).
   - Badge + banner poller-driven; the sheet reads the poller's cached result
     (fast, reliable).
   - **NOT YET BUILT:** the middleware background BHNM monitor + making the
     endpoint serve the *cached* health (fast) instead of the blocking probe.

## Guardrails / acceptance criteria (carry forward)
- App **never** hits BHNM directly — always via the middleware.
- Hop-aware banner: **middleware-down → "Can't reach the server · retrying…"**
  (NO cache claim); **BHNM-down (mw up) → "BHNM unreachable · showing cached data
  · retrying…"**. Reduce-motion → static (no blink). Banner sits **under** each
  header.
- Badge: green on any valid response; a Traefik **5xx = BHNM down**, not up.
  `checking` = amber **static**; blink reserved for disconnected.
- Diagnostics payload: no secrets (scrubbed/truncated, host only); isolated
  route/client/try-except; bounded probe (never hang); the BHNM check must not
  hammer BHNM (→ middleware-side, shared).
- Recent-call log: in-memory, query-strings stripped.
- Detection latency target ~**30 s** (200 s / 5 min is too long).

## Key verified facts
- **bhnm-b is behind Traefik.** BHNM app down → Traefik **502 after ~3 s**; box
  down → connect fails. ha_status when BHNM up → **200** (PHP body "API require
  HTTPS connection"). Rule: **<500 = alive, 5xx = down.**
- `servers.json` bhnm-b: name "Thomas' Lab Server", url `https://bhnm-b.tstolt.com`,
  api_key `ThisIsAPassword` (== `.secrets` `BHNM_B_API_KEY`). The admin **"Incidents
  cache"** toggle enables **all three** caches.
- Middleware `PROXY_TOKEN` == the phones' webhook secret (why old iOS auth worked).
  After `b2ad942`, iOS sends **api_key** as `X-Proxy-Token` (matches servers.json).
- **SSH** to VPS via `.secrets` (root@bhnm-apns.hurrikap.org, `~/.ssh/macbook.pem`,
  `IdentitiesOnly=yes`). Many rapid SSH conns → **fail2ban** (port 22 times out
  ~10–30 min; 443 still works). Back off; batch.
- Middleware tests: `scratchpad/mwtest-venv`. 2 pre-existing unrelated failures
  (`test_vapid_key_endpoint` = suite-ordering; `test_webhook_rejects_non_json` =
  fastapi quirk) — proven NOT diagnostics-caused.
- iOS: SourceKit false-positive "Cannot find type" is constant noise — trust
  `xcodebuild`. New files need `project.pbxproj` entries (xcodeproj gem installed
  `--user`). Build+deploy: `cd ios && ./build_and_deploy.sh`.

## Open follow-ups (separate from the core)
- Sanitize the **Incidents raw-502** error display (shows Cloudflare/Traefik HTML
  on cache-cold BHNM-down).
- Rename the misleading **"Incidents cache"** admin label (it controls all 3 caches).

## Resume checklist
1. Re-discuss the connection-status design (Thomas wants a fresh approach; the
   direction above is agreed but unfinished).
2. Build the middleware BHNM health monitor + fast endpoint.
3. Finish iOS wiring (fix the two VM compile errors; `configure()` in ContentView;
   sheet reads `lastResult`). Rebuild — currently broken.
4. Verify on device (middleware-down ≤30 s; BHNM-down ~30 s; recovery).
5. Proper git commit + push + clean git-pull deploy (replace the file-copy;
   `git checkout` the server's manual files first). Commit the iOS feature.
