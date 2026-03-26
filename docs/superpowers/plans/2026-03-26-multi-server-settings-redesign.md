# Multi-Server Settings Redesign & Compact Deep Link Format — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the inline Settings form with a polished multi-server list + dedicated ServerConfigView, and upgrade `generate_benem_link.py` to emit a compact single-payload `benem://configure?p=<blob>` URL with interactive mode and optional QR output.

**Architecture:** `SavedConnection` gains three new fields (`pushMiddlewareURL`, `symbol`, `accentColor`). `SettingsView` becomes a server list; editing/adding opens `ServerConfigView` (with `IconPickerSheet`). `DeepLinkHandler` supports both old multi-param format and new compact `p=` format. `AppDelegate.registerWithMiddleware` is updated to accept the middleware URL as a parameter instead of reading the global UserDefaults key.

**Tech Stack:** SwiftUI, Swift Compression framework (zlib), CryptoKit (AES-GCM), Python 3 (zlib, cryptography, qrcode), UserDefaults Codable persistence.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `BeNeM/Models/SavedConnection.swift` | Add `pushMiddlewareURL`, `symbol`, `accentColor` fields |
| Modify | `BeNeM/AppDelegate.swift` | `registerWithMiddleware` accepts `middlewareURL:` param; remove global key read |
| Modify | `BeNeM/ContentView.swift` | Pass `pushMiddlewareURL` from active connection to `registerWithMiddleware` |
| Modify | `BeNeM/BeNeMApp.swift` | Add `init()` with migration; update deep-link alert message |
| Modify | `BeNeM/Services/DeepLinkHandler.swift` | Add compact `p=` decoding; update `PendingImport` and `applyPendingImport()` |
| Create | `BeNeM/Views/IconPickerSheet.swift` | SF Symbol grid + colour palette + live preview sheet |
| Create | `BeNeM/Views/ServerConfigView.swift` | Dedicated add/edit server form with icon header and push toggle |
| Modify | `BeNeM/Views/SettingsView.swift` | Replace inline fields with NavigationLink server list |
| Modify | `generate_benem_link.py` | Compact payload, interactive mode, `--symbol`/`--color`, QR output |

---

## Task 1: Extend `SavedConnection` model

**Files:**
- Modify: `BeNeM/Models/SavedConnection.swift`

- [ ] **Step 1: Add three new fields with defaults**

Open `BeNeM/Models/SavedConnection.swift`. The current struct ends at `webhookSecret`. Add three lines after it:

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String
    var ackUser: String
    var webhookSecret: String = ""
    var pushMiddlewareURL: String = ""  // per-connection push middleware; replaces global push_middleware_url
    var symbol: String = "server.rack" // SF Symbol name for list icon
    var accentColor: String = "#0A84FF" // hex accent colour for icon background
}
```

The `UserDefaults` extension (`loadSavedConnections` / `saveSavedConnections`) needs no changes — `Codable` decodes missing keys to these defaults automatically.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Models/SavedConnection.swift
git commit -m "feat: add pushMiddlewareURL, symbol, accentColor to SavedConnection"
```

---

## Task 2: Update `AppDelegate.registerWithMiddleware`

**Files:**
- Modify: `BeNeM/AppDelegate.swift`

`registerWithMiddleware` currently reads `push_middleware_url` from the global UserDefaults key. We change it to accept the URL as a parameter.

- [ ] **Step 1: Update the function signature and body**

Replace the entire `registerWithMiddleware` function:

```swift
func registerWithMiddleware(token: String, secret: String, middlewareURL: String) {
    guard !middlewareURL.isEmpty, let url = URL(string: "\(middlewareURL)/register") else {
        print("[APNs] No middleware URL configured — skipping token registration.")
        return
    }
    guard !secret.isEmpty else {
        print("[APNs] No webhook secret for active connection — skipping token registration.")
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(secret, forHTTPHeaderField: "X-Webhook-Token")
    let body: [String: String] = [
        "token": token,
        "device_name": UIDevice.current.name
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            print("[APNs] Middleware registration error: \(error)")
        } else if let http = response as? HTTPURLResponse {
            print("[APNs] Middleware responded: \(http.statusCode)")
        }
    }.resume()
}
```

- [ ] **Step 2: Update the call site inside `didRegisterForRemoteNotificationsWithDeviceToken`**

The existing call is `registerWithMiddleware(token: token, secret: secret)`. Replace it:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("[APNs] Device token: \(token)")
    cachedDeviceToken = token
    let (secret, middlewareURL) = activeConnectionPushCredentials()
    registerWithMiddleware(token: token, secret: secret, middlewareURL: middlewareURL)
}
```

- [ ] **Step 3: Replace `activeWebhookSecret()` with `activeConnectionPushCredentials()`**

Remove the old `activeWebhookSecret()` private function and add:

```swift
private func activeConnectionPushCredentials() -> (secret: String, middlewareURL: String) {
    let ud = UserDefaults.standard
    guard let activeID = ud.string(forKey: "netreo_active_connection_id"),
          !activeID.isEmpty else { return ("", "") }
    let connections = ud.loadSavedConnections()
    guard let conn = connections.first(where: { $0.id.uuidString == activeID }) else { return ("", "") }
    return (conn.webhookSecret, conn.pushMiddlewareURL)
}
```

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` (compiler will flag all callers of the old signature — fix them as you go)

- [ ] **Step 5: Commit**

```bash
git add BeNeM/AppDelegate.swift
git commit -m "feat: registerWithMiddleware accepts explicit middlewareURL parameter"
```

---

## Task 3: Update `ContentView` — pass `pushMiddlewareURL` on server switch

**Files:**
- Modify: `BeNeM/ContentView.swift`

The `onChange(of: activeConnectionID)` handler calls `registerWithMiddleware` but currently only passes the `webhookSecret`. Update it to also pass `pushMiddlewareURL`.

- [ ] **Step 1: Update `onChange(of: activeConnectionID)` handler**

Find this block (lines 43–49):

```swift
.onChange(of: activeConnectionID) { _, newID in
    guard !newID.isEmpty,
          let token = AppDelegate.shared?.cachedDeviceToken else { return }
    let connections = UserDefaults.standard.loadSavedConnections()
    let secret = connections.first(where: { $0.id.uuidString == newID })?.webhookSecret ?? ""
    AppDelegate.shared?.registerWithMiddleware(token: token, secret: secret)
}
```

Replace with:

```swift
.onChange(of: activeConnectionID) { _, newID in
    guard !newID.isEmpty,
          let token = AppDelegate.shared?.cachedDeviceToken else { return }
    let connections = UserDefaults.standard.loadSavedConnections()
    if let conn = connections.first(where: { $0.id.uuidString == newID }) {
        AppDelegate.shared?.registerWithMiddleware(
            token: token,
            secret: conn.webhookSecret,
            middlewareURL: conn.pushMiddlewareURL
        )
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/ContentView.swift
git commit -m "feat: pass pushMiddlewareURL to registerWithMiddleware on server switch"
```

---

## Task 4: Add migration in `BeNeMApp`

**Files:**
- Modify: `BeNeM/BeNeMApp.swift`

Migrate the old global `push_middleware_url` UserDefaults key into the active connection's `pushMiddlewareURL` field on first launch.

- [ ] **Step 1: Add `init()` with migration to `BeNeMApp`**

Add before the `var body: some Scene` line:

```swift
init() {
    migrateGlobalPushURLIfNeeded()
}

private func migrateGlobalPushURLIfNeeded() {
    let ud = UserDefaults.standard
    guard let globalURL = ud.string(forKey: "push_middleware_url"), !globalURL.isEmpty else { return }
    let activeID = ud.string(forKey: "netreo_active_connection_id") ?? ""
    var connections = ud.loadSavedConnections()
    if let idx = connections.firstIndex(where: { $0.id.uuidString == activeID }),
       connections[idx].pushMiddlewareURL.isEmpty {
        connections[idx].pushMiddlewareURL = globalURL
        ud.saveSavedConnections(connections)
    }
    ud.removeObject(forKey: "push_middleware_url")
}
```

- [ ] **Step 2: Update the deep-link confirmation alert message**

In `BeNeMApp.body`, the alert message currently reads:

```swift
if let imp = deepLinkHandler.pendingImport {
    let push = imp.pushURL.isEmpty ? "" : "\nPush: \(imp.pushURL)"
    Text("Server: \(imp.serverURL)\nUser: \(imp.ackUser)\(push)")
}
```

Update to also show the server name when present:

```swift
if let imp = deepLinkHandler.pendingImport {
    let displayName = imp.name.isEmpty ? imp.serverURL : imp.name
    let push = imp.pushURL.isEmpty ? "" : "\nPush: \(imp.pushURL)"
    Text("Server: \(displayName)\nUser: \(imp.ackUser)\(push)")
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/BeNeMApp.swift
git commit -m "feat: migrate global push_middleware_url to per-connection on first launch"
```

---

## Task 5: Update `DeepLinkHandler` — compact `p=` format + new fields

**Files:**
- Modify: `BeNeM/Services/DeepLinkHandler.swift`

Add `Compression` framework import, update `PendingImport`, add new-format decoding path, update `applyPendingImport()`.

- [ ] **Step 1: Add `Compression` import and update `PendingImport`**

At the top of `DeepLinkHandler.swift`, add:

```swift
import Compression
import CryptoKit
import Foundation
```

Replace the `PendingImport` struct. **Remove `pushURL` and use only `pushMiddlewareURL`** — the old `pushURL` field is retired; all code that referenced `imp.pushURL` (including in `BeNeMApp.swift`) must be updated to `imp.pushMiddlewareURL`:

```swift
struct PendingImport {
    let serverURL: String
    let apiKey: String
    let pin: String               // "" if absent
    let ackUser: String
    let name: String              // "" if absent — falls back to hostname
    let pushMiddlewareURL: String // "" if absent; replaces old pushURL field
    let pushSecret: String        // "" if absent
    let symbol: String            // SF Symbol name; default "server.rack"
    let accentColor: String       // hex colour; default "#0A84FF"
}
```

Also update `BeNeMApp.swift` alert message that references `imp.pushURL` — change to `imp.pushMiddlewareURL`:

```swift
if let imp = deepLinkHandler.pendingImport {
    let displayName = imp.name.isEmpty ? imp.serverURL : imp.name
    let push = imp.pushMiddlewareURL.isEmpty ? "" : "\nPush: \(imp.pushMiddlewareURL)"
    Text("Server: \(displayName)\nUser: \(imp.ackUser)\(push)")
}
```

Also preserve the `Notification.Name.deepLinkConnectionApplied` extension at the bottom of `DeepLinkHandler.swift` — do not remove it.

- [ ] **Step 2: Add the compact-format decode path in `handle(url:)`**

Inside `handle(url:)`, after the `guard` that checks for `queryItems`, add detection of the new `p=` param **before** the existing `server`/`api_key` guards:

```swift
// New compact format: single encrypted+compressed payload
if let blob = param("p"), !blob.isEmpty {
    handleCompactPayload(blob)
    return
}
```

Then add the private helper method at the bottom of the class (before the `CryptoError` enum):

```swift
private func handleCompactPayload(_ blob: String) {
    do {
        let symmetricKey = try loadKey()
        let decrypted = try decryptToData(blob, using: symmetricKey)  // returns Data, not String
        let decompressed = try zlibDecompress(decrypted)
        guard let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any] else {
            fail("The link payload could not be parsed.")
            return
        }
        func str(_ key: String, default def: String = "") -> String {
            (json[key] as? String) ?? def
        }
        guard let server = json["server"] as? String, !server.isEmpty,
              server.hasPrefix("http://") || server.hasPrefix("https://") else {
            fail("The link is missing a valid server URL.")
            return
        }
        pendingImport = PendingImport(
            serverURL:         server,
            apiKey:            str("api_key"),
            pin:               str("pin"),
            ackUser:           str("user", default: "enter user name"),
            name:              str("name"),
            pushMiddlewareURL: str("push_url"),
            pushSecret:        str("push_secret"),
            symbol:            str("symbol", default: "server.rack"),
            accentColor:       str("color", default: "#0A84FF")
        )
    } catch {
        fail("The link is invalid or was created with a different key.")
    }
}

private func zlibDecompress(_ data: Data) throws -> Data {
    // Python's zlib.compress produces a zlib stream: 2-byte header + raw DEFLATE + 4-byte Adler-32.
    // Swift's Compression framework (COMPRESSION_ZLIB) expects raw DEFLATE only — strip both wrappers.
    guard data.count > 6 else { throw CryptoError.invalidBase64 }
    let deflateData = data.dropFirst(2).dropLast(4)  // remove 2-byte zlib header + 4-byte checksum
    var outputBuffer = [UInt8](repeating: 0, count: data.count * 8)
    let resultSize = deflateData.withUnsafeBytes { src in
        compression_decode_buffer(
            &outputBuffer, outputBuffer.count,
            src.baseAddress!.assumingMemoryBound(to: UInt8.self),
            src.count,
            nil, COMPRESSION_ZLIB
        )
    }
    guard resultSize > 0 else { throw CryptoError.invalidUTF8 }
    return Data(outputBuffer.prefix(resultSize))
}
```

Note: The `decrypt` helper already in the file handles base64url → AES-GCM decryption and returns `Data` — but currently returns a `String`. We need a `Data`-returning variant. Add:

```swift
private func decryptToData(_ base64url: String, using key: SymmetricKey) throws -> Data {
    var b64 = base64url
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = b64.count % 4
    if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }
    guard let combined = Data(base64Encoded: b64) else { throw CryptoError.invalidBase64 }
    let sealedBox = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(sealedBox, using: key)
}
```

Update `handleCompactPayload` to call `decryptToData` instead of `decrypt`:

```swift
let decrypted = try decryptToData(blob, using: symmetricKey)
```

- [ ] **Step 3: Update the old-format `PendingImport` construction**

In the existing `handle(url:)` path that builds `PendingImport` from individual params, add the new fields with defaults:

```swift
pendingImport = PendingImport(
    serverURL:         server,
    apiKey:            decryptedKey,
    pin:               decryptedPin,
    ackUser:           ackUser,
    name:              name,
    pushMiddlewareURL: pushURL,           // old `pushURL` local var → new field name
    pushSecret:        decryptedSecret,
    symbol:            "server.rack",     // old format carries no icon info
    accentColor:       "#0A84FF"
)
```

- [ ] **Step 4: Update `applyPendingImport()` to write new fields**

In `applyPendingImport()`, the upsert block that updates an existing connection (`connections[idx]`) currently sets `apiKey`, `pin`, `ackUser`, `webhookSecret`. Add:

```swift
connections[idx].symbol           = imp.symbol
connections[idx].accentColor      = imp.accentColor
connections[idx].pushMiddlewareURL = imp.pushMiddlewareURL
```

And in the new-connection branch, update `SavedConnection(...)` initialiser to pass:

```swift
let newConn = SavedConnection(
    id: UUID(),
    name: name,
    baseURL: imp.serverURL,
    apiKey: imp.apiKey,
    pin: imp.pin,
    ackUser: imp.ackUser,
    webhookSecret: imp.pushSecret,
    pushMiddlewareURL: imp.pushMiddlewareURL,
    symbol: imp.symbol,
    accentColor: imp.accentColor
)
```

- [ ] **Step 5: Remove the global `push_middleware_url` write**

Find and delete this block in `applyPendingImport()`:

```swift
// 4. Apply push notification settings if present
if !imp.pushURL.isEmpty {
    ud.set(imp.pushURL, forKey: "push_middleware_url")
}
```

(Push URL is now stored per-connection in `pushMiddlewareURL`.)

- [ ] **Step 6: Build**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add BeNeM/Services/DeepLinkHandler.swift
git commit -m "feat: add compact p= deep link format with zlib+AES-GCM, update PendingImport"
```

---

## Task 6: Create `IconPickerSheet`

**Files:**
- Create: `BeNeM/Views/IconPickerSheet.swift`

A sheet that lets the user pick an SF Symbol and an accent colour, with a live preview.

- [ ] **Step 1: Create the file**

```swift
// BeNeM/Views/IconPickerSheet.swift
import SwiftUI

struct IconPickerSheet: View {
    @Binding var symbol: String
    @Binding var accentColor: String
    @Environment(\.dismiss) private var dismiss

    private let symbols: [String] = [
        "server.rack", "network", "antenna.radiowaves.left.and.right",
        "wifi", "globe", "cloud.fill", "lock.shield.fill", "building.2.fill",
        "cpu", "externaldrive.connected.to.line.below.fill",
        "desktopcomputer", "laptopcomputer", "iphone",
        "shield.fill", "bolt.fill", "chart.bar.fill",
        "checkmark.seal.fill", "folder.fill", "gearshape.fill", "house.fill"
    ]

    private let palette: [Color] = [
        Color(hex: "#0A84FF"), Color(hex: "#30D158"), Color(hex: "#FF9F0A"),
        Color(hex: "#FF375F"), Color(hex: "#64D2FF"), Color(hex: "#BF5AF2"),
        Color(hex: "#FF6961"), Color(hex: "#5E5CE6"), Color(hex: "#32ADE6"),
        Color(hex: "#FFD60A")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Preview") {
                    HStack {
                        Spacer()
                        ServerIconView(symbol: symbol, accentColor: accentColor, size: 64)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(symbols, id: \.self) { sym in
                            Button {
                                symbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(symbol == sym ? Color(hex: accentColor) : .secondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(symbol == sym ? Color(hex: accentColor).opacity(0.15) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(symbol == sym ? Color(hex: accentColor) : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(palette, id: \.self) { colour in
                            let hex = colour.toHex() ?? accentColor
                            Button {
                                accentColor = hex
                            } label: {
                                Circle()
                                    .fill(colour)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: accentColor.lowercased() == hex.lowercased() ? 3 : 0)
                                    )
                                    .shadow(color: colour.opacity(0.4), radius: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Customise Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Reusable icon view — used in both the list rows and the picker preview.
struct ServerIconView: View {
    let symbol: String
    let accentColor: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(hex: accentColor))
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/IconPickerSheet.swift
git commit -m "feat: add IconPickerSheet with SF Symbol grid and colour palette"
```

---

## Task 7: Create `ServerConfigView`

**Files:**
- Create: `BeNeM/Views/ServerConfigView.swift`

The dedicated add/edit server form. Receives an optional existing connection (nil = add mode).

- [ ] **Step 1: Create the file**

```swift
// BeNeM/Views/ServerConfigView.swift
import SwiftUI

struct ServerConfigView: View {
    // nil = add mode; non-nil = edit mode
    let existingConnection: SavedConnection?

    @AppStorage("netreo_base_url")              private var baseURL = ""
    @AppStorage("netreo_api_key")               private var apiKey = ""
    @AppStorage("netreo_pin")                   private var pin = ""
    @AppStorage("netreo_ack_user")              private var ackUser = ""
    @AppStorage("netreo_active_connection_id")  private var activeSavedConnectionID = ""

    // Draft state
    @State private var draftName       = ""
    @State private var draftBaseURL    = ""
    @State private var draftApiKey     = ""
    @State private var draftPin        = ""
    @State private var draftAckUser    = ""
    @State private var draftSymbol     = "server.rack"
    @State private var draftColor      = "#0A84FF"
    @State private var pushEnabled     = false
    @State private var draftPushURL    = ""
    @State private var draftPushSecret = ""

    @State private var showingIconPicker       = false
    @State private var isTesting               = false
    @State private var testStatus: TestStatus  = .untested
    @State private var alertTitle              = ""
    @State private var alertMessage            = ""
    @State private var showingAlert            = false
    @State private var showingDeleteConfirm    = false

    @State private var savedConnections: [SavedConnection] = []

    private enum TestStatus { case untested, success, failure }
    private enum Field: Hashable { case name, url, apiKey, pin, ackUser, pushURL, pushSecret }
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private var isAddMode: Bool { existingConnection == nil }
    private var activeID: UUID? { UUID(uuidString: activeSavedConnectionID) }

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

            // Connection fields
            Section("Connection") {
                LabeledField("Server Name", placeholder: "e.g. Production BHNM") {
                    TextField("", text: $draftName)
                        .focused($focusedField, equals: .name)
                }
                LabeledField("Server URL", placeholder: "bhnm.example.com") {
                    TextField("", text: $draftBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .url)
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

            // Push notifications
            Section("Push Notifications") {
                Toggle("Enable Push Notifications", isOn: $pushEnabled)
                if pushEnabled {
                    LabeledField("Middleware URL", placeholder: "https://bhnm-apns.example.com") {
                        TextField("", text: $draftPushURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .pushURL)
                    }
                    LabeledField("Webhook Secret", placeholder: "Required") {
                        SecureField("", text: $draftPushSecret)
                            .focused($focusedField, equals: .pushSecret)
                    }
                }
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
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isAddMode ? "Test & Save" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .disabled(isTesting || draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || draftAckUser.isEmpty)

                if !isAddMode {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Server")
                            .frame(maxWidth: .infinity)
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
            draftName       = conn.name
            draftBaseURL    = conn.baseURL
            draftApiKey     = conn.apiKey
            draftPin        = conn.pin
            draftAckUser    = conn.ackUser
            draftSymbol     = conn.symbol
            draftColor      = conn.accentColor
            draftPushURL    = conn.pushMiddlewareURL
            draftPushSecret = conn.webhookSecret
            pushEnabled     = !conn.pushMiddlewareURL.isEmpty || !conn.webhookSecret.isEmpty
        }
    }

    @MainActor
    private func testAndSave() async {
        focusedField = nil
        isTesting = true
        defer { isTesting = false }

        // Auto-prepend https:// if no scheme
        var urlString = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        draftBaseURL = urlString

        guard let url = URL(string: urlString), url.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(urlString)\" as a URL."
            showingAlert = true
            return
        }

        guard let testURL = URL(string: "\(urlString.trimmingSuffix("/"))/fw/index.php?r=restful/devices/list") else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test endpoint."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
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
                    saveConnection(urlString: urlString)
                    testStatus = .success
                    dismiss()
                } else {
                    testStatus = .failure
                    alertTitle = "Connected — no devices found"
                    alertMessage = "Server responded but returned no devices. Check API key permissions."
                    showingAlert = true
                }
            case 401, 403:
                testStatus = .failure; alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): Check your API key and PIN."
                showingAlert = true
            case 404:
                testStatus = .failure; alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: Check the base URL."
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
            case .cannotFindHost: alertMessage = "Host not found: \"\(url.host ?? urlString)\"."
            case .cannotConnectToHost: alertMessage = "Cannot connect to \"\(url.host ?? urlString)\"."
            case .timedOut: alertMessage = "Timed out after 15 seconds."
            default: alertMessage = urlError.localizedDescription
            }
            showingAlert = true
        } catch {
            testStatus = .failure; alertTitle = "Error"
            alertMessage = error.localizedDescription; showingAlert = true
        }
    }

    private func saveConnection(urlString: String) {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
            baseURL: urlString,
            apiKey: draftApiKey,
            pin: draftPin,
            ackUser: draftAckUser,
            webhookSecret: pushEnabled ? draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            pushMiddlewareURL: pushEnabled ? draftPushURL.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            symbol: draftSymbol,
            accentColor: draftColor
        )
        if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
            savedConnections[idx] = now
        } else {
            savedConnections.append(now)
        }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        // Only set as active if: adding a new server, OR editing the currently active server.
        let isCurrentlyActive = existingConnection?.id.uuidString == activeSavedConnectionID
        if isAddMode || isCurrentlyActive {
            activeSavedConnectionID = now.id.uuidString
            baseURL  = now.baseURL
            apiKey   = now.apiKey
            pin      = now.pin
            ackUser  = now.ackUser
        }
    }

    private func deleteConnection() {
        guard let conn = existingConnection else { return }
        savedConnections.removeAll { $0.id == conn.id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        if activeSavedConnectionID == conn.id.uuidString {
            activeSavedConnectionID = ""
            baseURL = ""; apiKey = ""; pin = ""; ackUser = ""
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
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/ServerConfigView.swift
git commit -m "feat: add ServerConfigView — dedicated add/edit server form with icon picker"
```

---

## Task 8: Redesign `SettingsView` — server list

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

Replace the entire "BHNM Server" inline form section with a NavigationLink-based server list. Remove the global `push_middleware_url` AppStorage declaration.

- [ ] **Step 1: Replace SettingsView with the new list-based implementation**

Rewrite `SettingsView.swift` completely:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("netreo_api_version")   private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout")       private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count")   private var retryCount: Double = 3.0
    @AppStorage("refresh_interval")     private var refreshInterval: Double = 120.0
    @AppStorage("maxDevicesCount")      private var maxDevicesCount: Int = 20
    @AppStorage("netreo_active_connection_id") private var activeSavedConnectionID = ""

    @State private var savedConnections: [SavedConnection] = []
    @State private var switchingToConnection: SavedConnection? = nil
    @State private var switchingInProgress: UUID? = nil
    @State private var editingConnection: SavedConnection? = nil   // drives swipe-to-edit navigation
    @State private var navigateToAdd = false                        // drives + toolbar navigation
    @State private var isClassCWiFiAvailable = NetworkDiscovery.isOnClassCWiFi

    var body: some View {
        NavigationView {
            Form {
                // MARK: Discovery
                Section(
                    header: Text("Discovery"),
                    footer: Text(isClassCWiFiAvailable
                        ? "Scans your Wi‑Fi network for BHNM servers."
                        : "Requires a Wi‑Fi connection with a /24 (Class C) subnet.")
                ) {
                    NavigationLink(destination: AutoDiscoveryView()) {
                        Label("Discover BHNM Server", systemImage: "magnifyingglass.circle.fill")
                    }
                    .disabled(!isClassCWiFiAvailable)
                }

                // MARK: BHNM Servers list
                Section(header: Text("BHNM Servers")) {
                    if savedConnections.isEmpty {
                        Button {
                            navigateToAdd = true
                        } label: {
                            Label("Add BHNM Server", systemImage: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        ForEach(savedConnections) { connection in
                            serverRow(connection)
                        }
                    }
                }

                // MARK: Refresh
                Section(header: Text("Refresh")) {
                    VStack(alignment: .leading) {
                        Text("Auto-Refresh: \(Int(refreshInterval))s")
                        Slider(value: $refreshInterval, in: 30...300, step: 10)
                    }
                }

                // MARK: Devices
                Section(header: Text("Devices")) {
                    Stepper("Load up to \(maxDevicesCount) devices",
                            value: $maxDevicesCount, in: 10...100, step: 10)
                    Text("Limits how many devices are loaded in the Devices tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: API Configuration
                Section(header: Text("API Configuration")) {
                    Picker("API Version", selection: Binding(
                        get: { NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy },
                        set: { apiVersionString = $0.rawValue }
                    )) {
                        ForEach(NetreoAPIConfiguration.APIVersion.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    VStack(alignment: .leading) {
                        Text("Timeout: \(Int(timeout))s")
                        Slider(value: $timeout, in: 10...120, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Retry Count: \(Int(retryCount))")
                        Slider(value: $retryCount, in: 1...10, step: 1)
                    }
                }

                // MARK: About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            // NavigationLink inside swipeActions is not supported in SwiftUI.
            // Use @State + navigationDestination instead for both swipe-edit and + button navigation.
            .navigationDestination(item: $editingConnection) { conn in
                ServerConfigView(existingConnection: conn)
            }
            .navigationDestination(isPresented: $navigateToAdd) {
                ServerConfigView(existingConnection: nil)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { navigateToAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                isClassCWiFiAvailable = NetworkDiscovery.isOnClassCWiFi
                reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deepLinkConnectionApplied)) { _ in
                reload()
            }
            .confirmationDialog(
                "Switch to \"\(switchingToConnection?.name ?? "")\"?",
                isPresented: Binding(get: { switchingToConnection != nil }, set: { if !$0 { switchingToConnection = nil } }),
                titleVisibility: .visible
            ) {
                Button("Switch") {
                    if let conn = switchingToConnection { activateConnection(conn) }
                    switchingToConnection = nil
                }
                Button("Cancel", role: .cancel) { switchingToConnection = nil }
            }
        }
    }

    // MARK: - Server row
    // Active row → NavigationLink to edit. Inactive row → onTapGesture → confirmation dialog.
    // Swipe left on any row shows Edit action.

    @ViewBuilder
    private func serverRow(_ connection: SavedConnection) -> some View {
        let isActive = connection.id.uuidString == activeSavedConnectionID
        let isSwitching = switchingInProgress == connection.id
        let rowContent = serverRowContent(connection, isActive: isActive, isSwitching: isSwitching)

        // Swipe-to-edit uses @State editingConnection + .navigationDestination (NavigationLink
        // is not supported inside swipeActions). Active row taps navigate via NavigationLink.
        if isActive {
            NavigationLink(destination: ServerConfigView(existingConnection: connection)) {
                rowContent
            }
            .swipeActions(edge: .trailing) {
                Button { editingConnection = connection } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        } else {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture { switchingToConnection = connection }
                .swipeActions(edge: .trailing) {
                    Button { editingConnection = connection } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        }
    }

    private func serverRowContent(_ connection: SavedConnection, isActive: Bool, isSwitching: Bool) -> some View {
        HStack(spacing: 12) {
            ServerIconView(symbol: connection.symbol, accentColor: connection.accentColor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name).font(.body)
                if isActive {
                    Text("Active · \(hostname(connection.baseURL))")
                        .font(.caption).foregroundColor(.green)
                } else {
                    Text(hostname(connection.baseURL))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSwitching { ProgressView() }
        }
    }

    // MARK: - Actions

    private func reload() {
        savedConnections = UserDefaults.standard.loadSavedConnections()
    }

    private func activateConnection(_ connection: SavedConnection) {
        switchingInProgress = connection.id
        UserDefaults.standard.set(connection.baseURL, forKey: "netreo_base_url")
        UserDefaults.standard.set(connection.apiKey,  forKey: "netreo_api_key")
        UserDefaults.standard.set(connection.pin,     forKey: "netreo_pin")
        UserDefaults.standard.set(connection.ackUser, forKey: "netreo_ack_user")
        activeSavedConnectionID = connection.id.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switchingInProgress = nil
            reload()
        }
    }

    // MARK: - Helpers

    private func hostname(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
```

- [ ] **Step 2: Remove all remaining `push_middleware_url` references**

Search for any remaining usages:

```bash
grep -rn "push_middleware_url" /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM/BeNeM/
```

Remove any found references (the `@AppStorage("push_middleware_url")` declaration should now be gone from SettingsView; verify `AppDelegate` no longer references it).

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Deploy and smoke-test on device**

```bash
./build_and_deploy.sh
```

Manual checks:
- Settings tab shows server list (or "Add BHNM Server" if none configured)
- `+` toolbar button opens `ServerConfigView` in add mode
- Tapping an inactive server shows confirmation dialog
- Confirming switches active server (green "Active ·" moves)
- Tapping the active server opens `ServerConfigView` in edit mode
- Swipe left on any row shows "Edit" action
- Icon picker opens from the icon header; live preview updates
- `pushEnabled` toggle shows/hides middleware URL and secret fields

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: redesign SettingsView with multi-server list and NavigationLink rows"
```

---

## Task 9: Update `generate_benem_link.py`

**Files:**
- Modify: `generate_benem_link.py`

Rewrite the script to use the compact single-payload format, add `--i` interactive mode, `--symbol`/`--color`, and optional QR output.

- [ ] **Step 1: Rewrite the script**

```python
#!/usr/bin/env python3
"""Generate a benem:// deep-link URL for provisioning BeNeM app connections."""

import argparse
import base64
import getpass
import os
import sys
import zlib
import json
from urllib.parse import quote

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("Error: 'cryptography' package not found. Install with: pip install cryptography")
    sys.exit(1)


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
        secrets_path = os.path.join(os.path.dirname(__file__), "BeNeM", "Secrets.swift")
        try:
            with open(secrets_path) as f:
                for line in f:
                    if "encryptionKey" in line and "=" in line:
                        hex_key = line.split('"')[1]
                        break
        except FileNotFoundError:
            pass
    if not hex_key:
        print("Error: Could not find the encryption key.")
        print("Either set BENEM_SECRET_KEY or ensure BeNeM/Secrets.swift exists.")
        sys.exit(1)
    if len(hex_key) != 64:
        print(f"Error: Key must be 64 hex characters (32 bytes). Got {len(hex_key)}.")
        sys.exit(1)
    try:
        return bytes.fromhex(hex_key)
    except ValueError:
        print("Error: Key contains non-hex characters.")
        sys.exit(1)


def encrypt_payload(payload: dict, key: bytes) -> str:
    """Pack payload dict → JSON → zlib compress → AES-256-GCM encrypt → base64url."""
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, compressed, None)  # ct includes 16-byte tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")


def prompt(label: str, default: str = "", secret: bool = False) -> str:
    """Prompt the user for input, showing the default. Returns default on empty input."""
    display_default = "****" if secret and default else (default or "")
    suffix = f" [{display_default}]" if display_default else " []"
    if secret:
        value = getpass.getpass(f"{label}{suffix}: ")
    else:
        value = input(f"{label}{suffix}: ").strip()
    return value if value else default


def interactive_mode() -> dict:
    """Walk the user through each field interactively."""
    print("\nBeNeM Link Generator — Interactive Mode")
    print("=" * 42)
    print("Press Enter to accept the default shown in [brackets].\n")

    server = prompt("BHNM Server URL")
    if not server:
        print("Error: Server URL is required.")
        sys.exit(1)
    if not server.startswith("http://") and not server.startswith("https://"):
        server = "https://" + server

    api_key = prompt("API Token", secret=True)
    if not api_key:
        print("Error: API Token is required.")
        sys.exit(1)

    pin = prompt("PIN / License ID (leave blank for none)", secret=True)
    user = prompt("User Name", default="enter user name")

    # Default server name to hostname
    from urllib.parse import urlparse
    default_name = urlparse(server).hostname or server
    name = prompt("Server Name", default=default_name)

    symbol = prompt("SF Symbol", default="server.rack")
    color = prompt("Accent colour (hex)", default="#0A84FF")

    push_url = ""
    push_secret = ""
    enable_push = prompt("Enable push notifications? [y/N]").lower() == "y"
    if enable_push:
        push_url = prompt("  Middleware URL")
        push_secret = prompt("  Webhook Secret", secret=True)

    return {
        "server": server,
        "api_key": api_key,
        "pin": pin,
        "user": user,
        "name": name,
        "push_url": push_url,
        "push_secret": push_secret,
        "symbol": symbol,
        "color": color,
    }


def save_qr(url: str, path: str = "benem-link.png") -> None:
    try:
        import qrcode  # type: ignore
    except ImportError:
        print("QR code skipped — install with: pip install qrcode[pil]")
        return
    img = qrcode.make(url)
    img.save(path)
    print(f"QR code saved to {path}")


def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("-i", "--interactive", action="store_true",
                        help="Interactive mode: prompt for each field")
    parser.add_argument("--bhnm-server", dest="server",
                        help="BHNM server URL (e.g. https://bhnm.example.com)")
    parser.add_argument("--api_key", help="API token")
    parser.add_argument("--pin", default="", help="PIN / License ID (SaaS only, optional)")
    parser.add_argument("--user", default="enter user name", help="ACK user name")
    parser.add_argument("--server-name", "--name", dest="name", default="",
                        help="Connection display name (--name accepted for backwards compat)")
    parser.add_argument("--symbol", default="server.rack", help="SF Symbol name")
    parser.add_argument("--color", default="#0A84FF", help="Accent colour (hex)")
    parser.add_argument("--push-url", dest="push_url", default="",
                        help="Push middleware URL (encrypted in payload)")
    parser.add_argument("--push-secret", dest="push_secret", default="",
                        help="Push webhook secret (encrypted in payload)")
    parser.add_argument("--qr", action="store_true",
                        help="Also save a QR code PNG (benem-link.png)")
    args = parser.parse_args()

    if args.interactive:
        payload = interactive_mode()
        generate_qr = prompt("\nGenerate QR code? [y/N]").lower() == "y"
    else:
        if not args.server or not args.api_key:
            parser.error("--bhnm-server and --api_key are required (or use -i for interactive mode)")
        server = args.server
        if not server.startswith("http://") and not server.startswith("https://"):
            server = "https://" + server
        payload = {
            "server":      server,
            "api_key":     args.api_key,
            "pin":         args.pin,
            "user":        args.user,
            "name":        args.name,
            "push_url":    args.push_url,
            "push_secret": args.push_secret,
            "symbol":      args.symbol,
            "color":       args.color,
        }
        generate_qr = args.qr

    key = load_key()
    blob = encrypt_payload(payload, key)
    url = f"benem://configure?p={blob}"
    print(url)

    if generate_qr:
        save_qr(url)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Test the script (non-interactive)**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
python3 generate_benem_link.py \
  --bhnm-server https://bhnm.example.com \
  --api_key testkey \
  --user thomas \
  --server-name "Production BHNM" \
  --symbol server.rack \
  --color "#0A84FF"
```

Expected: `benem://configure?p=<blob>` printed. Blob should be under 300 chars.

- [ ] **Step 3: Test interactive mode**

```bash
python3 generate_benem_link.py -i
```

Walk through the prompts and verify output URL is produced.

- [ ] **Step 4: Test `--name` backwards compat**

```bash
python3 generate_benem_link.py \
  --bhnm-server https://bhnm.example.com \
  --api_key testkey \
  --name "Legacy name flag"
```

Expected: succeeds without error.

- [ ] **Step 5: Commit**

```bash
git add generate_benem_link.py
git commit -m "feat: compact p= payload, interactive mode, --symbol/--color/--qr flags in generate_benem_link.py"
```

---

## Task 10: Final build, deploy, and end-to-end test

- [ ] **Step 1: Build and deploy to device**

```bash
./build_and_deploy.sh
```

- [ ] **Step 2: End-to-end deep link test**

Generate a test link:

```bash
python3 generate_benem_link.py \
  --bhnm-server https://your-real-bhnm-server.com \
  --api_key YOUR_API_KEY \
  --user YourName \
  --server-name "Test Link" \
  --push-url https://bhnm-apns.hurrikap.org \
  --push-secret YOUR_SECRET
```

Copy the URL. On the device, paste it into Safari and navigate. Expected:
- BeNeM opens
- "Apply Configuration?" alert appears showing server name and user
- Tapping Apply: server appears in Settings list with correct icon and colour
- Push toggle is on with middleware URL pre-filled

- [ ] **Step 3: Test old-format link still works**

Generate using the old individual-param format manually or confirm `DeepLinkHandler` old path is untouched.

- [ ] **Step 4: Commit any remaining changes**

```bash
git status  # verify only expected files are modified
git add BeNeM/Models/SavedConnection.swift BeNeM/AppDelegate.swift BeNeM/ContentView.swift \
    BeNeM/BeNeMApp.swift BeNeM/Services/DeepLinkHandler.swift \
    BeNeM/Views/IconPickerSheet.swift BeNeM/Views/ServerConfigView.swift \
    BeNeM/Views/SettingsView.swift generate_benem_link.py
git commit -m "feat: v2.2.0 — multi-server list, ServerConfigView, compact deep link format"
```

- [ ] **Step 5: Bump version**

```bash
./scripts/bump_version.sh minor
git add BeNeM.xcodeproj/project.pbxproj
git commit -m "chore: bump version to 2.2.0"
```
