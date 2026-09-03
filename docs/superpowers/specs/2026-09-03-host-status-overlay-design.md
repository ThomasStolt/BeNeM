# Host-status overlay for the device list (Wave B) — design

**Status:** STOP-AT-DESIGN — spec only. Thomas reviews before any build.
**Date:** 2026-09-03 (rev 2 after a three-lens adversarial review; rev 1 assumed a 60 s iOS hold, which was wrong — see §5)
**Depends on:** middleware 2.11.0 (cache ON by default), PWA 0.13.1 / iOS 2.12.1 (Wave A: `monitor`-only fallback).
**Evidence:** `docs/evidence/2026-09-03-bhnm-host-status-down-row.md` — the first `"DOWN"` host row ever captured on this wire. Every mapping below is written against that row, not the docs.
**Amends:** `2026-09-02-maintenance-list-badges-design.md` §3 (names-only map) and §6 ("known false vs unknown" out of scope) — see §9.

## 1. Problem

After Wave A the device-list icon says "monitored" (green) or "unmonitored" (grey). It cannot say DOWN: `devices/list` carries no state field at all on BHNM 26.3.01 (key union verified, no `alarm_color` / `status` / `up_status`). A powered-off host keeps its green icon; only the red incident chip beside it tells the truth. The middleware already fetches the truthful per-device `status` for every monitored device every cycle (`maintenance_cache._fetch_in_maintenance`, one paged `get-host-and-service-status` call per category) and discards it in the row loop.

## 2. Goal / non-goals

**Goal.** The list icon reflects BHNM's host state for every device the crawl covers: `UP` → up, `DOWN` → down (red). Everything the crawl does not cover keeps Wave A semantics.

**Non-goals.** Service-check state (`service_desc`), the detail screens (see §10), site/category counts, any change to how `in_maintenance` or `scheduled` are shaped or served.

## 3. Wire contract — `/api/v1/maintenance-map`

One **additive top-level key**. Nothing existing moves.

```json
{
  "cache_age_seconds": 37,
  "in_maintenance": ["Synology920"],
  "scheduled": [{"name": "raspi-054", "start_time": 1788430500, "end_time": 1788434100}],
  "host_status": {"raspi-050": "DOWN", "raspi-054": "DOWN", "UDM-Pro": "UP", "...": "UP"}
}
```

- `host_status` is `{deviceName: "UP" | "DOWN"}`, **raw BHNM literals**, exact case, keyed by the row's `deviceName` (the identity `in_maintenance`, `maint_window_api` and `devices/find` already use).
- **Never nested inside `in_maintenance`.** Shipped iOS 2.12.x reads `raw["in_maintenance"] as? [String]` and `raw["scheduled"]` individually off `JSONSerialization` (`NetreoAPIService.swift`, `fetchMaintenanceMap`; no strict `Decodable`); shipped PWA 0.13.x reads `record.in_maintenance` / `record.scheduled` through `Array.isArray` and ignores other keys (`pwa/src/lib/api/maintenance.ts`, `fetchMaintenanceMap`). Both are additive-key tolerant by construction. A nested object inside `in_maintenance` would be *dropped* by both (`as? [String]` fails → empty set; the `typeof === 'string'` filter drops it) — the shipped wrenches would vanish. The PWA parser test pins tolerance of a *missing* key; the build adds the mirror case (an *extra* sibling key leaves the active set unchanged) so the contract is pinned in both directions.
- Cold cache, unresolved server, or a server with `cache_enabled: false` → `"host_status": {}` and `cache_age_seconds: null` — the same shape those cases already produce for the other keys.
- Docstrings updated in the build: the route docstring in `main.py` (`cached_maintenance_map`) — 2.11.0 already added `scheduled` to its Response block; the build adds `host_status` and rewrites the summary line ("Names of devices currently in maintenance…" → "Maintenance map + host status from the background cache"); the `maintenance_cache.py` module docstring ("Only names are stored…") and the `CachedMaintenance` docstring.

## 4. Middleware

`maintenance_cache.py`, twin-of-`threshold_cache` shape kept:

```python
@dataclass
class CachedMaintenance:
    """Per-server snapshot: in-maintenance names + host UP/DOWN by name."""
    names: set[str] = field(default_factory=set)
    host_status: dict[str, str] = field(default_factory=dict)   # deviceName -> "UP" | "DOWN"
    last_updated: float = 0.0
```

Row loop (today `if row.get("inMaintenance") is True and row.get("deviceName"): names.add(...)`) becomes:

```python
HOST_STATUS_LITERALS = {"UP", "DOWN"}   # documented host_only domain (API v1.0.9), wire-confirmed 2026-09-03

for row in rows:
    name = row.get("deviceName")
    if not name:
        continue
    if row.get("inMaintenance") is True:          # 26.3.01 gate, unchanged
        names.add(name)
    status = row.get("status")
    if status in HOST_STATUS_LITERALS:            # exact literal or nothing — never coerce
        host_status[name] = status
    elif status is not None:
        ignored.add(str(status))                  # null is dropped silently; anything else is logged
```

- `_fetch_in_maintenance` returns `(names, host_status)`; `_run_one_cycle` stores both in one atomic replace on success. A failed cycle keeps the previous complete snapshot (unchanged semantics), so a stale map is stale *uniformly* and `cache_age_seconds` grows.
- **Unknown literal policy: drop the row.** A status that is not exactly `UP` or `DOWN` (a future `UNREACHABLE`, `PENDING`, lower-case, …) is not stored, so the client falls back for that device. `null` is dropped silently. Every other ignored literal is printed once per cycle **only when the set is non-empty** (`[MaintenanceCache:<id>] host_status: ignored literals {...}`); on a server that permanently emits a third literal that is one line per minute — accepted, it is exactly the signal that a new state exists.
- **On-call visibility:** the existing cycle print becomes `Cache updated: {len(names)} in maintenance, {len(host_status)} host rows`. A crawl that suddenly yields 0 host rows (permission change, filter change) is then visible in the log; `/api/v1/diagnostics` keeps reporting the `maintenance_map` feed (2.11.0) — no new feed.
- **No version gate on `status`.** `inMaintenance` exists only on ≥ 26.3.01; `status` is documented on host rows since API v1.0.9, so servers between the repo minimum 26.1.02 and 26.3.01 should get `host_status` without wrenches. *Documented, not wire-verified* — the category crawl has only ever run against 26.3.01. The existing version-gate test is extended to assert status is kept on rows without `inMaintenance`.
- Cost: zero extra BHNM calls — same crawl, same cadence, same `PAGE_SIZE`.
- Payload: lab 38 entries ≈ +0.7 KB per fetch. At 10 k devices ≈ +200 KB per fetch, per client, every 60 s (PWA) — the size argument the names-only ruling was made on. `middleware/Caddyfile` has no `encode` directive in either site block (the map is served under `{$DOMAIN}`), and `pwa/nginx.conf` has no gzip either; `encode gzip` on the middleware block is the mitigation if a large tenant ever appears, not part of this wave.

## 5. Clients — per-row map-or-fallback

Rule, identical on both platforms:

```
rowStatus(device) =
  if host_status[device.name] exists (the map was accepted at parse time, §5.0):
      "UP"   → up
      "DOWN" → down
  else:
      device.status  — as parsed from devices/list (on 26.3.01 that is the Wave A
                       monitor rung: monitor==1 → up, else unknown; see §6.5)
```

### 5.0 When the map is usable — decided **once, at parse time**, from `cache_age_seconds` alone

| `cache_age_seconds` in the response | meaning | verdict |
|---|---|---|
| `null` / absent | no successful cycle yet (cold), server unresolved, or `cache_enabled: false` — a real production value today | **not usable → `host_status` parsed as empty → fallback** (a naive `age > BOUND` treats null as fresh; it must not) |
| `> HOST_STATUS_MAX_AGE_S` | the middleware loop is stalled or dead | **not usable → empty → fallback** |
| otherwise | fresh enough | usable |

Parse-time, not per-render, on purpose. Rev 1 added the client's own hold to the age at every render; that is wrong on iOS, where the map is refreshed only from `DeviceListViewModel.loadDevices`, i.e. on pull-to-refresh or the AutoRefresh timer at the **user's `refresh_interval` (Settings slider 30–300 s, default 120 s)** — `MaintenanceMapCache.staleDuration = 60` is only a minimum gap inside `refresh()`. Adding a 120–300 s hold to a 180 s bound would have made every DOWN icon flap red → green → red on a perfectly healthy middleware. Deciding at parse time means:

- the hold between fetches is the client's *existing* refetch cadence — PWA 60 s (`useMaintenanceMap` `refetchInterval: 60_000`), iOS the user's `refresh_interval` — exactly the staleness the wrench already has and that shipped without complaint;
- a dead middleware is noticed at the next fetch: PWA `fetchMaintenanceMap` already resolves to `empty` on any error (`cache_age_seconds` null → fallback within ≤ 60 s); iOS `refresh()` keeps the previous set on error (so the bound is enforced at the next successful fetch, and a hard-down middleware leaves the last colours for one `refresh_interval`, then the fetch fails and the map stays as it was — see §7);
- no `fetchedAt`/`secondsSinceFetch` plumbing on either platform (React Query's `dataUpdatedAt` and iOS's `lastFetched` exist already and are not needed for this).

**`HOST_STATUS_MAX_AGE_S = 300`**, a named constant on both clients. Wall-clock argument, from `_cache_loop`: the crawl is sequential, then `sleep(60)`; `last_updated` is stamped only after a *fully* successful cycle, and one category hitting `PROXY_TIMEOUT` (60 s) fails the whole cycle. So a single slow category costs 60 s (timeout) + 60 s (sleep) + one crawl before the next success: the age reaches ~120–150 s on **one** hiccup. A 180 s bound (3 × 60) would trip on one flaky category and flap colours; 300 s survives exactly one failed attempt and trips on two. Worst case after the middleware dies: a stale colour persists ≤ 300 s + one client hold (≤ 60 s PWA, ≤ `refresh_interval` iOS) — for a hint that sits beside the incident chip, that is the better trade than flapping.

Map hit wins over the fallback **only for the two known literals**; a device absent from the map is not "unknown", it is "use the fallback" — so unmonitored devices stay grey (fallback → `monitor == 0`) and monitored devices on an unusable map stay green (fallback → `monitor == 1`).

### 5.1 PWA

- `pwa/src/lib/api/maintenance.ts`: `MaintenanceMap` gains `hostStatus: Map<string, 'up' | 'down'>`. Parse: read `cache_age_seconds` (number or null); if null or `> HOST_STATUS_MAX_AGE_S` leave `hostStatus` empty; else read `host_status` (object only, string values only, exact `"UP"` / `"DOWN"`, anything else skipped). `empty` carries `hostStatus: new Map()`.
- `pwa/src/features/devices/DeviceListScreen.tsx`, next to the existing `isActive`/`inMaint` helpers: `const rowStatus = (d: Device) => maintMap?.hostStatus?.get(d.name) ?? d.status;` and `device={{ ...device, status: rowStatus(device) }}` on `DeviceRow`. The `?.` chain is load-bearing: `maintMap` is `undefined` before the first fetch, and every existing `useMaintenanceMap` mock returns `{ active, scheduled }` only (`pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` L114/L131, `MaintenanceCard.test.tsx`, `maintenanceLocal.test.ts`) — without the optional chain those suites throw. Covers page rows and search rows (same `displayDevices` path).
- `DeviceTypeIcon` already paints `'down'` as `#dc2626`; no change. The maintenance wrench coexists with a red icon (badges spec: the icon keeps its status colour, never masked).
- `useMaintenanceMap` unchanged (60 s refetch).

### 5.2 iOS

- `NetreoAPIService.fetchMaintenanceMap()` returns a third element `hostStatus: [String: NetreoDevice.DeviceStatus]`, built only when `raw["cache_age_seconds"]` is an `Int` `≤ HOST_STATUS_MAX_AGE_S`; mapping `"UP"` → `.up`, `"DOWN"` → `.down`, anything else skipped.
- `MaintenanceMapCache` (`ThresholdCache.swift`): `@Published private(set) var hostStatus: [String: NetreoDevice.DeviceStatus] = [:]`, assigned in `refresh()` beside `names`; cleared in `invalidate()` (2.12.1) so a server switch cannot carry colours across.
- `DeviceListView`: `DeviceRowView` gains `var hostStatus: NetreoDevice.DeviceStatus? = nil`, passed from `maintenanceMap.hostStatus[device.name]` at the single call site; `statusColor` switches on `hostStatus ?? device.status`. `NetreoDevice.status` stays a `let`; the view already observes `MaintenanceMapCache`, so tints update when a new map is published.
- No new timer. Optional upgrade if the `refresh_interval` hold is judged too long for colours: a 60 s `.task` loop in `DeviceListView` calling `MaintenanceMapCache.shared.refresh(using:)` (which already no-ops under 60 s) — matches the PWA cadence at the cost of one more loop; not in this wave.

### 5.3 What the user sees

| device | host row | icon before | icon after |
|---|---|---|---|
| raspi-050 (off) | DOWN | green + red chip | **red** + red chip |
| raspi-054 | UP | green | green |
| Miele-T1 (Ping-Only) | UP | green | green |
| BHNM-A-SE01 (monitor=0) | none | grey | grey (fallback) |
| any device, middleware loop stalled | last snapshot, age growing | green | last colour until age > 300 s at the next fetch, then green (fallback) |
| device in maintenance **and** DOWN | *expected* DOWN + inMaintenance — **unverified**, every captured row has `inMaintenance: false` | green + wrench | red + wrench if BHNM keeps `DOWN`; green + wrench (drop-the-row) if it emits anything else — safe either way, see §8 checklist |

## 6. Spec decisions

1. **SOFT vs HARD.** The captured DOWN row has `state_type: null`, as does every UP row on 26.3.01; the documented `stateType` does not exist on host rows. Decision: **`status` alone decides; `state_type` is not read.** If a future server populates it, a SOFT DOWN still renders DOWN — it is what BHNM reports as the host status and it already carries an `incidentID` (the captured row does), so the red chip and the red icon agree. Revisit only if a server is observed emitting `state_type` on host rows.
2. **Unknown literal → drop the row, never coerce** (§4). The client never sees it; the middleware logs it.
3. **Identity = `deviceName`, exact and case-sensitive**, like the wrench join. The lab matched 38/38 (`deviceName == devices/list name`). A renamed device is absent for one middleware cycle (≤ 60 s) plus one client hold → fallback, typically under 2 min. `deviceIndex` matched `dev_index` 38/38 and is the upgrade key if names ever collide; not used now.
4. **Multi-category devices.** `devices/list` carries a single `category` id per device, so a device cannot be in two rosters; nothing to dedupe.
5. **Precedence over `devices/list` fields.** If a server ever emits `alarm_color`/`status`/`up_status` on `devices/list` again, the map still wins for the two literals — a host-`UP` entry would override a `critical` icon derived from `alarm_color`. Accepted and listed in §7: no server this code has met since 26.3.01 emits those fields, the incident chips still carry the red count, and restricting the override to `device.status ∈ {up, unknown}` is a one-condition change if such a server appears.

## 7. Honest scope statement

Outside the overlay — these keep Wave A semantics (green = monitored, grey = unmonitored) for as long as they hold:

- **Servers with `cache_enabled: false`** (opt-out since 2.11.0; previously the default). No crawl → no map → `host_status: {}` with `cache_age_seconds: null`. On screen this is indistinguishable from a cold cache; only `/api/v1/diagnostics` (`server.cache_enabled`) tells them apart.
- **Devices in no category.** The crawl iterates categories; a device with no category has no roster and no row. None on the lab (every `devices/list` row carries a category id).
- **`monitor = 0` devices.** No host row on any grouping, even by device name (badges spec §a). Grey, correctly.
- **Cold cache** — first ≤ 60 s after a middleware start, `/internal/cache/reload`, **or any admin-portal server save** (`reload_server` pops the cache) — and a **stalled loop** (age > 300 s at the next fetch). Fallback until the map is usable again; operators will see DOWN devices go green for one cycle on every settings save.
- **Client hold.** Colours are as fresh as the client's map fetch: PWA ≤ 60 s; **iOS ≤ the user's `refresh_interval` (30–300 s, default 120 s)**, refreshed only with the list, never on "Load more". A DOWN that BHNM has already recorded shows red on iOS no sooner than that.
- **BHNM's own lag.** The icon is BHNM's host-check *opinion*: a real outage turns red no sooner than BHNM's check + retry interval (host rows share one `lastUpdateTime` bump; ≥ 3 min gaps measured) + ≤ 60 s crawl + the client hold. A stale colour after recovery, or after the middleware dies, lasts at most 300 s + one client hold.
- **Servers emitting `alarm_color`/`status`/`up_status` on `devices/list`** (none seen): map `UP` overrides a list-derived `critical` icon (§6.5).
- **Detail screens** — see §10.

## 8. Versions, order, tests

- **Middleware 2.12.0** — `middleware/VERSION`, `middleware/CHANGELOG.md` (`### Added` host_status; `### Changed` docstrings/log line), route + module docstrings (§3), pointer line at the top of the 09-02 spec (§9).
- **iOS 2.13.0 (35)** — `ios/scripts/bump_version.sh minor`, `ios/CHANGELOG.md` entry. Marketing version: red icons are user-visible.
- **PWA 0.14.0** — `pwa/package.json` + `pwa/package-lock.json` (there is no PWA changelog; the README version line is stale and left alone).
- **`shared/feature-spec.md`** (root CLAUDE.md: update before or alongside implementation) — the Device List "Icon status colour" bullet currently ends "…until the host_status overlay ships (iOS 2.12.1 / PWA 0.13.1)": rewrite to the map-or-fallback rule, the 300 s bound, and the versions; and the Maintenance Windows section's maintenance-map contract line gains `host_status`.
- Deploy in any order (additive key; new clients on the old middleware get no key → fallback). Recommended: middleware first so the first client release shows status on day one.
- **Middleware tests** (`middleware/tests/test_maintenance_map.py`): fetch keeps `UP`/`DOWN` per name; unknown literal dropped (and `null` dropped silently); nameless row skipped; route serves `host_status` — the two exact-dict asserts (`test_map_route_cold_cache_returns_empty_no_fallthrough`, `test_map_route_unresolvable_server_returns_empty`) gain `"host_status": {}`; the three `names = run(...)` unpacks (`collects_true_names`, `version_gate`, `paginates`) become `names, _ = run(...)`; the version-gate test also asserts status is kept on rows without `inMaintenance`; a failed cycle keeps the previous `host_status`.
- **PWA tests**: `pwa/src/lib/api/maintenance.test.ts` — `UP` / `DOWN` / odd literal / absent key / `cache_age_seconds` null → empty / `cache_age_seconds` 301 → empty / 299 → kept; plus the additive-contract mirror case (an unknown sibling key leaves `active` unchanged). `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` — raspi-050 icon background `rgb(220, 38, 38)` (jsdom serialises with spaces, cf. `DeviceTypeIcon.test.tsx`) with map DOWN; fallback colour when the mock has no `hostStatus` (the existing mocks) and when `hostStatus` is empty.
- **iOS**: no test target (feature-spec already schedules XCTest as next-wave first task). Manual checklist against the lab with raspi-050 off: red icon after the next list refresh (≤ `refresh_interval`); stop the middleware loop → still red until the next successful fetch reports age > 300 s, then green; switch servers → no carry-over; **put raspi-050 into a maintenance window while it is off, capture the host row, append it to the evidence file** (settles the unverified "in maintenance and DOWN" row in §5.3).

## 9. Amendment to `2026-09-02-maintenance-list-badges-design.md`

§3 ("only the in-maintenance device names are stored … a name list beats a full map on size and simplicity") and §6 ("serving known-false vs unknown distinctions" out of scope) are **superseded for host status only**: the map now also carries per-device `UP`/`DOWN` because the UI *does* use it (icon colour). `in_maintenance` itself stays a name list — "known false" for maintenance is still not served. A one-line pointer to this spec is added at the top of the 09-02 spec when built.

## 10. Follow-ons (not in this wave)

- **Detail screens.** `DeviceDetailScreen.tsx` / `DeviceDetailViewModel.effectiveStatus` still show Wave A status; the "Current State" rows read raw `device.status`. Cheapest truthful source there is the per-device route `POST /api/proxy/maintenance/status` (`main.py`, `proxy_maintenance_status`), which already has the host row in hand (`statuses[0]`) and reads only `inMaintenance` from it — reading `["status"]` is the one-line change, and it works on cache-off servers; it breaks the three exact-dict asserts in `tests/test_maintenance.py` (L328/L360/L388). Separate spec.
- **Client diagnostics screens** list three feeds by hard-coded key (`DiagnosticsScreen.tsx`, `DiagnosticsView.swift`); adding `maintenance_map` is a one-line change each, filed separately.
- **iOS 60 s map cadence** (§5.2) if the `refresh_interval` hold proves too long for colours.
