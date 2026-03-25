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
- `DashboardView`: replace 3-card `HStack` with 2×2 `LazyVGrid`, add ANOMALIES card, apply φ proportions to `statBox`
- `TacticalViewModel`: add `anomalyTotals` computed property for Dashboard aggregation

**Out of scope:**
- `GroupListView` rows (H/S/T/A per group row) — separate future feature
- Filter logic changes in `TacticalViewModel.applyFilter`

## Design

### Golden Ratio Proportions (Variant C)

All four cards are equal size. φ governs internal dimensions:

| Property | Value | Derivation |
|---|---|---|
| Card corner radius | `13pt` | `8 × φ ≈ 12.9` |
| Card padding (V/H) | `13pt / 10pt` | `8 × φ ≈ 12.9` |
| Internal gap | `8pt` | base unit |
| Grid gap | `8pt` | base unit |
| Count font size | `21pt` | `13 × φ ≈ 21.0` |
| Title font size | `13pt` | base |
| Badge corner radius | `8pt` | base unit |

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

**Fallback:** All anomaly fields default to `0` if absent (e.g. "Not configured" groups in BHNM). No crash, no UI change — card shows all-green.

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
// pass to GroupSummary initialiser
```

Update `GroupSummary` initialiser call to include anomaly values.

### `BeNeM/ViewModels/TacticalViewModel.swift`

Add aggregation property for Dashboard:

```swift
var anomalyTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) { ... }
```

### `BeNeM/Views/DashboardView.swift`

1. Replace `heatMapSection`'s `HStack` with `LazyVGrid`.
2. Add fourth `statBox` for ANOMALIES using `anomalyTotals`.
3. Update `statBox` function with φ-derived dimensions (padding `13pt`, corner radius `13pt`, count font `21pt`, title font `13pt`, badge corner radius `8pt`).

## Error Handling

- API returns no anomaly fields → all counts default to 0, card renders normally
- API entirely unavailable → existing error handling in `TacticalViewModel` unchanged

## Testing

- Build and deploy to TomiPhone13 after implementation
- Verify ANOMALIES card appears with correct counts matching BHNM web UI
- Verify all-zero anomaly groups still render (grey zeros, no background)
- Verify filter button in GroupListView is unaffected
