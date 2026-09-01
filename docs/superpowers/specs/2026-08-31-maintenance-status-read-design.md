# Maintenance Status — Read/Display — Design Spec

**Date:** 2026-08-31
**Status:** Proposed — awaiting review (do not build until approved)
**Scope:** iOS (lead), PWA (parity), Middleware
**Supersedes:** the "Out of Scope" note in `2026-04-09-maintenance-window-design.md`
(lines 101–107) and its claim that *"no query API exists"* (line 31). A query
path **does** exist on BHNM 26.3.x — verified live.

## 1. Overview

The **set** path (create maintenance window) already ships on all three
platforms. This spec adds the **read** side: show *whether a device is
currently in a maintenance window* and *when the active window ends*, on the
Device Detail screen.

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

**(b) Maintenance card** (detail): the existing "Create Maintenance Window"
card becomes **status-aware**:

- **Not in maintenance** → unchanged. "Create Maintenance Window" (sky-400),
  tap → existing create sheet.
- **In maintenance** → the card morphs into a read-only status display:
  maintenance icon + "In Maintenance", **"Ends HH:MM"** (from the active
  window's `end_time`; if multiple, the latest end), and the window `comment`
  (the stamped "Created by … on …" line). **Read-only** — no tap-to-create
  (avoids creating overlapping windows), no close button.

**Close-window is explicitly out of scope for this read feature.** It's a
*write* path (`maint_window_api.php action=close`) that doesn't exist in the
middleware or clients yet. Recommended as a **separate fast-follow**: a
`POST /api/proxy/maintenance/close` route + a confirmed "Close window" action
on the in-maintenance card. Called out here so the card layout leaves room for
it, but not built now. (Keeps this feature read-only / side-effect-free, per
the task constraint.)

## 4. Architecture

```
iOS / PWA  (Device Detail opens or refreshes)
    → POST /api/proxy/maintenance/status   name=<device name>   (middleware)
        → get-host-and-service-status  (BHNM)   → inMaintenance
        → maint_window_api.php action=list (BHNM)   → windows[]
    ← { inMaintenance, windows }
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
- `maintenanceCard` gains the in-maintenance branch (§3 D4b). The existing
  not-in-maintenance branch and create sheet are untouched.

`DeviceStatus.maintenance` already maps to blue in the badge colour switches
(`DeviceDetailView.swift:1089, 1159`) — no colour work needed.

### 5.2 PWA (parity)

- `pwa/src/lib/api/maintenance.ts` gains
  `fetchMaintenanceStatus(config, deviceName): Promise<MaintenanceStatus | null>`
  next to the existing `createMaintenanceWindow`.
- React Query hook (60 s, matching other device-detail queries) in the devices
  feature; best-effort (a failed query renders the plain create card).
- `DeviceDetailScreen.tsx`: header status label/colour flips to `maintenance`
  (the `STATUS_LABELS`/`STATUS_COLORS` maps already include `maintenance`) when
  `inMaintenance`; the "Create Maintenance Window" card gets the in-maintenance
  branch mirroring iOS.

Parity note: identical middleware contract, identical two states, same
"ends-at + comment, read-only" card. No platform-specific divergence.

## 6. The ~85 s disagreement (explicit)

| Phase | `inMaintenance` | `windows[]` | Badge | Card |
|---|---|---|---|---|
| Window just created (starts +15 min) | false | empty (not active yet) | normal | Create |
| Window becomes active, poll not caught up | **false** | **non-empty** | **normal** | **Create** |
| Poll catches up | true | non-empty | Maintenance | In Maintenance + ends/comment |
| Window ended, poll not caught up | true | empty | Maintenance | In Maintenance, "ends: —" |

**Rule (single, simple):** the badge **and** the in-maintenance card are gated
on `inMaintenance == true`. `windows[]` only supplies the ends-at/comment text
*inside* that state. We never show "In Maintenance" because `windows[]` is
non-empty, and never hide it because `windows[]` is empty. This makes the
~85 s gap a no-op in the UI — the badge simply flips one poll late, which is
the honest reflection of when BHNM actually starts suppressing alerts.

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

## 8. Mockups

Visual mockups (iOS not-in-maintenance / iOS in-maintenance / PWA in-maintenance)
are published as an Artifact for review — see the link in the review thread.
ASCII reference of the two Device Detail states:

```
NOT IN MAINTENANCE                    IN MAINTENANCE
┌──────────────────────────┐         ┌──────────────────────────┐
│ core-switch-01     [UP]   │         │ core-switch-01 [MAINT.]   │  ← header badge blue
│ 10.0.0.1 · HQ             │         │ 10.0.0.1 · HQ             │
│ ─ Current Issues ─────────│         │ ─ Current Issues ─────────│
│  … alarm bar …            │         │  … alarm bar …            │
│ ┌──────────────────────┐  │         │ ┌──────────────────────┐  │
│ │ + Create Maintenance │  │         │ │ ⏸  In Maintenance     │  │  ← card morphs
│ │      Window          │  │         │ │    Ends 14:30         │  │
│ └──────────────────────┘  │         │ │    "Created by tom …" │  │
│ ─ Host Information ───────│         │ └──────────────────────┘  │
└──────────────────────────┘         │ ─ Host Information ───────│
                                      └──────────────────────────┘
```

## 9. Out of scope (this feature)

- Device-**list** maintenance badges + the bulk `maintenance_cache` (D1/D3
  fast-follow).
- **Closing** a window from the read UI + `maintenance/close` proxy route (D4
  fast-follow, keeps this read-only).
- Scheduled/future windows (BHNM's `action=list` doesn't return them).
- Service-row maintenance (unverified; we read host rows only).

## 10. Test plan (when built — TDD, read-only)

- **Middleware:** unit-test the merged route's parsing — host row present →
  correct bool; empty `statuses[]` → false; list failure → windows empty +
  bool preserved; missing `name` → 400. Mock both BHNM calls.
- **iOS/PWA:** the four §6 phases render the correct badge + card; a read
  failure falls back to the plain create card with no error surfaced.
- No live side effects — the read path calls only `list`/`get-status`
  (side-effect-free); create/close remain the only write paths.
