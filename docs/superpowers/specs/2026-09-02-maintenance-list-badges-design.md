# Device-List Maintenance Visibility — Design Spec

**Date:** 2026-09-02
**Status:** APPROVED (Tom + reviewer, 2026-09-02) — **Option B + COEXIST, plus
Option D's filter chip** — IMPLEMENTED 2026-09-02 (middleware 2.9.0, iOS 2.11.0, PWA 0.12.0), lab-verified
**Target:** next release wave — middleware 2.9, iOS 2.11, PWA 0.12 (the
in-flight 2.10.0/0.11.0 commits stay untouched)

**Recorded rulings:**
1. **List rows: Option B** — blue wrench glyph beside the device name, fed by
   the middleware name list; renders on device-list rows AND search-result
   rows (same anatomy).
2. **List precedence: COEXIST** — maintenance adds context, never masks; a
   device in maintenance AND critical shows the wrench and its red count.
   *Rationale:* the list is what you scan to find problems; blue-overrides-red
   can hide an outage that outlives its window (BHNM's close-all semantics
   make stale windows real). The count strip is multi-signal by design.
3. **Detail header stays maintenance-wins** (Rev 3, unchanged). *Rationale:*
   the header badge is a single status slot — one honest headline — and while
   BHNM suppresses alerts, "maintenance" is that headline; the incident data
   below it remains visible.
4. **Option D ships too:** an "In maintenance (N)" filter chip — pure
   client-side filter over the same set, free once the map exists.
**Prereq:** the Rev 3 detail-screen feature (`2026-08-31-maintenance-status-read-design.md`) —
this is its named D1/D3 fast-follow.

## 1. Overview

Show *which devices are in maintenance* on the device **list**, on both
platforms, fed by one bulk middleware cache — no per-device fan-out, no
client-side bulk calls.

## 2. Data path (settled + verified)

**Settled (Tom, verified against the lab):** `get-host-and-service-status`
with `groupFilterBy=category` and the category **NAME** (IDs → `"Bad input
parameter"` — the mistake that misled the old "no bulk API" claim) returns
ALL devices in the category, each row carrying `inMaintenance`. Verified:
"Network Infrastructure" → 10 rows, `US_24_G1_Keller` true among nine false.

`maint_window_api action=list` is strictly per-device (no `name` → "Missing
required information"; `name=*`/`%` → "Device not found"; `all=1` ignored).
It stays the **detail view's** source only.

### Verified this design round (live probes, 2026-09-02, lab 26.3.01)

**(a) Coverage — the per-category sums do NOT cover `devices/list`, and
that's correct.** Lab: `devices/list` = **41** devices (every row carries a
category id; none uncategorized); the union of all 15 category status
rosters = **38 unique** names. The 3 missing (`BHNM-A-SE01`, `BHNM-A-SE02`,
`bhnm-apns.hurrikap.org`) are all **`poll: 0, monitor: 0`** — unmonitored —
and have **no host-status rows even when queried directly by device name**
("No data available"). So the gap is inherent to the monitoring core, not
the iteration scheme: *no* grouping (site included) can surface them, and an
unmonitored device cannot be "in maintenance" (there is nothing to
suppress). **Fallback ruling: absent from the map = no state shown.** No
site iteration needed.

**Multi-category / dedupe:** no device appeared in more than one category
roster in the lab. The map is keyed by device name, so accidental multi-
membership dedupes structurally (the row is per-device; values can't
conflict).

**(b) Pagination:** `recordCount` and `recordStart` are honored on the
category-scoped call (`recordCount=3` → `displayRecords: 3` with
`totalRecords: 10`; `recordStart=3` returns the next page, no overlap). The
fetcher pages at `recordCount=500` per category until accumulated rows reach
`totalRecords`.

**(d) Version gate:** the map is built ONLY from rows that actually carry an
`inMaintenance` key. On BHNM < 26.3.01 no row carries it → the map is empty
→ the list shows nothing. Never a wrong state.

## 3. Middleware — `maintenance_cache` (twin of `threshold_cache`)

Mirror `threshold_cache.py` exactly in shape and lifecycle:

- `maintenance_cache.py`: `CachedMaintenance { names: set[str], last_updated }`
  — **only the in-maintenance device names** are stored and served. The UI
  never uses "known false", and false vs unknown render identically (no
  state), so a name list beats a full `{name: bool}` map on size and
  simplicity.
- One `asyncio.Task` per `cache_enabled` server. Cycle:
  1. `restful/category/list` (1 call)
  2. per category: `get-host-and-service-status`
     (`groupFilterBy=category`, `groupFilterValue=<name>`,
     `serviceFilter=host_only`, `recordCount=500`, paged via `recordStart`)
  3. collect `deviceName` where `inMaintenance is True` → replace the set
     atomically.
  Lab volume: 1 + 15 calls per cycle. Failures: keep the previous set,
  record telemetry like the other caches (a failed cycle must not blank the
  map and flap the UI).
- **(c) Cadence: its own task on the same per-server `cache_refresh_seconds`**
  (default 120 s, min 60, max 900) — identical to the incident/tactical/
  threshold pattern rather than literally piggybacking the threshold task
  (keeps the twin symmetry; a shared task would couple two unrelated fetch
  failure domains). **Amended 2026-09-02 (latency fix, Tom's ruling):** the
  map refreshes on a **fixed 60 s**, independent of `cache_refresh_seconds`
  — the map drives visible UI freshness and its cost is bounded (1 +
  #categories cheap calls/min/server).
  **Stated staleness (post-fix):** for viewers other than the creator, the
  wrench appears once the window opens + BHNM's ~85 s poll + ≤60 s map cycle
  + the client's ≤60–120 s refresh — typically **2–4 min after the window
  opens**. For the **creator**, both clients apply deliberate, openly
  documented local optimism (this is an open-source project — no hidden
  tricks): a successful create notes the device name locally and shows the
  wrench immediately, with an **8-minute expiry** (covers snap wait + poll +
  cycle) and early removal on cancel/close; the server set remains the truth
  everyone else sees. The detail screen (live merged read) stays the fresher
  truth; a row badge and the detail badge may disagree for one cache cycle.
- Lifecycle: `start_all()` on lifespan, `reload_server()` from
  `POST /internal/cache/reload` — wired exactly where `threshold_cache` is.

**Route (twin of `/api/v1/threshold-counts`):**

```
GET /api/v1/maintenance-map
  → { "cache_age_seconds": N, "in_maintenance": ["US_24_G1_Keller", ...] }
```

Auth `X-Proxy-Token`; server resolved like the threshold route. **Cold cache
→ `{"cache_age_seconds": null, "in_maintenance": []}`** — NO live
fall-through (the threshold route's fall-through is one CSV call; ours would
be 16+ upstream calls in-request). Empty list = list shows nothing = safe.

## 4. Clients

- **PWA:** `useMaintenanceMap()` — React Query, 60 s, same enablement rules
  as `useThresholds`; provides a `Set<string>`. `DeviceRow` gains the chosen
  marker when `set.has(device.name)`.
- **iOS:** `MaintenanceMapCache.shared` mirroring `ThresholdCache.shared`
  (fetch on list load + refresh cycle); `DeviceRowView` gains the marker.
- No client calls BHNM; nothing per-device.

## 5. UI options (canvas artboards; pick one)

All four are mocked on the REAL row anatomy (icon · name/ip/category·site ·
HEALTHY/ACK/WARNING/CRITICAL badge strip · incident ticker), both platforms,
and each option is shown BOTH ways for the maintenance+critical case
(blue overrides red vs coexist).

- **(a) MAINT joins the badge strip** as a sixth blue pill. Familiar spot —
  but the strip is *counts* and MAINT is a *state*; a countless pill breaks
  the strip's grammar, and six pills crowd small phones.
- **(b) Blue wrench glyph beside the name.** Smallest addition; state lives
  with the identity, counts stay pure alarm data.
- **(c) Dimmed row + blue left-edge stripe.** "Expected quiet" as visual
  de-emphasis; strongest scanning aid, but dimming a row that is ALSO
  critical mutes a real signal.
- **(d) List filter/section:** "In maintenance (N)" filter chip / section
  header. Best for many devices; invisible when you don't ask.

### Precedence — RECOMMENDATION: coexist (never suppress alarm colors)

On Device **Detail** the header badge is a single status slot, so
maintenance wins (Rev 3 ruling — honest headline). The **list** strip is
multi-signal by design: it shows count pills, not one status. Recommendation:
**maintenance adds context and never masks** — a device in maintenance AND
critical shows the blue marker *and* its red count. Rationale: the list is
what you scan to find problems; blue-overrides-red can hide an outage that
outlives its window behind "expected quiet" (and BHNM's close-all semantics
mean stale windows happen). The device-type icon keeps its status color.

**Recommended option: (b) wrench-by-name, coexist**, optionally adding
**(d)'s filter chip** in the same release (it's a pure client-side filter
over the same set — near-free). (c) is attractive but conflicts with
coexist; (a) breaks the strip's count grammar. Blue matches the Rev 3
Maintenance badge color family.

## 6. Out of scope

- Any change to the detail screen (Rev 3, already in-flight).
- Site/group screens' maintenance counts (future; same map can feed them).
- Serving "known false" vs "unknown" distinctions (UI renders both as
  nothing).

## 7. Test plan (when built)

- **Middleware:** map built only from rows with the field (absent → not in
  set); pagination loop (totalRecords > page size); failed cycle keeps the
  previous set; cold route returns empty + null age; reload restarts the
  task. Mock BHNM.
- **Clients:** marker renders for set members only; maintenance+critical
  renders per the picked precedence; empty/cold map renders no markers;
  filter chip counts (if (d) ships).
