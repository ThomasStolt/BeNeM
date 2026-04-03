# Resilient Metric Cards — Design Spec

**Date:** 2026-04-03
**Status:** Approved

## Problem

On the Device Detail dashboard, metric cards (Latency, CPU, Memory, Disk) disappear when the API fails to return data or returns partial results. This causes the layout to shift unpredictably — any combination of metrics can vanish. Additionally, when the API returns NaN values, stats display as `nan%` instead of a meaningful fallback.

Users have no way to retry a failed metric without refreshing the entire page.

## Solution

Always render all four metric slots (Latency, CPU, Memory, Disk) regardless of data availability. When data is unavailable, show a tappable "No data available" placeholder with a brief loading spinner on retry. Filter NaN values from API responses at the fetch layer.

## Approach: Resilient Cards with Per-Metric Retry

### 1. ViewModel Changes (`DeviceDetailViewModel.swift`)

**New `retryCard(instanceKey:)` method:**
- Resets `hasBeenFetched` to `false`, clears `error` and `data`
- Calls existing `fetchCard(instanceKey:)` which re-fetches since `hasBeenFetched` is now false
- Guard against retrying while already loading

**NaN filtering in `fetchCard`:**
- After receiving time-series data from `apiService.fetchTimeSeries(...)`, filter out data points where `value.isNaN`
- This prevents NaN from reaching `MetricCardState.current`, `.average`, and `.max` computations

### 2. Latency Section View Changes (`DeviceDetailView.swift`)

**Current behavior:** `latencySection` filters states with `states.filter { !$0.data.isEmpty }` — metrics with no data are hidden entirely.

**New behavior:** Render all latency states. Each state shows one of three visual states:

| State | Condition | Display |
|-------|-----------|---------|
| Loading | `isLoading && !hasBeenFetched` | Spinner |
| Data loaded | `!data.isEmpty` | Chart + stats (existing `latencyChart`) |
| Error/empty | `hasBeenFetched && data.isEmpty` | Tappable placeholder |

**Placeholder layout:**
- Instance title (e.g. "Ping Latency") as section label
- `arrow.clockwise` SF Symbol + "No data available" text, centered
- Entire placeholder area is tap target
- Tap calls `viewModel.retryCard(instanceKey:)`, shows spinner while refetching

**Stats strip:** Not shown when data is empty — the placeholder replaces the entire card content.

### 3. Server Utilization Section View Changes (`DeviceDetailView.swift`)

Same pattern as latency. 

**Current behavior:** `serverUtilizationSection` filters to `group.states.filter { !$0.data.isEmpty }` and skips groups where all states are empty.

**New behavior:** Always render all three groups (CPU, Memory, Disk) regardless of data state.

**`serverUtilizationStates` computed property change:** Currently returns `nil` (via `compactMap`) when a category has no data. Change so that when instances exist but have no loaded data, the group is still returned — the view decides whether to show the chart or the retry placeholder.

**Per-group rendering:**

| State | Display |
|-------|---------|
| Loading | Spinner per card |
| Data loaded | `utilizationChart` (existing) |
| Error/empty | Tappable placeholder with category name (e.g. "CPU Utilization") |

**Stats strip (CURRENT/AVG/MAX):** Not shown when data is empty. NaN filter in `fetchCard` prevents `nan%` when data does exist.

### 4. MetricCard Changes (`DeviceDetailView.swift`)

The `MetricCard` struct (used in Performance section and Pinned Interfaces) already shows "No data available" when expanded with empty data, but it is not tappable.

**New `onRetry` closure parameter:**
```swift
MetricCard(
    state: ...,
    onTap: { ... },
    onRetry: { Task { await viewModel.retryCard(instanceKey: key) } }
)
```

**When expanded and `data.isEmpty && hasBeenFetched`:**
- Show `arrow.clockwise` icon + "No data available" as tappable area
- Tap calls `onRetry`
- Spinner shows in card header (existing loading indicator) while refetching

The entire empty-data area is the tap target — one tap retries the whole metric.

## Files Modified

| File | Changes |
|------|---------|
| `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Add `retryCard()`, NaN filter in `fetchCard()`, adjust `serverUtilizationStates` to preserve empty groups |
| `BeNeM/Views/DeviceDetailView.swift` | Update `latencySection`, `serverUtilizationSection`, and `MetricCard` for always-render + retry |

## Out of Scope

- Auto-retry with backoff
- Global "retry all" button
- Changes to the Performance section's collapsible category structure (only MetricCard within it)
