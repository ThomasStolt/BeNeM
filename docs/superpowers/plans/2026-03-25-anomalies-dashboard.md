# Anomalies Dashboard Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fourth ANOMALIES stat card to the Dashboard, arranged in a 2×2 LazyVGrid with HOSTS/SERVICES/THRESHOLDS, using golden-ratio (φ ≈ 1.618) card proportions.

**Architecture:** The `GroupSummary` model gains anomaly fields; `NetreoAPIService` parses `anomaly_*_count` from the existing tactical overview response; `DashboardView` adds an `anomalyTotals` computed property, replaces the `HStack` with a `LazyVGrid`, and updates `statBox` dimensions. No other files change.

**Tech Stack:** Swift 5, SwiftUI, iOS 16+. No unit test target exists — verification is build + device deploy.

---

## Files Modified

| File | Change |
|---|---|
| `BeNeM/Models/GroupSummary.swift` | Add 5 anomaly stored properties + `totalAnomalies` |
| `BeNeM/Services/NetreoAPIService.swift` | Parse `anomaly_` prefix; expand `GroupSummary` init call |
| `BeNeM/Views/DashboardView.swift` | Add `anomalyTotals`; replace `HStack` with `LazyVGrid`; add ANOMALIES `statBox`; update `statBox` φ-dimensions |

---

## Task 1: Add anomaly fields to GroupSummary

**File:** `BeNeM/Models/GroupSummary.swift`

Current file ends at line 36 with `thresholdsRed` and `totalHosts`/`hasDevices`. We add five stored properties and one computed property.

- [ ] **Step 1: Add anomaly stored properties and computed property**

  In `BeNeM/Models/GroupSummary.swift`, replace the closing brace of the struct with:

  ```swift
      // T — Thresholds (only devices with threshold incidents)
      let thresholdsGreen: Int
      let thresholdsBlue: Int
      let thresholdsYellow: Int
      let thresholdsOrange: Int
      let thresholdsRed: Int
      // A — Anomalies (ML-based deviation detections, distinct from threshold alarms)
      let anomaliesGreen: Int
      let anomaliesBlue: Int
      let anomaliesYellow: Int
      let anomaliesOrange: Int
      let anomaliesRed: Int

      var totalHosts: Int { hostsGreen + hostsBlue + hostsYellow + hostsOrange + hostsRed }
      var totalAnomalies: Int { anomaliesGreen + anomaliesBlue + anomaliesYellow + anomaliesOrange + anomaliesRed }
      var hasDevices: Bool { totalHosts > 0 }
  }
  ```

  The exact old block to replace (lines 28–36):

  ```swift
      let thresholdsGreen: Int
      let thresholdsBlue: Int
      let thresholdsYellow: Int
      let thresholdsOrange: Int
      let thresholdsRed: Int

      var totalHosts: Int { hostsGreen + hostsBlue + hostsYellow + hostsOrange + hostsRed }
      var hasDevices: Bool { totalHosts > 0 }
  }
  ```

- [ ] **Step 2: Verify the project still builds (GroupSummary init will be broken — expected)**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
    -destination 'id=00008110-00167D41263A801E' \
    -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: **BUILD FAILED** with errors about missing `anomaliesGreen` etc. in `NetreoAPIService.swift`. That is correct — the model now requires the new fields and the API layer hasn't been updated yet.

- [ ] **Step 3: Commit**

  ```bash
  git add BeNeM/Models/GroupSummary.swift
  git commit -m "feat: add anomaly fields to GroupSummary model"
  ```

---

## Task 2: Parse anomaly_* fields in NetreoAPIService

**File:** `BeNeM/Services/NetreoAPIService.swift` (lines 480–496)

The `fetchTacticalOverviewSummaries` function already has a `statusCounts` helper and variables `h`, `s`, `t`. We add `a` for anomalies and expand the `GroupSummary` init call.

- [ ] **Step 1: Add anomaly parsing and expand the GroupSummary init**

  Replace the block at lines 484–496:

  ```swift
          let h = statusCounts(status, prefix: "host_")
          let s = statusCounts(status, prefix: "service_")
          let t = statusCounts(status, prefix: "threshold_")
          guard h.green + h.blue + h.yellow + h.orange + h.red > 0 else { continue }
          result.append(GroupSummary(
              id: name, name: name,
              hostsGreen:      h.green,  hostsBlue:      h.blue,  hostsYellow:      h.yellow,
              hostsOrange:     h.orange, hostsRed:       h.red,
              servicesGreen:   s.green,  servicesBlue:   s.blue,  servicesYellow:   s.yellow,
              servicesOrange:  s.orange, servicesRed:    s.red,
              thresholdsGreen: t.green,  thresholdsBlue: t.blue,  thresholdsYellow: t.yellow,
              thresholdsOrange: t.orange, thresholdsRed: t.red
          ))
  ```

  With:

  ```swift
          let h = statusCounts(status, prefix: "host_")
          let s = statusCounts(status, prefix: "service_")
          let t = statusCounts(status, prefix: "threshold_")
          let a = statusCounts(status, prefix: "anomaly_")
          guard h.green + h.blue + h.yellow + h.orange + h.red > 0 else { continue }
          result.append(GroupSummary(
              id: name, name: name,
              hostsGreen:       h.green,  hostsBlue:       h.blue,  hostsYellow:       h.yellow,
              hostsOrange:      h.orange, hostsRed:        h.red,
              servicesGreen:    s.green,  servicesBlue:    s.blue,  servicesYellow:    s.yellow,
              servicesOrange:   s.orange, servicesRed:     s.red,
              thresholdsGreen:  t.green,  thresholdsBlue:  t.blue,  thresholdsYellow:  t.yellow,
              thresholdsOrange: t.orange, thresholdsRed:   t.red,
              anomaliesGreen:   a.green,  anomaliesBlue:   a.blue,  anomaliesYellow:   a.yellow,
              anomaliesOrange:  a.orange, anomaliesRed:    a.red
          ))
  ```

  Note: `statusCounts` already uses `?? 0` for all fields, so missing `anomaly_*_count` fields in the API response automatically default to 0.

- [ ] **Step 2: Verify build succeeds**

  ```bash
  xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
    -destination 'id=00008110-00167D41263A801E' \
    -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: **BUILD SUCCEEDED** (model and service are now consistent).

- [ ] **Step 3: Commit**

  ```bash
  git add BeNeM/Services/NetreoAPIService.swift
  git commit -m "feat: parse anomaly_* counts in tactical overview response"
  ```

---

## Task 3: Update DashboardView — anomalyTotals + 2×2 grid + φ proportions

**File:** `BeNeM/Views/DashboardView.swift`

Four changes, all in one task since they are tightly coupled and must build together.

### Change 1 — Add `anomalyTotals` computed property (after line 146)

- [ ] **Step 1: Add anomalyTotals below thresholdTotals**

  After the `thresholdTotals` property (currently ending around line 146), insert:

  ```swift
      private var anomalyTotals: (green: Int, blue: Int, yellow: Int, orange: Int, red: Int) {
          let g = categoryViewModel.groups
          return (g.reduce(0) { $0 + $1.anomaliesGreen }, g.reduce(0) { $0 + $1.anomaliesBlue },
                  g.reduce(0) { $0 + $1.anomaliesYellow }, g.reduce(0) { $0 + $1.anomaliesOrange },
                  g.reduce(0) { $0 + $1.anomaliesRed })
      }
  ```

### Change 2 — Replace HStack with LazyVGrid in heatMapSection

- [ ] **Step 2: Replace the heatMapSection body**

  The current `heatMapSection` (lines 148–199) opens with `let h = hostTotals` bindings and closes with `return HStack(spacing: 10) { ... }`. Keep all `let` bindings; replace only the `HStack` wrapper and add the fourth card.

  Replace the entire `heatMapSection` computed property:

  ```swift
      private var heatMapSection: some View {
          let h = hostTotals
          let hostsTotal = h.green + h.blue + h.yellow + h.orange + h.red
          let s = serviceTotals
          let servicesTotal = s.green + s.blue + s.yellow + s.orange + s.red
          let t = thresholdTotals
          let thresholdsTotal = t.green + t.blue + t.yellow + t.orange + t.red
          let a = anomalyTotals
          let anomaliesTotal = a.green + a.blue + a.yellow + a.orange + a.red

          return LazyVGrid(
              columns: [GridItem(.flexible()), GridItem(.flexible())],
              spacing: 8
          ) {
              statBox(
                  title: "HOSTS",
                  count: hostsTotal,
                  isLoading: categoryViewModel.isLoading,
                  badges: [
                      (h.green,  hmGreen),
                      (h.blue,   hmBlue),
                      (h.yellow, hmYellow),
                      (h.orange, hmOrange),
                      (h.red,    hmRed),
                  ]
              )
              statBox(
                  title: "SERVICES",
                  count: servicesTotal,
                  isLoading: categoryViewModel.isLoading,
                  badges: [
                      (s.green,  hmGreen),
                      (s.blue,   hmBlue),
                      (s.yellow, hmYellow),
                      (s.orange, hmOrange),
                      (s.red,    hmRed),
                  ]
              )
              statBox(
                  title: "THRESHOLDS",
                  count: thresholdsTotal,
                  isLoading: categoryViewModel.isLoading,
                  badges: [
                      (t.green,  hmGreen),
                      (t.blue,   hmBlue),
                      (t.yellow, hmYellow),
                      (t.orange, hmOrange),
                      (t.red,    hmRed),
                  ]
              )
              statBox(
                  title: "ANOMALIES",
                  count: anomaliesTotal,
                  isLoading: categoryViewModel.isLoading,
                  badges: [
                      (a.green,  hmGreen),
                      (a.blue,   hmBlue),
                      (a.yellow, hmYellow),
                      (a.orange, hmOrange),
                      (a.red,    hmRed),
                  ]
              )
          }
      }
  ```

### Change 3 — Update statBox with φ-derived dimensions

- [ ] **Step 3: Update statBox function**

  The `statBox` function signature is unchanged. Update four values inside it:

  | Location | Old | New |
  |---|---|---|
  | Count font size (`.system(size: 18, ...)`) | `18` | `21` |
  | `.padding(.vertical, 10)` | `10` | `13` |
  | `.padding(.horizontal, 8)` | `8` | `10` |
  | `.cornerRadius(12)` (background) | `12` | `13` |
  | `.cornerRadius(12)` (overlay stroke) | `12` | `13` |
  | Badge `.clipShape(RoundedRectangle(cornerRadius: 3))` | `3` | `8` |
  | Badge `.overlay(RoundedRectangle(cornerRadius: 3)...)` | `3` | `8` |

  The updated `statBox` function in full:

  ```swift
      private func statBox(title: String, count: Int, isLoading: Bool,
                           badges: [(Int, Color)]) -> some View {
          VStack(spacing: 4) {
              Text(title)
                  .font(.system(size: 13, weight: .bold))
                  .foregroundColor(.secondary)

              if isLoading && count == 0 {
                  ProgressView().scaleEffect(0.7).frame(height: 22)
              } else {
                  ScrollingText(
                      text: "\(count)",
                      font: .system(size: 21, weight: .semibold, design: .rounded),
                      weight: .semibold,
                      color: .primary,
                      centerWhenFitting: true
                  )
                  .frame(height: 22)
              }

              // All badges in one row
              HStack(spacing: 3) {
                  ForEach(0..<badges.count, id: \.self) { idx in
                      let (n, color) = badges[idx]
                      if n > 0 {
                          ScrollingText(
                              text: "\(n)",
                              font: .system(size: 9, weight: .semibold),
                              weight: .semibold,
                              color: color == hmYellow ? Color.black : Color.white,
                              centerWhenFitting: true
                          )
                          .frame(maxWidth: .infinity)
                          .padding(.vertical, 2)
                          .background(color)
                          .clipShape(RoundedRectangle(cornerRadius: 8))
                      } else {
                          Text("0")
                              .font(.system(size: 9, weight: .regular))
                              .lineLimit(1)
                              .foregroundColor(Color(.systemGray3))
                              .frame(maxWidth: .infinity)
                              .padding(.vertical, 2)
                              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                      }
                  }
              }
          }
          .padding(.vertical, 13)
          .padding(.horizontal, 10)
          .frame(maxWidth: .infinity)
          .background(Color(.systemGray6))
          .cornerRadius(13)
          .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(.systemGray4), lineWidth: 0.5))
      }
  ```

- [ ] **Step 4: Build and deploy to TomiPhone13**

  ```bash
  ./build_and_deploy.sh
  ```

  Expected: **BUILD SUCCEEDED**, app installs on device.

- [ ] **Step 5: Verify on device**

  - Open the app → Dashboard tab
  - Confirm four cards appear in a 2×2 grid: HOSTS (top-left), SERVICES (top-right), THRESHOLDS (bottom-left), ANOMALIES (bottom-right)
  - Confirm ANOMALIES counts match the BHNM web UI Anomalies column aggregate
  - Confirm all-zero anomaly groups show grey zeros (no colored badges)
  - Confirm Incident Ticker, StatusCards, and GroupListView rows are unaffected

- [ ] **Step 6: Commit**

  ```bash
  git add BeNeM/Views/DashboardView.swift
  git commit -m "feat: add ANOMALIES card to Dashboard in 2x2 golden-ratio grid"
  ```
