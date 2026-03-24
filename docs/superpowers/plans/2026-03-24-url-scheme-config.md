# benem:// URL Scheme Configuration Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow an admin to send a `benem://configure?...` URL that, when opened on device, prompts the user to accept encrypted server credentials and saves them as an active connection.

**Architecture:** A new `DeepLinkHandler` ObservableObject handles URL parsing and AES-256-GCM decryption; `BeNeMApp` owns it as a `@StateObject`, registers `.onOpenURL`, and shows confirmation/error alerts. `SettingsView`'s in-memory `activeSavedID` is migrated to a persisted `@AppStorage` key so the active connection survives app restarts. A standalone Python script generates valid `benem://` URLs for administrators.

**Tech Stack:** Swift/SwiftUI, Apple CryptoKit (AES-256-GCM), Python 3 + `cryptography` pip package (link generator only).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `BeNeM/Extensions/Data+Hex.swift` | `Data(hexString:)` extension for hex key parsing |
| Create | `BeNeM/Secrets.swift.template` | Committed template showing shape of `Secrets.swift` |
| Create | `BeNeM/Secrets.swift` _(gitignored)_ | Real 32-byte AES key as 64-char hex string |
| Create | `BeNeM/Services/DeepLinkHandler.swift` | URL parsing, decryption, upsert logic |
| Modify | `BeNeM/BeNeMApp.swift` | Wire `DeepLinkHandler`, `.onOpenURL`, two `.alert` modifiers |
| Modify | `BeNeM/Info.plist` | Add `CFBundleURLTypes` for `benem://` scheme |
| Modify | `BeNeM/Views/SettingsView.swift` | Migrate `@State activeSavedID: UUID?` → `@AppStorage` |
| Modify | `.gitignore` | Add `BeNeM/Secrets.swift` and `.env` |
| Modify | `BeNeM.xcodeproj/project.pbxproj` | Add new Swift files to compile sources; add build phase |
| Create | `generate_benem_link.py` | Standalone Python URL generator |
| Create | `.env.template` | Documents `BENEM_SECRET_KEY` env var |
| Create | `SETUP.md` | Developer onboarding for secrets and script usage |

---

## Task 1: Add `Data+Hex.swift` extension

**Files:**
- Create: `BeNeM/Extensions/Data+Hex.swift`

- [ ] **Step 1.1: Create the Extensions directory and file**

Create `BeNeM/Extensions/Data+Hex.swift` with this exact content:

```swift
import Foundation

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            data.append(byte)
        }
        self = data
    }
}
```

- [ ] **Step 1.2: Add the file to the Xcode project**

In Xcode: right-click the `BeNeM` group → Add Files → select `Data+Hex.swift`. Ensure target membership is checked for `BeNeM`.

- [ ] **Step 1.3: Verify it compiles**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

---

## Task 2: Secret key infrastructure

**Files:**
- Create: `BeNeM/Secrets.swift.template`
- Create: `BeNeM/Secrets.swift` _(gitignored)_
- Modify: `.gitignore`

- [ ] **Step 2.1: Update `.gitignore`**

Add these two lines to `.gitignore` under the `# Credentials / Secrets` section:

```
BeNeM/Secrets.swift
.env
```

- [ ] **Step 2.2: Create `Secrets.swift.template`**

Create `BeNeM/Secrets.swift.template` with this exact content:

```swift
// Copy this file to Secrets.swift and fill in the key.
// Secrets.swift is listed in .gitignore and must NEVER be committed.
// Generate a key: python3 -c "import secrets; print(secrets.token_hex(32))"
//             or: openssl rand -hex 32
enum Secrets {
    static let encryptionKey = "YOUR_64_HEX_CHAR_KEY_HERE"
}
```

- [ ] **Step 2.3: Generate a real key and create `Secrets.swift`**

```bash
KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
echo $KEY   # Save this — it is also needed for BENEM_SECRET_KEY
```

Create `BeNeM/Secrets.swift` (do **not** add to git):

```swift
// DO NOT COMMIT — listed in .gitignore
enum Secrets {
    static let encryptionKey = "<paste KEY here>"
}
```

- [ ] **Step 2.4: Add `Secrets.swift` to the Xcode project (compile sources only)**

In Xcode: right-click the `BeNeM` group → Add Files → select `Secrets.swift`. Ensure target membership is checked. Verify it does **not** appear in `git status` (should be ignored).

Run: `git status BeNeM/Secrets.swift`
Expected: no output (file is ignored).

- [ ] **Step 2.5: Verify the project still builds**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

---

## Task 3: Register `benem://` URL scheme in `Info.plist`

**Files:**
- Modify: `BeNeM/Info.plist`

- [ ] **Step 3.1: Add `CFBundleURLTypes` to `Info.plist`**

Open `BeNeM/Info.plist` and add the following inside the root `<dict>`, after the existing `UISupportedInterfaceOrientations~ipad` block:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.benem.configure</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>benem</string>
        </array>
    </dict>
</array>
```

- [ ] **Step 3.2: Verify the build still succeeds**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

---

## Task 4: Add Xcode build phase warning for missing `Secrets.swift`

This must run **before** Compile Sources so the warning appears before the compiler error.

- [ ] **Step 4.1: Add a new Run Script build phase in Xcode**

In Xcode:
1. Select the `BeNeM` target → Build Phases tab
2. Click `+` → New Run Script Phase
3. Name it: **"Check Secrets.swift exists"**
4. Drag it above the "Compile Sources" phase
5. Paste this script:

```bash
if [ ! -f "$SRCROOT/BeNeM/Secrets.swift" ]; then
  echo "warning: Secrets.swift is missing. Copy BeNeM/Secrets.swift.template → BeNeM/Secrets.swift and fill in your 64-char hex key."
fi
```

6. Uncheck "Based on dependency analysis" (so it always runs).

- [ ] **Step 4.2: Verify the warning fires correctly by temporarily renaming the file**

```bash
mv BeNeM/Secrets.swift BeNeM/Secrets.swift.bak
xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep "warning: Secrets.swift"
mv BeNeM/Secrets.swift.bak BeNeM/Secrets.swift
```

Expected: one line containing `warning: Secrets.swift is missing.`

---

## Task 5: Implement `DeepLinkHandler`

**Files:**
- Create: `BeNeM/Services/DeepLinkHandler.swift`

- [ ] **Step 5.1: Create `DeepLinkHandler.swift`**

Create `BeNeM/Services/DeepLinkHandler.swift` with this exact content:

```swift
import CryptoKit
import Foundation

@MainActor
final class DeepLinkHandler: ObservableObject {

    struct PendingImport {
        let serverURL: String
        let apiKey: String
        let pin: String       // "" if absent
        let ackUser: String
    }

    @Published var pendingImport: PendingImport? = nil
    @Published var showImportError = false
    private(set) var importErrorMessage = ""

    // MARK: - Public API

    func handle(url: URL) {
        guard url.scheme == "benem", url.host == "configure" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            fail("The link is missing required fields.")
            return
        }

        func param(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let server = param("server"), !server.isEmpty,
              let encryptedKey = param("api_key"), !encryptedKey.isEmpty else {
            fail("The link is missing required fields.")
            return
        }

        let encryptedPin = param("pin") ?? ""
        let ackUser = param("ack_user") ?? "enter user name"

        do {
            let symmetricKey = try loadKey()
            let decryptedKey = try decrypt(encryptedKey, using: symmetricKey)
            let decryptedPin = encryptedPin.isEmpty ? "" : try decrypt(encryptedPin, using: symmetricKey)
            pendingImport = PendingImport(
                serverURL: server,
                apiKey: decryptedKey,
                pin: decryptedPin,
                ackUser: ackUser
            )
        } catch {
            fail("The link is invalid or was created with a different key.")
        }
    }

    func applyPendingImport() {
        guard let imp = pendingImport else { return }
        pendingImport = nil

        // 1. Write active AppStorage keys directly to UserDefaults
        let ud = UserDefaults.standard
        ud.set(imp.serverURL, forKey: "netreo_base_url")
        ud.set(imp.apiKey,    forKey: "netreo_api_key")
        ud.set(imp.pin,       forKey: "netreo_pin")
        ud.set(imp.ackUser,   forKey: "netreo_ack_user")

        // 2. Upsert SavedConnection (match by server URL, case-insensitive)
        var connections = ud.loadSavedConnections()
        let serverLower = imp.serverURL.lowercased()
        let upsertedID: UUID

        if let idx = connections.firstIndex(where: { $0.baseURL.lowercased() == serverLower }) {
            // Update credentials in place; preserve id, baseURL, name
            connections[idx].apiKey  = imp.apiKey
            connections[idx].pin     = imp.pin
            connections[idx].ackUser = imp.ackUser
            upsertedID = connections[idx].id
        } else {
            // New entry — derive display name from hostname
            let name = URL(string: imp.serverURL)?.host ?? imp.serverURL
            let newConn = SavedConnection(
                id: UUID(),
                name: name,
                baseURL: imp.serverURL,
                apiKey: imp.apiKey,
                pin: imp.pin,
                ackUser: imp.ackUser
            )
            connections.append(newConn)
            upsertedID = newConn.id
        }

        ud.saveSavedConnections(connections)

        // 3. Persist active connection ID (same key read by SettingsView @AppStorage)
        ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")

        // 4. Notify SettingsView to reload if visible
        NotificationCenter.default.post(name: .deepLinkConnectionApplied, object: nil)
    }

    // MARK: - Private

    private func fail(_ message: String) {
        importErrorMessage = message
        showImportError = true
    }

    private func loadKey() throws -> SymmetricKey {
        guard let keyData = Data(hexString: Secrets.encryptionKey), keyData.count == 32 else {
            throw CryptoError.invalidKey
        }
        return SymmetricKey(data: keyData)
    }

    private func decrypt(_ base64url: String, using key: SymmetricKey) throws -> String {
        // Convert base64url → standard base64 with padding
        var b64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }

        guard let combined = Data(base64Encoded: b64) else {
            throw CryptoError.invalidBase64
        }
        // Pass full blob to SealedBox — CryptoKit extracts nonce (12 bytes) and tag (16 bytes) internally
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext  = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }
        return string
    }

    private enum CryptoError: Error {
        case invalidKey, invalidBase64, invalidUTF8
    }
}

extension Notification.Name {
    static let deepLinkConnectionApplied = Notification.Name("DeepLinkConnectionApplied")
}
```

- [ ] **Step 5.2: Add `DeepLinkHandler.swift` to the Xcode project**

In Xcode: right-click the `Services` group → Add Files → select `DeepLinkHandler.swift`. Ensure target membership is checked.

- [ ] **Step 5.3: Verify the project builds**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5.4: Commit**

```bash
git add BeNeM/Extensions/Data+Hex.swift \
        BeNeM/Secrets.swift.template \
        BeNeM/Services/DeepLinkHandler.swift \
        BeNeM/Info.plist \
        BeNeM.xcodeproj/project.pbxproj \
        .gitignore
git commit -m "feat: add DeepLinkHandler, Secrets template, Data+Hex, benem:// URL scheme registration"
```

---

## Task 6: Wire `DeepLinkHandler` into `BeNeMApp`

**Files:**
- Modify: `BeNeM/BeNeMApp.swift`

- [ ] **Step 6.1: Replace `BeNeMApp.swift` with the wired version**

Current content of `BeNeM/BeNeMApp.swift`:
```swift
import SwiftUI

@main
struct BeNeMApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    if showSplash {
                        SplashView {
                            showSplash = false
                        }
                    }
                }
        }
    }
}
```

Replace with:
```swift
import SwiftUI

@main
struct BeNeMApp: App {
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    if showSplash {
                        SplashView {
                            showSplash = false
                        }
                    }
                }
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
                .alert(
                    "Apply Configuration?",
                    isPresented: Binding(
                        get: { deepLinkHandler.pendingImport != nil },
                        set: { if !$0 { deepLinkHandler.pendingImport = nil } }
                    )
                ) {
                    Button("Apply") { deepLinkHandler.applyPendingImport() }
                    Button("Cancel", role: .cancel) { deepLinkHandler.pendingImport = nil }
                } message: {
                    if let imp = deepLinkHandler.pendingImport {
                        Text("Server: \(imp.serverURL)\nUser: \(imp.ackUser)")
                    }
                }
                .alert(
                    "Invalid Link",
                    isPresented: $deepLinkHandler.showImportError
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deepLinkHandler.importErrorMessage)
                }
        }
    }
}
```

- [ ] **Step 6.2: Build and verify**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6.3: Commit**

```bash
git add BeNeM/BeNeMApp.swift
git commit -m "feat: wire DeepLinkHandler into BeNeMApp with onOpenURL and confirmation alerts"
```

---

## Task 7: Migrate `SettingsView` active connection to `@AppStorage`

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

The goal is to replace `@State private var activeSavedID: UUID?` with a persisted `@AppStorage` key so the active selection survives app restarts and is visible to `DeepLinkHandler`.

- [ ] **Step 7.1: Replace the `activeSavedID` property declaration**

Find (around line 17 in `SettingsView.swift`):
```swift
@State private var activeSavedID: UUID? = nil
```

Replace with:
```swift
@AppStorage("netreo_active_connection_id") private var activeSavedConnectionID: String = ""
private var activeSavedUUID: UUID? { UUID(uuidString: activeSavedConnectionID) }
```

- [ ] **Step 7.2: Update all call sites — systematic substitution**

Apply the following substitutions throughout `SettingsView.swift`:

| Find | Replace |
|------|---------|
| `activeSavedID == nil` | `activeSavedConnectionID.isEmpty` |
| `activeSavedID != nil` | `!activeSavedConnectionID.isEmpty` |
| `activeSavedID = nil` | `activeSavedConnectionID = ""` |
| `activeSavedID = connection.id` | `activeSavedConnectionID = connection.id.uuidString` |
| `activeSavedID = now.id` | `activeSavedConnectionID = now.id.uuidString` |
| `activeSavedID ?? UUID()` | `activeSavedUUID ?? UUID()` |
| `guard let id = activeSavedID` | `guard let id = activeSavedUUID` |
| `connection.id == activeSavedID` | `connection.id.uuidString == activeSavedConnectionID` |

Known locations (verify each with a text search):
- `testConnection()`: `activeSavedID ?? UUID()` and `activeSavedID = now.id`
- `selectConnection(_:)`: `activeSavedID = connection.id`
- `selectNewConnection()`: `activeSavedID = nil`
- `deleteActiveConnection()`: `guard let id = activeSavedID` and `activeSavedID = nil`
- Form body: `.disabled(activeSavedID == nil)` on the Delete button
- Dropdown label: `connection.id == activeSavedID` in the `ForEach`

- [ ] **Step 7.3: Replace the `onAppear` credential-matching block**

Find the `onAppear` block (around line 170):
```swift
.onAppear {
    savedConnections = UserDefaults.standard.loadSavedConnections()
    draftBaseURL = baseURL
    draftApiKey  = apiKey
    draftPin     = pin
    draftAckUser = ackUser
    // Find which saved connection matches current @AppStorage credentials
    if let match = savedConnections.first(where: {
        $0.baseURL == baseURL &&
        $0.apiKey  == apiKey  &&
        $0.pin     == pin     &&
        $0.ackUser == ackUser
    }) {
        activeSavedID = match.id
        draftName = match.name
    }
}
```

Replace with:
```swift
.onAppear {
    savedConnections = UserDefaults.standard.loadSavedConnections()
    draftBaseURL = baseURL
    draftApiKey  = apiKey
    draftPin     = pin
    draftAckUser = ackUser
    // Restore display name from persisted active connection ID
    if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
        draftName = match.name
    }
}
```

- [ ] **Step 7.4: Add `onReceive` for deep-link reload**

Add the following modifier to the `NavigationView` in `SettingsView` (after the existing `.toolbar` modifier):

```swift
.onReceive(NotificationCenter.default.publisher(for: .deepLinkConnectionApplied)) { _ in
    savedConnections = UserDefaults.standard.loadSavedConnections()
    draftBaseURL = baseURL
    draftApiKey  = apiKey
    draftPin     = pin
    draftAckUser = ackUser
    if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
        draftName = match.name
    }
}
```

- [ ] **Step 7.5: Build and verify**

Run: `xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7.6: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: persist active connection ID to AppStorage; react to deep-link apply in SettingsView"
```

---

## Task 8: Manual end-to-end test on device

Before writing the Python script, verify the iOS side works independently.

- [ ] **Step 8.1: Build and deploy to device**

```bash
./build_and_deploy.sh
```

- [ ] **Step 8.2: Smoke test — valid link opens correctly**

In Safari on the same device, open a URL in this form (construct one manually using known credentials):

```
benem://configure?server=http%3A%2F%2F192.168.1.1&api_key=TEST&pin=TEST&ack_user=Test%20User
```

> Note: `api_key` and `pin` must be legitimately encrypted to pass decryption. Use a temporary `Secrets.encryptionKey` of `"00"*32` (all zeros) and a Python one-liner to produce a valid ciphertext if the Python script isn't ready yet:
>
> ```python
> from cryptography.hazmat.primitives.ciphers.aead import AESGCM
> import os, base64
> key = bytes(32)  # 32 zero bytes
> nonce = os.urandom(12)
> ct = AESGCM(key).encrypt(nonce, b"testkey", None)
> print(base64.urlsafe_b64encode(nonce+ct).rstrip(b'=').decode())
> ```

Expected: BeNeM opens, "Apply Configuration?" dialog appears showing the server URL and user.

- [ ] **Step 8.3: Smoke test — invalid link shows error**

Open: `benem://configure?server=http%3A%2F%2F192.168.1.1&api_key=AAAAAAAAAA`
Expected: "Invalid Link" alert appears.

- [ ] **Step 8.4: Verify active connection persists across restart**

After applying a valid link: force-quit the app and reopen it. The app should connect using the applied credentials without showing the setup screen.

---

## Task 9: Python link generator script

**Files:**
- Create: `generate_benem_link.py`
- Create: `.env.template`

- [ ] **Step 9.1: Create `.env.template`**

```
# Copy this file to .env and fill in your key — NEVER commit .env
# Generate a key: python3 -c "import secrets; print(secrets.token_hex(32))"
BENEM_SECRET_KEY=YOUR_64_HEX_CHAR_KEY_HERE
```

- [ ] **Step 9.2: Create `generate_benem_link.py`**

```python
#!/usr/bin/env python3
"""Generate a benem:// deep-link URL for provisioning BeNeM app connections."""

import argparse
import base64
import os
import sys
from urllib.parse import quote

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("Error: 'cryptography' package not found. Install it with: pip install cryptography")
    sys.exit(1)


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
        print("Error: BENEM_SECRET_KEY environment variable is not set.")
        print("Set it to the same 64-character hex key embedded in your BeNeM build.")
        print("Example: export BENEM_SECRET_KEY=a1b2c3...  (64 hex chars)")
        sys.exit(1)
    if len(hex_key) != 64:
        print(f"Error: BENEM_SECRET_KEY must be 64 hex characters (32 bytes). Got {len(hex_key)} characters.")
        sys.exit(1)
    try:
        return bytes.fromhex(hex_key)
    except ValueError:
        print("Error: BENEM_SECRET_KEY contains non-hex characters.")
        sys.exit(1)


def encrypt(plaintext: str, key: bytes) -> str:
    """Encrypt plaintext with AES-256-GCM. Returns base64url-encoded nonce+ciphertext+tag."""
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode("utf-8"), None)  # ct includes 16-byte tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("--server",  required=True,  help="BHNM server URL (plain text, e.g. https://bhnm.example.com)")
    parser.add_argument("--api_key", required=True,  help="API key to encrypt")
    parser.add_argument("--pin",     default="",     help="PIN to encrypt (optional, omit for non-SaaS servers)")
    parser.add_argument("--user",    default="enter user name", help="ACK user name (plain text, optional)")
    args = parser.parse_args()

    key = load_key()

    enc_api_key = encrypt(args.api_key, key)
    enc_pin     = encrypt(args.pin, key)

    # Percent-encode plain-text fields (%20 for spaces, matching Swift URLComponents)
    server   = quote(args.server, safe=":/?#[]@!$&'()*+,;=")  # safe chars valid in URLs
    ack_user = quote(args.user, safe="")

    url = f"benem://configure?server={server}&api_key={enc_api_key}&pin={enc_pin}&ack_user={ack_user}"
    print(url)


if __name__ == "__main__":
    main()
```

- [ ] **Step 9.3: Test the script locally**

```bash
export BENEM_SECRET_KEY=<your 64-char hex key from Task 2>
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key myApiKey \
  --pin myPin \
  --user "John Smith"
```

Expected: a single `benem://configure?...` URL printed to stdout.

- [ ] **Step 9.4: Test without `--pin` and without `--user`**

```bash
python3 generate_benem_link.py --server https://bhnm.example.com --api_key myApiKey
```

Expected: URL with `pin` parameter (encrypting empty string) and `ack_user=enter%20user%20name`.

- [ ] **Step 9.5: Test error cases**

```bash
unset BENEM_SECRET_KEY
python3 generate_benem_link.py --server https://bhnm.example.com --api_key key
```

Expected: error message about `BENEM_SECRET_KEY` not set; exit code 1.

- [ ] **Step 9.6: End-to-end: open generated URL on device**

Generate a URL using real credentials, open it in Safari on the test device, and verify the correct connection is applied and persisted after restart.

- [ ] **Step 9.7: Commit**

```bash
git add generate_benem_link.py .env.template .gitignore
git commit -m "feat: add Python link generator script and .env.template"
```

---

## Task 10: Write `SETUP.md`

**Files:**
- Create: `SETUP.md`

- [ ] **Step 10.1: Create `SETUP.md`**

```markdown
# BeNeM — Developer Setup

## 1. Secrets Setup (`Secrets.swift`)

The app uses AES-256-GCM to decrypt credentials received via the `benem://` URL scheme.
The decryption key lives in `Secrets.swift`, which is **gitignored and must never be committed**.

### Steps

1. Copy the template:
   ```bash
   cp BeNeM/Secrets.swift.template BeNeM/Secrets.swift
   ```

2. Generate a 32-byte (64-char hex) key:
   ```bash
   python3 -c "import secrets; print(secrets.token_hex(32))"
   # or
   openssl rand -hex 32
   ```

3. Paste the key into `BeNeM/Secrets.swift`:
   ```swift
   enum Secrets {
       static let encryptionKey = "<your 64-char hex key here>"
   }
   ```

4. Add `Secrets.swift` to the Xcode project (target: BeNeM, compile sources).

5. Verify it's ignored by git:
   ```bash
   git status BeNeM/Secrets.swift   # should produce no output
   ```

> **Team note:** Every developer and CI machine must have their own `Secrets.swift`.
> Testers must receive links generated with the **same key** as the build installed on their device.
> Distributing a build with key A and links generated with key B will cause "Invalid Link" errors.

---

## 2. Python Link Generator

The `generate_benem_link.py` script creates `benem://` URLs for provisioning testers.

### Install dependency

```bash
pip install cryptography
```

### Set the secret key

```bash
export BENEM_SECRET_KEY=<the same 64-char hex key from your Secrets.swift>
```

Or copy `.env.template` to `.env`, fill it in, and source it:

```bash
cp .env.template .env
# edit .env
source .env   # or: export $(cat .env | xargs)
```

### Generate a link

```bash
# With PIN (SaaS servers):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY \
  --pin YOUR_PIN \
  --user "John Smith"

# Without PIN (self-hosted servers):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY \
  --user "John Smith"

# Without specifying user (defaults to "enter user name"):
python3 generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key YOUR_API_KEY
```

The script prints a single `benem://configure?...` URL. Send it to the tester via any channel (email, Slack, AirDrop). The tester opens it on their device with BeNeM installed.

---

## 3. Security Notes

- `BENEM_SECRET_KEY` (and `Secrets.swift`) is equivalent to knowing the credentials in any link generated with that key.
- Without the correct `BENEM_SECRET_KEY`, no valid links can be generated and no links can be decrypted.
- The key should be rotated if it is ever exposed; all existing links will stop working after rotation.
```

- [ ] **Step 10.2: Commit**

```bash
git add SETUP.md
git commit -m "docs: add SETUP.md for Secrets.swift and link generator onboarding"
```

---

## Task 11: Final verification

- [ ] **Step 11.1: Clean build**

```bash
xcodebuild clean -scheme BeNeM && xcodebuild -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 11.2: Deploy to device and full end-to-end test**

```bash
./build_and_deploy.sh
```

Checklist:
- [ ] Generate a URL with the Python script using real credentials
- [ ] Open it on device — confirmation dialog shows correct server and user
- [ ] Tap Apply — app connects and Dashboard loads
- [ ] Force-quit and reopen — same connection used (no setup screen)
- [ ] Open Settings — correct server is highlighted in the dropdown
- [ ] Open an invalid URL — "Invalid Link" alert shown

- [ ] **Step 11.3: Verify `.gitignore` protections**

```bash
git status    # Secrets.swift and .env must not appear
git diff HEAD # no secrets in any tracked file
```

- [ ] **Step 11.4: Final commit**

```bash
git add BeNeM.xcodeproj/project.pbxproj   # if any remaining project file changes
git commit -m "feat: benem:// URL scheme configuration import — complete"
```
