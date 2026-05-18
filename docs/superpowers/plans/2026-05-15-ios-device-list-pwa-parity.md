# iOS Device List — PWA Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align `DeviceListView` on iOS with the PWA device list — two-column row layout, compact 5-chip alarm badges (green/blue/yellow/orange/red), and a per-row scrolling incident ticker.

**Architecture:** All changes are confined to `ios/BeNeM/Views/DeviceListView.swift`. The data model structs (`DeviceAlarmCounts`) and summary function are replaced with a 5-color equivalent (`DeviceAlarmColorCounts` + `DeviceAlarmSummary`). A new `AlarmChipsView` renders the compact chips. `DeviceRowView` is rewritten to a two-column HStack that reuses the existing `MarqueeText.swift` for the ticker. No other files change.

**Tech Stack:** Swift 5.9, SwiftUI, `MarqueeText.swift` (existing), `ThresholdCache` (existing), `NetreoIncident` model (existing)

**Spec:** `docs/superpowers/specs/2026-05-15-ios-device-list-pwa-parity-design.md`

---

## File Map

| File | Change |
|---|---|
| `ios/BeNeM/Views/DeviceListView.swift` | Replace structs, function, `DeviceRowView`; add `AlarmChipsView` |
| `shared/feature-spec.md` | Update Device List feature entry |

---

## Task 1: Replace data model structs and summary function

**Files:**
- Modify: `ios/BeNeM/Views/DeviceListView.swift:1-32`

- [ ] **Step 1: Replace the top of `DeviceListView.swift` (lines 1–32)**

Delete everything from `import SwiftUI` through the closing `}` of `deviceAlarmCounts()` and replace with:

```swift
import SwiftUI

struct DeviceAlarmColorCounts {
    let green: Int   // healthy (threshold − active); -1 = threshold cache not yet loaded
    let blue: Int    // acknowledged + informational
    let yellow: Int  // warning severity (unack)
    let orange: Int  // major + minor severity (unack)
    let red: Int     // critical severity (unack)
}

struct DeviceAlarmSummary {
    let counts: DeviceAlarmColorCounts
    let activeSummaries: [String]  // incident summaries, critical-first (drives ticker)
}

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

- [ ] **Step 2: Verify the file compiles (data model only)**

```bash
cd /Users/tstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD FAILED` due to unresolved references to the old `DeviceAlarmCounts` type in `DeviceRowView` and the call site — that is expected at this stage and confirms the old type is gone. If you see an unexpected error unrelated to `DeviceAlarmCounts`, investigate before continuing.

---

## Task 2: Add `AlarmChipsView`

**Files:**
- Modify: `ios/BeNeM/Views/DeviceListView.swift` (append after the closing `}` of `DeviceListView`)

- [ ] **Step 1: Add `AlarmChipsView` after `DeviceListView`'s closing brace (before `DeviceRowView`)**

Insert the following struct between `DeviceListView` and `DeviceRowView`:

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

Note on `textColor`:
- All chips use white text when active — **except yellow**, which uses `Color(.label)` (near-black in light mode, white in dark mode) because white-on-yellow is unreadable. This matches the PWA's `text-slate-900` on `bg-yellow-400`.
- When `count == -1` (only possible for green, meaning threshold cache not yet loaded), the chip shows "—" in grey with no background fill.

---

## Task 3: Replace `DeviceRowView` and update the call site

**Files:**
- Modify: `ios/BeNeM/Views/DeviceListView.swift` (DeviceRowView struct — near the end of the file)
- Modify: `ios/BeNeM/Views/DeviceListView.swift` (call site inside `DeviceListView.body`)

Do both steps in one edit pass to avoid an intermediate build error.

- [ ] **Step 1: Replace `DeviceRowView`**

Find the struct starting with `struct DeviceRowView: View {` (near the end of the file). Delete the entire struct and replace with:

```swift
struct DeviceRowView: View {
    let device: NetreoDevice
    let alarmSummary: DeviceAlarmSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DeviceTypeIcon(typeClass: device.typeClass, size: 40, color: statusColor)

            // Left info column
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(device.ip)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: alarm chips + incident ticker
            VStack(alignment: .trailing, spacing: 4) {
                AlarmChipsView(counts: alarmSummary.counts)
                if alarmSummary.activeSummaries.isEmpty {
                    Spacer().frame(height: 14)
                } else {
                    MarqueeText(
                        text: alarmSummary.activeSummaries.joined(separator: " · "),
                        font: .system(size: 10),
                        color: .red
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var metaLine: String {
        [device.category, device.site].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}
```

- [ ] **Step 2: Update the call site in `DeviceListView.body`**

Find this block (inside `DeviceListView.body`, inside the `ForEach`):

```swift
DeviceRowView(
    device: device,
    alarmCounts: deviceAlarmCounts(for: device.name, incidents: incidentViewModel.incidents)
)
```

Replace with:

```swift
DeviceRowView(
    device: device,
    alarmSummary: deviceAlarmSummary(for: device.name, incidents: incidentViewModel.incidents)
)
```

- [ ] **Step 3: Build to confirm no errors**

```bash
cd /Users/tstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors. If you see `error:`, read the full error context with:

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -A 3 "error:"
```

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/Views/DeviceListView.swift
git commit -m "feat(ios): device list — PWA-parity row layout with 5-chip badges and incident ticker"
```

---

## Task 4: Verify on device/simulator

- [ ] **Step 1: Run on simulator**

```bash
cd /Users/tstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build 2>&1 | tail -5
```

Then open Simulator and launch BeNeM. Navigate to the **Devices** tab.

- [ ] **Step 2: Verify the visual checklist**

For each device row, confirm:
- [ ] Icon is 40px, status-coloured (green=up, red=down, amber=warning, blue=maintenance, grey=unknown)
- [ ] Left column: device name truncates to 1 line; IP in monospace; category · site on third line
- [ ] Right column: 5 chips (green / blue / yellow / orange / red) are right-aligned
- [ ] Chips with count > 0 show a filled coloured background with white text (yellow chip uses dark text)
- [ ] Chips with count == 0 show a grey outline with grey text
- [ ] Green chip shows "—" when threshold cache hasn't loaded yet (first few seconds after launch)
- [ ] Devices with active incidents show a red scrolling ticker below the chips
- [ ] Devices with no active incidents show a blank spacer (row height is consistent)
- [ ] "Load more" / search / pull-to-refresh all still work

- [ ] **Step 3: Deploy to iPhone 13 Pro Max**

```bash
cd /Users/tstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
./build_and_deploy.sh
```

Requires `build.local.sh` to be configured with the iPhone 13 Pro Max UDID. See `ios/CLAUDE.md` for setup. If the first install fails with error 3002, re-run the command — this is a known first-install quirk that resolves on retry.

---

## Task 5: Update feature-spec.md

**Files:**
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Find the Device List iOS-specific section**

Open `shared/feature-spec.md` and find the `### Feature: Device List` section (search for `Device List`). Update the `#### iOS-specific` block to reflect the new row layout:

Append the following lines under `#### iOS-specific` (after the existing bullets):

```markdown
- v2.8.0: Device list row redesigned to PWA-parity layout — icon (40px) + left info column (name/IP/category·site) + right column (5-chip alarm badges + incident ticker)
- Alarm chips use 5 raw severity colours: green (healthy/threshold-based) · blue (ack+informational) · yellow (warning) · orange (major+minor) · red (critical). Zero counts shown as grey outlined chips; green shows "—" when threshold cache not yet loaded.
- Per-row incident ticker reuses `MarqueeText.swift`; shows active incident summaries joined by " · ", sorted critical-first. Hidden (stable-height spacer) when no active incidents.
```

- [ ] **Step 2: Commit**

```bash
git add shared/feature-spec.md
git commit -m "docs: update feature-spec — iOS device list PWA-parity row layout v2.8.0"
```
