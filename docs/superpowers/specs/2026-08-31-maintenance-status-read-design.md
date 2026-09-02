# Maintenance Status — Read/Display — Design Spec

**Date:** 2026-08-31 · **Rev 2:** 2026-09-02 — three-state maintenance button
(both platforms, same release wave) + start-time boundary snapping (§3a)
· **Rev 3:** 2026-09-02 — close-maintenance moves INTO this release (state C
tappable → confirm dialog → new close proxy route, §3b); stop-square icon on
state C; scheduled-window close probed live (§3b)
**Status:** Approved (Rev 3, Tom + reviewer) — implemented 2026-09-02
**Scope:** iOS + PWA (same release wave — supersedes Rev 1's iOS-first scoping), Middleware
**Supersedes:** the "Out of Scope" note in `2026-04-09-maintenance-window-design.md`
(lines 101–107) and its claim that *"no query API exists"* (line 31). A query
path **does** exist on BHNM 26.3.x — verified live.

## 1. Overview

The **set** path (create maintenance window) already ships on all three
platforms. This spec adds the **read** side: show *whether a device is
currently in a maintenance window* and *when the active window ends*, on the
Device Detail screen — plus, since Rev 3, one write: **ending maintenance**
from the in-maintenance button, behind a confirmation dialog (§3b).

Two independent BHNM signals, per the reviewer's rulings:

| Signal | Source | Role |
|---|---|---|
| `inMaintenance` (bool) | `get-host-and-service-status`, host row | **Source of truth** for the badge — reflects BHNM actually suppressing alerts |
| Active windows `[{start, end, comment}]` | `maint_window_api.php` `action=list` | **Detail only** — enriches the display (ends-at, comment); never decides the badge |

These two can **disagree for ~1 poll cycle (~85 s observed)** after a window
becomes active. That is expected. The badge follows `inMaintenance`; we do not
reconcile them. See §6.

## 2. Verified API facts (probed live on 26.3.01 — not re-derived)

**`inMaintenance` (the boolean):**
- `POST /fw/index.php?r=restful/devices/get-host-and-service-status`
- Params: `groupFilterBy=device`, `groupFilterValue=<device NAME, not IP>`,
  `serviceFilter=host_only`, `recordCount=<n>` **(required — omit it and
  `statuses[]` comes back empty even though `totalRecords>0`)**.
- Host rows carry `inMaintenance` as a JSON boolean. Service-row behaviour is
  unverified — we only read host rows.
- IP as the filter value → `"Bad input parameter"`. Must be the name.

**Active windows (the detail):**
- `POST /api/maint_window_api.php` with `action=list` + `name` **(name
  required; without it → `"Missing required information"`)**.
- Returns `{result, windows:[{start_time (epoch), end_time (epoch), comment}]}`.
- **ACTIVE windows only** — scheduled/future windows do **not** appear. Rows
  carry no device name (the request was already device-scoped by `name`).

Proven request shapes copied from `~/dev/mcp-netreo`
(`restful_host_service_status`, `legacy_list_maintenance`) — the same shapes
this middleware will send.

## 3. Decisions (resolved — reviewer to weigh in)

### D1 — Data path: per-device read on Device Detail (v1) ✅

**Choice:** v1 reads maintenance *per device, on demand, on the Device Detail
screen only.* No bulk fetch, no cache.

**Rationale (lazy + matches where the action lives):**
- The **set** path already lives on Device Detail. Read state belongs on the
  same screen — that's where a user goes to ask "is this in maintenance?"
- Device-list status today is derived from incidents + `threshold_cache`, and
  does **not** touch `get-host-and-service-status`. Adding maintenance to the
  list is a **new bulk data path + a cache** to keep it cheap at scale — that's
  `threshold_cache`-shaped work for a low-frequency signal. Don't build it on
  spec.
- Volume is one extra pair of cheap single-device reads when a detail screen
  opens/refreshes. Negligible.

**Fast-follow (not v1):** a middleware `maintenance_cache` mirroring
`threshold_cache` — one background task polling `get-host-and-service-status`
(all hosts) per server, storing `{deviceName: inMaintenance}` — to light up
maintenance badges on the device **list**. Build it only if list badges are
actually wanted (see D3). Deferring it costs nothing: the client contract in
D2 is identical whether the data comes live or from a cache.

### D2 — Middleware surface: one merged smart route ✅

**Choice:** a single new route

```
POST /api/proxy/maintenance/status   (body: name=<device name>)
  → returns { inMaintenance: bool, windows: [{start_time, end_time, comment}] }
```

The middleware makes **both** BHNM calls server-side, extracts the host row's
`inMaintenance`, and returns the merged shape. It follows the existing
`/api/proxy/maintenance/create` pattern: `_verify_proxy_token` +
`_resolve_server_config`, api_key resolved server-side, **client never sends
the key**.

**Rationale:**
- The endpoint's quirks (recordCount required, name-not-IP, dig `inMaintenance`
  out of `statuses[]`) get encoded **once** in the middleware instead of twice
  in Swift and TypeScript. Net system code is *smaller* than two passthroughs.
- One client round-trip, one loading state, one clean `{inMaintenance, windows}`
  contract that maps exactly to the badge/detail split of §1.
- Consistent with the sibling `maintenance/create` route (key resolved
  server-side, not forwarded).

**Alternative considered (reviewer may prefer):** two thin passthrough routes
reusing the existing `_proxy_to_bhnm` helper —
`POST /api/proxy/host-status` and `POST /api/proxy/maintenance/list` — with the
clients doing two calls and the parsing/merge. Lazier in middleware *lines*,
but duplicates the endpoint quirks across both clients and gives the UI two
loading states to juggle. Rejected on total-system size, but it's a legitimate
call if you'd rather keep the middleware a dumb proxy.

**Middleware logic (merged route):**
1. `_verify_proxy_token`; `name` required (400 if blank).
2. Resolve server config (`_resolve_server_config` → `_single_server_url`);
   get `api_key` server-side.
3. Call A → `get-host-and-service-status` with
   `groupFilterBy=device&groupFilterValue=<name>&serviceFilter=host_only&recordCount=100&password=<api_key>`.
   Extract `inMaintenance` from the host row. If no row / call fails →
   `inMaintenance: false` (fail safe: never claim maintenance we can't confirm).
4. Call B → `maint_window_api.php` `action=list&name=<name>&password=<api_key>`.
   Take `windows` (empty list on failure).
5. Return `{ "inMaintenance": <bool>, "windows": [...] }` (HTTP 200).

No cache, no state — pure read + merge. Best-effort: partial upstream failure
degrades gracefully (see §7), it does not 5xx the whole read.

### D3 — Device-list badges: not in v1 ✅

**Choice:** Device Detail only for v1. The device **list** gets no maintenance
badge yet.

**Rationale:** ties to D1 — list badges need the bulk cache. Ship the
detail-screen read, learn whether "which devices are in maintenance right now"
is a real list-scanning need, then add the cache + list badge as the D1
fast-follow. The `DeviceStatus.maintenance` enum case already exists, so the
list badge is a small addition later — no rework, just deferred.

### D4 — UI: status-aware card + header badge, read-only ✅

The single boolean drives **two** surfaces, exactly matching the ruling
(boolean → badge, windows → detail):

**(a) Header device-status badge** (at-a-glance): when `inMaintenance == true`,
the Device Detail header status shows **MAINTENANCE** (blue), overriding the
incident/threshold-derived status. This is the long-empty
`NetreoDevice.DeviceStatus.maintenance` case finally wired to a real signal —
*not* a parallel field. BHNM is suppressing alerts, so "maintenance" is the
honest headline over a possibly-stale "critical".

**(b) Maintenance button — three states** (Rev 2; both platforms, identical):
the existing "Create Maintenance Window" button stays **one button-shaped
element** whose style tells the state:

1. **Normal** → unchanged. Current outline style — sky-400 text on the card
   background. "Create Maintenance Window", tap → existing create sheet.
2. **Starting (interim, local knowledge)** → shown after a **successful
   create**, reading **"Starts at HH:MM"**. Needed because BHNM's
   `action=list` returns only ACTIVE windows and `inMaintenance` lags ~1 poll
   (~85 s) after the window opens — without this state the user presses
   Create and sees nothing change for minutes. The start time comes from the
   create response (middleware echoes its computed start, §3a); held in
   client memory only (not persisted). Cleared when `inMaintenance` flips
   true; reverts to normal if it hasn't flipped by ~3 min past the start
   (window closed elsewhere, or the create silently failed upstream).
   **Tappable (Rev 3):** tap → "Cancel scheduled maintenance?" confirmation
   (§3b copy) → the close route cancels the scheduled window (verified by
   probe, §3b) → clear the pending start → state 1. Never opens the create
   sheet (avoids overlapping windows).
3. **In Maintenance (inverted)** → **filled blue** (sky fill, white text),
   with a **stop-square icon** (iOS `stop.fill`, PWA a matching filled
   square), reading **"In Maintenance · ends HH:MM"** (`end_time` from
   `windows[]`; if multiple, the latest end; "ends —" if `windows[]` is
   empty). Gated strictly on `inMaintenance == true` (§6). **Tappable
   (Rev 3):** tap → confirmation dialog *"End maintenance for `<device>`
   now? Alerting for this device will resume."* — confirm button **"End
   Maintenance"** (destructive-styled), Cancel is the default. On confirm →
   `POST /api/proxy/maintenance/close` (§3b); on success clear to state 1
   and refresh the maintenance status.

   *Icon rationale (for the record):* ‖ reads as "paused"; × reads as
   "dismiss this notice"; ■ reads as "stop the running thing" — which is
   what the tap now does.

Precedence: `inMaintenance == true` → state 3, regardless of any local
pending start. Else a live local pending start → state 2. Else state 1.
The window `comment` (the stamped "Created by … on …" line) renders as a
caption under the button in state 3.

**Close-window is IN scope (Rev 3** — supersedes Rev 1's fast-follow
deferral, accepted by Tom + reviewer**).** The write path is the new
`POST /api/proxy/maintenance/close` route (§3b) behind the state-3
confirmation dialog above. **BHNM's `action=close` ends ALL maintenance
windows for the device** (probed; the response says so verbatim) — the
dialog therefore speaks of ending *maintenance*, not *a window*.

## 3a. Start-time rule change (create path — Rev 2)

**Where the +15 min lives (located, not assumed):** `middleware/main.py:782` —
`start_time = int(time.time()) + 900` in `/api/proxy/maintenance/create`.
Neither client computes a start time (PWA sends `name/duration/comment` only;
iOS likewise). **The rule change is middleware-only and ships to both apps
with NO client release.**

**New rule — snap to the next 5-minute wall-clock boundary,** with a ≥60 s
safety margin: if the next boundary is less than 60 s away, use the
*following* boundary. BHNM rejects non-future start times (probed live:
`now−120` → `"Start time error"`), so a 1-second-future start can fail on
arrival.

```python
BOUNDARY = 300  # 5 min
MARGIN = 60     # s — min lead time so the start is still future on arrival

def snap_start(now: int) -> int:
    nxt = (now // BOUNDARY + 1) * BOUNDARY
    if nxt - now < MARGIN:
        nxt += BOUNDARY
    return nxt
```

Canonical examples (preserved exactly):
- press **10:00:00** → start **10:05:00** (exactly on a boundary still goes
  to the *next* one)
- press **10:05:01** → start **10:10:00**
- press **10:04:59** → start **10:10:00** (10:05:00 is <60 s away)
- press 10:04:00 → start 10:05:00 (exactly 60 s = allowed; margin is strict `<`)

Epoch `% 300` boundaries coincide with local wall-clock 5-minute boundaries
in every real timezone (all UTC offsets are multiples of 15 min), so no
timezone handling is needed.

**Echoing the start to clients:** the create route today passes BHNM's
response through verbatim. It additionally sets an
**`X-Maintenance-Start: <epoch>`** response header so clients can render the
interim "Starts at HH:MM" state (§3 D4b-2) without duplicating the boundary
math in Swift and TypeScript. Clients that don't see the header (old
middleware) simply skip the interim state — graceful.

**Client copy fix (rides the button-state release):**
`ios/BeNeM/Views/MaintenanceWindowSheet.swift:134` says *"will start in 15
minutes"* — becomes *"will start at HH:MM"* from the echoed start. The PWA
dialog has no such copy.

**Not part of this:** `mcp-netreo`'s `legacy_set_maintenance` (`start_in`
default 15) is a separate, optional alignment in its own repo.

## 3b. Close maintenance (Rev 3 — the one write path added)

**Route:** `POST /api/proxy/maintenance/close` (body: `name=<device name>`),
mirroring the create proxy exactly: `_verify_proxy_token`, `name` required
(400 if blank), server config + `api_key` resolved server-side
(`_resolve_server_config` → `_single_server_url`), then a form POST to
`maint_window_api.php` with `action=close&name=<name>&password=<api_key>`,
response passed through verbatim (same hop-by-hop header handling as
create). No client ever sends the key.

**Semantics: `action=close` ends ALL maintenance windows for the device** —
there is no per-window close in the legacy API (rows carry no window id).
Success response (probed live): `{"result": "completed", "detail": "All
maintenance windows for this device are closed"}`.

**Client flow (both platforms):** state-3 button tap → confirmation dialog
(§3 D4b-3 copy) → on confirm call the route → on success set the button to
state 1 immediately and re-fetch `/api/proxy/maintenance/status` (the badge
follows `inMaintenance`, which lags the close by ~1 poll like everything
else — the button clearing instantly is the local acknowledgment). On
failure show the create-path's standard error surface; state unchanged.

**Scheduled (future-start) windows — probed live (2026-09-02, lab BHNM
26.3.01, device `BHNM-B-SE01`): `action=close` ALSO cancels a scheduled
window.** Method: created a window with start ≈ +5 min (confirmed scheduled —
absent from `action=list`, which shows active only), called `action=close`
(→ `"completed"`), then verified past the scheduled start that the window
never became active: `list` stayed empty (active windows appear there
immediately) and `inMaintenance` stayed `false`.

**Consequence — state 2 is tappable too:** tap on "Starts at HH:MM" →
confirmation dialog *"Cancel scheduled maintenance for `<device>`? The
window starting at HH:MM will not open."* — confirm button **"Cancel
Maintenance"** (destructive-styled), the dismiss button is **"Keep"** (the
default; not named "Cancel", to avoid two cancel-meanings in one dialog).
On confirm → the same close route → on success clear the local pending
start → state 1. (One route serves both flows; `action=close` takes no
window id anyway.)

## 4. Architecture

```
iOS / PWA  (Device Detail opens or refreshes)
    → POST /api/proxy/maintenance/status   name=<device name>   (middleware)
        → get-host-and-service-status  (BHNM)   → inMaintenance
        → maint_window_api.php action=list (BHNM)   → windows[]
    ← { inMaintenance, windows }

iOS / PWA  (state-3 button tap → confirmed dialog)
    → POST /api/proxy/maintenance/close    name=<device name>   (middleware)
        → maint_window_api.php action=close (BHNM)   → ends ALL windows
    ← BHNM response passthrough; client clears to state 1 + refetches status
```

Apps never call BHNM directly. Same auth as every other proxy route.

## 5. Client design

### 5.1 iOS (lead)

**Model** — a small read struct (no new "status" field on `NetreoDevice`):

```swift
struct MaintenanceStatus {
    let inMaintenance: Bool
    let windows: [MaintenanceWindow]   // {start: Date, end: Date, comment: String}
    var activeEnd: Date? { windows.map(\.end).max() }
    var comment: String? { windows.sorted { $0.end > $1.end }.first?.comment }
}
```

**Service** — `NetreoAPIService.fetchMaintenanceStatus(deviceName:) async -> MaintenanceStatus?`
POSTs to `/api/proxy/maintenance/status`. Returns `nil` on failure (best-effort).

**ViewModel** — `DeviceDetailViewModel` gains
`@Published var maintenance: MaintenanceStatus?`, loaded **concurrently** in
`load()` alongside the existing incident/service/performance loads (it already
fans these out concurrently — add one more child task). Refreshes with the
120 s auto-refresh like everything else.

**View** — `DeviceDetailView`:
- Header status badge = `.maintenance` (blue) when
  `vm.maintenance?.inMaintenance == true`, else `device.status`. Don't mutate
  the struct — compute `effectiveStatus` in the view/VM.
- `maintenanceCard` becomes the three-state button (§3 D4b): normal branch
  and create sheet untouched; a `@Published var pendingStart: Date?` on the
  VM (set from `X-Maintenance-Start` on successful create, auto-expiring
  ~3 min past start) drives the interim state; `inMaintenance` drives the
  filled state.

`DeviceStatus.maintenance` already maps to blue in the badge colour switches
(`DeviceDetailView.swift:1089, 1159`) — no colour work needed.

### 5.2 PWA (parity)

- `pwa/src/lib/api/maintenance.ts` gains
  `fetchMaintenanceStatus(config, deviceName): Promise<MaintenanceStatus | null>`
  next to the existing `createMaintenanceWindow`.
- React Query hook (60 s, matching other device-detail queries) in the devices
  feature; best-effort (a failed query renders the plain create card).
- `DeviceDetailScreen.tsx`: header status label/colour flips to `maintenance`
  (the `STATUS_LABELS`/`STATUS_COLORS` maps already include `maintenance` —
  but `STATUS_COLORS.maintenance` is currently `text-slate-400` grey and
  flips to `text-sky-400` blue, per the blue-badge ruling) when
  `inMaintenance`; the "Create Maintenance Window" button gets the three
  states mirroring iOS (local `pendingStart` state from `X-Maintenance-Start`
  for the interim, `inMaintenance` for the filled state).

Parity note: identical middleware contract, identical three states, same
release wave (Rev 2 — supersedes iOS-first). No platform-specific divergence.

## 6. The ~85 s disagreement (explicit)

| Phase | `inMaintenance` | `windows[]` | Badge | Button |
|---|---|---|---|---|
| Window just created (starts at next 5-min boundary) | false | empty (not active yet) | normal | **Starts at HH:MM** (local, §3 D4b-2) |
| Window becomes active, poll not caught up | **false** | **non-empty** | **normal** | **Starts at HH:MM** (still) |
| Poll catches up | true | non-empty | Maintenance | In Maintenance · ends HH:MM (filled blue) |
| Window ended, poll not caught up | true | empty | Maintenance | In Maintenance · ends — |

**Rule (single, simple):** the badge **and** the filled-blue button state are
gated on `inMaintenance == true`. `windows[]` only supplies the ends-at/comment
text *inside* that state. We never show "In Maintenance" because `windows[]`
is non-empty, and never hide it because `windows[]` is empty. The interim
"Starts at" state is **local knowledge only** — it never claims maintenance,
it announces the scheduled start, so the ~85 s gap reads as "starting soon →
in maintenance" instead of "nothing happened".

## 7. Error / edge handling

- **Read is best-effort enrichment.** Any failure (middleware down, cache cold,
  BHNM error, device not found) → treat as **not in maintenance**: plain
  "Create Maintenance Window" card, normal header status, **no error toast**.
  We never block or alarm the user over a failed maintenance read.
- **`inMaintenance == true` but `windows[]` empty** (reverse gap, or list
  quirk): show "In Maintenance" with "Ends: —" (unknown). Badge still honest.
- **Multiple active windows:** ends-at = latest `end_time`; comment = that
  window's comment. (Overlapping windows are rare; latest-end is the
  conservative "still suppressed until".)
- **Timezone:** `end_time` is UTC epoch; render in device-local time, same as
  the create path's timestamps.
- **Older BHNM (< 26.3.01) — version gate (Rev 2):** the host row carries no
  `inMaintenance` key on older servers; the middleware's extraction finds
  nothing and returns `false`, so clients show the normal button and **no
  maintenance state at all** — never a wrong one. The filled-blue state can
  only appear when the field is actually present and true. No explicit
  version check needed — the fail-safe already gates it. (If explicit gating
  is ever wanted: a BHNM SaaS environment reports its version at
  `GET <base>/cloudversion`, e.g.
  `https://portal-netreo-ash-np2.onbmc.com/cloudversion`.)

## 8. Mockups (Rev 2 — three button states × both platforms)

A design-canvas mockup showing all three states on iOS **and** PWA, plus the
blue header badge alongside, is published as an Artifact for review — see the
link in the review thread. ASCII reference of the button progression:

```
(a) NORMAL                     (b) STARTING (interim, local)   (c) IN MAINTENANCE (inverted)
+ Create Maintenance Window    ⏱ Starts at 10:05               ⏸ In Maintenance · ends 14:30
[outline: sky-400 text on      [outline + blue tint; after     [FILLED blue, white text;
 card bg; tap → create sheet]   successful create; not          gated on inMaintenance==true;
                                tappable; covers ~85 s lag]     header badge = MAINTENANCE]
```


## 9. Out of scope (this feature)

- Device-**list** maintenance badges + the bulk `maintenance_cache` (D1/D3
  fast-follow).
- ~~Closing a window~~ — **in scope since Rev 3** (§3b).
- Reading/displaying scheduled/future windows (BHNM's `action=list` doesn't
  return them).
- Service-row maintenance (unverified; we read host rows only).

## 10. Test plan (when built — TDD, read-only)

- **Middleware:** unit-test the merged route's parsing — host row present →
  correct bool; empty `statuses[]` → false; **host row without an
  `inMaintenance` key (BHNM < 26.3.01) → false**; list failure → windows
  empty + bool preserved; missing `name` → 400. Mock both BHNM calls.
- **Middleware — `snap_start` boundary math (§3a), pure-function unit tests:**
  - exact boundary: 10:00:00 → 10:05:00
  - one second past boundary: 10:05:01 → 10:10:00
  - inside margin: 10:04:59 → 10:10:00 (and 10:04:01 → 10:10:00)
  - exactly at margin: 10:04:00 → 10:05:00 (60 s lead is allowed; `<` is strict)
  - plus: create route sets `X-Maintenance-Start` to the snapped value.
- **iOS/PWA:** the four §6 phases render the correct badge + button state;
  interim-state precedence (`inMaintenance` true beats local pending start)
  and its ~3-min-past-start expiry; a read failure falls back to the plain
  create button with no error surfaced.
- **Middleware — close route (§3b):** missing/invalid proxy token → 401;
  missing `name` → 400; correct passthrough body
  (`action=close`, `name`, key server-side, never from the client); BHNM
  response passed through verbatim. Mock the BHNM call.
- **iOS/PWA — close flow:** tap in state 3 shows the end-maintenance dialog
  (cancel = no call); confirm → close call → success clears to state 1 and
  triggers a status re-fetch; failure leaves state 3 and surfaces the error.
  Tap in state 2 shows the cancel-scheduled dialog; confirm → close call →
  success clears the pending start to state 1; failure leaves state 2.
- The read path calls only `list`/`get-status` (side-effect-free);
  create/close are the only write paths, and close is always behind the
  confirmation dialog.
