# iOS Device List — PWA Parity Design

**Date:** 2026-05-15
**Status:** approved

## Goal

Align `DeviceListView` on iOS with the PWA `DeviceListScreen` / `DeviceRow` layout. The result should be visually identical: two-column row layout, compact 5-chip alarm badges, and a scrolling incident ticker per row.

## Scope

- `ios/BeNeM/Views/DeviceListView.swift` — data model, summary function, `DeviceRowView`, new `AlarmChipsView`
- No changes to `DeviceDetailView`, pagination behaviour, search, toolbar, or `MarqueeText.swift`

## Data Model

Replace `DeviceAlarmCounts` (4 fields) with two new structs that mirror the PWA's `DeviceAlarmSummary`:

```swift
struct DeviceAlarmColorCounts {
    let green: Int   // healthy (threshold − active), -1 = threshold cache not yet loaded
    let blue: Int    // acknowledged + informational
    let yellow: Int  // warning severity (unack)
    let orange: Int  // major + minor severity (unack)
    let red: Int     // critical severity (unack)
}

struct DeviceAlarmSummary {
    let counts: DeviceAlarmColorCounts
    let activeSummaries: [String]  // incident summaries, critical-first (drives ticker)
}
```

### Severity mapping

| `IncidentStatus` | `IncidentSeverity` | Color bucket | In ticker? |
|---|---|---|---|
| `.acknowledged` | any | blue | No |
| `.active` | `.critical` | red | Yes |
| `.active` | `.major`, `.minor` | orange | Yes |
| `.active` | `.warning` | yellow | Yes |
| `.active` | `.informational` | blue | No |
| `.resolved`, `.closed` | any | skipped | No |

Green is computed from `ThresholdCache`: `max(0, thresholds − activeCount)`. Returns `-1` when the threshold cache has not yet loaded (same behaviour as today — shown as "—" in the chip).

`activeSummaries` is sorted critical-first using the `SEVERITY_ORDER = [.critical, .major, .minor, .warning, .informational]` ordering.

## Summary Function

Replace `deviceAlarmCounts(for:incidents:)` with `deviceAlarmSummary(for:incidents:)`:

```swift
@MainActor
private func deviceAlarmSummary(for deviceName: String, incidents: [NetreoIncident]) -> DeviceAlarmSummary {
    let deviceIncidents = incidents.filter {
        ($0.deviceName ?? "").caseInsensitiveCompare(deviceName) == .orderedSame
    }

    var blue = 0, yellow = 0, orange = 0, red = 0
    var activeIncidents: [NetreoIncident] = []

    for incident in deviceIncidents {
        if incident.status == .acknowledged {
            blue += 1
        } else if incident.status == .active {
            switch incident.severity {
            case .critical:       red += 1
            case .major, .minor:  orange += 1
            case .warning:        yellow += 1
            case .informational:  blue += 1
            }
            activeIncidents.append(incident)
        }
        // resolved / closed: skip
    }

    let thresholdsLoaded = !ThresholdCache.shared.counts.isEmpty
    let thresholds = ThresholdCache.shared.count(for: deviceName)
    let green = thresholdsLoaded ? max(0, thresholds - activeIncidents.count) : -1

    let severityOrder: [NetreoIncident.IncidentSeverity] = [.critical, .major, .minor, .warning, .informational]
    let sorted = activeIncidents.sorted {
        (severityOrder.firstIndex(of: $0.severity) ?? 99) < (severityOrder.firstIndex(of: $1.severity) ?? 99)
    }

    return DeviceAlarmSummary(
        counts: DeviceAlarmColorCounts(green: green, blue: blue, yellow: yellow, orange: orange, red: red),
        activeSummaries: sorted.map { $0.summary }
    )
}
```

## AlarmChipsView

New SwiftUI view, defined in `DeviceListView.swift` alongside `DeviceRowView`:

- HStack of 5 chips in order: green · blue · yellow · orange · red
- Each chip: 10pt semibold, `padding(.horizontal, 5).padding(.vertical, 2)`, `cornerRadius(3)`
- **Count > 0:** filled background (color), white text — **except yellow, which uses dark text** (`.primary` / near-black) because yellow-on-white is unreadable. Matches PWA (`text-slate-900` on `bg-yellow-400`).
- **Count == 0:** grey outline (`systemGray5`), grey text (`systemGray4`)
- **Count == -1 (green only):** grey outline, grey text, displays "—"

```swift
struct AlarmChipsView: View {
    let counts: DeviceAlarmColorCounts

    var body: some View {
        HStack(spacing: 3) {
            chip(count: counts.green,  color: .green,  textColor: .white)
            chip(count: counts.blue,   color: .blue,   textColor: .white)
            chip(count: counts.yellow, color: .yellow, textColor: Color(.label))
            chip(count: counts.orange, color: .orange, textColor: .white)
            chip(count: counts.red,    color: .red,    textColor: .white)
        }
    }

    private func chip(count: Int, color: Color, textColor: Color) -> some View {
        let active = count > 0
        let missing = count == -1
        return Text(missing ? "—" : "\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(active ? textColor : Color(.systemGray4))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(active ? color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(active ? Color.clear : Color(.systemGray5), lineWidth: 1)
                    )
            )
    }
}
```

## DeviceRowView

Replace the existing stacked layout with a two-column HStack:

```
HStack(spacing: 12) {
    DeviceTypeIcon(size: 40)          // unchanged, grown from 36 → 40 px
    VStack(left info, flex:1)         // name / IP / category·site
    VStack(right column, flex:1) {    // trailing aligned
        AlarmChipsView
        MarqueeText OR Spacer(14pt)
    }
}
.padding(.vertical, 6)
```

**Left column:** name (`.subheadline .semibold`, 1-line), IP (11pt monospaced), category · site (11pt, 1-line). Both left and right columns use `.frame(maxWidth: .infinity)`.

**Right column (trailing aligned):**
- Top: `AlarmChipsView(counts: summary.counts)`
- Bottom: `MarqueeText(text: tickerText, font: .system(size: 10), color: .red)` when `!summary.activeSummaries.isEmpty`; otherwise a 14pt height `Spacer` to keep row height stable.
- `tickerText = summary.activeSummaries.joined(separator: " · ")`

`MarqueeText` is the existing `MarqueeText.swift` component, reused without modification.

## Call Site

In `DeviceListView.body`, update the `DeviceRowView` initialiser:

```swift
DeviceRowView(
    device: device,
    alarmSummary: deviceAlarmSummary(for: device.name, incidents: incidentViewModel.incidents)
)
```

## What Does Not Change

- `DeviceDetailView` — out of scope
- `MarqueeText.swift` — used as-is
- `DeviceTypeIcon.swift` — used as-is (only `size` parameter changes: 36 → 40)
- Pagination ("Load more" append behaviour)
- Search, toolbar, auto-refresh ring
- `ThresholdCache` logic

## Files Changed

| File | Change |
|---|---|
| `ios/BeNeM/Views/DeviceListView.swift` | Replace structs, function, `DeviceRowView`; add `AlarmChipsView` |

## feature-spec.md Update

Update the **Device List** feature entry to note iOS now uses the 5-color compact chip layout and per-row incident ticker, matching PWA.
