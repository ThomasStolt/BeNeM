# Multi-Server BHNM + Middleware Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `bhnmURL` + `notificationsEnabled` to `SavedConnection`, route all API calls through a per-request middleware proxy using `X-Proxy-Token` / `X-BHNM-Target` headers, support push unregistration on server switch, and update the deep-link provisioning tool.

**Architecture:** `SavedConnection` gains `bhnmURL` (direct BHNM URL) and `notificationsEnabled`; `baseURL` is renamed `middlewareURL`. When a connection has a middleware URL, every API call is proxied through it using two new headers; when middleware is absent the app connects directly to `bhnmURL`. Push registration/unregistration is coordinated in `AppDelegate` and triggered from `SettingsView` on server switch.

**Tech Stack:** Swift/SwiftUI, URLSession, `UserDefaults` (Codable JSON), APNs, Python 3 (`argparse`, `cryptography`)

---

## File Map

| File | Change |
|---|---|
| `BeNeM/Models/SavedConnection.swift` | Add `bhnmURL`, rename `baseURL`→`middlewareURL`, add `notificationsEnabled`; custom `init(from:)` for migration defaults |
| `BeNeM/Services/NetreoAPIConfiguration.swift` | Add `bhnmURL` field + init param |
| `BeNeM/Services/NetreoAPIService.swift` | `addProxyToken` → also sets `X-BHNM-Target` |
| `BeNeM/AppDelegate.swift` | Add `unregisterWithMiddleware`; update `activeConnectionPushCredentials` field name; guard launch registration on `notificationsEnabled` |
| `BeNeM/ContentView.swift` | Add `netreo_bhnm_url` AppStorage; update `updateAPIService` condition + config construction; guard push registration on `notificationsEnabled` |
| `BeNeM/Views/SettingsView.swift` | `activateConnection` syncs `bhnmURL`; unregisters old push, registers new; migration warning banner; `hostname()` uses `bhnmURL` |
| `BeNeM/Views/ServerConfigView.swift` | Redesign: split into Connection + Push Notifications sections; `draftBhnmURL`; notifications toggle + conditional middleware fields; updated test + save logic |
| `BeNeM/Services/DeepLinkHandler.swift` | `PendingImport` adds `bhnmURL`/`middlewareURL`/`notificationsEnabled`; `handleCompactPayload` reads new keys + backward compat `server`; `applyPendingImport` upserts by `bhnmURL` |
| `BeNeM/BeNeMApp.swift` | Fix `.baseURL` reference in migration guard (Task 1); update alert message from `imp.serverURL` to `imp.bhnmURL` (Task 8) |
| `generate_benem_link.py` | New `--bhnm-url` (required), optional `--middleware-url`, `--notifications/--no-notifications`; payload keys `bhnm_url`/`middleware_url` replace `server` |

---

## Task 1: Update `SavedConnection` data model

**Files:**
- Modify: `BeNeM/Models/SavedConnection.swift`

This is the foundation — all downstream tasks compile against this new model. We rename `baseURL` → `middlewareURL`, add `bhnmURL` and `notificationsEnabled`, and write a custom `init(from:)` so existing JSON (which has `"baseURL"` key, no `bhnmURL` or `notificationsEnabled`) decodes cleanly with safe defaults.

- [ ] **Step 1: Replace the entire `SavedConnection.swift` with the updated model**

```swift
// BeNeM/Models/SavedConnection.swift
import Foundation

struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var middlewareURL: String    // previously "baseURL"; proxy + APNs registration endpoint
    var bhnmURL: String         // direct BHNM server URL; sent as X-BHNM-Target
    var notificationsEnabled: Bool
    var apiKey: String
    var pin: String             // "" = absent
    var ackUser: String         // "" = absent
    var webhookSecret: String
    var symbol: String
    var accentColor: String

    // MARK: - Memberwise init (notificationsEnabled defaults true for new connections)
    init(
        id: UUID = UUID(),
        name: String,
        middlewareURL: String = "",
        bhnmURL: String,
        notificationsEnabled: Bool = true,
        apiKey: String,
        pin: String = "",
        ackUser: String = "",
        webhookSecret: String = "",
        symbol: String = "server.rack",
        accentColor: String = "#0A84FF"
    ) {
        self.id = id
        self.name = name
        self.middlewareURL = middlewareURL
        self.bhnmURL = bhnmURL
        self.notificationsEnabled = notificationsEnabled
        self.apiKey = apiKey
        self.pin = pin
        self.ackUser = ackUser
        self.webhookSecret = webhookSecret
        self.symbol = symbol
        self.accentColor = accentColor
    }

    // MARK: - Codable: maps "baseURL" JSON key → middlewareURL field; defaults for new fields
    enum CodingKeys: String, CodingKey {
        case id, name, apiKey, pin, ackUser, webhookSecret, symbol, accentColor
        case middlewareURL = "baseURL"   // backward compat: existing JSON uses "baseURL"
        case bhnmURL
        case notificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(UUID.self,   forKey: .id)
        name                 = try c.decode(String.self, forKey: .name)
        middlewareURL        = try c.decode(String.self, forKey: .middlewareURL)
        bhnmURL              = try c.decodeIfPresent(String.self, forKey: .bhnmURL)              ?? ""
        // Migration default: false — bhnmURL is empty so push registration would be incomplete
        notificationsEnabled = try c.decodeIfPresent(Bool.self,   forKey: .notificationsEnabled) ?? false
        apiKey               = try c.decode(String.self, forKey: .apiKey)
        pin                  = try c.decodeIfPresent(String.self, forKey: .pin)                  ?? ""
        ackUser              = try c.decodeIfPresent(String.self, forKey: .ackUser)              ?? ""
        webhookSecret        = try c.decodeIfPresent(String.self, forKey: .webhookSecret)        ?? ""
        symbol               = try c.decodeIfPresent(String.self, forKey: .symbol)               ?? "server.rack"
        accentColor          = try c.decodeIfPresent(String.self, forKey: .accentColor)          ?? "#0A84FF"
    }
}

extension UserDefaults {
    private static let savedConnectionsKey = "saved_connections"

    func loadSavedConnections() -> [SavedConnection] {
        guard let data = data(forKey: Self.savedConnectionsKey) else { return [] }
        return (try? JSONDecoder().decode([SavedConnection].self, from: data)) ?? []
    }

    func saveSavedConnections(_ connections: [SavedConnection]) {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        set(data, forKey: Self.savedConnectionsKey)
    }
}
```

- [ ] **Step 2: Fix all `conn.baseURL` / `.baseURL` references broken by the rename**

The rename of `baseURL` → `middlewareURL` breaks these call sites. Fix each:

**`BeNeM/AppDelegate.swift`** line 115:
```swift
// OLD:
return (conn.webhookSecret, conn.baseURL)
// NEW:
return (conn.webhookSecret, conn.middlewareURL)
```

**`BeNeM/ContentView.swift`** line 54:
```swift
// OLD:
AppDelegate.shared?.registerWithMiddleware(token: token, secret: conn.webhookSecret, middlewareURL: conn.baseURL)
// NEW:
AppDelegate.shared?.registerWithMiddleware(token: token, secret: conn.webhookSecret, middlewareURL: conn.middlewareURL)
```

**`BeNeM/Views/SettingsView.swift`** — `activateConnection` (line 186) + `serverRowContent` (lines 166, 169):
```swift
// activateConnection:
// OLD: UserDefaults.standard.set(connection.baseURL, forKey: "netreo_base_url")
// NEW: UserDefaults.standard.set(connection.middlewareURL, forKey: "netreo_base_url")

// serverRowContent:
// OLD: Text("Active · \(hostname(connection.baseURL))")
// NEW: Text("Active · \(hostname(connection.middlewareURL))")
// OLD: Text(hostname(connection.baseURL))
// NEW: Text(hostname(connection.middlewareURL))
```

**`BeNeM/Views/ServerConfigView.swift`** — `populateDrafts` (line 170) + `saveConnection`:
```swift
// populateDrafts:
// OLD: draftBaseURL = conn.baseURL
// NEW: draftBaseURL = conn.middlewareURL

// saveConnection — the SavedConnection init:
// OLD: baseURL: urlString,
// NEW: middlewareURL: urlString, bhnmURL: "",
```

**`BeNeM/Services/DeepLinkHandler.swift`** — `applyPendingImport`:
```swift
// line 97: OLD: $0.baseURL.lowercased() == serverLower
// NEW: $0.middlewareURL.lowercased() == serverLower  (temporary — Task 8 changes this to bhnmURL)

// line 115: OLD: baseURL: imp.serverURL,
// NEW: middlewareURL: imp.serverURL, bhnmURL: "",

// line 139: OLD: middlewareURL: conn.baseURL
// NEW: middlewareURL: conn.middlewareURL
```

**`BeNeM/BeNeMApp.swift`** — `migrateLegacyKeysToSavedConnectionIfNeeded`:
```swift
// line 22: OLD: guard !connections.contains(where: { $0.baseURL.lowercased() == url.lowercased() }) else { return }
// NEW: guard !connections.contains(where: { $0.middlewareURL.lowercased() == url.lowercased() }) else { return }

// line 26-33: OLD SavedConnection init: baseURL: url
// NEW:
let newConn = SavedConnection(
    id: UUID(),
    name: name,
    middlewareURL: url,
    bhnmURL: "",
    notificationsEnabled: false,   // migration default
    apiKey: key,
    pin: pin,
    ackUser: ackUser
)
```

- [ ] **Step 3: Build to verify no compilation errors**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|warning:|BUILD)'
```

Expected: `BUILD SUCCEEDED` (or only pre-existing warnings)

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Models/SavedConnection.swift \
        BeNeM/AppDelegate.swift \
        BeNeM/ContentView.swift \
        BeNeM/Views/SettingsView.swift \
        BeNeM/Views/ServerConfigView.swift \
        BeNeM/Services/DeepLinkHandler.swift
git commit -m "refactor: rename SavedConnection.baseURL → middlewareURL, add bhnmURL + notificationsEnabled"
```

---

## Task 2: Add `bhnmURL` to `NetreoAPIConfiguration`

**Files:**
- Modify: `BeNeM/Services/NetreoAPIConfiguration.swift`

The configuration now carries `bhnmURL` so `NetreoAPIService` can inject it as `X-BHNM-Target`.

- [ ] **Step 1: Add `bhnmURL` field and init parameter to `NetreoAPIConfiguration`**

```swift
struct NetreoAPIConfiguration {
    let baseURL: String       // = middlewareURL when proxy is active; = bhnmURL for direct connections
    let bhnmURL: String       // direct BHNM URL — sent as X-BHNM-Target; "" for direct connections
    let apiKey: String
    let pin: String?
    let proxyToken: String
    let version: APIVersion
    let timeout: TimeInterval
    let retryCount: Int

    init(baseURL: String, bhnmURL: String = "", apiKey: String, pin: String? = nil,
         proxyToken: String = "", version: APIVersion = .legacy,
         timeout: TimeInterval = 30, retryCount: Int = 3) {
        let normalizedURL = baseURL.trimmingSuffix("/")
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            self.baseURL = "http://\(normalizedURL)"
        } else {
            self.baseURL = normalizedURL
        }
        self.bhnmURL    = bhnmURL
        self.apiKey     = apiKey
        self.pin        = pin
        self.proxyToken = proxyToken
        self.version    = version
        self.timeout    = timeout
        self.retryCount = retryCount
    }
    // ... rest unchanged
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Services/NetreoAPIConfiguration.swift
git commit -m "feat: add bhnmURL field to NetreoAPIConfiguration"
```

---

## Task 3: Add `X-BHNM-Target` header in `NetreoAPIService`

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

A one-line addition to `addProxyToken` so every outbound request gains both headers when a proxy is configured.

- [ ] **Step 1: Extend `addProxyToken` to also set `X-BHNM-Target`**

In `NetreoAPIService.swift`, replace the `addProxyToken` method:

```swift
// OLD:
private func addProxyToken(_ request: inout URLRequest) {
    guard !configuration.proxyToken.isEmpty else { return }
    request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
}

// NEW:
private func addProxyToken(_ request: inout URLRequest) {
    guard !configuration.proxyToken.isEmpty else { return }
    request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
    if !configuration.bhnmURL.isEmpty {
        request.setValue(configuration.bhnmURL, forHTTPHeaderField: "X-BHNM-Target")
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: add X-BHNM-Target header to all proxied API requests"
```

---

## Task 4: Add `unregisterWithMiddleware` to `AppDelegate`

**Files:**
- Modify: `BeNeM/AppDelegate.swift`

Adds the unregister endpoint and guards launch-time registration on `notificationsEnabled`.

- [ ] **Step 1: Add `unregisterWithMiddleware` method**

After the `registerWithMiddleware` method, add:

```swift
func unregisterWithMiddleware(token: String, secret: String, middlewareURL: String) {
    guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
        print("[APNs] No middleware URL — skipping token unregistration.")
        return
    }
    guard !secret.isEmpty else {
        print("[APNs] No webhook secret — skipping token unregistration.")
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(secret, forHTTPHeaderField: "X-Webhook-Token")
    let body: [String: String] = ["token": token]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            print("[APNs] Middleware unregistration error: \(error)")
        } else if let http = response as? HTTPURLResponse {
            print("[APNs] Middleware unregister responded: \(http.statusCode)")
        }
    }.resume()
}
```

- [ ] **Step 2: Guard `didRegisterForRemoteNotificationsWithDeviceToken` on `notificationsEnabled`**

Replace the `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` body:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("[APNs] Device token: \(token)")
    cachedDeviceToken = token
    let ud = UserDefaults.standard
    guard let activeID = ud.string(forKey: "netreo_active_connection_id"), !activeID.isEmpty,
          let conn = ud.loadSavedConnections().first(where: { $0.id.uuidString == activeID }),
          conn.notificationsEnabled else {
        print("[APNs] notificationsEnabled is false for active connection — skipping registration.")
        return
    }
    registerWithMiddleware(token: token, secret: conn.webhookSecret, middlewareURL: conn.middlewareURL)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/AppDelegate.swift
git commit -m "feat: add unregisterWithMiddleware; guard launch push registration on notificationsEnabled"
```

---

## Task 5: Wire `bhnmURL` + push logic in `ContentView`

**Files:**
- Modify: `BeNeM/ContentView.swift`

Adds `netreo_bhnm_url` AppStorage, updates the API service condition and configuration, and guards the push registration on `notificationsEnabled`.

- [ ] **Step 1: Add `netreo_bhnm_url` AppStorage property**

After `@AppStorage("netreo_webhook_secret") private var webhookSecret = ""`, add:

```swift
@AppStorage("netreo_bhnm_url") private var bhnmURL = ""
```

- [ ] **Step 2: Update `updateAPIService()` and tab condition**

Replace `updateAPIService` and the tab-show condition:

```swift
// Tab show condition — in body:
// OLD: if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
// NEW: if !bhnmURL.isEmpty && !apiKey.isEmpty, let service = apiService {

private func updateAPIService() {
    guard !bhnmURL.isEmpty && !apiKey.isEmpty else {
        apiService = nil
        return
    }
    let apiVersion = NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy
    // Route through middleware when configured; connect directly to BHNM otherwise
    let serviceBaseURL = baseURL.isEmpty ? bhnmURL : baseURL
    let serviceProxyToken = baseURL.isEmpty ? "" : webhookSecret
    let serviceBhnmURL = baseURL.isEmpty ? "" : bhnmURL
    let configuration = NetreoAPIConfiguration(
        baseURL: serviceBaseURL,
        bhnmURL: serviceBhnmURL,
        apiKey: apiKey,
        pin: pin.isEmpty ? nil : pin,
        proxyToken: serviceProxyToken,
        version: apiVersion,
        timeout: timeout,
        retryCount: Int(retryCount)
    )
    apiService = NetreoAPIService(configuration: configuration)
}
```

- [ ] **Step 3: Add `onChange(of: bhnmURL)` and guard push on `notificationsEnabled`**

In the body modifiers, add:
```swift
.onChange(of: bhnmURL) { _, _ in updateAPIService() }
```

Update `onChange(of: activeConnectionID)` to unregister the old connection's push before registering the new one. This handles connection switches triggered by deep links (which don't go through `SettingsView.activateConnection`):
```swift
.onChange(of: activeConnectionID) { oldID, newID in
    let connections = UserDefaults.standard.loadSavedConnections()
    // Unregister old connection's push if it had notifications enabled
    if !oldID.isEmpty,
       let oldConn = connections.first(where: { $0.id.uuidString == oldID }),
       oldConn.notificationsEnabled,
       !oldConn.middlewareURL.isEmpty,
       let token = AppDelegate.shared?.cachedDeviceToken {
        AppDelegate.shared?.unregisterWithMiddleware(
            token: token,
            secret: oldConn.webhookSecret,
            middlewareURL: oldConn.middlewareURL
        )
    }
    // Register new connection's push if it has notifications enabled
    guard !newID.isEmpty,
          let conn = connections.first(where: { $0.id.uuidString == newID }),
          conn.notificationsEnabled,
          let token = AppDelegate.shared?.cachedDeviceToken else { return }
    UserDefaults.standard.set(conn.webhookSecret, forKey: "netreo_webhook_secret")
    AppDelegate.shared?.registerWithMiddleware(
        token: token,
        secret: conn.webhookSecret,
        middlewareURL: conn.middlewareURL
    )
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/ContentView.swift
git commit -m "feat: wire netreo_bhnm_url AppStorage; guard push registration on notificationsEnabled"
```

---

## Task 6: Update `SettingsView` — `activateConnection` + migration banner

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

`activateConnection` must: unregister old push → sync all new credentials (including `bhnmURL`) → registration of new push happens via `ContentView.onChange(of: activeConnectionID)`. Also: show migration warning banner, and display `bhnmURL` hostname in server rows.

- [ ] **Step 1: Sync `netreo_bhnm_url` in `activateConnection` and add unregister/register logic**

Replace `activateConnection`:

```swift
private func activateConnection(_ new: SavedConnection) {
    switchingInProgress = new.id

    // Unregister push for the connection we're leaving
    if let old = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }),
       old.notificationsEnabled,
       !old.middlewareURL.isEmpty,
       let token = AppDelegate.shared?.cachedDeviceToken {
        AppDelegate.shared?.unregisterWithMiddleware(
            token: token,
            secret: old.webhookSecret,
            middlewareURL: old.middlewareURL
        )
    }

    // Sync all credentials for the new connection
    UserDefaults.standard.set(new.middlewareURL,  forKey: "netreo_base_url")
    UserDefaults.standard.set(new.bhnmURL,        forKey: "netreo_bhnm_url")
    UserDefaults.standard.set(new.apiKey,         forKey: "netreo_api_key")
    UserDefaults.standard.set(new.pin,            forKey: "netreo_pin")
    UserDefaults.standard.set(new.ackUser,        forKey: "netreo_ack_user")
    UserDefaults.standard.set(new.webhookSecret,  forKey: "netreo_webhook_secret")
    activeSavedConnectionID = new.id.uuidString
    // Push registration for the new connection fires via ContentView.onChange(of: activeConnectionID)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        switchingInProgress = nil
        reload()
    }
}
```

- [ ] **Step 2: Show `bhnmURL` hostname in server rows**

In `serverRowContent`, update the subtitle lines to show `bhnmURL` hostname (more meaningful than middleware host):

```swift
// OLD:
if isActive {
    Text("Active · \(hostname(connection.middlewareURL))")
} else {
    Text(hostname(connection.middlewareURL))
}

// NEW:
let displayHost = connection.bhnmURL.isEmpty ? connection.middlewareURL : connection.bhnmURL
if isActive {
    Text("Active · \(hostname(displayHost))")
        .font(.caption).foregroundColor(.green)
} else {
    Text(hostname(displayHost))
        .font(.caption).foregroundColor(.secondary)
}
```

- [ ] **Step 3: Add migration warning banner**

In the BHNM Servers section, after the `ForEach`, add a banner shown when the active connection has an empty `bhnmURL`. The banner should appear as the first item in the section (before `ForEach`), inline:

```swift
Section(header: Text("BHNM Servers")) {
    // Migration banner: shown when active connection has no bhnmURL set
    if let active = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }),
       active.bhnmURL.isEmpty {
        Button {
            editingConnection = active
            showEditNavigation = true
        } label: {
            Label("Tap to complete setup — BHNM URL required", systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.subheadline)
        }
    }
    ForEach(savedConnections) { connection in
        serverRow(connection)
    }
    Button {
        navigateToAdd = true
    } label: {
        Label("Add BHNM Server", systemImage: "plus.circle.fill")
            .foregroundColor(.accentColor)
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: sync bhnmURL on connection switch, add migration banner, unregister old push"
```

---

## Task 7: Redesign `ServerConfigView` — two-section layout

**Files:**
- Modify: `BeNeM/Views/ServerConfigView.swift`

Replaces the single-section layout with **Connection** (BHNM URL replaces Middleware URL) and **Push Notifications** (toggle + greyed middleware URL + secret) sections. Updates the test-and-save logic to test via middleware (when enabled) or directly to BHNM (when disabled).

- [ ] **Step 1: Replace the entire `ServerConfigView.swift`**

```swift
// BeNeM/Views/ServerConfigView.swift
import SwiftUI

struct ServerConfigView: View {
    let existingConnection: SavedConnection?

    @AppStorage("netreo_base_url")              private var storedMiddlewareURL = ""
    @AppStorage("netreo_bhnm_url")              private var storedBhnmURL = ""
    @AppStorage("netreo_api_key")               private var apiKey = ""
    @AppStorage("netreo_pin")                   private var pin = ""
    @AppStorage("netreo_ack_user")              private var ackUser = ""
    @AppStorage("netreo_active_connection_id")  private var activeSavedConnectionID = ""

    // Draft state — Connection section
    @State private var draftName       = ""
    @State private var draftBhnmURL    = ""
    @State private var draftApiKey     = ""
    @State private var draftPin        = ""
    @State private var draftAckUser    = ""
    @State private var draftSymbol     = "server.rack"
    @State private var draftColor      = "#0A84FF"

    // Draft state — Push Notifications section
    @State private var draftNotificationsEnabled = true
    @State private var draftMiddlewareURL        = ""
    @State private var draftPushSecret           = ""

    @State private var showingIconPicker       = false
    @State private var isTesting               = false
    @State private var testStatus: TestStatus  = .untested
    @State private var alertTitle              = ""
    @State private var alertMessage            = ""
    @State private var showingAlert            = false
    @State private var showingDeleteConfirm    = false

    @State private var savedConnections: [SavedConnection] = []

    private enum TestStatus { case untested, success, failure }
    private enum Field: Hashable { case name, bhnmURL, apiKey, pin, ackUser, middlewareURL, pushSecret }
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private var isAddMode: Bool { existingConnection == nil }
    private var activeID: UUID? { UUID(uuidString: activeSavedConnectionID) }

    // Save button disabled when required fields are empty
    private var saveDisabled: Bool {
        isTesting
        || draftName.isEmpty
        || draftBhnmURL.isEmpty
        || draftApiKey.isEmpty
        || draftAckUser.isEmpty
        || (draftNotificationsEnabled && (draftMiddlewareURL.isEmpty || draftPushSecret.isEmpty))
    }

    var body: some View {
        Form {
            // Icon header
            Section {
                VStack(spacing: 6) {
                    Button {
                        showingIconPicker = true
                    } label: {
                        VStack(spacing: 6) {
                            ServerIconView(symbol: draftSymbol, accentColor: draftColor, size: 72)
                                .shadow(color: Color(hex: draftColor).opacity(0.35), radius: 8, y: 4)
                            Text("Tap to customise")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

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

                LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
                    TextField("", text: $draftMiddlewareURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .middlewareURL)
                        .disabled(!draftNotificationsEnabled)
                }
                .opacity(draftNotificationsEnabled ? 1 : 0.4)

                LabeledField("Webhook Secret", placeholder: "Required for push") {
                    SecureField("", text: $draftPushSecret)
                        .focused($focusedField, equals: .pushSecret)
                        .disabled(!draftNotificationsEnabled)
                }
                .opacity(draftNotificationsEnabled ? 1 : 0.4)
            }

            // Actions
            Section {
                Button {
                    Task { await testAndSave() }
                } label: {
                    HStack {
                        if testStatus == .success {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if testStatus == .failure {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        }
                        if isTesting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(isAddMode ? "Test & Save" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .disabled(saveDisabled)

                if !isAddMode {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Server").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(isAddMode ? "Add Server" : draftName)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focusedField = nil } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(symbol: $draftSymbol, accentColor: $draftColor)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Delete \"\(draftName)\"?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteConnection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This server will be removed from your saved list.")
        }
        .onAppear { populateDrafts() }
    }

    // MARK: - Helpers

    private func populateDrafts() {
        savedConnections = UserDefaults.standard.loadSavedConnections()
        if let conn = existingConnection {
            draftName                 = conn.name
            draftBhnmURL              = conn.bhnmURL
            draftApiKey               = conn.apiKey
            draftPin                  = conn.pin
            draftAckUser              = conn.ackUser
            draftSymbol               = conn.symbol
            draftColor                = conn.accentColor
            draftNotificationsEnabled = conn.notificationsEnabled
            draftMiddlewareURL        = conn.middlewareURL
            draftPushSecret           = conn.webhookSecret
        }
    }

    @MainActor
    private func testAndSave() async {
        focusedField = nil
        isTesting = true
        defer { isTesting = false }

        // Normalize BHNM URL
        var bhnmURLString = draftBhnmURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bhnmURLString.hasPrefix("http://") && !bhnmURLString.hasPrefix("https://") {
            bhnmURLString = "https://\(bhnmURLString)"
        }
        draftBhnmURL = bhnmURLString

        // Normalize middleware URL if push is enabled
        if draftNotificationsEnabled {
            var mw = draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mw.isEmpty, !mw.hasPrefix("http://"), !mw.hasPrefix("https://") {
                mw = "https://\(mw)"
            }
            draftMiddlewareURL = mw
        }

        guard let bhnmURLParsed = URL(string: bhnmURLString), bhnmURLParsed.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(bhnmURLString)\" as a URL."
            showingAlert = true
            return
        }

        // Build test URL and request
        let testBase: String
        let addProxyHeaders: Bool
        if draftNotificationsEnabled && !draftMiddlewareURL.isEmpty {
            testBase = draftMiddlewareURL.trimmingSuffix("/")
            addProxyHeaders = true
        } else {
            testBase = bhnmURLString.trimmingSuffix("/")
            addProxyHeaders = false
        }

        guard let testURL = URL(string: "\(testBase)/fw/index.php?r=restful/devices/list") else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test endpoint."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        if addProxyHeaders {
            request.setValue(draftPushSecret, forHTTPHeaderField: "X-Proxy-Token")
            request.setValue(bhnmURLString, forHTTPHeaderField: "X-BHNM-Target")
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyItems = [URLQueryItem(name: "password", value: draftApiKey)]
        if !draftPin.isEmpty { bodyItems.append(URLQueryItem(name: "pin", value: draftPin)) }
        var comps = URLComponents()
        comps.queryItems = bodyItems
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        do {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 15
            let (data, response) = try await URLSession(configuration: sessionConfig).data(for: request)
            let statusCode = (response as! HTTPURLResponse).statusCode

            switch statusCode {
            case 200:
                var deviceCount = 0
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let arr = json["devices"] as? [[String: Any]] { deviceCount = arr.count }
                    else if let nested = json["data"] as? [String: Any],
                            let arr = nested["devices"] as? [[String: Any]] { deviceCount = arr.count }
                }
                if deviceCount > 0 {
                    saveConnection(bhnmURLString: bhnmURLString)
                    testStatus = .success
                    dismiss()
                } else {
                    let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8>"
                    testStatus = .failure
                    alertTitle = "Connected — no devices found"
                    alertMessage = "Server responded but returned no devices.\n\nRaw response:\n\(preview)"
                    showingAlert = true
                }
            case 401, 403:
                testStatus = .failure; alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): Check your API key and PIN."
                showingAlert = true
            case 404:
                testStatus = .failure; alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: Check the BHNM URL."
                showingAlert = true
            default:
                testStatus = .failure; alertTitle = "Unexpected response"
                alertMessage = "HTTP \(statusCode)"
                showingAlert = true
            }
        } catch let urlError as URLError {
            testStatus = .failure
            alertTitle = "Connection failed"
            switch urlError.code {
            case .notConnectedToInternet: alertMessage = "No internet connection."
            case .cannotFindHost:
                alertMessage = "Host not found: \"\(bhnmURLParsed.host ?? bhnmURLString)\"."
            case .cannotConnectToHost:
                alertMessage = "Cannot connect to \"\(bhnmURLParsed.host ?? bhnmURLString)\"."
            case .timedOut: alertMessage = "Timed out after 15 seconds."
            default: alertMessage = urlError.localizedDescription
            }
            showingAlert = true
        } catch {
            testStatus = .failure; alertTitle = "Error"
            alertMessage = error.localizedDescription; showingAlert = true
        }
    }

    private func saveConnection(bhnmURLString: String) {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middlewareURL = draftNotificationsEnabled
            ? draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let webhookSecret = draftNotificationsEnabled
            ? draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let now = SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
            middlewareURL: middlewareURL,
            bhnmURL: bhnmURLString,
            notificationsEnabled: draftNotificationsEnabled,
            apiKey: draftApiKey,
            pin: draftPin,
            ackUser: draftAckUser,
            webhookSecret: webhookSecret,
            symbol: draftSymbol,
            accentColor: draftColor
        )

        if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
            savedConnections[idx] = now
        } else {
            savedConnections.append(now)
        }
        UserDefaults.standard.saveSavedConnections(savedConnections)

        // Sync to active AppStorage keys if this is the active server
        let isCurrentlyActive = existingConnection?.id.uuidString == activeSavedConnectionID
        if isAddMode || isCurrentlyActive {
            activeSavedConnectionID = now.id.uuidString
            storedMiddlewareURL = now.middlewareURL
            storedBhnmURL       = now.bhnmURL
            apiKey              = now.apiKey
            pin                 = now.pin
            ackUser             = now.ackUser
            UserDefaults.standard.set(now.webhookSecret, forKey: "netreo_webhook_secret")
        }
    }

    private func deleteConnection() {
        guard let conn = existingConnection else { return }
        savedConnections.removeAll { $0.id == conn.id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        if activeSavedConnectionID == conn.id.uuidString {
            activeSavedConnectionID = ""
            storedMiddlewareURL = ""
            storedBhnmURL = ""
            apiKey = ""; pin = ""; ackUser = ""
        }
        dismiss()
    }
}

// MARK: - LabeledField helper

private struct LabeledField<Content: View>: View {
    let label: String
    let placeholder: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, placeholder: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.placeholder = placeholder
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/ServerConfigView.swift
git commit -m "feat: redesign ServerConfigView with Connection + Push Notifications sections"
```

---

## Task 8: Update `DeepLinkHandler` — new payload keys + backward compat

**Files:**
- Modify: `BeNeM/Services/DeepLinkHandler.swift`

Updates `PendingImport` to carry the two new URL fields plus `notificationsEnabled`, reads new keys in `handleCompactPayload` (with backward compat for old `server` key), and upserts by `bhnmURL` in `applyPendingImport`.

- [ ] **Step 1: Update `PendingImport` struct**

```swift
struct PendingImport {
    let bhnmURL: String          // direct BHNM server URL (from "bhnm_url" key)
    let middlewareURL: String    // push middleware URL (from "middleware_url" key); "" if absent
    let notificationsEnabled: Bool
    let apiKey: String
    let pin: String
    let ackUser: String
    let name: String
    let pushSecret: String
    let symbol: String
    let accentColor: String
}
```

- [ ] **Step 2: Update `handleCompactPayload` to read new keys + backward compat**

Replace the `handleCompactPayload` body:

```swift
private func handleCompactPayload(_ blob: String) {
    do {
        let symmetricKey = try loadKey()
        let decrypted = try decryptToData(blob, using: symmetricKey)
        let decompressed = try zlibDecompress(decrypted)
        guard let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any] else {
            fail("The link payload could not be parsed.")
            return
        }
        func str(_ key: String, default def: String = "") -> String {
            (json[key] as? String) ?? def
        }

        // New keys: bhnm_url + middleware_url
        // Backward compat: old links have "server" (= middleware URL) but no "bhnm_url"
        let bhnmURL: String
        let middlewareURL: String
        if let newBhnmURL = json["bhnm_url"] as? String, !newBhnmURL.isEmpty {
            bhnmURL = newBhnmURL
            middlewareURL = str("middleware_url")
        } else if let oldServer = json["server"] as? String, !oldServer.isEmpty {
            // Old format: "server" held the middleware URL; bhnmURL is unknown — leave empty
            bhnmURL = ""
            middlewareURL = oldServer
        } else {
            fail("The link is missing a valid server URL.")
            return
        }

        let notificationsEnabled = (json["notifications"] as? Bool) ?? true

        pendingImport = PendingImport(
            bhnmURL:              bhnmURL,
            middlewareURL:        middlewareURL,
            notificationsEnabled: notificationsEnabled,
            apiKey:               str("api_key"),
            pin:                  str("pin"),
            ackUser:              str("user", default: "enter user name"),
            name:                 str("name"),
            pushSecret:           str("push_secret"),
            symbol:               str("symbol", default: "server.rack"),
            accentColor:          str("color", default: "#0A84FF")
        )
    } catch {
        fail("The link is invalid or was created with a different key.")
    }
}
```

- [ ] **Step 3: Update `handle(url:)` legacy (non-compact) path**

The legacy URL parameter path at the top of `handle(url:)` still uses `serverURL`. Update to use the new `PendingImport` fields. Change the `pendingImport` construction:

```swift
pendingImport = PendingImport(
    bhnmURL:              "",         // legacy links don't carry bhnmURL — migration banner will show
    middlewareURL:        server,
    notificationsEnabled: false,      // migration default
    apiKey:               decryptedKey,
    pin:                  decryptedPin,
    ackUser:              ackUser,
    name:                 name,
    pushSecret:           decryptedSecret,
    symbol:               "server.rack",
    accentColor:          "#0A84FF"
)
```

- [ ] **Step 4: Update `applyPendingImport` — upsert by `bhnmURL`, write new fields**

Replace `applyPendingImport`:

```swift
func applyPendingImport() {
    guard let imp = pendingImport else { return }

    let ud = UserDefaults.standard

    // 1. Write active AppStorage keys
    ud.set(imp.middlewareURL,         forKey: "netreo_base_url")
    ud.set(imp.bhnmURL,               forKey: "netreo_bhnm_url")
    ud.set(imp.apiKey,                forKey: "netreo_api_key")
    ud.set(imp.pin,                   forKey: "netreo_pin")
    ud.set(imp.ackUser,               forKey: "netreo_ack_user")
    if !imp.pushSecret.isEmpty {
        ud.set(imp.pushSecret, forKey: "netreo_webhook_secret")
    }

    // 2. Upsert SavedConnection — match by bhnmURL (case-insensitive)
    //    If bhnmURL is empty (backward compat import), fall back to matching by middlewareURL
    var connections = ud.loadSavedConnections()
    let upsertedID: UUID
    let matchIdx: Int?
    if !imp.bhnmURL.isEmpty {
        let bhnmLower = imp.bhnmURL.lowercased()
        matchIdx = connections.firstIndex(where: { $0.bhnmURL.lowercased() == bhnmLower })
    } else {
        let mwLower = imp.middlewareURL.lowercased()
        matchIdx = connections.firstIndex(where: { $0.middlewareURL.lowercased() == mwLower })
    }

    if let idx = matchIdx {
        if !imp.name.isEmpty { connections[idx].name = imp.name }
        connections[idx].bhnmURL              = imp.bhnmURL
        connections[idx].middlewareURL        = imp.middlewareURL
        connections[idx].notificationsEnabled = imp.notificationsEnabled
        connections[idx].apiKey               = imp.apiKey
        connections[idx].pin                  = imp.pin
        connections[idx].ackUser              = imp.ackUser
        if !imp.pushSecret.isEmpty { connections[idx].webhookSecret = imp.pushSecret }
        connections[idx].symbol               = imp.symbol
        connections[idx].accentColor          = imp.accentColor
        upsertedID = connections[idx].id
    } else {
        let name = imp.name.isEmpty
            ? (URL(string: imp.bhnmURL.isEmpty ? imp.middlewareURL : imp.bhnmURL)?.host ?? imp.bhnmURL)
            : imp.name
        let newConn = SavedConnection(
            id: UUID(),
            name: name,
            middlewareURL: imp.middlewareURL,
            bhnmURL: imp.bhnmURL,
            notificationsEnabled: imp.notificationsEnabled,
            apiKey: imp.apiKey,
            pin: imp.pin,
            ackUser: imp.ackUser,
            webhookSecret: imp.pushSecret,
            symbol: imp.symbol,
            accentColor: imp.accentColor
        )
        connections.append(newConn)
        upsertedID = newConn.id
    }

    ud.saveSavedConnections(connections)
    ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")

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

    pendingImport = nil
    NotificationCenter.default.post(name: .deepLinkConnectionApplied, object: nil)
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Fix `BeNeMApp.swift` alert message**

`BeNeMApp.swift` body references `imp.serverURL` in the "Apply Configuration?" alert (this field was removed from `PendingImport` in Step 1). Update the message to use the new fields:

```swift
// OLD:
Text("Server: \(imp.serverURL)\nUser: \(imp.ackUser)")

// NEW:
let displayURL = imp.bhnmURL.isEmpty ? imp.middlewareURL : imp.bhnmURL
Text("Server: \(displayURL)\nUser: \(imp.ackUser)")
```

- [ ] **Step 7: Build**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add BeNeM/Services/DeepLinkHandler.swift BeNeM/BeNeMApp.swift
git commit -m "feat: update DeepLinkHandler for bhnm_url/middleware_url payload, upsert by bhnmURL"
```

---

## Task 9: Update `generate_benem_link.py`

**Files:**
- Modify: `generate_benem_link.py`

Replaces `--middleware-url` with `--bhnm-url` (required), makes `--middleware-url` optional, adds `--notifications/--no-notifications`, and updates payload keys and interactive prompts.

- [ ] **Step 1: Update `interactive_mode()`**

```python
def interactive_mode() -> dict:
    print("\nBeNeM Link Generator — Interactive Mode")
    print("=" * 42)
    print("Press Enter to accept the default shown in [brackets].\n")

    bhnm_url = prompt("BHNM URL (direct server, e.g. https://bhnm.corp.com)")
    if not bhnm_url:
        print("Error: BHNM URL is required.")
        sys.exit(1)
    if not bhnm_url.startswith("http://") and not bhnm_url.startswith("https://"):
        bhnm_url = "https://" + bhnm_url

    api_key = prompt("API Token", secret=True)
    if not api_key:
        print("Error: API Token is required.")
        sys.exit(1)

    pin = prompt("PIN / License ID (leave blank for none)", secret=True)
    user = prompt("User Name", default="enter user name")

    from urllib.parse import urlparse
    default_name = urlparse(bhnm_url).hostname or bhnm_url
    name = prompt("Server Name", default=default_name)

    symbol = prompt("SF Symbol", default="server.rack")
    color = prompt("Accent colour (hex)", default="#0A84FF")

    enable_push = prompt("Enable push notifications? [Y/n]").lower() != "n"
    middleware_url = ""
    push_secret = ""
    if enable_push:
        middleware_url = prompt("Middleware URL (e.g. https://bhnm-apns.corp.com)")
        if middleware_url and not middleware_url.startswith("http://") and not middleware_url.startswith("https://"):
            middleware_url = "https://" + middleware_url
        push_secret = prompt("Webhook Secret", secret=True)

    return {
        "bhnm_url":       bhnm_url,
        "middleware_url": middleware_url,
        "notifications":  enable_push,
        "api_key":        api_key,
        "pin":            pin,
        "user":           user,
        "name":           name,
        "push_secret":    push_secret,
        "symbol":         symbol,
        "color":          color,
    }
```

- [ ] **Step 2: Update `main()` argument parser and payload construction**

```python
def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("-i", "--interactive", action="store_true",
                        help="Interactive mode: prompt for each field")
    parser.add_argument("--bhnm-url", dest="bhnm_url",
                        help="Direct BHNM server URL (e.g. https://bhnm.yourcompany.com) — required unless -i")
    parser.add_argument("--middleware-url", dest="middleware_url", default="",
                        help="Push middleware URL (optional; omit if push not needed)")
    parser.add_argument("--api_key", help="API token")
    parser.add_argument("--pin", default="", help="PIN / License ID (SaaS only, optional)")
    parser.add_argument("--user", default="enter user name", help="ACK user name")
    parser.add_argument("--server-name", "--name", dest="name", default="",
                        help="Connection display name (--name accepted for backwards compat)")
    parser.add_argument("--symbol", default="server.rack", help="SF Symbol name")
    parser.add_argument("--color", default="#0A84FF", help="Accent colour (hex)")
    parser.add_argument("--push-secret", dest="push_secret", default="",
                        help="Push webhook secret (encrypted in payload)")
    parser.add_argument("--notifications", dest="notifications",
                        action="store_true", default=True,
                        help="Enable push notifications for this connection (default)")
    parser.add_argument("--no-notifications", dest="notifications",
                        action="store_false",
                        help="Disable push notifications for this connection")
    parser.add_argument("--qr", action="store_true",
                        help="Also save a QR code PNG (benem-link.png)")
    args = parser.parse_args()

    if args.interactive:
        payload = interactive_mode()
        generate_qr = prompt("\nGenerate QR code? [y/N]").lower() == "y"
    else:
        if not args.bhnm_url or not args.api_key:
            parser.error("--bhnm-url and --api_key are required (or use -i for interactive mode)")
        bhnm_url = args.bhnm_url
        if not bhnm_url.startswith("http://") and not bhnm_url.startswith("https://"):
            bhnm_url = "https://" + bhnm_url
        middleware_url = args.middleware_url
        if middleware_url and not middleware_url.startswith("http://") and not middleware_url.startswith("https://"):
            middleware_url = "https://" + middleware_url
        payload = {
            "bhnm_url":       bhnm_url,
            "middleware_url": middleware_url,
            "notifications":  args.notifications,
            "api_key":        args.api_key,
            "pin":            args.pin,
            "user":           args.user,
            "name":           args.name,
            "push_secret":    args.push_secret,
            "symbol":         args.symbol,
            "color":          args.color,
        }
        generate_qr = args.qr

    key = load_key()
    blob = encrypt_payload(payload, key)
    url = f"benem://configure?p={blob}"
    print(url)

    if generate_qr:
        save_qr(url)
```

- [ ] **Step 3: Smoke-test the script**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
python3 generate_benem_link.py \
  --bhnm-url https://bhnm.example.com \
  --api_key testkey123 \
  --user Thomas
```

Expected: prints a `benem://configure?p=...` URL without errors.

```bash
python3 generate_benem_link.py \
  --bhnm-url https://bhnm.example.com \
  --api_key testkey123 \
  --user Thomas \
  --middleware-url https://bhnm-apns.example.com \
  --push-secret secret123
```

Expected: prints a `benem://configure?p=...` URL without errors.

- [ ] **Step 4: Commit**

```bash
git add generate_benem_link.py
git commit -m "feat: update generate_benem_link.py — --bhnm-url required, --middleware-url optional, bhnm_url/middleware_url payload keys"
```

---

## Task 10: Final build + deploy

- [ ] **Step 1: Full build and deploy to device**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
./build_and_deploy.sh
```

Expected: `BUILD SUCCEEDED`, app installed on TomiPhone13.

- [ ] **Step 2: Smoke-test on device**

1. Open app → Settings → existing connection should have orange "Tap to complete setup" banner (migration case, `bhnmURL` is empty)
2. Tap banner → `ServerConfigView` opens in edit mode showing Connection section (BHNM URL field empty) and Push Notifications section (toggle on, middleware URL + secret populated)
3. Fill in BHNM URL → tap Save → banner disappears, app loads data through middleware
4. Add new server → both sections shown, toggle defaults ON, all required fields enforced
5. Switch connections → push unregistered for old, registered for new (check Xcode console for `[APNs]` logs)
6. Test `--no-notifications` flag: add server with toggle OFF → middleware URL greyed out → saves; API calls go directly to BHNM URL, no push

- [ ] **Step 3: Version bump**

```bash
./scripts/bump_version.sh minor
git add BeNeM.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 2.3.0 for multi-server middleware feature"
```

---

## Notes for implementers

- **`SavedConnection` JSON key stability:** The `CodingKeys` enum maps `middlewareURL` field → `"baseURL"` JSON key. This is intentional. Existing UserDefaults blobs decode without loss. Do not change this mapping.
- **Direct connection mode (notifications OFF):** When `middlewareURL` is empty, `ContentView.updateAPIService()` uses `bhnmURL` as `serviceBaseURL` and passes empty `proxyToken` + empty `bhnmURL` to the config — `addProxyToken` guard fires, no headers are added, app connects directly to BHNM.
- **SourceKit false positives:** SourceKit may show red errors on `SavedConnection` field references; `xcodebuild` is the authoritative check.
- **Middleware backward compat:** Old middleware instances (which validated `PROXY_SECRET`) are NOT updated in this plan — the middleware `main.py` changes are described in the spec but belong to the `bhnm-apns` repo.
