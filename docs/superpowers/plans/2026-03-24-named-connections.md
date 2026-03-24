# Named Connections & Stale API Service Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add named, saveable BHNM server connections to Settings and fix the stale API service bug affecting all ViewModels after a connection switch.

**Architecture:** A new `SavedConnection` Codable model lives in `UserDefaults`. `SettingsView` grows state for the saved list and `activeSavedID`; successful `testConnection()` becomes the sole write-to-AppStorage path. The stale-service fix applies `.onChange(of: ObjectIdentifier(apiService))` in three views, each calling `updateAPIService()` on their ViewModels.

**Tech Stack:** Swift 5.9+, SwiftUI, UserDefaults (JSON), xcodebuild for build verification, `./build_and_deploy.sh` to push to device.

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| **Create** | `BeNeM/Models/SavedConnection.swift` | Codable model + UserDefaults load/save helpers |
| **Modify** | `BeNeM/ViewModels/DeviceListViewModel.swift` | `let` → `var` on `apiService`; add `updateAPIService()` |
| **Modify** | `BeNeM/ViewModels/TacticalViewModel.swift` | `let` → `var` on `apiService`; add `updateAPIService()` |
| **Modify** | `BeNeM/Views/IncidentListView.swift` | Add `.onChange(of: ObjectIdentifier(apiService))` |
| **Modify** | `BeNeM/Views/DeviceListView.swift` | Add `.onChange(of: ObjectIdentifier(apiService))` |
| **Modify** | `BeNeM/Views/DashboardView.swift` | Add `.onChange(of: ObjectIdentifier(apiService))` for all 3 VMs |
| **Modify** | `BeNeM/Views/SettingsView.swift` | New state, Connection section, Name field, delete button; `testConnection()` refactored to write `@AppStorage` on success; Save button removed |
| **Modify** | `BeNeM.xcodeproj/project.pbxproj` | Register `SavedConnection.swift` in the app target |

---

## Task 1 — SavedConnection model

**Files:**
- Create: `BeNeM/Models/SavedConnection.swift`

- [ ] **Create the file with the model and UserDefaults helpers**

```swift
// BeNeM/Models/SavedConnection.swift
import Foundation

struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String      // "" = absent
    var ackUser: String  // "" = absent
}

extension UserDefaults {
    private static let savedConnectionsKey = "saved_connections"

    func loadSavedConnections() -> [SavedConnection] {
        guard let data = data(forKey: Self.savedConnectionsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    func saveSavedConnections(_ connections: [SavedConnection]) {
        let data = try? JSONEncoder().encode(connections)
        set(data, forKey: Self.savedConnectionsKey)
    }
}
```

- [ ] **Register the file in the Xcode project**

  In Xcode: right-click `BeNeM/Models` group → Add Files → select `SavedConnection.swift`, ensure the BeNeM app target is checked.

  Alternatively, edit `BeNeM.xcodeproj/project.pbxproj` and add a PBXBuildFile + PBXFileReference entry mirroring the pattern used for `NetreoIncident.swift`.

- [ ] **Build to confirm it compiles**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit**

```bash
git add BeNeM/Models/SavedConnection.swift BeNeM.xcodeproj/project.pbxproj
git commit -m "feat: add SavedConnection model with UserDefaults load/save"
```

---

## Task 2 — Stale service fix: ViewModels

**Files:**
- Modify: `BeNeM/ViewModels/DeviceListViewModel.swift:12` (`private let apiService`)
- Modify: `BeNeM/ViewModels/TacticalViewModel.swift:15` (`private let apiService`)

- [ ] **DeviceListViewModel — change `let` to `var` and add `updateAPIService`**

  In `DeviceListViewModel.swift`, find:
  ```swift
  private let apiService: NetreoAPIService
  ```
  Change to:
  ```swift
  private var apiService: NetreoAPIService
  ```

  Add this method after `deleteDevice`:
  ```swift
  func updateAPIService(_ newService: NetreoAPIService) {
      apiService = newService
      Task { await loadDevices(limit: currentLimit) }
  }
  ```

- [ ] **TacticalViewModel — change `let` to `var` and add `updateAPIService`**

  In `TacticalViewModel.swift`, find:
  ```swift
  private let apiService: NetreoAPIService
  ```
  Change to:
  ```swift
  private var apiService: NetreoAPIService
  ```

  Add this method after `load()`:
  ```swift
  func updateAPIService(_ newService: NetreoAPIService) {
      apiService = newService
      Task { await load() }
  }
  ```

  Note: `IncidentListViewModel` already has `private var apiService` and `updateAPIService()` — no changes needed there.

- [ ] **Build to confirm it compiles**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit**

```bash
git add BeNeM/ViewModels/DeviceListViewModel.swift BeNeM/ViewModels/TacticalViewModel.swift
git commit -m "fix: add updateAPIService to DeviceListViewModel and TacticalViewModel"
```

---

## Task 3 — Stale service fix: wire Views

**Files:**
- Modify: `BeNeM/Views/IncidentListView.swift`
- Modify: `BeNeM/Views/DeviceListView.swift`
- Modify: `BeNeM/Views/DashboardView.swift`

**How this works:** `NetreoAPIService` is a class. `.onChange(of: ObjectIdentifier(apiService))` compares the object's identity (memory address) across renders. When `ContentView` rebuilds with a new `NetreoAPIService` instance, SwiftUI updates the view's stored `let apiService` property and re-evaluates `body`. The `onChange` detects the identity change and fires, calling `updateAPIService` on the ViewModel.

- [ ] **IncidentListView — add `.onChange`**

  In `IncidentListView.swift`, find the last modifier on the `NavigationStack` (likely `.navigationDestination` or `.toolbar`). Add immediately after:
  ```swift
  .onChange(of: ObjectIdentifier(apiService)) { _, _ in
      viewModel.updateAPIService(apiService)
  }
  ```

- [ ] **DeviceListView — add `.onChange`**

  In `DeviceListView.swift`, find the `NavigationView` and add after its last modifier:
  ```swift
  .onChange(of: ObjectIdentifier(apiService)) { _, _ in
      viewModel.updateAPIService(apiService)
  }
  ```

- [ ] **DashboardView — add `.onChange` for all three ViewModels**

  In `DashboardView.swift`, find the `NavigationStack` and add after its last modifier:
  ```swift
  .onChange(of: ObjectIdentifier(apiService)) { _, _ in
      incidentViewModel.updateAPIService(apiService)
      deviceViewModel.updateAPIService(apiService)
      categoryViewModel.updateAPIService(apiService)
  }
  ```

- [ ] **Build and deploy to device**

```bash
./build_and_deploy.sh
```

- [ ] **Manual verification**

  1. Open the app connected to the on-prem server.
  2. Go to Settings → change Base URL and API Key to a different server → tap Test Connection (still using old Save button at this point).
  3. Navigate to Dashboard, Incidents, Devices — confirm they all reload against the new server, not the old one.

- [ ] **Commit**

```bash
git add BeNeM/Views/IncidentListView.swift BeNeM/Views/DeviceListView.swift BeNeM/Views/DashboardView.swift
git commit -m "fix: propagate apiService updates to all ViewModels via onChange"
```

---

## Task 4 — SettingsView: new state, UI skeleton, remove Save button

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

This task adds all the new UI and state without wiring any logic yet (testConnection still works as before; we'll extend it in Task 5).

- [ ] **Add new `@State` vars to `SettingsView`**

  Below the existing draft `@State` declarations (after `draftAckUser`), add:
  ```swift
  @State private var draftName = "New BHNM Connection"
  @State private var activeSavedID: UUID? = nil
  @State private var savedConnections: [SavedConnection] = []
  ```

- [ ] **Remove the existing `hasUnsavedChanges` computed property and the Save toolbar button**

  Delete the entire `hasUnsavedChanges` computed property.

  In the `.toolbar` block, delete:
  ```swift
  if hasUnsavedChanges {
      ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
              baseURL = draftBaseURL
              apiKey = draftApiKey
              pin = draftPin
              ackUser = draftAckUser
          }
          .fontWeight(.semibold)
      }
  }
  ```

- [ ] **Add the conditional "Connection" section above the existing "BHNM Server" section**

  In the `Form { }`, before `Section(header: Text("BHNM Server"))`, insert:
  ```swift
  if savedConnections.count >= 2 {
      Section(header: Text("Connection")) {
          HStack {
              Text("Server")
                  .foregroundColor(.secondary)
              Spacer()
              Menu {
                  ForEach(savedConnections) { connection in
                      Button(connection.name) {
                          // TODO Task 6: selectConnection(connection)
                      }
                  }
                  Divider()
                  Button("+ New Connection") {
                      // TODO Task 6: selectNewConnection()
                  }
              } label: {
                  HStack(spacing: 4) {
                      Text(activeSavedID != nil
                           ? (savedConnections.first(where: { $0.id == activeSavedID })?.name ?? draftName)
                           : draftName)
                      Image(systemName: "chevron.up.chevron.down")
                          .font(.caption)
                  }
                  .foregroundColor(.primary)
              }
          }
      }
  }
  ```

- [ ] **Add the "Name" field as the first row in the "BHNM Server" section**

  Inside `Section(header: Text("BHNM Server"))`, before the Base URL `TextField`, add:
  ```swift
  TextField("Connection Name", text: $draftName)
      .autocapitalization(.none)
  ```

- [ ] **Replace the existing `testConnection()` button with the new action row**

  Find the existing `Button { Task { await testConnection() } }` row and replace it with:
  ```swift
  HStack(spacing: 0) {
      Button {
          Task { await testConnection() }
      } label: {
          HStack {
              if isTesting {
                  ProgressView().padding(.trailing, 6)
                  Text("Testing…")
              } else {
                  Text("Test Connection")
              }
          }
          .frame(maxWidth: .infinity)
      }
      .disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || isTesting)

      if activeSavedID != nil {
          Divider().frame(height: 44)
          Button(role: .destructive) {
              // TODO Task 7: showDeleteConfirmation()
          } label: {
              Image(systemName: "trash")
                  .padding(.horizontal, 16)
          }
      }
  }
  ```

- [ ] **Build to confirm UI compiles and renders correctly**

```bash
./build_and_deploy.sh
```

  Open Settings — confirm:
  - Name field appears above Base URL.
  - No Save button in toolbar.
  - Connection section is hidden (0 saved connections so far).
  - Test Connection button is disabled when Name is empty.
  - Trash icon is hidden (no `activeSavedID`).

- [ ] **Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: add named connection UI skeleton to SettingsView"
```

---

## Task 5 — SettingsView: testConnection() writes to @AppStorage on success

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

Currently `testConnection()` shows an alert but does NOT write to `@AppStorage`. The Save button (now removed) did that. This task makes successful testing the sole write path.

- [ ] **Refactor the `case 200:` branch in `testConnection()`**

  Find the existing `case 200:` block. Replace the entire `if deviceCount > 0 { ... } else { ... }` with:

  ```swift
  case 200:
      var deviceCount = 0
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
          if let arr = json["devices"] as? [[String: Any]] {
              deviceCount = arr.count
          } else if let nested = json["data"] as? [String: Any],
                    let arr = nested["devices"] as? [[String: Any]] {
              deviceCount = arr.count
          }
      }
      if deviceCount > 0 {
          // Upsert into savedConnections
          let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
          let now = SavedConnection(
              id: activeSavedID ?? UUID(),
              name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
              baseURL: draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
              apiKey: draftApiKey,
              pin: draftPin,
              ackUser: draftAckUser
          )
          if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
              savedConnections[idx] = now
          } else {
              savedConnections.append(now)
          }
          UserDefaults.standard.saveSavedConnections(savedConnections)
          activeSavedID = now.id

          // Write to @AppStorage (triggers ContentView.updateAPIService via onChange)
          baseURL  = now.baseURL
          apiKey   = now.apiKey
          pin      = now.pin
          ackUser  = now.ackUser

          alertTitle   = "Connection successful"
          alertMessage = "Connected — \(deviceCount) device\(deviceCount == 1 ? "" : "s") found. '\(now.name)' saved."
      } else {
          alertTitle   = "Connected — no devices found"
          alertMessage = "The server responded successfully but returned no devices.\n\nCheck that your API key has permission to list devices."
      }
  ```

  > **Note:** the test URL inside `testConnection()` is built from `draftBaseURL` directly (not `baseURL`). That is correct — it tests the draft values before writing them to `@AppStorage`.

- [ ] **Build and deploy**

```bash
./build_and_deploy.sh
```

- [ ] **Manual verification**

  1. Clear any existing connection in Settings.
  2. Enter a valid server URL, API key, and a name (e.g. "SaaS Demo").
  3. Tap Test Connection → confirm success alert says *"Found N devices. 'SaaS Demo' saved."*
  4. Navigate to Dashboard/Incidents/Devices — confirm they load from the new server.
  5. Go back to Settings — confirm the Name field still shows "SaaS Demo".
  6. Check UserDefaults in Debug section to confirm `saved_connections` is persisted (optional, or just re-launch and check).

- [ ] **Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: testConnection() now upserts SavedConnection and writes to @AppStorage on success"
```

---

## Task 6 — SettingsView: picker selection and + New Connection

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

- [ ] **Add `selectConnection(_:)` helper to `SettingsView`**

  Add below `testConnection()`:
  ```swift
  private func selectConnection(_ connection: SavedConnection) {
      draftName    = connection.name
      draftBaseURL = connection.baseURL
      draftApiKey  = connection.apiKey
      draftPin     = connection.pin
      draftAckUser = connection.ackUser
      activeSavedID = connection.id
      Task { await testConnection() }
  }

  private func selectNewConnection() {
      draftName    = "New BHNM Connection"
      draftBaseURL = ""
      draftApiKey  = ""
      draftPin     = ""
      draftAckUser = ""
      activeSavedID = nil
  }
  ```

- [ ] **Wire the TODO stubs in the Connection section Menu**

  Replace:
  ```swift
  Button(connection.name) {
      // TODO Task 6: selectConnection(connection)
  }
  ```
  With:
  ```swift
  Button(connection.name) {
      selectConnection(connection)
  }
  ```

  Replace:
  ```swift
  Button("+ New Connection") {
      // TODO Task 6: selectNewConnection()
  }
  ```
  With:
  ```swift
  Button("+ New Connection") {
      selectNewConnection()
  }
  ```

- [ ] **Build and deploy**

```bash
./build_and_deploy.sh
```

- [ ] **Manual verification — requires 2 saved connections**

  1. Save two connections via successful Test Connection (e.g. "SaaS Demo" and "Lab").
  2. Confirm the "Connection" picker section appears.
  3. Tap the picker → confirm the dropdown shows both names plus "+ New Connection".
  4. Tap "Lab" → confirm fields fill and auto-test fires.
  5. Tap "+ New Connection" → confirm all fields clear and name resets to "New BHNM Connection".

- [ ] **Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: wire connection picker selection and + New Connection in SettingsView"
```

---

## Task 7 — SettingsView: delete connection

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

- [ ] **Add delete confirmation state**

  Add with the other `@State` vars:
  ```swift
  @State private var showingDeleteConfirmation = false
  ```

- [ ] **Add the confirmation alert to the Form**

  After the existing `.alert(alertTitle, ...)`, add:
  ```swift
  .alert("Delete '\(draftName)'?", isPresented: $showingDeleteConfirmation) {
      Button("Delete", role: .destructive) {
          deleteActiveConnection()
      }
      Button("Cancel", role: .cancel) {}
  } message: {
      Text("This connection will be removed from your saved list.")
  }
  ```

- [ ] **Add `deleteActiveConnection()` helper**

  Add below `selectNewConnection()`:
  ```swift
  private func deleteActiveConnection() {
      guard let id = activeSavedID else { return }
      savedConnections.removeAll { $0.id == id }
      UserDefaults.standard.saveSavedConnections(savedConnections)
      activeSavedID = nil
      // Keep draft fields populated so the user can see what was deleted.
      if savedConnections.isEmpty {
          // Clear @AppStorage — ContentView will set apiService = nil → WelcomeView.
          baseURL  = ""
          apiKey   = ""
          pin      = ""
          ackUser  = ""
      }
      // If connections remain, do NOT auto-switch. User picks from the picker.
  }
  ```

- [ ] **Wire the TODO stub in the action row**

  Replace:
  ```swift
  Button(role: .destructive) {
      // TODO Task 7: showDeleteConfirmation()
  } label: {
  ```
  With:
  ```swift
  Button(role: .destructive) {
      showingDeleteConfirmation = true
  } label: {
  ```

- [ ] **Build and deploy**

```bash
./build_and_deploy.sh
```

- [ ] **Manual verification**

  1. With 2+ saved connections, select one — confirm trash icon appears.
  2. Tap trash → confirm confirmation alert appears.
  3. Tap Cancel → confirm nothing changes.
  4. Tap trash again → Delete → confirm the connection is removed, picker updates.
  5. Delete down to 0 connections → confirm the Connection picker section disappears and the app shows WelcomeView (no server configured).

- [ ] **Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: add delete connection with confirmation to SettingsView"
```

---

## Task 8 — SettingsView: onAppear pre-fill and activeSavedID matching

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

This task makes the form remember which saved connection was last active, so re-opening Settings shows the right name and enables the trash icon.

- [ ] **Replace the existing `.onAppear` block**

  The current `.onAppear` sets the four draft fields from `@AppStorage`. Replace the entire block:
  ```swift
  .onAppear {
      savedConnections = UserDefaults.standard.loadSavedConnections()
      draftBaseURL = baseURL
      draftApiKey  = apiKey
      draftPin     = pin
      draftAckUser = ackUser
      // Find which saved connection matches current @AppStorage credentials
      activeSavedID = savedConnections.first(where: {
          $0.baseURL == baseURL &&
          $0.apiKey  == apiKey  &&
          $0.pin     == pin     &&
          $0.ackUser == ackUser
      })?.id
      if let id = activeSavedID,
         let match = savedConnections.first(where: { $0.id == id }) {
          draftName = match.name
      }
  }
  ```

- [ ] **Build and deploy**

```bash
./build_and_deploy.sh
```

- [ ] **Full end-to-end manual verification**

  1. Force-quit and relaunch the app.
  2. Go to Settings — confirm Name field shows the name of the active connection, trash icon is visible.
  3. If 2+ connections saved, confirm the picker shows the correct active one.
  4. Switch connections, navigate to Dashboard — confirm data reloads from the new server.
  5. Delete a connection, relaunch — confirm it is gone.

- [ ] **Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: onAppear restores activeSavedID and connection name in SettingsView"
```

---

## Task 9 — Final build and version bump

- [ ] **Run a clean build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'generic/platform=iOS' clean build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Bump the minor version** (new feature)

```bash
./scripts/bump_version.sh minor
```

- [ ] **Deploy to device for final smoke test**

```bash
./build_and_deploy.sh
```

  Confirm:
  - New connection: enter name, URL, key → Test Connection → saved, data loads.
  - Saved connections: picker appears with 2+ entries, switching reloads data.
  - Delete: connection removed, WelcomeView shown when last is deleted.
  - Re-launch: Settings remembers active connection.

- [ ] **Commit**

```bash
git add BeNeM.xcodeproj/project.pbxproj
git commit -m "chore: bump minor version for named connections feature"
```
