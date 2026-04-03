# Device Header 3-Column Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the DeviceDetailView header from 2 columns (icon | info) to 3 columns (icon | info | latency mini-histogram) for at-a-glance latency trends.

**Architecture:** The header's `HStack` gains a third column containing a mini bar chart. It reuses the existing `latencyStates` data from `DeviceDetailViewModel` (already fetched at 24h). A new private `miniLatencyHistogram` subview downsamples to ~16 bars and renders via SwiftUI Charts `BarMark`. No new API calls, models, or files.

**Tech Stack:** SwiftUI, Swift Charts

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `BeNeM/Views/DeviceDetailView.swift` | Modify | Rewrite `headerSection()` to 3-column layout; add `miniLatencyHistogram` private subview |

No new files. No ViewModel changes needed — `fetchCard` already uses `.last24Hours` and `latencyStates` is already a computed property.

---

### Task 1: Rewrite headerSection to 3-column layout

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift:37-62`

- [ ] **Step 1: Replace headerSection with 3-column HStack**

Replace the current `headerSection` method (lines 37–62) with:

```swift
// MARK: - Header

private func headerSection(_ device: NetreoDevice) -> some View {
    HStack(spacing: 0) {
        // Left column — device type icon (compact)
        DeviceTypeIcon(
            typeClass: device.typeClass,
            size: 56,
            color: statusColor(device.status)
        )
        .frame(width: 70)

        // Middle column — name, IP, category, site
        VStack(alignment: .leading, spacing: 4) {
            MarqueeText(text: device.name, font: .headline, fontWeight: .bold, color: .primary)
            MarqueeText(text: device.ip, font: .subheadline, color: .secondary)
            MarqueeText(text: device.category, font: .subheadline, color: .secondary)
            MarqueeText(text: device.site, font: .subheadline, color: .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Right column — mini latency histogram (only if data available)
        if let firstLatency = viewModel.latencyStates.first, !firstLatency.data.isEmpty {
            miniLatencyHistogram(data: firstLatency.data)
                .frame(width: 100)
        }
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 12)
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
    .padding(.horizontal, 16)
    .padding(.top, 16)
}
```

Key changes from the current code:
- Icon `size` reduced from `90` to `56`, column pinned to `width: 70` instead of `maxWidth: .infinity`
- Info column spacing tightened from `6` to `4`, removed `.padding(.trailing, 16)` (the HStack padding handles it)
- Added `.padding(.horizontal, 12)` to the card for consistent inner padding
- Right column conditionally renders only when latency data exists — otherwise header naturally renders as 2-column

- [ ] **Step 2: Build and verify header renders without latency data**

Run:
```bash
./build_and_deploy.sh
```
Expected: Header displays with icon and info in a 2-column layout (latency not yet loaded). No crash, no layout overflow. Once latency data loads, the histogram column should appear (implemented in next task).

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: rewrite device header to 3-column layout"
```

---

### Task 2: Add miniLatencyHistogram subview

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift` (add new private method after `headerSection`)

- [ ] **Step 1: Add the miniLatencyHistogram method**

Add this method directly below `headerSection` in `DeviceDetailView.swift`:

```swift
private func miniLatencyHistogram(data: [PerformanceDataPoint]) -> some View {
    let bars = downsample(data, targetPoints: 16)
    let maxVal = bars.map(\.value).max() ?? 1
    return HStack(alignment: .bottom, spacing: 2) {
        ForEach(Array(bars.enumerated()), id: \.offset) { _, point in
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.2, green: 0.8, blue: 0.4))
                .frame(height: max(2, CGFloat(point.value / maxVal) * 40))
        }
    }
    .frame(height: 44)
}
```

This reuses the existing `downsample()` function with `targetPoints: 16` to get ~16 bars. Each bar height is proportional to the max value. Minimum bar height of 2pt so zero values are still visible. Single green color as agreed.

- [ ] **Step 2: Build and deploy to device**

Run:
```bash
./build_and_deploy.sh
```
Expected: After latency data loads, a small green bar histogram appears in the right column of the header card. The 3 columns should fit side by side on iPhone without clipping or overflow.

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: add mini latency histogram to device header"
```
