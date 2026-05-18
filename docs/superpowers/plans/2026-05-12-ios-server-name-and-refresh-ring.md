# iOS Server Name + PWA-Style Refresh Ring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the active BHNM server name reliably appear in all four iOS toolbars (Home, Incidents, Devices, Settings), and restyle the refresh ring to PWA proportions with iOS-adaptive colors.

**Architecture:** A single pure resolver `resolveActiveServerName(...)` with a deterministic fallback chain (Approach B from the spec) is called from both `ContentView` write sites so the toolbar subtitle is populated for legacy/migrated/single-server/QR-imported configs, not just when `activeConnectionID` resolves. The refresh ring is a contained restyle of `AutoRefreshButton.swift` (40 px, tightened monospace countdown, adaptive colors) that all screens using it inherit automatically.

**Tech Stack:** Swift / SwiftUI, `xcodebuild`, `xcrun devicectl`.

**Spec:** `docs/superpowers/specs/2026-05-12-ios-server-name-and-refresh-ring-design.md`

---

## Testing approach (deviation from default TDD)

This Xcode project has **no test target** (no XCTest, no Tests scheme, build script runs `xcodebuild build` only). The approved spec scoped verification as **compile + manual**. Therefore each code task is gated by an `xcodebuild` **simulator build** (fast, no code-signing) instead of an XCTest run, and Task 6 performs the on-device manual verification checklist. `xcodebuild` is the source of truth for compilation — SourceKit reports false positives in this project (per `ios/CLAUDE.md`). Do not add a test target; that is out of scope for this spec.

Per-task build command (used as the "verify" step throughout):

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected on success: `** BUILD SUCCEEDED **`.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `ios/BeNeM/Models/ActiveServerName.swift` | Pure resolver: best display name for the active connection + URL-host helper | Create |
| `ios/BeNeM/ContentView.swift` | Call the resolver from `updateAPIService()` and `handleConnectionChange(from:to:)`; preserve disconnect-clears-subtitle and push-registration behavior | Modify |
| `ios/BeNeM/Views/AutoRefreshButton.swift` | Refresh ring restyle: 40 px, adaptive colors, tightened countdown | Modify |
| `shared/feature-spec.md` | Document the iOS resolver + adaptive-ring behavior under Navigation (Tab Bar) | Modify |

---

## Task 1: Create `resolveActiveServerName` resolver

**Files:**
- Create: `ios/BeNeM/Models/ActiveServerName.swift`

- [ ] **Step 1: Create the resolver file**

Create `ios/BeNeM/Models/ActiveServerName.swift` with exactly:

```swift
import Foundation

/// Resolves the best human-readable name for the active BHNM connection,
/// used as the toolbar subtitle on all four main screens.
///
/// Fallback chain (first non-empty wins):
/// 1. Saved connection whose id matches `activeConnectionID`
/// 2. Saved connection whose apiKey + middlewareURL match the active config
///    (covers legacy/migrated configs where the active ID was never set)
/// 3. The sole saved connection, if exactly one exists
/// 4. Host component of the BHNM URL
/// 5. Host component of the middleware URL
/// 6. "BeNeM" — guaranteed non-empty final fallback
func resolveActiveServerName(
    connections: [SavedConnection],
    activeConnectionID: String,
    middlewareURL: String,
    bhnmURL: String,
    apiKey: String
) -> String {
    if let byID = connections.first(where: { $0.id.uuidString == activeConnectionID }),
       !byID.name.isEmpty {
        return byID.name
    }
    if !apiKey.isEmpty,
       let byConfig = connections.first(where: {
           $0.apiKey == apiKey && $0.middlewareURL == middlewareURL
       }),
       !byConfig.name.isEmpty {
        return byConfig.name
    }
    if connections.count == 1, !connections[0].name.isEmpty {
        return connections[0].name
    }
    if let h = hostComponent(from: bhnmURL) { return h }
    if let h = hostComponent(from: middlewareURL) { return h }
    return "BeNeM"
}

/// Extracts the host (e.g. `bhnm.example.com`) from a possibly scheme-less
/// URL string. Returns nil for empty/unparseable input.
func hostComponent(from urlString: String) -> String? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else {
        return nil
    }
    return host
}
```

- [ ] **Step 2: Verify it compiles**

Run:

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`. (New Swift files in the `BeNeM` group are auto-included by the project's file-system-synchronized group; if the build reports the file is not found, add it to the `BeNeM` target in Xcode's Project Navigator.)

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/Models/ActiveServerName.swift
git commit -m "feat(ios): add resolveActiveServerName resolver with fallback chain"
```

---

## Task 2: Wire resolver into `updateAPIService()`

**Files:**
- Modify: `ios/BeNeM/ContentView.swift` (the tail of `updateAPIService()`, currently the block that writes `netreo_active_connection_name`)

- [ ] **Step 1: Replace the name-write block**

Find this block at the end of `private func updateAPIService()`:

```swift
        // Sync active server name for toolbar subtitle (covers app startup path)
        let connections = UserDefaults.standard.loadSavedConnections()
        if let active = connections.first(where: { $0.id.uuidString == activeConnectionID }) {
            UserDefaults.standard.set(active.name, forKey: "netreo_active_connection_name")
        }
    }
```

Replace it with:

```swift
        // Sync active server name for toolbar subtitle (covers app startup path).
        // updateAPIService() already early-returns when baseURL/apiKey are empty,
        // so a working config is guaranteed here and the resolver never returns "".
        let connections = UserDefaults.standard.loadSavedConnections()
        let resolvedName = resolveActiveServerName(
            connections: connections,
            activeConnectionID: activeConnectionID,
            middlewareURL: baseURL,
            bhnmURL: bhnmURL,
            apiKey: apiKey
        )
        UserDefaults.standard.set(resolvedName, forKey: "netreo_active_connection_name")
    }
```

- [ ] **Step 2: Verify it compiles**

Run:

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/ContentView.swift
git commit -m "fix(ios): resolve active server name on startup via fallback chain"
```

---

## Task 3: Wire resolver into `handleConnectionChange(from:to:)`

**Files:**
- Modify: `ios/BeNeM/ContentView.swift` (`handleConnectionChange`, the block currently doing `removeObject` then `guard ... let conn`)

This must (a) clear the subtitle only when there is genuinely no config (disconnect), (b) otherwise write the resolved name even when `newID` does not resolve, and (c) preserve the existing push-registration path which still needs the concrete `conn` for `newID`.

- [ ] **Step 1: Replace the subtitle/guard block**

Find this block inside `handleConnectionChange`:

```swift
        // Always update the server name subtitle
        UserDefaults.standard.removeObject(forKey: "netreo_active_connection_name")
        guard !newID.isEmpty,
              let conn = connections.first(where: { $0.id.uuidString == newID }) else { return }
        UserDefaults.standard.set(conn.name, forKey: "netreo_active_connection_name")
```

Replace it with:

```swift
        // No working config at all (active connection deleted, nothing
        // configured) → clear the subtitle so a disconnected app shows none.
        if newID.isEmpty && baseURL.isEmpty && apiKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: "netreo_active_connection_name")
            return
        }
        // Otherwise always write a resolved name — covers legacy/migrated/
        // single-server configs where newID does not resolve to a saved row.
        let resolvedName = resolveActiveServerName(
            connections: connections,
            activeConnectionID: newID,
            middlewareURL: baseURL,
            bhnmURL: bhnmURL,
            apiKey: apiKey
        )
        UserDefaults.standard.set(resolvedName, forKey: "netreo_active_connection_name")
        // Push registration still needs the concrete saved connection for newID.
        guard !newID.isEmpty,
              let conn = connections.first(where: { $0.id.uuidString == newID }) else { return }
```

(The lines after this block — `guard conn.notificationsEnabled, ...` and the `registerWithMiddleware` call — are unchanged and still compile because `conn` is still bound.)

- [ ] **Step 2: Verify it compiles**

Run:

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/ContentView.swift
git commit -m "fix(ios): resolve server name on connection change; clear only when truly unconfigured"
```

---

## Task 4: Restyle `AutoRefreshButton` (PWA shape, iOS-adaptive colors)

**Files:**
- Modify: `ios/BeNeM/Views/AutoRefreshButton.swift` (the `var body` of `struct AutoRefreshButton`)

Four changes: loading spinner `0.7 → 0.8`; countdown text `.kerning(-0.3)` added; countdown color `Color(.systemGray3) → .secondary`; frame `32 → 40`. Track (`Color(.systemGray4)`) and progress arc (`Color.accentColor`) are intentionally kept — they are already adaptive, matching "PWA shape, iOS adaptive colors".

- [ ] **Step 1: Apply the four edits**

In `struct AutoRefreshButton`'s `var body`, change:

`ProgressView().scaleEffect(0.7)` → `ProgressView().scaleEffect(0.8)`

The countdown `Text` block from:

```swift
                Text(countdownLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(.systemGray3))
```

to:

```swift
                Text(countdownLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(-0.3)
                    .foregroundColor(.secondary)
```

And the frame from `.frame(width: 32, height: 32)` to `.frame(width: 40, height: 40)`.

- [ ] **Step 2: Verify it compiles**

Run:

```bash
cd ios && xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/BeNeM/Views/AutoRefreshButton.swift
git commit -m "feat(ios): refresh ring 40px with tightened adaptive countdown (PWA parity)"
```

---

## Task 5: Update `shared/feature-spec.md`

**Files:**
- Modify: `shared/feature-spec.md` (Feature: Navigation (Tab Bar), `#### iOS-specific`)

- [ ] **Step 1: Append iOS-specific notes**

Under `### Feature: Navigation (Tab Bar)`, find the `#### iOS-specific` section:

```
#### iOS-specific
- Native UITabBarController / SwiftUI TabView
```

Replace it with:

```
#### iOS-specific
- Native UITabBarController / SwiftUI TabView
- All four toolbars show the active server name as a subtitle, resolved via `resolveActiveServerName()` with a fallback chain (active-ID match → apiKey+middlewareURL match → sole saved connection → BHNM host → middleware host → "BeNeM"), so the name shows for legacy/migrated/single-server/QR-imported configs, not only when `activeConnectionID` resolves
- `AutoRefreshButton` ring matches the PWA `RefreshRing` proportions (40 px, centered tight monospace M:SS, counter-clockwise drain) but uses iOS-adaptive colors (system track, accent progress arc) instead of the PWA's fixed dark-theme palette
```

- [ ] **Step 2: Commit**

```bash
git add shared/feature-spec.md
git commit -m "docs: note iOS server-name resolver + adaptive refresh ring in feature-spec"
```

---

## Task 6: Build, deploy to iPhone 13 Pro Max, manual verification

**Files:** none (verification only)

`ios/build.local.sh` already targets the iPhone 13 Pro Max (`BENEM_DEVICE_ID=00008110-00167D41263A801E`). `build_and_deploy.sh` builds for that device and installs via `xcrun devicectl`.

- [ ] **Step 1: Confirm the device is connected**

Run: `xcrun devicectl list devices`
Expected: an iPhone with UDID `00008110-00167D41263A801E` listed as available/connected. If absent, ask the user to connect/unlock the iPhone 13 Pro Max before continuing.

- [ ] **Step 2: Build and deploy to the device**

Run: `cd ios && ./build_and_deploy.sh`
Expected: `** BUILD SUCCEEDED **`, then `==> Installing on device...` and `==> Done! App installed.`

- [ ] **Step 3: Manual verification on the device**

Confirm on the running app:

1. **Server name — all 4 screens:** Launch the app cold. Home, Incidents, Devices, and Settings each show the active server name under the title. (Per the spec, the prior bug was a *blank* subtitle on every screen; it must now be populated.)
2. **Server name — after switch:** In Settings, switch the active server (or, on a single/legacy config, confirm the name is still shown). The subtitle updates without needing another switch.
3. **Refresh ring:** On Home/Incidents/Devices the ring is visibly larger (40 px), shows a centered `M:SS` countdown, and the arc drains counter-clockwise over the refresh interval. Tapping it triggers an immediate refresh.
4. **Light + dark mode:** Toggle iOS appearance — ring track/text and countdown remain legible and adapt (no hardcoded dark-only colors).

- [ ] **Step 4: Report results**

Summarize what was verified and any deviations. Do not claim success for items not actually observed on the device; if the device is unavailable, state that on-device verification is pending and stop.

---

## Self-Review

**Spec coverage:**
- Part 1 root cause / Approach B resolver → Task 1 (resolver), Task 2 (`updateAPIService`), Task 3 (`handleConnectionChange`, incl. disconnect-clear + push-path preservation). ✓
- Fallback chain order (ID → apiKey+middleware → single → bhnm host → middleware host → "BeNeM") → implemented verbatim in Task 1. ✓
- Part 2 ring restyle (40 px, adaptive colors, kerning, loading scale, kept counter-clockwise drain/animation) → Task 4. ✓
- Spec "feature spec impact" → Task 5. ✓
- Spec "Risks & verification" (build + manual light/dark, cold launch, switch) → Task 6 + per-task simulator builds. ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code; commands have expected output. ✓

**Type consistency:** `resolveActiveServerName(connections:activeConnectionID:middlewareURL:bhnmURL:apiKey:)` and `hostComponent(from:)` defined in Task 1 are called with identical signatures/labels in Tasks 2 and 3. AppStorage-backed locals used (`baseURL`=`netreo_base_url`, `bhnmURL`=`netreo_bhnm_url`, `apiKey`=`netreo_api_key`, `activeConnectionID`=`netreo_active_connection_id`) match `ContentView.swift` declarations. `SavedConnection` fields used (`id`, `name`, `apiKey`, `middlewareURL`) match the model. ✓
