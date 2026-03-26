# Multi-Server Push Notification Routing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each BHNM server connection stores its own webhook secret; the middleware routes push notifications only to devices currently active on that server.

**Architecture:** `SavedConnection` gains a `webhookSecret` field. `AppDelegate` caches the APNs device token and registers with the active connection's secret on launch and on server switch. The `bhnm-apns` middleware stores one `active_secret` per device and filters webhook forwarding accordingly.

**Tech Stack:** Swift/SwiftUI (iOS), `UserDefaults`/`@AppStorage`, APNs, Python middleware (`bhnm-apns` — separate git repo), `xcodebuild` for build verification.

**Note on testing:** The project has no automated test target. Verification steps use `xcodebuild` to confirm the build compiles, then manual device testing described in the final task.

**Spec:** `docs/superpowers/specs/2026-03-26-multi-server-push-notifications-design.md`

---

## Files Changed

| File | Action | Responsibility |
|---|---|---|
| `BeNeM/Models/SavedConnection.swift` | Modify | Add `webhookSecret` field with default `""` |
| `BeNeM/Views/SettingsView.swift` | Modify | Move webhook secret UI to per-connection; update 4 methods |
| `BeNeM/AppDelegate.swift` | Modify | Cache device token; load secret from active connection |
| `BeNeM/ContentView.swift` | Modify | Re-register on `netreo_active_connection_id` change |
| `BeNeM/Services/DeepLinkHandler.swift` | Modify | Write `pushSecret` to `SavedConnection.webhookSecret` |
| `bhnm-apns` middleware (separate repo) | Modify | Store `active_secret` per device; filter webhook forwarding |

---

## Task 1: Add `webhookSecret` to `SavedConnection`

**Files:**
- Modify: `BeNeM/Models/SavedConnection.swift`

- [ ] **Step 1: Add `webhookSecret` field**

In `SavedConnection.swift`, add the new field after `ackUser` **with an explicit default value**:

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String
    var ackUser: String
    var webhookSecret: String = ""   // "" = push notifications disabled for this server
}
```

The `= ""` default value is required for Codable migration. Without it, Swift's synthesized `init(from:)` will throw `DecodingError.keyNotFound` when decoding existing JSON records that don't have `webhookSecret` — and `loadSavedConnections()` returns `[]` on any decode error, silently erasing all saved connections for existing users. The explicit default value makes `decodeIfPresent` behaviour kick in automatically.

- [ ] **Step 2: Build to verify no compile errors**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination "generic/platform=iOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

Note: `DeepLinkHandler.swift` will now produce a compile error because its `SavedConnection(...)` literal is missing `webhookSecret`. That's expected — it will be fixed in Task 5.

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Models/SavedConnection.swift
git commit -m "feat: add webhookSecret field to SavedConnection"
```

---

## Task 2: Update `SettingsView` — per-connection webhook secret UI

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

- [ ] **Step 1: Add `draftWebhookSecret` state and remove global secret**

Add draft state near the other draft properties (around line 17):
```swift
@State private var draftWebhookSecret = ""
```

Remove **two things**:
1. The `@AppStorage("push_middleware_secret") private var pushMiddlewareSecret = ""` property declaration at line 14.
2. The global "Webhook Secret" `SecureField` from the Push Notifications section (lines 61–62).

The Push Notifications section should retain only the Middleware URL field:

```swift
Section(
    header: Text("Push Notifications"),
    footer: Text("URL of the BHNM APNs middleware server (e.g. https://bhnm-apns.hurrikap.org). Leave empty to disable push notifications.")
) {
    TextField("Middleware URL", text: $pushMiddlewareURL)
        .autocapitalization(.none)
        .keyboardType(.URL)
}
```

- [ ] **Step 2: Add "Webhook Secret" field to the BHNM Server section**

In the BHNM Server section, add a `SecureField` below the ACK User field (after line 108):

```swift
SecureField("Webhook Secret", text: $draftWebhookSecret)
    .focused($focusedField, equals: .webhookSecret)
```

Also add `.webhookSecret` to the `Field` enum (line 28):
```swift
private enum Field: Hashable { case name, baseURL, apiKey, pin, ackUser, webhookSecret }
```

- [ ] **Step 3: Update `testConnection()` — include `webhookSecret` in `SavedConnection` literal**

In `testConnection()` around line 300, the `SavedConnection` is constructed. Add `webhookSecret`:

```swift
let now = SavedConnection(
    id: activeSavedUUID ?? UUID(),
    name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
    baseURL: draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
    apiKey: draftApiKey,
    pin: draftPin,
    ackUser: draftAckUser,
    webhookSecret: draftWebhookSecret.trimmingCharacters(in: .whitespacesAndNewlines)
)
```

- [ ] **Step 4: Update `selectConnection(_:)` — populate `draftWebhookSecret`**

In `selectConnection(_:)` (around line 373), add:
```swift
draftWebhookSecret = connection.webhookSecret
```

- [ ] **Step 5: Update `selectNewConnection()` — clear `draftWebhookSecret`**

In `selectNewConnection()` (around line 384), add:
```swift
draftWebhookSecret = ""
```

- [ ] **Step 6: Update `deleteActiveConnection()` — clear `draftWebhookSecret`**

In `deleteActiveConnection()` (around line 400), add:
```swift
draftWebhookSecret = ""
```

- [ ] **Step 7: Update `.onAppear` — restore `draftWebhookSecret` from active connection**

In `.onAppear` (around line 207), after the existing `draftAckUser = ackUser` line, add:
```swift
if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
    draftWebhookSecret = match.webhookSecret
}
```

(This block already restores `draftName` from the active connection — add `webhookSecret` restoration to the same `if let match` block.)

- [ ] **Step 8: Update `.onReceive(deepLinkConnectionApplied)` — restore `draftWebhookSecret`**

In the `.onReceive(NotificationCenter...)` block (around line 229), add the same restoration:
```swift
if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
    draftWebhookSecret = match.webhookSecret
}
```

- [ ] **Step 9: Build to verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination "generic/platform=iOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED` (DeepLinkHandler may still error — fixed in Task 5)

- [ ] **Step 10: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: move webhook secret to per-connection in SettingsView"
```

---

## Task 3: Update `AppDelegate` — cache token, load secret from active connection

**Files:**
- Modify: `BeNeM/AppDelegate.swift`

- [ ] **Step 1: Add `cachedDeviceToken` property**

After the `pendingIncidentID` property (line 10), add:

```swift
var cachedDeviceToken: String? = nil
```

- [ ] **Step 2: Cache the token in `didRegisterForRemoteNotificationsWithDeviceToken`**

In `didRegisterForRemoteNotificationsWithDeviceToken` (line 35), cache the token before calling registration:

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("[APNs] Device token: \(token)")
    cachedDeviceToken = token
    // Load secret from the currently active SavedConnection
    let secret = activeWebhookSecret()
    registerWithMiddleware(token: token, secret: secret)
}
```

- [ ] **Step 3: Add `activeWebhookSecret()` helper**

Add this private helper method below `registerWithMiddleware`:

```swift
private func activeWebhookSecret() -> String {
    let ud = UserDefaults.standard
    guard let activeID = ud.string(forKey: "netreo_active_connection_id"),
          !activeID.isEmpty else { return "" }
    let connections = ud.loadSavedConnections()
    return connections.first(where: { $0.id.uuidString == activeID })?.webhookSecret ?? ""
}
```

- [ ] **Step 4: Update `registerWithMiddleware` signature to accept a secret**

Replace the existing `private func registerWithMiddleware(token:)` method. The replacement must be `internal` (no `private`) because `ContentView` and `DeepLinkHandler` will call it via `AppDelegate.shared?`. Omitting the access modifier makes it `internal` by default:

```swift
func registerWithMiddleware(token: String, secret: String) {
    let middlewareURL = UserDefaults.standard.string(forKey: "push_middleware_url") ?? ""
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

Note: The secret is now passed as a parameter and sent as `X-Webhook-Token`. The deprecated `push_middleware_secret` UserDefaults key is no longer read.

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination "generic/platform=iOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add BeNeM/AppDelegate.swift
git commit -m "feat: cache APNs token and load webhook secret from active connection"
```

---

## Task 4: Update `ContentView` — re-register on server switch

**Files:**
- Modify: `BeNeM/ContentView.swift`

- [ ] **Step 1: Add `@AppStorage` for `netreo_active_connection_id`**

At the top of `ContentView` (after the existing `@AppStorage` properties), add:

```swift
@AppStorage("netreo_active_connection_id") private var activeConnectionID = ""
```

- [ ] **Step 2: Add `onChange` observer for server switch**

In the `body` of `ContentView`, after the existing `.onChange(of: retryCount)` (line 41), add:

```swift
.onChange(of: activeConnectionID) { _, newID in
    guard !newID.isEmpty,
          let token = AppDelegate.shared?.cachedDeviceToken else { return }
    let connections = UserDefaults.standard.loadSavedConnections()
    let secret = connections.first(where: { $0.id.uuidString == newID })?.webhookSecret ?? ""
    AppDelegate.shared?.registerWithMiddleware(token: token, secret: secret)
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination "generic/platform=iOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/ContentView.swift
git commit -m "feat: re-register push middleware on server switch"
```

---

## Task 5: Update `DeepLinkHandler` — write `pushSecret` to `SavedConnection`

**Files:**
- Modify: `BeNeM/Services/DeepLinkHandler.swift`

- [ ] **Step 1: Write `pushSecret` into `SavedConnection.webhookSecret` (update branch)**

In `applyPendingImport()`, around line 86, in the **update** branch (existing connection), add `webhookSecret` update:

```swift
if let idx = connections.firstIndex(where: { $0.baseURL.lowercased() == serverLower }) {
    if !imp.name.isEmpty { connections[idx].name = imp.name }
    connections[idx].apiKey        = imp.apiKey
    connections[idx].pin           = imp.pin
    connections[idx].ackUser       = imp.ackUser
    if !imp.pushSecret.isEmpty {
        connections[idx].webhookSecret = imp.pushSecret
    }
    upsertedID = connections[idx].id
}
```

- [ ] **Step 2: Write `pushSecret` into `SavedConnection.webhookSecret` (insert branch)**

In the **insert** branch (new connection, around line 96), add `webhookSecret`:

```swift
let newConn = SavedConnection(
    id: UUID(),
    name: name,
    baseURL: imp.serverURL,
    apiKey: imp.apiKey,
    pin: imp.pin,
    ackUser: imp.ackUser,
    webhookSecret: imp.pushSecret
)
```

- [ ] **Step 3: Remove the old `push_middleware_secret` write**

Delete or comment out lines 117–119:

```swift
// REMOVED: push_middleware_secret is deprecated
// if !imp.pushSecret.isEmpty {
//     ud.set(imp.pushSecret, forKey: "push_middleware_secret")
// }
```

The `push_middleware_url` write (line 114–116) is kept — that setting remains global.

- [ ] **Step 4: Trigger re-registration after deep link import**

After `ud.saveSavedConnections(connections)` (line 108), add:

```swift
// Re-register push middleware with the new connection's secret
if let token = AppDelegate.shared?.cachedDeviceToken {
    let secret = connections.first(where: { $0.id == upsertedID })?.webhookSecret ?? ""
    AppDelegate.shared?.registerWithMiddleware(token: token, secret: secret)
}
```

- [ ] **Step 5: Build to verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination "generic/platform=iOS" build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add BeNeM/Services/DeepLinkHandler.swift
git commit -m "feat: write deep link pushSecret to SavedConnection.webhookSecret"
```

---

## Task 6: Update `bhnm-apns` middleware

**Repo:** `github.com/ThomasStolt/bhnm-apns` (separate from this iOS repo — work in that repo's directory)

The middleware needs two changes:
1. `/register` stores the `active_secret` from the `X-Webhook-Token` header alongside the device token.
2. `/webhook` filters: only forward to devices where `active_secret` matches the webhook's secret.

This task is written generically — adapt to the actual Python/storage implementation in that repo.

- [ ] **Step 1: Add `active_secret` to the device storage schema**

Find where device tokens are stored (likely a JSON file, SQLite DB, or in-memory dict). Add an `active_secret` field per device record.

Example (if using a JSON file or dict):
```python
# Before: {"token": "abc...", "device_name": "iPhone"}
# After:  {"token": "abc...", "device_name": "iPhone", "active_secret": "xyz..."}
```

If using SQLite, add a column:
```sql
ALTER TABLE devices ADD COLUMN active_secret TEXT NOT NULL DEFAULT '';
```

- [ ] **Step 2: Update `/register` to store `active_secret`**

Read the `X-Webhook-Token` header and upsert it as `active_secret` for this device token:

```python
@app.route('/register', methods=['POST'])
def register():
    secret = request.headers.get('X-Webhook-Token', '')
    body = request.get_json()
    token = body.get('token', '')
    device_name = body.get('device_name', '')
    # Upsert: if token exists, update active_secret and device_name; else insert
    upsert_device(token=token, device_name=device_name, active_secret=secret)
    return '', 200
```

- [ ] **Step 3: Update `/webhook` to filter by `active_secret`**

When a webhook arrives with `?secret=<secret>`, only forward APNs notifications to devices where `active_secret == secret`:

```python
@app.route('/webhook', methods=['POST'])
def webhook():
    secret = request.args.get('secret', '')
    # Only forward to devices registered for this secret
    matching_tokens = get_tokens_for_secret(secret)
    for token in matching_tokens:
        send_apns_notification(token, request.get_json())
    return '', 200
```

- [ ] **Step 4: Test the middleware locally**

Register two fake device tokens with different secrets:
```bash
curl -X POST http://localhost:5000/register \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: secret_A" \
  -d '{"token": "token_device_1", "device_name": "iPhone A"}'

curl -X POST http://localhost:5000/register \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: secret_B" \
  -d '{"token": "token_device_2", "device_name": "iPhone B"}'
```

Switch device_1 to secret_B:
```bash
curl -X POST http://localhost:5000/register \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: secret_B" \
  -d '{"token": "token_device_1", "device_name": "iPhone A"}'
```

Send a webhook with secret_A — verify it does NOT reach token_device_1 (now on secret_B):
```bash
curl -X POST "http://localhost:5000/webhook?secret=secret_A" \
  -H "Content-Type: application/json" \
  -d '{"incident_id": "TEST-1", "hostname": "test"}'
```

Expected: no notification forwarded (token_device_1 switched away from secret_A; token_device_2 was never on secret_A).

- [ ] **Step 5: Deploy**

```bash
docker compose build && docker compose up -d
```

- [ ] **Step 6: Commit in the middleware repo**

```bash
git add .
git commit -m "feat: per-device active_secret routing for webhook forwarding"
```

---

## Task 7: iOS version bump and deploy

**Files:**
- Run: `./scripts/bump_version.sh minor` (new feature)
- Run: `./build_and_deploy.sh`

- [ ] **Step 1: Bump version**

```bash
cd "/Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM"
./scripts/bump_version.sh minor
```

- [ ] **Step 2: Build and deploy to device**

```bash
./build_and_deploy.sh
```

Expected: app installs on TomiPhone13.

- [ ] **Step 3: Commit version bump**

```bash
git add BeNeM.xcodeproj/project.pbxproj
git commit -m "feat: v2.1.0 — per-server push notification routing"
```

---

## Task 8: End-to-End Verification

Manual test procedure with two BHNM servers (Server A and Server B), both configured with webhooks pointing to the same middleware but with different secrets.

- [ ] **Step 1: Configure Server A in the app**

In Settings → BHNM Server, select or create Server A. Enter its Webhook Secret (e.g. `secret_A`). Tap Test. Verify green dot.

Check middleware logs:
```bash
docker compose logs bhnm-apns -t --tail 10
```
Expected: `POST /register` with status 200.

- [ ] **Step 2: Verify Server A notifications work**

Trigger a test webhook from Server A:
```bash
curl -X POST "https://bhnm-apns.hurrikap.org/webhook?secret=secret_A" \
  -H "Content-Type: application/json" \
  -d '{"incident_id":"TEST-A","hostname":"server-a","host_address":"1.1.1.1","host_state":"DOWN","notification_type":"PROBLEM","severity":"CRITICAL","site":"HQ","category":"Routers","service_desc":"Ping","output":"Host unreachable","incident_time":"2026-03-26 10:00:00"}'
```

Expected: push notification appears on iPhone.

- [ ] **Step 3: Switch to Server B**

In Settings, switch to Server B (different `webhookSecret`, e.g. `secret_B`). Tap Test.

Check logs — should see a new `POST /register` with Server B's secret.

- [ ] **Step 4: Verify Server A no longer notifies**

Send the same Server A test webhook again (same curl from Step 2).

Expected: **no notification** on iPhone.

- [ ] **Step 5: Verify Server B notifications work**

```bash
curl -X POST "https://bhnm-apns.hurrikap.org/webhook?secret=secret_B" \
  -H "Content-Type: application/json" \
  -d '{"incident_id":"TEST-B","hostname":"server-b","host_address":"2.2.2.2","host_state":"DOWN","notification_type":"PROBLEM","severity":"CRITICAL","site":"DC","category":"Switches","service_desc":"Ping","output":"Host unreachable","incident_time":"2026-03-26 10:00:00"}'
```

Expected: push notification appears on iPhone.
