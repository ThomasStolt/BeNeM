# Design: `benem://` URL Scheme Configuration Import

**Date:** 2026-03-24
**Status:** Approved
**Scope:** Deep-link configuration provisioning for BeNeM iOS app

---

## Overview

Allow an administrator to send a `benem://configure?...` URL to a tester. Opening the URL on device launches BeNeM, shows a confirmation dialog, and — on approval — saves the server credentials and sets that connection as active. The API key and PIN are AES-256-GCM encrypted so they cannot be read from the URL at a glance.

---

## URL Format

```
benem://configure?server=SERVER_URL&api_key=ENCRYPTED_BASE64URL&pin=ENCRYPTED_BASE64URL&ack_user=John%20Smith
```

| Parameter | Encoding | Required |
|-----------|----------|----------|
| `server` | Plain text, percent-encoded (`%20` for spaces) | Yes |
| `api_key` | AES-256-GCM → base64url (no padding) | Yes |
| `pin` | AES-256-GCM → base64url (no padding) | No — absent or empty-string encryption both accepted |
| `ack_user` | Plain text, percent-encoded (`%20` for spaces) | No (defaults to `"enter user name"`) |

**Spaces** must be encoded as `%20` throughout (not `+`). Swift's `URLComponents`/`URLQueryItem` uses `%20`; the Python script must match.

**`pin` optionality:** If the server does not use a PIN, the `pin` parameter may be omitted from the URL entirely. `applyPendingImport` treats a missing `pin` parameter as an empty string, which is the same as how `SavedConnection.pin = ""` represents "no PIN". The Python script `--pin` argument is optional and defaults to `""` (encrypts an empty string).

---

## Architecture

### New files

| File | Purpose |
|------|---------|
| `BeNeM/Services/DeepLinkHandler.swift` | `ObservableObject` — URL parsing, decryption, upsert logic |
| `BeNeM/Secrets.swift` | **Gitignored.** Contains `enum Secrets { static let encryptionKey }` |
| `BeNeM/Secrets.swift.template` | Committed. Content: `enum Secrets { static let encryptionKey = "YOUR_64_HEX_CHAR_KEY_HERE" // never commit Secrets.swift }` |
| `generate_benem_link.py` | Standalone Python script to generate `benem://` URLs |
| `.env.template` | Documents `BENEM_SECRET_KEY` env var; safe to commit |
| `SETUP.md` | Developer onboarding (see required sections below) |

### Modified files

| File | Change |
|------|--------|
| `BeNeM/BeNeMApp.swift` | Add `@StateObject DeepLinkHandler`, `.onOpenURL`, two `.alert` modifiers |
| `BeNeM/Info.plist` | Add `CFBundleURLTypes` entry for scheme `benem` |
| `BeNeM/Views/SettingsView.swift` | Migrate `@State activeSavedID: UUID?` → `@AppStorage("netreo_active_connection_id") activeSavedConnectionID: String`; update `onAppear` |
| `.gitignore` | Add `Secrets.swift`, `.env` |
| `BeNeM.xcodeproj` | Add `Secrets.swift` to compile sources; add pre-compile build phase script |

**Minimum deployment target note:** `CryptoKit.AES.GCM` requires iOS 13+. The app already targets iOS 15+, so no change is needed; this is documented as an assumption.

---

## `DeepLinkHandler`

```swift
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

    func handle(url: URL)          // parse → decrypt → set pendingImport or showImportError
    func applyPendingImport()      // write AppStorage keys + upsert SavedConnection + persist active ID
}
```

**Note on threading:** CryptoKit AES-256-GCM decryption of short strings is fast (~microseconds). Both `handle(url:)` and `applyPendingImport()` run on `@MainActor`. No background dispatch is needed.

### `handle(url:)` steps

1. Validate scheme == `"benem"` and host == `"configure"`. If not, return silently.
2. Extract query items via `URLComponents`. Parse: `server`, `api_key`, `pin` (optional), `ack_user` (optional, default `"enter user name"`).
3. If `server` or `api_key` is missing or empty → `importErrorMessage = "The link is missing required fields."`, `showImportError = true`, return.
4. Decrypt `api_key` (and `pin` if present) using AES-256-GCM with key from `Secrets.encryptionKey`.
5. On success → set `pendingImport` (triggers confirmation alert in `BeNeMApp`).
6. On decryption failure → `importErrorMessage = "The link is invalid or was created with a different key."`, `showImportError = true`.

### `applyPendingImport()` steps

1. Guard `pendingImport` is non-nil; capture it and clear `self.pendingImport = nil`.
2. Write `UserDefaults.standard.set(imp.serverURL, forKey: "netreo_base_url")` — and same for `netreo_api_key`, `netreo_pin`, `netreo_ack_user`. (**Use `UserDefaults.standard.set(_:forKey:)` directly** — `@AppStorage` in `BeNeMApp`/`SettingsView` observes `UserDefaults` and will update automatically.)
3. Load `[SavedConnection]` from `UserDefaults.standard.loadSavedConnections()`.
4. Search for an existing entry where `connection.baseURL.lowercased() == imp.serverURL.lowercased()`.
   - **Found:** update `connection.apiKey`, `connection.pin`, `connection.ackUser` in place. **Do not change `connection.id`, `connection.baseURL`, or `connection.name`** (preserve the user's chosen display name).
   - **Not found:** create a new `SavedConnection(id: UUID(), name: hostname(imp.serverURL), baseURL: imp.serverURL, apiKey: imp.apiKey, pin: imp.pin, ackUser: imp.ackUser)` and append it. `hostname()` extracts the `host` from `URL(string:)`, falling back to the full `serverURL` string if parsing fails.
5. Persist the updated list via `UserDefaults.standard.saveSavedConnections(connections)`.
6. Write the upserted connection's `id.uuidString` to `UserDefaults.standard.set(id.uuidString, forKey: "netreo_active_connection_id")`. This is the **same key** read by `SettingsView`'s `@AppStorage("netreo_active_connection_id")`.
7. Post `Notification.Name("DeepLinkConnectionApplied")` on `NotificationCenter.default` so that `SettingsView` can reload its `savedConnections` array if it is currently visible (see SettingsView section).

---

## `BeNeMApp` Wiring

```swift
@main
struct BeNeMApp: App {
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay { if showSplash { SplashView { showSplash = false } } }
                .onOpenURL { url in deepLinkHandler.handle(url: url) }
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

---

## `SettingsView` Migration

### What changes

`@State private var activeSavedID: UUID?` is replaced by:

```swift
@AppStorage("netreo_active_connection_id") private var activeSavedConnectionID: String = ""
```

Helper computed property (private, inside `SettingsView`):
```swift
private var activeSavedUUID: UUID? { UUID(uuidString: activeSavedConnectionID) }
```

**Sentinel value:** `""` (empty string) means "no active connection".

### Call-site substitutions

| Old | New |
|-----|-----|
| `activeSavedID == nil` | `activeSavedConnectionID.isEmpty` |
| `activeSavedID != nil` | `!activeSavedConnectionID.isEmpty` |
| `activeSavedID = nil` | `activeSavedConnectionID = ""` |
| `activeSavedID = connection.id` | `activeSavedConnectionID = connection.id.uuidString` |
| `activeSavedID ?? UUID()` | `activeSavedUUID ?? UUID()` |
| `guard let id = activeSavedID` | `guard let id = activeSavedUUID` |

### `onAppear` update

The current `onAppear` block credential-matches to derive `activeSavedID`. This block must be **replaced** — keeping it would overwrite `@AppStorage` on every appearance. The new block:

```swift
.onAppear {
    savedConnections = UserDefaults.standard.loadSavedConnections()
    draftBaseURL = baseURL
    draftApiKey  = apiKey
    draftPin     = pin
    draftAckUser = ackUser
    // Restore display name from the persisted active connection ID
    if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
        draftName = match.name
    }
}
```

### Reloading on deep-link apply

Add an `onReceive` in `SettingsView` to handle the notification posted by `DeepLinkHandler`:

```swift
.onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeepLinkConnectionApplied"))) { _ in
    savedConnections = UserDefaults.standard.loadSavedConnections()
    draftBaseURL = baseURL   // @AppStorage already updated
    draftApiKey  = apiKey
    draftPin     = pin
    draftAckUser = ackUser
    if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
        draftName = match.name
    }
}
```

**Accepted tradeoff:** Applying a deep link while `SettingsView` is open and the user is mid-edit will discard unsaved draft edits. This matches the existing behaviour of switching connections via the dropdown and is acceptable for an admin provisioning flow.

### All `activeSavedID` references to update

All four private helper functions in `SettingsView` also reference `activeSavedID` and must be updated using the substitution table above:

- `testConnection()` — line with `activeSavedID ?? UUID()` and `activeSavedID = now.id`
- `selectConnection(_:)` — `activeSavedID = connection.id`
- `selectNewConnection()` — `activeSavedID = nil`
- `deleteActiveConnection()` — `guard let id = activeSavedID` and `activeSavedID = nil`
- The Delete button's `.disabled(activeSavedID == nil)` modifier in the Form body

---

## Encryption

**Algorithm:** AES-256-GCM via Apple `CryptoKit` (no external Swift dependencies).

**Wire format:**
```
base64url-no-padding( nonce[12 bytes] || ciphertext || tag[16 bytes] )
```

- Nonce is randomly generated per encryption operation.
- `||` denotes concatenation. The entire blob is base64url-encoded using the URL-safe alphabet (`-` and `_` instead of `+` and `/`) with **no padding characters (`=`)**.
- The Python script uses `base64.urlsafe_b64encode(...).rstrip(b'=')` to match.
- Swift decodes with: `base64url → standard base64 (replace `-`→`+`, `_`→`/`, add padding) → Data`.

**Swift decryption (correct CryptoKit API usage):**

```swift
func decrypt(_ base64url: String, key: SymmetricKey) throws -> String {
    // 1. Convert base64url → standard base64 and decode
    var b64 = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64 += "=" }
    guard let combined = Data(base64Encoded: b64) else { throw DecryptionError.invalidBase64 }
    // 2. Pass the full blob to SealedBox(combined:) — CryptoKit extracts nonce (first 12 bytes)
    //    and tag (last 16 bytes) internally. Do NOT split manually.
    let sealedBox = try AES.GCM.SealedBox(combined: combined)
    let plaintext = try AES.GCM.open(sealedBox, using: key)
    guard let string = String(data: plaintext, encoding: .utf8) else { throw DecryptionError.invalidUTF8 }
    return string
}
```

**Key loading:**
```swift
guard let keyBytes = Data(hexString: Secrets.encryptionKey), keyBytes.count == 32 else {
    fatalError("Secrets.encryptionKey must be a 64-character hex string")
}
let symmetricKey = SymmetricKey(data: keyBytes)
```

(`Data(hexString:)` is a small extension that parses two-hex-char bytes. It lives in `BeNeM/Extensions/Data+Hex.swift`:
```swift
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
```)

**Key storage:** 32-byte key stored as a 64-character hex string in `Secrets.swift`:
```swift
enum Secrets {
    static let encryptionKey = "a1b2c3d4..."  // 64 hex chars = 32 bytes — NEVER COMMIT
}
```

---

## Secret Key Management

- `Secrets.swift` is listed in `.gitignore` and must never be committed.
- A build phase script (shell script, runs **before Compile Sources**) emits an Xcode **warning** if `Secrets.swift` is absent. Because `Secrets.swift` is also a compile-time dependency (`enum Secrets` is referenced in `DeepLinkHandler`), a missing file will also produce a compiler error — the build phase warning provides a clearer, actionable message before the compiler error fires.

**Build phase name:** `Check Secrets.swift exists`

**Build phase script:**
```bash
if [ ! -f "$SRCROOT/BeNeM/Secrets.swift" ]; then
  echo "warning: Secrets.swift is missing. Copy BeNeM/Secrets.swift.template → BeNeM/Secrets.swift and fill in your 64-char hex key."
fi
```

---

## `Info.plist` — URL Scheme Registration

Add the following to `BeNeM/Info.plist` inside the root `<dict>`:

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

---

## Python Script (`generate_benem_link.py`)

**Dependencies:** `cryptography` pip package. Script prints `pip install cryptography` and exits if missing.

**Usage:**
```bash
BENEM_SECRET_KEY=<64-hex> python generate_benem_link.py \
  --server https://bhnm.example.com \
  --api_key myApiKey \
  [--pin myPin] \
  [--user "John Smith"]
```

- Reads key from `BENEM_SECRET_KEY` env var; exits with a descriptive error message if absent.
- `--pin` is optional; defaults to `""` (encrypts empty string).
- `--user` is optional; defaults to `"enter user name"`.
- `server` and `ack_user` are percent-encoded using `urllib.parse.quote(value, safe='')` — this produces `%20` for spaces, consistent with Swift's `URLComponents`.
- Output: the complete `benem://` URL printed to stdout.

**Encryption (Python):**
```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os, base64

def encrypt(plaintext: str, key: bytes) -> str:
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode(), None)  # ct includes tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b'=').decode()
```

---

## `SETUP.md` Required Sections

The `SETUP.md` file must cover:

1. **Secrets setup** — how to copy `Secrets.swift.template` → `Secrets.swift`; how to generate a random 32-byte key (`python3 -c "import secrets; print(secrets.token_hex(32))"` or `openssl rand -hex 32`); where to paste it.
2. **Python script setup** — `pip install cryptography`; how to set `BENEM_SECRET_KEY`; example commands with and without `--pin` and `--user`.
3. **CI / team note** — `Secrets.swift` must never be committed; each developer generates their own; testers must receive links generated with the same key as the build they are running.
4. **Security note** — without `BENEM_SECRET_KEY` (matching the build), no valid links can be generated; possession of the key is equivalent to knowing the credentials.

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| URL scheme not `benem` / host not `configure` | Silently ignored |
| Missing `server` or `api_key` parameter | Error alert: "The link is missing required fields." |
| Decryption failure (wrong key, corrupt data, invalid base64) | Error alert: "The link is invalid or was created with a different key." |
| User taps Cancel on confirmation | No changes made; `pendingImport` cleared |
| `saveSavedConnections` JSON encoding failure | Silent failure (matches existing behaviour in `SettingsView`); not surfaced to user |

---

## Out of Scope

- No support for importing multiple connections in one URL.
- No QR code generation (can be added later by any QR tool wrapping the URL).
- No expiry or one-time-use tokens on the URL.
