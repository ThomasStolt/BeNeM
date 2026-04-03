# Resilient Metric Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Always show Latency, CPU, Memory, and Disk metric cards on the Device Detail dashboard, even when data fetch fails, with tap-to-retry on failed metrics.

**Architecture:** Add a `retryCard` method to `DeviceDetailViewModel` and NaN filtering in `fetchCard`. Update view sections to always render metric slots with a tappable "No data available" placeholder when data is missing. Add an `onRetry` closure to `MetricCard`.

**Tech Stack:** Swift, SwiftUI, Swift Charts

**Spec:** `docs/superpowers/specs/2026-04-03-resilient-metric-cards-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Modify | Add `retryCard()`, NaN filter in `fetchCard()`, adjust `serverUtilizationStates` |
| `BeNeM/Views/DeviceDetailView.swift` | Modify | Update `latencySection`, `serverUtilizationSection`, `MetricCard` |

---

### Task 1: Add NaN filtering to `fetchCard`

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift:300-317`

- [ ] **Step 1: Add NaN filter to fetchCard success path**

In `DeviceDetailViewModel.swift`, in the `fetchCard` method, change line 309:

```swift
// Before:
cardStates[instanceKey]?.data = data

// After:
cardStates[instanceKey]?.data = data.filter { !$0.value.isNaN }
```

- [ ] **Step 2: Add NaN filter to tapCard success path**

In the same file, in the `tapCard` method, change line 336:

```swift
// Before:
cardStates[instanceKey]?.data = data

// After:
cardStates[instanceKey]?.data = data.filter { !$0.value.isNaN }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "fix: filter NaN values from performance time-series data"
```

---

### Task 2: Add `retryCard` method to ViewModel

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift:297-317`

- [ ] **Step 1: Add retryCard method**

In `DeviceDetailViewModel.swift`, add this method directly after the `fetchCard` method (after line 317):

```swift
/// Retry a failed or empty metric fetch — resets state and re-fetches
func retryCard(instanceKey: String) async {
    guard let state = cardStates[instanceKey], !state.isLoading else { return }
    cardStates[instanceKey]?.hasBeenFetched = false
    cardStates[instanceKey]?.error = nil
    cardStates[instanceKey]?.data = []
    await fetchCard(instanceKey: instanceKey)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat: add retryCard method for per-metric retry"
```

---

### Task 3: Update `serverUtilizationStates` to preserve empty groups

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift:250-275`

- [ ] **Step 1: Change the return logic to keep groups with instances even if data is empty**

In the `serverUtilizationStates` computed property, replace the section starting at line 250 (`return orderedKeywords.compactMap`) through line 275 (closing brace of `compactMap`) with:

```swift
        return orderedKeywords.compactMap { keyword in
            guard let cat = categories.first(where: { $0.name.lowercased().contains(keyword) }) else { return nil }
            let states = cardStates.values
                .filter { state in
                    guard state.instance.categoryId == cat.id else { return false }
                    guard state.instance.unit == "%" else { return false }
                    let title = state.instance.title.lowercased()
                    if title.contains("core") || title.contains("voltage") { return false }
                    return true
                }
                .sorted { $0.instance.key < $1.instance.key }
            // For disk: pick the partition with highest current usage
            if keyword == "disk" {
                let loaded = states.filter { $0.hasBeenFetched && !$0.data.isEmpty }
                if let highest = loaded.max(by: { ($0.current ?? 0) < ($1.current ?? 0) }) {
                    return (category: cat, states: [highest])
                }
                // Fallback to root "/" if data hasn't loaded yet, or first available
                if let root = states.first(where: { $0.instance.instanceDescr == "/" }) {
                    return (category: cat, states: [root])
                }
                // Still return first instance so placeholder can render
                if let first = states.first {
                    return (category: cat, states: [first])
                }
                return nil
            }
            // Take only the first instance per category — return even if data is empty
            let limited = Array(states.prefix(1))
            return limited.isEmpty ? nil : (category: cat, states: limited)
        }
```

The key change: for disk, instead of returning `nil` when no root "/" exists and no data is loaded, we fall back to the first available instance. This ensures the disk card always appears when instances exist.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat: preserve empty groups in serverUtilizationStates for placeholder rendering"
```

---

### Task 4: Update `latencySection` to always render all states

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift:239-265`

- [ ] **Step 1: Replace the latencySection computed property**

Replace the entire `latencySection` computed property (lines 239-265) with:

```swift
    private var latencySection: some View {
        let states = viewModel.latencyStates
        let isLoading = viewModel.isLoadingCategories || states.contains(where: { $0.isLoading })
        let hasAnyState = !states.isEmpty

        return Group {
            if hasAnyState || viewModel.isLoadingCategories {
                VStack(spacing: 0) {
                    if isLoading && !hasAnyState {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else {
                        ForEach(states, id: \.instance.key) { state in
                            if state.isLoading && !state.hasBeenFetched {
                                VStack(spacing: 8) {
                                    Text(state.instance.title)
                                        .font(.caption2).fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 10)
                                    HStack { Spacer(); ProgressView(); Spacer() }
                                        .padding(.vertical, 40)
                                }
                            } else if !state.data.isEmpty {
                                latencyChart(state: state)
                            } else if state.hasBeenFetched {
                                retryPlaceholder(
                                    title: state.instance.title,
                                    isLoading: state.isLoading
                                ) {
                                    Task { await viewModel.retryCard(instanceKey: state.instance.key) }
                                }
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                        latencyChartAppeared = true
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Add the reusable `retryPlaceholder` helper**

Add this method in the `// MARK: - Helpers` section (before `statusColor`), around line 865:

```swift
    private func retryPlaceholder(title: String, isLoading: Bool, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption2).fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 30)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onRetry() }
            }
        }
    }
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: always render latency section with tap-to-retry placeholder"
```

---

### Task 5: Update `serverUtilizationSection` to always render all groups

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift:400-435`

- [ ] **Step 1: Replace the serverUtilizationSection computed property**

Replace the entire `serverUtilizationSection` computed property (lines 400-435) with:

```swift
    private var serverUtilizationSection: some View {
        let groups = viewModel.serverUtilizationStates
        let isLoading = viewModel.isLoadingCategories

        return Group {
            if !groups.isEmpty || isLoading {
                VStack(spacing: 0) {
                    if isLoading && groups.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else {
                        ForEach(groups, id: \.category.id) { group in
                            ForEach(group.states, id: \.instance.key) { state in
                                if state.isLoading && !state.hasBeenFetched {
                                    VStack(spacing: 8) {
                                        Text(state.instance.title)
                                            .font(.caption2).fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 10)
                                        HStack { Spacer(); ProgressView(); Spacer() }
                                            .padding(.vertical, 20)
                                    }
                                } else if !state.data.isEmpty {
                                    utilizationChart(state: state, categoryName: group.category.name)
                                } else if state.hasBeenFetched {
                                    retryPlaceholder(
                                        title: state.instance.title,
                                        isLoading: state.isLoading
                                    ) {
                                        Task { await viewModel.retryCard(instanceKey: state.instance.key) }
                                    }
                                }
                                if state.instance.key != group.states.last?.instance.key
                                    || group.category.id != groups.last?.category.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                        serverUtilChartAppeared = true
                    }
                }
            }
        }
    }
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: always render server utilization section with tap-to-retry placeholder"
```

---

### Task 6: Add `onRetry` to `MetricCard`

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift:949-978` (MetricCard struct)

- [ ] **Step 1: Add onRetry property to MetricCard**

In the `MetricCard` struct, add the `onRetry` closure after the existing `onTap` property (line 953):

```swift
private struct MetricCard: View {
    @Binding var state: MetricCardState
    let onTap: () -> Void
    var onRetry: (() -> Void)? = nil
```

- [ ] **Step 2: Replace the empty-data text with a tappable retry placeholder**

In MetricCard's body, replace the empty-data section (line 976-978):

```swift
// Before:
                    if state.data.isEmpty {
                        Text(state.error != nil ? "Failed to load data" : "No data available")
                            .font(.caption).foregroundColor(.secondary).padding()

// After:
                    if state.data.isEmpty {
                        if state.isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding()
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(state.error != nil ? "Failed to load data" : "No data available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { onRetry?() }
                        }
```

- [ ] **Step 3: Update all MetricCard call sites to pass onRetry**

There are three call sites. Update each:

**Pinned Interfaces section (~line 737):**
```swift
MetricCard(
    state: Binding(
        get: { viewModel.cardStates[state.instance.key] ?? state },
        set: { viewModel.cardStates[state.instance.key] = $0 }
    ),
    onTap: {
        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
    },
    onRetry: {
        Task { await viewModel.retryCard(instanceKey: state.instance.key) }
    }
)
```

**Performance regular instances (~line 783):**
```swift
MetricCard(
    state: Binding(
        get: { viewModel.cardStates[state.instance.key] ?? state },
        set: { viewModel.cardStates[state.instance.key] = $0 }
    ),
    onTap: {
        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
    },
    onRetry: {
        Task { await viewModel.retryCard(instanceKey: state.instance.key) }
    }
)
```

Note: The existing `MetricCard` call sites that don't pass `onRetry` will still compile because the parameter has a default value of `nil`. But we pass it at both sites so retry works everywhere.

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: add tap-to-retry on MetricCard empty/error state"
```

---

### Task 7: Build, deploy, and verify on device

**Files:** None (verification only)

- [ ] **Step 1: Full build and deploy**

Run: `./build_and_deploy.sh`
Expected: Build succeeds and app installs on TomiPhone13.

- [ ] **Step 2: Manual verification checklist**

On the device, navigate to a device detail view and verify:
1. Latency card always visible — shows chart when data loads, shows "No data available" with retry icon when it doesn't
2. CPU/Memory/Disk cards always visible — same behavior
3. Tapping "No data available" shows spinner and re-fetches
4. Stats (CURRENT/AVG/MAX) show "—" instead of "nan%" when data is missing
5. MetricCard in Performance section shows retry placeholder when expanded with no data
6. Tapping retry in MetricCard re-fetches and shows spinner in header

- [ ] **Step 3: Final commit if any tweaks needed**

```bash
git add -A
git commit -m "fix: adjustments from on-device testing"
```
