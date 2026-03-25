# Anomalies Dashboard Card — Design Spec

**Date:** 2026-03-25
**Status:** Approved

## Background

BHNM's Tactical Overview exposes four monitoring dimensions: Hosts, Services, Thresholds, and **Anomalies**. Anomalies are ML-based deviation detections (distinct from threshold alarms) and are visible as a separate column in the BHNM web UI. The BeNeM app currently shows only H/S/T on the Dashboard and ignores anomaly data entirely.

The user observed discrepancies: the app shows 1 yellow Threshold, while the BHNM web UI shows 2 additional yellow anomalies and 2 red anomalies. These are separate concepts and must be surfaced separately.

## Goal

Add a fourth **ANOMALIES** stat card to the Dashboard's `heatMapSection`, arranged in a 2×2 grid with the existing three cards. Apply golden-ratio (φ ≈ 1.618) proportions to the card internals for visual harmony.

## Scope

**In scope:**
- `GroupSummary` model: add anomaly count fields
- `NetreoAPIService`: parse `anomaly_*_count` fields from tactical overview response
- `DashboardView`: replace 3-card `HStack` with 2×2 `LazyVGrid`, add ANOMALIES card, apply φ proportions to `statBox`, add `anomalyTotals` private computed property
- `GroupListView`: **no changes** — the new `GroupSummary` anomaly fields are simply unused by this view for now

**Out of scope:**
- Per-row anomaly columns in `GroupListView` — separate future feature
- `TacticalViewModel`: no changes needed

## Design

### Golden Ratio Proportions (Variant C)

All four cards are equal size. φ governs internal dimensions:

| Property | Old value | New value | Derivation |
|---|---|---|---|
| Card padding vertical | `10pt` | `13pt` | `8 × φ ≈ 12.9` |
| Card padding horizontal | `8pt` | `10pt` | base |
| Card corner radius | `12pt` | `13pt` | `8 × φ ≈ 12.9` |
| Count font size | `18pt` | `21pt` | `13 × φ ≈ 21.0` |
| Title font size | `13pt` | `13pt` | unchanged (base) |
| Grid gap | `10pt` | `8pt` | base unit |
| Badge corner radius | `3pt` | `8pt` | base unit |

### 2×2 Grid Layout

```
┌─────────────┬─────────────┐
│   HOSTS     │  SERVICES   │
│     24      │    145      │
│ ■ □ □ □ □  │ ■ ■ ■ □ ■  │
├─────────────┼─────────────┤
│ THRESHOLDS  │  ANOMALIES  │
│     386     │     52      │
│ ■ □ ■ ■ □  │ ■ □ ■ □ ■  │
└─────────────┴─────────────┘
```

Implemented as `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8)`.

### API Field Mapping

The `restful/tactical-overview/data` endpoint returns a `Status` dict per group. Existing fields already parsed:

- `host_ok_count`, `host_ack_count`, `host_warn_count`, `host_un_count`, `host_crit_count`
- `service_*_count`, `threshold_*_count`

New fields to parse:

- `anomaly_ok_count` → Green
- `anomaly_ack_count` → Blue
- `anomaly_warn_count` → Yellow
- `anomaly_un_count` → Orange
- `anomaly_crit_count` → Red

**Fallback:** All anomaly fields default to `0` if absent (e.g. "Not configured" groups in BHNM). No crash, no UI change — card shows all-green zeros.

### Guard Clause in `fetchTacticalOverviewSummaries`

The current parsing loop contains:

```swift
guard h.green + h.blue + h.yellow + h.orange + h.red > 0 else { continue }
```

This drops groups with all-zero host counts. Since anomaly data is secondary (anomaly-only groups without any hosts are extremely unlikely in practice), this guard is **intentionally preserved unchanged**. If BHNM ever returns such groups they will be invisible in the app — acceptable for now.

## Files Changed

### `BeNeM/Models/GroupSummary.swift`

Add five new stored properties after `thresholdsRed`:

```swift
let anomaliesGreen: Int
let anomaliesBlue: Int
let anomaliesYellow: Int
let anomaliesOrange: Int
let anomaliesRed: Int
```

Add computed property:
```swift
var totalAnomalies: Int { anomaliesGreen + anomaliesBlue + anomaliesYellow + anomaliesOrange + anomaliesRed }
```

### `BeNeM/Services/NetreoAPIService.swift`

In `fetchTacticalOverviewSummaries`, add anomaly parsing alongside existing H/S/T:

```swift
let a = statusCounts(status, prefix: "anomaly_")
```

Update `GroupSummary` initialiser call to include all five anomaly values (defaulting `anomaly_*` to 0 via the existing `?? 0` pattern in `statusCounts`).

### `BeNeM/Views/DashboardView.swift`

Four changes:

1. **Add `anomalyTotals`** as a `private var` computed property on `DashboardView`, directly below the existing `thresholdTotals` property. Same pattern as `hostTotals`, `serviceTotals`, `thresholdTotals` — all three live on `DashboardView`, not on `TacticalViewModel`.

2. **Replace `heatMapSection` body**: The current implementation opens with `let h = hostTotals` bindings and closes with an explicit `return HStack(...)`. When replacing the `HStack` with a `LazyVGrid`, the `return` keyword must be kept (or the leading `let` bindings moved inline) to avoid a compile error. The safest approach is to keep all `let` bindings and change only `HStack` → `LazyVGrid`.

3. **Add the ANOMALIES `statBox` call** as the fourth item in the grid, using `anomalyTotals`.

4. **Update `statBox` function** with the new φ-derived values per the table above (padding, corner radius, count font size, badge corner radius).

### `BeNeM/Views/GroupListView.swift`

**No changes.** `GroupListView` iterates `GroupSummary` for H/S/T display only. The new anomaly fields on `GroupSummary` are simply unused here — intentional, out of scope.

## Error Handling

- API returns no anomaly fields → all counts default to 0, card renders normally
- API entirely unavailable → existing error handling in `TacticalViewModel` unchanged

## Testing

- Build and deploy to TomiPhone13 after implementation
- Verify ANOMALIES card appears in bottom-right of 2×2 grid
- Verify counts match BHNM web UI Anomalies column (aggregate across all categories)
- Verify all-zero anomaly groups render correctly (grey zeros, no background)
- Verify GroupListView, Ticker, and StatusCards are unaffected
