# Host-status overlay for the device list (Wave B) — design

**Status:** STOP-AT-DESIGN — spec only. Thomas reviews before any build.
**Date:** 2026-09-03 (rev 4: reviewer amendments A+B — DOWN-only list instead of a full map; iOS error path clears the down set; "in maintenance AND DOWN" now captured. rev 3: rulings; rev 2: three-lens review; rev 1 assumed a 60 s iOS hold, which was wrong — see §5)
**Depends on:** middleware 2.11.0 (cache ON by default), PWA 0.13.1 / iOS 2.12.1 (Wave A: `monitor`-only fallback).
**Evidence:** `docs/evidence/2026-09-03-bhnm-host-status-down-row.md` — the first `"DOWN"` host row ever captured on this wire. Every mapping below is written against that row, not the docs.
**Amends:** `2026-09-02-maintenance-list-badges-design.md` §6 ("known false vs unknown" out of scope) — see §9. Its §3 name-list ruling is *kept*: this wave adds a second name list, not a map.

## 1. Problem

After Wave A the device-list icon says "monitored" (green) or "unmonitored" (grey). It cannot say DOWN: `devices/list` carries no state field at all on BHNM 26.3.01 (key union verified, no `alarm_color` / `status` / `up_status`). A powered-off host keeps its green icon; only the red incident chip beside it tells the truth. The middleware already fetches the truthful per-device `status` for every monitored device every cycle (`maintenance_cache._fetch_in_maintenance`, one paged `get-host-and-service-status` call per category) and discards it in the row loop.

## 2. Goal / non-goals

**Goal.** The list icon turns red for every device whose host row BHNM reports as `DOWN`. Everything else keeps Wave A semantics (green = monitored, grey = unmonitored) — which already renders every `UP` device correctly, so `UP` is not served at all.

**Non-goals.** Service-check state (`service_desc`), the detail screens (see §10), site/category counts, any change to how `in_maintenance` or `scheduled` are shaped or served.

## 3. Wire contract — `/api/v1/maintenance-map`

One **additive top-level key**, a DOWN-only name list. Nothing existing moves.

```json
{
  "cache_age_seconds": 37,
  "in_maintenance": ["raspi-054"],
  "scheduled": [],
  "host_down": ["raspi-050", "raspi-054"]
}
```

- `host_down` is the sorted list of `deviceName`s whose host row carries the literal `"DOWN"` — the same identity and the same shape as `in_maintenance`. `UP` rows are counted but not served: nothing on screen consumes an UP entry (the Wave A fallback already paints every monitored device green, so map-UP and absent-from-map are indistinguishable), and a full map would only buy its own costs — +200 KB/fetch/client at 10 k devices, and an UP entry overriding a list-derived `critical` on a server that emits `alarm_color`. A DOWN list is ~0 bytes on a healthy network and scales with outages, not fleet size.
- **Never nested inside `in_maintenance`.** Shipped iOS 2.12.x reads `raw["in_maintenance"] as? [String]` and `raw["scheduled"]` individually off `JSONSerialization` (`NetreoAPIService.swift`, `fetchMaintenanceMap`; no strict `Decodable`); shipped PWA 0.13.x reads `record.in_maintenance` / `record.scheduled` through `Array.isArray` and ignores other keys (`pwa/src/lib/api/maintenance.ts`, `fetchMaintenanceMap`). Both are additive-key tolerant by construction, and `host_down` is exactly the shape they already parse for `in_maintenance`. A nested object inside `in_maintenance` would be *dropped* by both (`as? [String]` fails → empty set; the `typeof === 'string'` filter drops it) — the shipped wrenches would vanish. The PWA parser test pins tolerance of a *missing* key; the build adds the mirror case (an *extra* sibling key leaves the active set unchanged) so the contract is pinned in both directions.
- Cold cache, unresolved server, or a server with `cache_enabled: false` → `"host_down": []` and `cache_age_seconds: null` — the same shape those cases already produce for the other keys.
- Docstrings updated in the build: the route docstring in `main.py` (`cached_maintenance_map`) — 2.11.0 already added `scheduled` to its Response block; the build adds `host_down` and rewrites the summary line ("Names of devices currently in maintenance…" → "Maintenance map + host status from the background cache"); the `maintenance_cache.py` module docstring ("Only names are stored…") and the `CachedMaintenance` docstring.

## 4. Middleware

`maintenance_cache.py`, twin-of-`threshold_cache` shape kept:

```python
@dataclass
class CachedMaintenance:
    """Per-server snapshot: in-maintenance names + names whose host row is DOWN."""
    names: set[str] = field(default_factory=set)
    down: set[str] = field(default_factory=set)      # deviceName with host status "DOWN"
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
        host_rows += 1                            # UP and DOWN both count as a seen host row
        if status == "DOWN":
            down.add(name)
    elif status is not None:
        ignored.add(str(status))                  # null is dropped silently; anything else is logged
```

- `_fetch_in_maintenance` returns `(names, down, host_rows)`; `_run_one_cycle` stores `names` and `down` in one atomic replace on success and prints `host_rows`. A failed cycle keeps the previous complete snapshot (unchanged semantics), so a stale map is stale *uniformly* and `cache_age_seconds` grows.
- **Unknown literal policy: drop the row.** A status that is not exactly `UP` or `DOWN` (a future `UNREACHABLE`, `PENDING`, lower-case, …) is neither counted nor listed, so the client falls back (green) for that device. `null` is dropped silently. Every other ignored literal is printed once per cycle **only when the set is non-empty** (`[MaintenanceCache:<id>] host rows: ignored literals {...}`); on a server that permanently emits a third literal that is one line per minute — accepted, it is exactly the signal that a new state exists.
- **On-call visibility:** the existing cycle print becomes `Cache updated: {len(names)} in maintenance, {host_rows} host rows, {len(down)} down`. A crawl that suddenly yields 0 host rows (permission change, filter change) is then visible in the log even though `host_down` would look healthy; `/api/v1/diagnostics` keeps reporting the `maintenance_map` feed (2.11.0) — no new feed.
- **No version gate on `status`.** `inMaintenance` exists only on ≥ 26.3.01; `status` is documented on host rows since API v1.0.9, so servers between the repo minimum 26.1.02 and 26.3.01 should get `host_down` without wrenches. *Documented, not wire-verified* — the category crawl has only ever run against 26.3.01. The existing version-gate test is extended to assert status is kept on rows without `inMaintenance`.
- Cost: zero extra BHNM calls — same crawl, same cadence, same `PAGE_SIZE`.
- Payload: one short string per DOWN host — `[]` on a healthy network, two names on the lab today. Scales with outages, not fleet size, so the names-only size ruling of the 09-02 spec still holds. (`middleware/Caddyfile` has no `encode` directive in either site block and `pwa/nginx.conf` no gzip; irrelevant at this size.)

## 5. Clients — per-row map-or-fallback

Rule, identical on both platforms:

```
rowStatus(device) =
  if device.name ∈ host_down (and the map was accepted at parse time, §5.0):
      down
  else:
      device.status  — as parsed from devices/list (on 26.3.01 that is the Wave A
                       monitor rung: monitor==1 → up, else unknown)
```

### 5.0 When the map is usable — decided **once, at parse time**, from `cache_age_seconds` alone

| `cache_age_seconds` in the response | meaning | verdict |
|---|---|---|
| `null` / absent | no successful cycle yet (cold), server unresolved, or `cache_enabled: false` — a real production value today | **not usable → `host_down` parsed as empty → fallback** (a naive `age > BOUND` treats null as fresh; it must not) |
| `> HOST_STATUS_MAX_AGE_S` | the middleware loop is stalled or dead | **not usable → empty → fallback** |
| otherwise | fresh enough | usable |

Parse-time, not per-render, on purpose. Rev 1 added the client's own hold to the age at every render; that is wrong on iOS, where the map is refreshed only from `DeviceListViewModel.loadDevices`, i.e. on pull-to-refresh or the AutoRefresh timer at the **user's `refresh_interval` (Settings slider 30–300 s, default 120 s)** — `MaintenanceMapCache.staleDuration = 60` is only a minimum gap inside `refresh()`. Adding a 120–300 s hold to a 180 s bound would have made every DOWN icon flap red → green → red on a perfectly healthy middleware. Deciding at parse time means:

- the hold between fetches is the client's *existing* refetch cadence — PWA 60 s (`useMaintenanceMap` `refetchInterval: 60_000`), iOS the user's `refresh_interval` — exactly the staleness the wrench already has and that shipped without complaint;
- a dead middleware is noticed at the next fetch on both platforms: PWA `fetchMaintenanceMap` already resolves to `empty` on any error (`cache_age_seconds` null → fallback within ≤ 60 s). **iOS (amendment B):** `MaintenanceMapCache.refresh()` today keeps the previous set on error; the build changes it to **clear `down` on any fetch error while keeping `names`** — a stale wrench costs a wrong "quiet" badge for one cycle, a stale red icon costs an on-call engineer a false outage, so the two are allowed to differ. With that, a hard-down middleware turns a red icon green at the next fetch attempt (≤ one `refresh_interval`), and a stalled-but-answering loop is caught by the 300 s bound at parse time. §7's promise — stale colour ≤ 300 s + one client hold — is therefore true on both platforms, by these two mechanisms;
- no `fetchedAt`/`secondsSinceFetch` plumbing on either platform (React Query's `dataUpdatedAt` and iOS's `lastFetched` exist already and are not needed for this).

**`HOST_STATUS_MAX_AGE_S = 300`**, a named constant on both clients. Wall-clock argument, from `_cache_loop`: the crawl is sequential, then `sleep(60)`; `last_updated` is stamped only after a *fully* successful cycle, and one category hitting `PROXY_TIMEOUT` (60 s) fails the whole cycle. So a single slow category costs 60 s (timeout) + 60 s (sleep) + one crawl before the next success: the age reaches ~120–150 s on **one** hiccup. A 180 s bound (3 × 60) would trip on one flaky category and flap colours; 300 s survives exactly one failed attempt and trips on two. Worst case after the middleware dies: a stale colour persists ≤ 300 s + one client hold (≤ 60 s PWA, ≤ `refresh_interval` iOS) — for a hint that sits beside the incident chip, that is the better trade than flapping.

A name in `host_down` wins over the fallback; a name absent from it is not "unknown", it is "use the fallback" — so unmonitored devices stay grey (fallback → `monitor == 0`) and every other monitored device stays green (fallback → `monitor == 1`), whether the map is usable or not.

### 5.1 PWA

- `pwa/src/lib/api/maintenance.ts`: `MaintenanceMap` gains `down: Set<string>`, parsed exactly like `active` (`Array.isArray` + string filter) but only when `cache_age_seconds` is a number `≤ HOST_STATUS_MAX_AGE_S`; otherwise `down` stays empty. `empty` carries `down: new Set()`.
- `pwa/src/features/devices/DeviceListScreen.tsx`, next to the existing `isActive`/`inMaint` helpers: `const rowStatus = (d: Device) => (maintMap?.down?.has(d.name) ? 'down' : d.status);` and `device={{ ...device, status: rowStatus(device) }}` on `DeviceRow`. The `?.` chain is load-bearing: `maintMap` is `undefined` before the first fetch, and every existing `useMaintenanceMap` mock returns `{ active, scheduled }` only (`pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` L114/L131, `MaintenanceCard.test.tsx`, `maintenanceLocal.test.ts`) — without the optional chain those suites throw. Covers page rows and search rows (same `displayDevices` path).
- `DeviceTypeIcon` already paints `'down'` as `#dc2626`; no change. The maintenance wrench coexists with a red icon (badges spec: the icon keeps its status colour, never masked).
- `useMaintenanceMap` unchanged (60 s refetch).

### 5.2 iOS

- `NetreoAPIService.fetchMaintenanceMap()` returns a third element `down: Set<String>` — `Set(raw["host_down"] as? [String] ?? [])`, the same line that reads `in_maintenance` — but only when `raw["cache_age_seconds"]` is an `Int` `≤ HOST_STATUS_MAX_AGE_S`; otherwise `[]`.
- `MaintenanceMapCache` (`ThresholdCache.swift`): `@Published private(set) var down: Set<String> = []`, assigned in `refresh()` beside `names` on success; **on fetch error `down = []` while `names` is kept** (amendment B, §5.0); cleared in `invalidate()` (2.12.1) so a server switch cannot carry colours across.
- `DeviceListView`: `DeviceRowView` gains `var hostDown: Bool = false`, passed as `maintenanceMap.down.contains(device.name)` at the single call site; `statusColor` returns `.red` when `hostDown`, else switches on `device.status` as today. `NetreoDevice.status` stays a `let`; the view already observes `MaintenanceMapCache`, so tints update when a new map is published.
- No new timer. Optional upgrade if the `refresh_interval` hold is judged too long for colours: a 60 s `.task` loop in `DeviceListView` calling `MaintenanceMapCache.shared.refresh(using:)` (which already no-ops under 60 s) — matches the PWA cadence at the cost of one more loop; not in this wave.

### 5.2a Client diagnostics screens (same files, same releases — reviewer ruling 2026-09-03)

Both screens list feeds from a hard-coded three-key array (`pwa/src/features/diagnostics/DiagnosticsScreen.tsx:88`, `ios/BeNeM/Views/DiagnosticsView.swift:115`); the middleware has served the fourth feed, `maintenance_map`, since 2.11.0. Wave B adds `maintenance_map` to both arrays (one line each, plus the divider condition on iOS) so an operator can see the crawl that now drives icon colour: cached / age / count / consecutive failures.

### 5.3 What the user sees

| device | host row | icon before | icon after |
|---|---|---|---|
| raspi-050 (off) | DOWN | green + red chip | **red** + red chip |
| raspi-054 | UP | green | green |
| Miele-T1 (Ping-Only) | UP | green | green |
| BHNM-A-SE01 (monitor=0) | none | grey | grey (fallback) |
| any device, middleware loop stalled (route still answers) | last snapshot, age growing | green | last colour until age > 300 s at the next fetch, then green (fallback) |
| any device, middleware dead (fetch fails) | — | green | PWA: green within ≤ 60 s (error → empty); iOS: green at the next fetch attempt (error clears `down`) |
| device in maintenance **and** DOWN | **verified 2026-09-03 on raspi-054** (evidence file addendum): `status: "DOWN"` unchanged, `inMaintenance: true`; incident 27729 stays OPEN | green + wrench + red chip | **red + wrench + red chip** — the coexist doctrine holds; BHNM suppresses notifications, it does not alter the incident |

## 6. Spec decisions

1. **SOFT vs HARD.** The captured DOWN row has `state_type: null`, as does every UP row on 26.3.01; the documented `stateType` does not exist on host rows. Decision: **`status` alone decides; `state_type` is not read.** If a future server populates it, a SOFT DOWN still renders DOWN — it is what BHNM reports as the host status and it already carries an `incidentID` (the captured row does), so the red chip and the red icon agree. Revisit only if a server is observed emitting `state_type` on host rows.
2. **Unknown literal → drop the row, never coerce** (§4). Only the exact literal `DOWN` reaches a client; the middleware logs everything that is neither `UP` nor `DOWN`.
3. **Identity = `deviceName`, exact and case-sensitive**, like the wrench join. The lab matched 38/38 (`deviceName == devices/list name`). A renamed device is absent for one middleware cycle (≤ 60 s) plus one client hold → fallback, typically under 2 min. `deviceIndex` matched `dev_index` 38/38 and is the upgrade key if names ever collide; not used now.
4. **Multi-category devices.** `devices/list` carries a single `category` id per device, so a device cannot be in two rosters; nothing to dedupe.
5. **Precedence over `devices/list` fields.** A name in `host_down` paints red regardless of what `devices/list` said — red is the most severe colour the icon has, so there is nothing to override wrongly. (The rev-3 concern — a map-`UP` entry overriding a list-derived `critical` — is dissolved by not serving `UP`.)

## 7. Honest scope statement

Outside the overlay — these keep Wave A semantics (green = monitored, grey = unmonitored) for as long as they hold:

- **Servers with `cache_enabled: false`** (opt-out since 2.11.0; previously the default). No crawl → no map → `host_down: []` with `cache_age_seconds: null`. On screen this is indistinguishable from a cold cache; only `/api/v1/diagnostics` (`server.cache_enabled`) tells them apart.
- **Devices in no category.** The crawl iterates categories; a device with no category has no roster and no row. None on the lab (every `devices/list` row carries a category id).
- **`monitor = 0` devices.** No host row on any grouping, even by device name (badges spec §a). Grey, correctly.
- **Cold cache** — first ≤ 60 s after a middleware start, `/internal/cache/reload`, **or any admin-portal server save** (`reload_server` pops the cache) — and a **stalled loop** (age > 300 s at the next fetch). Fallback until the map is usable again; operators will see DOWN devices go green for one cycle on every settings save.
- **Client hold.** Colours are as fresh as the client's map fetch: PWA ≤ 60 s; **iOS ≤ the user's `refresh_interval` (30–300 s, default 120 s)**, refreshed only with the list, never on "Load more". A DOWN that BHNM has already recorded shows red on iOS no sooner than that.
- **The icon is BHNM's opinion, not a reachability probe.** If BHNM marks a device DOWN for its own reasons — a parent/dependency down, a check that cannot reach it from the appliance while the device is fine from elsewhere — Wave B paints it red anyway, exactly as BHNM's own UI does; the row does not second-guess BHNM. (raspi-054 on 2026-09-03 is the live example: BHNM records "Ping CRITICAL: Packet Loss 100%" with no related alarms and no dependency data in the incident detail, so BHNM's stated cause is simply that it cannot reach the host.)
- **BHNM's own lag.** The icon is BHNM's host-check *opinion*: a real outage turns red no sooner than BHNM's check + retry interval (host rows share one `lastUpdateTime` bump; ≥ 3 min gaps measured) + ≤ 60 s crawl + the client hold. A stale red after recovery, or after the middleware stalls, lasts at most 300 s + one client hold (§5.0: parse-time bound; PWA error → empty; iOS error → `down` cleared).
- **Detail screens** — see §10.

## 8. Versions, order, tests

- **Middleware 2.12.0** — `middleware/VERSION`, `middleware/CHANGELOG.md` (`### Added` host_down; `### Changed` docstrings/log line), route + module docstrings (§3), pointer line at the top of the 09-02 spec (§9).
- **iOS 2.13.0 (35)** — `ios/scripts/bump_version.sh minor`, `ios/CHANGELOG.md` entry. Marketing version: red icons are user-visible.
- **PWA 0.14.0** — `pwa/package.json` + `pwa/package-lock.json` (there is no PWA changelog; the README version line is stale and left alone).
- **`shared/feature-spec.md`** (root CLAUDE.md: update before or alongside implementation) — the Device List "Icon status colour" bullet currently ends "…until the host_status overlay ships (iOS 2.12.1 / PWA 0.13.1)": rewrite to the map-or-fallback rule, the 300 s bound, and the versions; and the Maintenance Windows section's maintenance-map contract line gains `host_down`.
- Deploy in any order (additive key; new clients on the old middleware get no key → fallback). Recommended: middleware first so the first client release shows status on day one.
- **Middleware tests** (`middleware/tests/test_maintenance_map.py`): fetch lists `DOWN` names and not `UP` ones; unknown literal neither listed nor counted (and `null` dropped silently); nameless row skipped; route serves `host_down` — the two exact-dict asserts (`test_map_route_cold_cache_returns_empty_no_fallthrough`, `test_map_route_unresolvable_server_returns_empty`) gain `"host_down": []`; the three `names = run(...)` unpacks (`collects_true_names`, `version_gate`, `paginates`) become `names, _, _ = run(...)`; the version-gate test also asserts a `DOWN` row without `inMaintenance` is listed; a failed cycle keeps the previous `down` set. Canonical command: `python -m pytest tests` from `middleware/` (CLAUDE.md).
- **PWA tests**: `pwa/src/lib/api/maintenance.test.ts` — `host_down` names parsed / non-string entries dropped / absent key → empty / `cache_age_seconds` null → empty / 301 → empty / 299 → kept; plus the additive-contract mirror case (an unknown sibling key leaves `active` unchanged). `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` — raspi-050 icon background `rgb(220, 38, 38)` (jsdom serialises with spaces, cf. `DeviceTypeIcon.test.tsx`) when its name is in `down`; fallback colour when the mock has no `down` (the existing mocks) and when `down` is empty.
- **iOS**: no test target (feature-spec already schedules XCTest as next-wave first task). Verified means **on a device against the lab** (reviewer ruling 5). Checklist with raspi-050 off: red icon after the next list refresh (≤ `refresh_interval`); stop the middleware container → green at the next fetch attempt (error clears `down`); stall the loop but keep the route up → red until the reported age passes 300 s, then green; switch servers → no carry-over; raspi-054 in its window → red icon + wrench + red chip together.

## 9. Amendment to `2026-09-02-maintenance-list-badges-design.md`

§6 ("serving known-false vs unknown distinctions" out of scope) is **superseded for host state only**: the response now also carries the names whose host row is `DOWN`, because the UI *does* use that (icon colour). §3's ruling — a name list beats a full map on size and simplicity — is *reaffirmed*, not reversed: `host_down` is a second name list, `UP` is never served, and `in_maintenance` is unchanged. A one-line pointer to this spec is added at the top of the 09-02 spec when built.

## 10. Follow-ons (not in this wave)

- **Detail screens.** `DeviceDetailScreen.tsx` / `DeviceDetailViewModel.effectiveStatus` still show Wave A status; the "Current State" rows read raw `device.status`. Cheapest truthful source there is the per-device route `POST /api/proxy/maintenance/status` (`main.py`, `proxy_maintenance_status`), which already has the host row in hand (`statuses[0]`) and reads only `inMaintenance` from it — reading `["status"]` is the one-line change, and it works on cache-off servers; it breaks the three exact-dict asserts in `tests/test_maintenance.py` (L328/L360/L388). Separate spec.
- **iOS 60 s map cadence** (§5.2) if the `refresh_interval` hold proves too long for colours.
- **Verification rule (reviewer ruling 5):** iOS "verified" means run on a device against the lab, not a simulator build; the Wave B iOS commit may exist before that, but it does not push until it has been.
