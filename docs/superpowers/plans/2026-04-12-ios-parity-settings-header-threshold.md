# iOS Parity: Settings UX, AppHeader, Middleware Enforcement & Threshold Cache

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring iOS to full parity with the PWA on server selection UX, app header, middleware-only architecture enforcement, and HEALTHY alarm counts.

**Architecture:** All API traffic routes through the middleware (never direct to BHNM). A new `ThresholdCache` singleton fetches threshold counts once per 10 minutes from `GET /api/v1/threshold-counts` and feeds the HEALTHY computation in both the device list and device detail. The `AutoRefreshButton` gains a live M:SS countdown and the navigation toolbar gains a server name subtitle across all four tabs.

**Tech Stack:** Swift 5.9+, SwiftUI, `@AppStorage`, `@MainActor`, `URLSession`, `JSONSerialization`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `ios/BeNeM/ContentView.swift` | Modify | Remove direct-BHNM fallback; write `netreo_active_connection_name`; pass `incidentViewModel` to `DeviceListView` |
| `ios/BeNeM/Services/DeepLinkHandler.swift` | Modify | Remove auto-activate on QR import |
| `ios/BeNeM/Views/AutoRefreshButton.swift` | Modify | Replace arrow icon with M:SS countdown text; resize to 32×32 |
| `ios/BeNeM/Views/ServerConfigView.swift` | Modify | Move Middleware URL to Connection section; always require it; remove direct-BHNM test branch |
| `ios/BeNeM/Views/SettingsView.swift` | Modify | Radio select button; inline delete with confirmation; connection badge; server name subtitle |
| `ios/BeNeM/Views/DashboardView.swift` | Modify | Add server name subtitle to principal toolbar item |
| `ios/BeNeM/Views/IncidentListView.swift` | Modify | Add server name subtitle to principal toolbar item |
| `ios/BeNeM/Views/DeviceListView.swift` | Modify | Add server name subtitle; accept `incidentViewModel`; per-row alarm badges |
| `ios/BeNeM/ViewModels/DeviceListViewModel.swift` | Modify | Call `ThresholdCache.shared.refresh(using:)` on load |
| `ios/BeNeM/ViewModels/DeviceDetailViewModel.swift` | Modify | New HEALTHY formula; load `okServiceChecks` concurrently |
| `ios/BeNeM/Models/ThresholdCache.swift` | **Create** | `@MainActor` singleton; `[String: Int]` cache; 10-min staleness guard |
| `ios/BeNeM/Services/NetreoAPIService.swift` | Modify | `fetchThresholdCounts()` and `fetchDeviceServices(deviceName:)` |

---

## Task 1: Middleware Enforcement — ContentView

Remove the direct-BHNM fallback so the app only connects via the middleware.

**Files:**
- Modify: `ios/BeNeM/ContentView.swift`

- [ ] **Step 1: Update `updateAPIService()` — remove fallback**

  In `ContentView.swift`, replace the entire `updateAPIService()` function body:

  ```swift
  private func updateAPIService() {
      guard !baseURL.isEmpty && !apiKey.isEmpty else {
          apiService = nil
          return
      }
      let apiVersion = NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy
      let configuration = NetreoAPIConfiguration(
          baseURL: baseURL,
          bhnmURL: bhnmURL,
          apiKey: apiKey,
          pin: pin.isEmpty ? nil : pin,
          proxyToken: webhookSecret,
          version: apiVersion,
          timeout: timeout,
          retryCount: Int(retryCount)
      )
      let service = NetreoAPIService(configuration: configuration)
      apiService = service
      incidentViewModel.updateAPIService(service)
      // Reset all navigation stacks so stale data from the old server is never shown
      homeNavResetID = UUID()
      incidentNavResetID = UUID()
      settingsNavResetID = UUID()
      // Sync active server name for toolbar subtitle
      let connections = UserDefaults.standard.loadSavedConnections()
      if let active = connections.first(where: { $0.id.uuidString == activeConnectionID }) {
          UserDefaults.standard.set(active.name, forKey: "netreo_active_connection_name")
      }
  }
  ```

- [ ] **Step 2: Update `mainTabs` guard condition**

  In `ContentView.swift`, find the `mainTabs` computed property. Change:
  ```swift
  if !bhnmURL.isEmpty && !apiKey.isEmpty, let service = apiService {
  ```
  to:
  ```swift
  if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
  ```

- [ ] **Step 3: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds, deploys to device.

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/ContentView.swift
  git commit -m "fix(ios): remove direct-BHNM fallback — middleware is always required"
  ```

---

## Task 2: Middleware Enforcement — ServerConfigView

Move Middleware URL to the Connection section (always visible, always required), remove the direct-BHNM test branch.

**Files:**
- Modify: `ios/BeNeM/Views/ServerConfigView.swift`

- [ ] **Step 1: Update `saveDisabled` to always require Middleware URL**

  Replace the `saveDisabled` computed property:
  ```swift
  private var saveDisabled: Bool {
      isTesting
      || draftName.isEmpty
      || draftBhnmURL.isEmpty
      || draftMiddlewareURL.isEmpty
      || draftApiKey.isEmpty
      || draftAckUser.isEmpty
      || (draftNotificationsEnabled && draftPushSecret.isEmpty)
      || (!isAddMode && !hasChanges)
  }
  ```

- [ ] **Step 2: Move Middleware URL into the Connection section**

  Replace the Connection and Push Notifications sections in `body`:

  ```swift
  // Connection section
  Section("Connection") {
      LabeledField("Server Name", placeholder: "e.g. Production BHNM") {
          TextField("", text: $draftName)
              .focused($focusedField, equals: .name)
      }
      LabeledField("BHNM URL", placeholder: "https://bhnm.yourcompany.com") {
          TextField("", text: $draftBhnmURL)
              .keyboardType(.URL)
              .autocapitalization(.none)
              .focused($focusedField, equals: .bhnmURL)
      }
      LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
          TextField("", text: $draftMiddlewareURL)
              .keyboardType(.URL)
              .autocapitalization(.none)
              .focused($focusedField, equals: .middlewareURL)
      }
      LabeledField("API Token", placeholder: "Required") {
          SecureField("", text: $draftApiKey)
              .focused($focusedField, equals: .apiKey)
      }
      LabeledField("PIN / License ID", placeholder: "SaaS only") {
          SecureField("", text: $draftPin)
              .focused($focusedField, equals: .pin)
      }
      LabeledField("User Name", placeholder: "Required") {
          TextField("", text: $draftAckUser)
              .autocapitalization(.none)
              .focused($focusedField, equals: .ackUser)
      }
  }

  // Push Notifications section
  Section("Push Notifications") {
      Toggle("Enable Push Notifications", isOn: $draftNotificationsEnabled)

      LabeledField("Webhook Secret", placeholder: "Required for push") {
          SecureField("", text: $draftPushSecret)
              .focused($focusedField, equals: .pushSecret)
              .disabled(!draftNotificationsEnabled)
      }
      .opacity(draftNotificationsEnabled ? 1 : 0.4)
  }
  ```

- [ ] **Step 3: Replace the test-connection logic to always use middleware**

  Find the block that reads:
  ```swift
  // Normalize middleware URL if push is enabled
  if draftNotificationsEnabled {
  ```
  
  Replace the entire normalization + test-URL construction block (from that `if draftNotificationsEnabled {` down through where `testBase` and `addProxyHeaders` are set) with:

  ```swift
  // Always normalize middleware URL (required for all connections)
  var mwURLString = draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
  if !mwURLString.hasPrefix("http://") && !mwURLString.hasPrefix("https://") {
      mwURLString = "https://\(mwURLString)"
  }
  draftMiddlewareURL = mwURLString

  guard !mwURLString.isEmpty else {
      testStatus = .failure
      alertTitle = "Middleware URL Required"
      alertMessage = "Enter the Middleware URL before saving. All API calls route through the middleware."
      showingAlert = true
      return
  }

  let testBase = mwURLString.trimmingSuffix("/")
  let addProxyHeaders = true
  ```

- [ ] **Step 4: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Verify in the app that the Add Server form now shows Middleware URL in the Connection section (not Push section).

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/ServerConfigView.swift
  git commit -m "fix(ios): middleware URL required in all connections — move to Connection section, enforce in test"
  ```

---

## Task 3: QR Import — No Auto-Switch

When a QR code is scanned and confirmed, save the server but do not activate it.

**Files:**
- Modify: `ios/BeNeM/Services/DeepLinkHandler.swift`

- [ ] **Step 1: Remove the auto-activate line and push re-registration block**

  In `DeepLinkHandler.applyPendingImport()`, find and remove these two things:

  1. The line: `ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")`
  2. The entire push re-registration block that follows:
     ```swift
     // 3. Re-register push if notificationsEnabled
     if imp.notificationsEnabled,
        let token = AppDelegate.shared?.cachedDeviceToken,
        let conn = connections.first(where: { $0.id == upsertedID }) {
         AppDelegate.shared?.registerWithMiddleware(
             token: token,
             secret: conn.webhookSecret,
             middlewareURL: conn.middlewareURL
         )
     }
     ```

  After these removals, `applyPendingImport()` should end with:
  ```swift
  ud.saveSavedConnections(connections)

  pendingImport = nil
  NotificationCenter.default.post(name: .deepLinkConnectionApplied, object: nil)
  ```

- [ ] **Step 2: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Scan a QR code — server appears in the list but the active server does not change.

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Services/DeepLinkHandler.swift
  git commit -m "fix(ios): QR import adds server to list without switching active connection"
  ```

---

## Task 4: AutoRefreshButton — M:SS Countdown

Replace the static arrow icon with a live countdown in M:SS format.

**Files:**
- Modify: `ios/BeNeM/Views/AutoRefreshButton.swift`

- [ ] **Step 1: Replace `AutoRefreshButton` body**

  Replace the entire `AutoRefreshButton` struct (keep `ConnectionStatus`, `ChainIcon`, and `ConnectionBadgeButton` unchanged above it):

  ```swift
  // MARK: - AutoRefreshButton

  /// A toolbar button that shows a circular countdown ring and auto-refreshes every `interval` seconds.
  /// Tapping the button triggers an immediate refresh and resets the countdown.
  struct AutoRefreshButton: View {
      let interval: Double          // seconds between auto-refreshes
      let isLoading: Bool
      let action: () async -> Void

      @State private var elapsed: Double = 0
      private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

      private var progress: Double { min(elapsed / interval, 1.0) }

      private var countdownLabel: String {
          let remaining = max(0, interval - elapsed)
          let minutes = Int(remaining) / 60
          let seconds = Int(remaining) % 60
          return "\(minutes):\(String(format: "%02d", seconds))"
      }

      var body: some View {
          ZStack {
              // Countdown ring — hidden while loading
              if !isLoading {
                  Circle()
                      .stroke(Color(.systemGray4), lineWidth: 2)
                  Circle()
                      .trim(from: 0, to: progress)
                      .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                      .rotationEffect(.degrees(-90))
                      .animation(.linear(duration: 1), value: progress)
              }

              if isLoading {
                  ProgressView()
                      .scaleEffect(0.7)
              } else {
                  Text(countdownLabel)
                      .font(.system(size: 9, weight: .bold, design: .monospaced))
                      .foregroundColor(Color(.systemGray3))
              }
          }
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
          .onTapGesture {
              guard !isLoading else { return }
              elapsed = 0
              Task { await action() }
          }
          .onReceive(ticker) { _ in
              elapsed += 1
              if elapsed >= interval, !isLoading {
                  elapsed = 0
                  Task { await action() }
              }
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Refresh ring in toolbar now shows e.g. `1:58` counting down with no arrow icon.

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/AutoRefreshButton.swift
  git commit -m "feat(ios): AutoRefreshButton shows M:SS countdown instead of static arrow icon"
  ```

---

## Task 5: Active Server Name — Propagation + AppStorage Key

Store the active server's human-readable name in `@AppStorage` so all four tabs can read it for the toolbar subtitle.

**Files:**
- Modify: `ios/BeNeM/Views/SettingsView.swift` (write the name when activating)

- [ ] **Step 1: Write name to AppStorage in `activateConnection(_:)`**

  In `SettingsView.activateConnection(_:)`, add one line after `activeSavedConnectionID = new.id.uuidString`:

  ```swift
  UserDefaults.standard.set(new.name, forKey: "netreo_active_connection_name")
  ```

  The full function should then read:
  ```swift
  private func activateConnection(_ new: SavedConnection) {
      switchingInProgress = new.id

      UserDefaults.standard.set(new.middlewareURL,  forKey: "netreo_base_url")
      UserDefaults.standard.set(new.bhnmURL,        forKey: "netreo_bhnm_url")
      UserDefaults.standard.set(new.apiKey,         forKey: "netreo_api_key")
      UserDefaults.standard.set(new.pin,            forKey: "netreo_pin")
      UserDefaults.standard.set(new.ackUser,        forKey: "netreo_ack_user")
      UserDefaults.standard.set(new.webhookSecret,  forKey: "netreo_webhook_secret")
      UserDefaults.standard.set(new.name,           forKey: "netreo_active_connection_name")
      activeSavedConnectionID = new.id.uuidString

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
          switchingInProgress = nil
          reload()
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds.

- [ ] **Step 3: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/SettingsView.swift
  git commit -m "feat(ios): persist active server name to AppStorage for toolbar subtitle"
  ```

---

## Task 6: AppHeader Subtitle — Dashboard, Incidents, Devices

Add the active server name as a subtitle below the title in the three data tabs' toolbar.

**Files:**
- Modify: `ios/BeNeM/Views/DashboardView.swift`
- Modify: `ios/BeNeM/Views/IncidentListView.swift`
- Modify: `ios/BeNeM/Views/DeviceListView.swift`

- [ ] **Step 1: DashboardView — add `@AppStorage` and update principal item**

  At the top of `DashboardView`, after the existing `@AppStorage` declarations, add:
  ```swift
  @AppStorage("netreo_active_connection_name") private var activeServerName = ""
  ```

  Find the `ToolbarItem(placement: .principal)` block and replace it:
  ```swift
  ToolbarItem(placement: .principal) {
      VStack(spacing: 1) {
          HStack(spacing: 6) {
              Image("BMCHelixLogo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: 22, height: 22)
              Text("Home")
                  .font(.system(size: 17, weight: .bold))
          }
          if !activeServerName.isEmpty {
              Text(activeServerName)
                  .font(.caption2)
                  .foregroundColor(.secondary)
          }
      }
  }
  ```

- [ ] **Step 2: IncidentListView — add `@AppStorage` and update principal item**

  At the top of `IncidentListView`, add:
  ```swift
  @AppStorage("netreo_active_connection_name") private var activeServerName = ""
  ```

  Find the `ToolbarItem(placement: .principal)` block and replace it:
  ```swift
  ToolbarItem(placement: .principal) {
      VStack(spacing: 1) {
          HStack(spacing: 6) {
              Image("BMCHelixLogo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: 22, height: 22)
              Text("Incidents")
                  .font(.system(size: 17, weight: .bold))
          }
          if !activeServerName.isEmpty {
              Text(activeServerName)
                  .font(.caption2)
                  .foregroundColor(.secondary)
          }
      }
  }
  ```

- [ ] **Step 3: DeviceListView — add `@AppStorage` and update principal item**

  At the top of `DeviceListView`, add:
  ```swift
  @AppStorage("netreo_active_connection_name") private var activeServerName = ""
  ```

  Find the `ToolbarItem(placement: .principal)` block — it currently shows `Text("Devices (\(viewModel.totalRecords))")` conditionally. Replace the whole `ToolbarItem(placement: .principal)`:
  ```swift
  ToolbarItem(placement: .principal) {
      VStack(spacing: 1) {
          HStack(spacing: 6) {
              Image("BMCHelixLogo")
                  .resizable()
                  .scaledToFit()
                  .frame(width: 22, height: 22)
              if viewModel.totalRecords > 0 {
                  Text("Devices (\(viewModel.totalRecords))")
                      .font(.system(size: 17, weight: .bold))
              } else {
                  Text("Devices")
                      .font(.system(size: 17, weight: .bold))
              }
          }
          if !activeServerName.isEmpty {
              Text(activeServerName)
                  .font(.caption2)
                  .foregroundColor(.secondary)
          }
      }
  }
  ```

- [ ] **Step 4: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. All three data tabs show the server name below the screen title in the toolbar.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/DashboardView.swift ios/BeNeM/Views/IncidentListView.swift ios/BeNeM/Views/DeviceListView.swift
  git commit -m "feat(ios): add active server name subtitle to Dashboard, Incidents, Devices toolbar"
  ```

---

## Task 7: Settings AppHeader — Connection Badge + Server Name Subtitle

Add the ConnectionBadge and server name subtitle to the Settings toolbar.

**Files:**
- Modify: `ios/BeNeM/Views/SettingsView.swift`

- [ ] **Step 1: Add required `@AppStorage` declarations to `SettingsView`**

  At the top of `SettingsView`, after the existing `@AppStorage` declarations, add:
  ```swift
  @AppStorage("netreo_base_url")    private var storedMiddlewareURL = ""
  @AppStorage("netreo_active_connection_name") private var activeServerName = ""
  ```
  
  (Note: `netreo_base_url` is the middleware URL — it's already read via `@AppStorage` in `ContentView`; we just need a local read here to derive connection status.)

- [ ] **Step 2: Replace the `.toolbar` block in `SettingsView`**

  Find the `.toolbar` modifier on the `Form` inside the `NavigationStack`. Replace it:
  ```swift
  .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
          ConnectionBadgeButton(
              status: (!storedMiddlewareURL.isEmpty && !activeSavedConnectionID.isEmpty)
                  ? .connected : .disconnected
          ) { /* no-op: Settings makes no live API calls */ }
      }
      ToolbarItem(placement: .principal) {
          VStack(spacing: 1) {
              HStack(spacing: 6) {
                  Image("BMCHelixLogo")
                      .resizable()
                      .scaledToFit()
                      .frame(width: 22, height: 22)
                  Text("Settings")
                      .font(.system(size: 17, weight: .bold))
              }
              if !activeServerName.isEmpty {
                  Text(activeServerName)
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
          Button { navigateToAdd = true } label: {
              Image(systemName: "plus")
          }
      }
  }
  ```

- [ ] **Step 3: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Settings tab now shows the connection chain badge on the left and server name subtitle in the center.

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/SettingsView.swift
  git commit -m "feat(ios): add connection badge and server name subtitle to Settings toolbar"
  ```

---

## Task 8: Settings Server List — Radio Select Button

Replace the passive green dot with a tappable radio-style circle button. The text area always navigates to edit.

**Files:**
- Modify: `ios/BeNeM/Views/SettingsView.swift`

- [ ] **Step 1: Replace `serverRowContent` active indicator with a circle Button**

  In `SettingsView`, replace the entire `serverRowContent(_:isActive:isSwitching:)` function:

  ```swift
  private func serverRowContent(_ connection: SavedConnection, isActive: Bool, isSwitching: Bool) -> some View {
      let displayHost = connection.bhnmURL.isEmpty ? connection.middlewareURL : connection.bhnmURL
      return HStack(spacing: 10) {
          // Radio circle — tapping selects (switch) or navigates to edit (active)
          Button {
              if isActive {
                  editingConnection = connection
                  showEditNavigation = true
              } else {
                  switchingToConnection = connection
              }
          } label: {
              ZStack {
                  Circle()
                      .strokeBorder(isActive ? Color.accentColor : Color(.systemGray4), lineWidth: 2)
                      .frame(width: 22, height: 22)
                  if isActive {
                      Circle()
                          .fill(Color.accentColor)
                          .frame(width: 22, height: 22)
                      Image(systemName: "checkmark")
                          .font(.system(size: 10, weight: .bold))
                          .foregroundColor(.white)
                  }
              }
          }
          .buttonStyle(.plain)
          .frame(width: 22)

          ServerIconView(symbol: connection.symbol, accentColor: connection.accentColor, size: 36)

          VStack(alignment: .leading, spacing: 2) {
              Text(connection.name).font(.body)
              Text(hostname(displayHost))
                  .font(.caption).foregroundColor(isActive ? .green : .secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if isSwitching { ProgressView() }
      }
  }
  ```

- [ ] **Step 2: Simplify `serverRow` — text area always edits**

  Replace the entire `serverRow(_:)` function so the text area opens edit for both active and inactive rows (remove the distinction):

  ```swift
  @ViewBuilder
  private func serverRow(_ connection: SavedConnection) -> some View {
      let isActive = connection.id.uuidString == activeSavedConnectionID
      let isSwitching = switchingInProgress == connection.id

      HStack(spacing: 0) {
          serverRowContent(connection, isActive: isActive, isSwitching: isSwitching)
              .contentShape(Rectangle())
              .onTapGesture {
                  editingConnection = connection
                  showEditNavigation = true
              }
      }
      .swipeActions(edge: .trailing) {
          Button {
              editingConnection = connection
              showEditNavigation = true
          } label: {
              Label("Edit", systemImage: "pencil")
          }
          .tint(.blue)
      }
  }
  ```

- [ ] **Step 3: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Inactive rows show an empty circle on the left; active row shows a filled blue circle with checkmark. Tapping the circle on inactive → switch dialog; tapping text → edit.

- [ ] **Step 4: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/SettingsView.swift
  git commit -m "feat(ios): replace green dot with radio circle button for server selection"
  ```

---

## Task 9: Settings Server List — Inline Delete

Add a trash button to each server row with two-tap confirmation, protected against deleting the active server.

**Files:**
- Modify: `ios/BeNeM/Views/SettingsView.swift`

- [ ] **Step 1: Add `deleteConfirmID` state and `deleteServer` helper**

  At the top of `SettingsView`, add a new `@State` property after the existing state declarations:
  ```swift
  @State private var deleteConfirmID: UUID? = nil
  @State private var showDeleteActiveAlert = false
  ```

  Add a new private helper function after `activateConnection(_:)`:
  ```swift
  private func deleteServer(_ connection: SavedConnection) {
      var connections = UserDefaults.standard.loadSavedConnections()
      connections.removeAll { $0.id == connection.id }
      UserDefaults.standard.saveSavedConnections(connections)
      deleteConfirmID = nil
      reload()
  }
  ```

- [ ] **Step 2: Update `serverRow` to include the trash button**

  Replace the `serverRow(_:)` function (replacing what was written in Task 8 Step 2):

  ```swift
  @ViewBuilder
  private func serverRow(_ connection: SavedConnection) -> some View {
      let isActive = connection.id.uuidString == activeSavedConnectionID
      let isSwitching = switchingInProgress == connection.id
      let isConfirmingDelete = deleteConfirmID == connection.id

      HStack(spacing: 0) {
          serverRowContent(connection, isActive: isActive, isSwitching: isSwitching)
              .contentShape(Rectangle())
              .onTapGesture {
                  deleteConfirmID = nil
                  editingConnection = connection
                  showEditNavigation = true
              }

          // Trash / confirm delete button
          Button {
              if isActive {
                  showDeleteActiveAlert = true
              } else if isConfirmingDelete {
                  deleteServer(connection)
              } else {
                  deleteConfirmID = connection.id
              }
          } label: {
              if isConfirmingDelete {
                  Text("Delete?")
                      .font(.caption).fontWeight(.semibold)
                      .foregroundColor(.white)
                      .padding(.horizontal, 8)
                      .padding(.vertical, 4)
                      .background(Color.red)
                      .cornerRadius(6)
              } else {
                  Image(systemName: "trash")
                      .font(.system(size: 14))
                      .foregroundColor(Color(.systemGray3))
                      .frame(width: 36, height: 36)
                      .contentShape(Rectangle())
              }
          }
          .buttonStyle(.plain)
          .padding(.trailing, 4)
      }
      .swipeActions(edge: .trailing) {
          Button {
              editingConnection = connection
              showEditNavigation = true
          } label: {
              Label("Edit", systemImage: "pencil")
          }
          .tint(.blue)
      }
      .onTapGesture {
          // Tapping outside the row buttons resets confirmation state
          if isConfirmingDelete { deleteConfirmID = nil }
      }
  }
  ```

- [ ] **Step 3: Add the "cannot delete active server" alert**

  In the `body`, inside the `ZStack`, after the `SwitchServerPopup` block, add:
  ```swift
  .alert("Cannot Delete Active Server", isPresented: $showDeleteActiveAlert) {
      Button("OK", role: .cancel) { }
  } message: {
      Text("Switch to another server before deleting this one.")
  }
  ```
  
  Add this as a modifier on the outer `ZStack`'s `.animation(...)` modifier line, chained after it.

- [ ] **Step 4: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Each server row has a trash icon on the right. First tap → "Delete?" confirmation in red. Second tap → deletes. Tapping active server's trash → alert.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/SettingsView.swift
  git commit -m "feat(ios): inline delete with two-tap confirmation in server list"
  ```

---

## Task 10: ThresholdCache + NetreoAPIService Methods

Create the shared threshold cache and add the two new API methods.

**Files:**
- Create: `ios/BeNeM/Models/ThresholdCache.swift`
- Modify: `ios/BeNeM/Services/NetreoAPIService.swift`

- [ ] **Step 1: Create `ThresholdCache.swift`**

  Create `ios/BeNeM/Models/ThresholdCache.swift`:

  ```swift
  import Foundation

  /// Shared in-memory cache for per-device threshold counts fetched from the middleware.
  /// Refreshes at most once every 10 minutes. Thread-safe via @MainActor.
  @MainActor
  final class ThresholdCache: ObservableObject {
      static let shared = ThresholdCache()

      @Published private(set) var counts: [String: Int] = [:]
      private var lastFetched: Date? = nil
      private let staleDuration: TimeInterval = 600 // 10 minutes

      private init() {}

      /// Fetch fresh counts if the cache is empty or stale.
      func refresh(using service: NetreoAPIService) async {
          guard lastFetched == nil || Date().timeIntervalSince(lastFetched!) > staleDuration else { return }
          if let fresh = try? await service.fetchThresholdCounts() {
              counts = fresh
              lastFetched = Date()
          }
      }

      /// Threshold count for a given device name. Returns 0 if the device is not in the cache.
      func count(for deviceName: String) -> Int {
          counts[deviceName] ?? 0
      }

      /// Invalidate cache so the next refresh() call fetches fresh data.
      func invalidate() {
          lastFetched = nil
      }
  }
  ```

- [ ] **Step 2: Add `fetchThresholdCounts()` to `NetreoAPIService`**

  Add the following method to `NetreoAPIService` (place it in a new `// MARK: - Threshold Cache` section):

  ```swift
  // MARK: - Threshold Cache

  /// Fetches pre-aggregated threshold counts per device from the middleware cache.
  /// Returns a dictionary mapping device name → threshold count.
  func fetchThresholdCounts() async throws -> [String: Int] {
      guard let url = URL(string: "\(configuration.baseURL)/api/v1/threshold-counts") else {
          throw URLError(.badURL)
      }
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      addProxyToken(&request)
      let (data, response) = try await urlSession.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
          throw URLError(.badServerResponse)
      }
      guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          return [:]
      }
      var result: [String: Int] = [:]
      for (key, value) in raw {
          if let intVal = value as? Int {
              result[key] = intVal
          } else if let numVal = value as? NSNumber {
              result[key] = numVal.intValue
          }
      }
      return result
  }
  ```

- [ ] **Step 3: Add `fetchDeviceServices(deviceName:)` to `NetreoAPIService`**

  Add the following method in the same `// MARK: - Threshold Cache` section:

  ```swift
  /// Fetches the count of enabled + OK service checks for a device.
  func fetchDeviceServices(deviceName: String) async throws -> Int {
      guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/services") else {
          throw URLError(.badURL)
      }
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      addProxyToken(&request)
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      var params = [
          URLQueryItem(name: "password", value: configuration.apiKey),
          URLQueryItem(name: "name",     value: deviceName)
      ]
      if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
      request.httpBody = formEncodedBody(params)
      let (data, _) = try await urlSession.data(for: request)
      guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
          return 0
      }
      return raw.filter { item in
          let enabled = (item["enabled"] as? Bool) ?? ((item["enabled"] as? Int) == 1)
          let status  = (item["status"] as? String ?? "").lowercased()
          return enabled && (status == "ok" || status == "up")
      }.count
  }
  ```

- [ ] **Step 4: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Models/ThresholdCache.swift ios/BeNeM/Services/NetreoAPIService.swift
  git commit -m "feat(ios): add ThresholdCache singleton and fetchThresholdCounts/fetchDeviceServices API methods"
  ```

---

## Task 11: DeviceDetailViewModel — Real HEALTHY Formula

Replace the binary HEALTHY count with the threshold-based formula.

**Files:**
- Modify: `ios/BeNeM/ViewModels/DeviceDetailViewModel.swift`

- [ ] **Step 1: Add `okServiceChecks` published property**

  In `DeviceDetailViewModel`, after `@Published var criticalCount: Int = 0`, add:
  ```swift
  @Published var okServiceChecks: Int = 0
  @Published var isLoadingServices: Bool = false
  ```

- [ ] **Step 2: Update `loadIncidents()` to use the new HEALTHY formula**

  In `DeviceDetailViewModel.loadIncidents()`, replace the alarm counts block:

  ```swift
  // Replace this:
  var healthy = 0, ack = 0, warn = 0, crit = 0
  for incident in incidents {
      if incident.status == .acknowledged {
          ack += 1
      } else {
          switch incident.severity {
          case .critical, .major: crit += 1
          case .warning, .minor:  warn += 1
          case .informational: break
          }
      }
  }
  if incidents.isEmpty { healthy = 1 }
  healthyCount = healthy
  ackCount = ack
  warningCount = warn
  criticalCount = crit

  // With this:
  var ack = 0, warn = 0, crit = 0
  for incident in incidents {
      if incident.status == .acknowledged {
          ack += 1
      } else {
          switch incident.severity {
          case .critical, .major: crit += 1
          case .warning, .minor:  warn += 1
          case .informational: break
          }
      }
  }
  let activeIncidents = crit + warn
  let thresholds = await ThresholdCache.shared.count(for: device.name)
  healthyCount = max(0, thresholds + okServiceChecks - activeIncidents)
  ackCount = ack
  warningCount = warn
  criticalCount = crit
  ```

  Note: `loadIncidents()` is already `async`, so `await ThresholdCache.shared.count(for:)` is valid (though `ThresholdCache` is `@MainActor` and `count(for:)` is not throwing — remove `await` if the compiler complains; `ThresholdCache.shared.count(for:)` can be called synchronously since it's `@MainActor` and `loadIncidents` runs on `@MainActor` too).

  Correct form (both are `@MainActor`, so no `await` needed):
  ```swift
  let thresholds = ThresholdCache.shared.count(for: device.name)
  healthyCount = max(0, thresholds + okServiceChecks - activeIncidents)
  ```

- [ ] **Step 3: Add `loadServices()` and call it concurrently with `loadIncidents()`**

  Add a new private method to `DeviceDetailViewModel`:

  ```swift
  private func loadServices() async {
      isLoadingServices = true
      if let count = try? await apiService.fetchDeviceServices(deviceName: device.name) {
          okServiceChecks = count
      }
      isLoadingServices = false
  }
  ```

  `load()` already exists in `DeviceDetailViewModel` and uses `withTaskGroup`. Update it to also add the services task and the threshold cache refresh:

  ```swift
  func load() async {
      loadPinnedInterfaces()
      await ThresholdCache.shared.refresh(using: apiService)
      await withTaskGroup(of: Void.self) { group in
          group.addTask { await self.loadIncidents() }
          group.addTask { await self.loadPerformanceStructure() }
          group.addTask { await self.loadServices() }
      }
  }
  ```

- [ ] **Step 4: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. On the device detail screen, HEALTHY now shows threshold-based counts.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/ViewModels/DeviceDetailViewModel.swift
  git commit -m "feat(ios): HEALTHY count uses threshold cache + service checks formula"
  ```

---

## Task 12: DeviceListView — incidentViewModel + Per-Row Alarm Badges

Pass the global incident list into `DeviceListView` and show per-row alarm badges.

**Files:**
- Modify: `ios/BeNeM/Views/DeviceListView.swift`
- Modify: `ios/BeNeM/ViewModels/DeviceListViewModel.swift`
- Modify: `ios/BeNeM/ContentView.swift`

- [ ] **Step 1: Update `DeviceListViewModel.loadDevices()` to refresh the threshold cache**

  In `DeviceListViewModel.loadDevices()`, add a cache refresh call after the devices are loaded successfully:

  ```swift
  func loadDevices() async {
      isLoading = true
      errorMessage = nil
      do {
          let page = try await apiService.fetchDevices(recordStart: 0, recordCount: pageSize)
          devices = page.devices
          totalRecords = page.totalRecords
          hasMore = page.devices.count < page.totalRecords
          await ThresholdCache.shared.refresh(using: apiService)
      } catch {
          errorMessage = error.localizedDescription
      }
      isLoading = false
  }
  ```

- [ ] **Step 2: Add `DeviceAlarmCounts` struct and helper to `DeviceListView.swift`**

  Add these two types at the top of `DeviceListView.swift`, below the `import SwiftUI` line:

  ```swift
  struct DeviceAlarmCounts {
      let healthy: Int   // -1 means "threshold cache not loaded yet" → show "—"
      let ack: Int
      let warning: Int
      let critical: Int
  }

  private func deviceAlarmCounts(for deviceName: String, incidents: [NetreoIncident]) -> DeviceAlarmCounts {
      let deviceIncidents = incidents.filter {
          ($0.deviceName ?? "").caseInsensitiveCompare(deviceName) == .orderedSame
      }
      var ack = 0, warn = 0, crit = 0
      for incident in deviceIncidents {
          if incident.status == .acknowledged {
              ack += 1
          } else {
              switch incident.severity {
              case .critical, .major: crit += 1
              case .warning, .minor:  warn += 1
              case .informational: break
              }
          }
      }
      let thresholdsLoaded = !ThresholdCache.shared.counts.isEmpty
      let thresholds = ThresholdCache.shared.count(for: deviceName)
      let activeCount = crit + warn
      let healthy = thresholdsLoaded ? max(0, thresholds - activeCount) : -1
      return DeviceAlarmCounts(healthy: healthy, ack: ack, warning: warn, critical: crit)
  }
  ```

- [ ] **Step 3: Add `incidentViewModel` parameter to `DeviceListView`**

  Update `DeviceListView`'s declaration and `init`:

  ```swift
  struct DeviceListView: View {
      @StateObject private var viewModel: DeviceListViewModel
      @ObservedObject var incidentViewModel: IncidentListViewModel
      @ObservedObject private var thresholdCache = ThresholdCache.shared
      @State private var connectionStatus: ConnectionStatus = .unknown
      @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
      @AppStorage("netreo_active_connection_name") private var activeServerName = ""
      private let apiService: NetreoAPIService

      init(apiService: NetreoAPIService, incidentViewModel: IncidentListViewModel) {
          self.apiService = apiService
          self.incidentViewModel = incidentViewModel
          _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
      }
  ```

- [ ] **Step 4: Update `DeviceRowView` to accept and display alarm counts**

  Replace `DeviceRowView`:

  ```swift
  struct DeviceRowView: View {
      let device: NetreoDevice
      let alarmCounts: DeviceAlarmCounts

      var body: some View {
          VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 12) {
                  DeviceTypeIcon(typeClass: device.typeClass, size: 36, color: statusColor)

                  VStack(alignment: .leading, spacing: 2) {
                      Text(device.name)
                          .font(.headline)
                      HStack(spacing: 4) {
                          Text(device.ip)
                          Text("·")
                          Text(device.category)
                          Text("·")
                          Text(device.site)
                      }
                      .font(.caption)
                      .foregroundColor(.secondary)
                      .lineLimit(1)
                  }

                  Spacer()
              }

              // Alarm badge strip
              HStack(spacing: 0) {
                  alarmBadge(
                      label: "HEALTHY",
                      value: alarmCounts.healthy,
                      color: .green,
                      missing: alarmCounts.healthy == -1
                  )
                  alarmBadge(label: "ACK",      value: alarmCounts.ack,      color: .blue)
                  alarmBadge(label: "WARNING",  value: alarmCounts.warning,  color: .orange)
                  alarmBadge(label: "CRITICAL", value: alarmCounts.critical, color: .red)
              }
          }
          .padding(.vertical, 4)
      }

      private func alarmBadge(label: String, value: Int, color: Color, missing: Bool = false) -> some View {
          VStack(spacing: 1) {
              if missing {
                  Text("—")
                      .font(.caption).fontWeight(.bold)
                      .foregroundColor(Color(.systemGray4))
              } else {
                  Text("\(value)")
                      .font(.caption).fontWeight(.bold)
                      .foregroundColor(value > 0 ? color : Color(.systemGray4))
              }
              Text(label)
                  .font(.system(size: 7))
                  .foregroundColor(Color(.systemGray3))
          }
          .frame(maxWidth: .infinity)
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

- [ ] **Step 5: Update `NavigationLink` in `DeviceListView.body` to pass alarm counts**

  In `DeviceListView.body`, find the `ForEach` with `NavigationLink` and update it:

  ```swift
  ForEach(viewModel.displayedDevices) { device in
      NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
          DeviceRowView(
              device: device,
              alarmCounts: deviceAlarmCounts(for: device.name, incidents: incidentViewModel.incidents)
          )
      }
  }
  ```

- [ ] **Step 6: Update `ContentView.mainTabs` to pass `incidentViewModel`**

  In `ContentView.swift`, find `DeviceListView(apiService: service)` and update it:

  ```swift
  DeviceListView(apiService: service, incidentViewModel: incidentViewModel)
      .tag(2)
  ```

- [ ] **Step 7: Build**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/ios
  ./build_and_deploy.sh
  ```
  Expected: build succeeds. Device list rows now show HEALTHY / ACK / WARNING / CRITICAL badge strip. HEALTHY shows `—` until threshold cache loads.

- [ ] **Step 8: Commit**

  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add ios/BeNeM/Views/DeviceListView.swift ios/BeNeM/ViewModels/DeviceListViewModel.swift ios/BeNeM/ContentView.swift
  git commit -m "feat(ios): per-row alarm badges with threshold-based HEALTHY count in device list"
  ```

---

## Post-Implementation: Update feature-spec.md

- [ ] **Update shared/feature-spec.md**

  Update the **Threshold Cache** feature status from `shipped-pwa` to `shipped-both`:
  ```
  **Status:** shipped-both
  ```

  Add an `#### iOS-specific` subsection under Threshold Cache:
  ```markdown
  #### iOS-specific
  - `ThresholdCache.shared` singleton (`Models/ThresholdCache.swift`); refreshes on `DeviceListViewModel.loadDevices()` and `DeviceDetailViewModel.load()`
  - HEALTHY in device list: `ThresholdCache[name] − activeIncidents`
  - HEALTHY in device detail alarm bar: `ThresholdCache[name] + okServiceChecks − activeIncidents`
  - Shows `—` in device list if cache is empty (not yet loaded)
  ```

  Commit:
  ```bash
  cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
  git add shared/feature-spec.md
  git commit -m "docs: mark Threshold Cache as shipped-both, add iOS implementation notes"
  ```
