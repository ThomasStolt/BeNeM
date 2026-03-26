# Multi-Server Settings Redesign & Compact Deep Link Format

**Date:** 2026-03-26
**Status:** Approved

## Overview

Two related improvements:

1. **Settings screen redesign** — the BHNM Server section becomes a proper multi-server list with a dedicated per-server configuration screen, SF Symbol icons with accent colour pickers, and a tap-to-switch-with-confirmation flow.
2. **Compact deep link format** — `generate_benem_link.py` produces a shorter `benem://configure?p=<blob>` URL using a single zlib-compressed AES-GCM-encrypted JSON payload instead of multiple individual encrypted query parameters.

---

## 1. Settings Screen Redesign

### 1.1 BHNM Servers List (SettingsView)

The existing inline form fields in the "BHNM Server" section are replaced by a `List`-based row per saved connection.

**Row anatomy:**
- Left: rounded-rectangle SF Symbol icon in the connection's accent colour (32 × 32 pt)
- Middle: server name (primary text) + subtitle
  - Active connection: `"Active · <hostname>"` in green (`.systemGreen`)
  - Inactive: `"<hostname>"` in `.secondary`
- Right: chevron (`›`)

**Interactions:**

| Gesture | Target | Behaviour |
|---|---|---|
| Tap | Inactive row | Confirmation dialog: *"Switch to [Name]?"* with **Switch** / **Cancel** → on confirm, activates connection + re-tests in background (inline spinner replaces chevron during test) |
| Tap | Active row | Navigates to `ServerConfigView` in edit mode |
| Swipe left | Any row | "Edit" action → navigates to `ServerConfigView` in edit mode |
| Tap `+` toolbar button | — | Navigates to `ServerConfigView` in add mode |

**Empty state:** A single row labelled *"Add BHNM Server"* with a `plus.circle` SF Symbol and chevron. Tapping it navigates to `ServerConfigView` in add mode.

**Push Notifications section:** The existing standalone `push_middleware_url` global setting is removed from `SettingsView`. Push configuration moves entirely into per-server `ServerConfigView`. This supersedes the architectural decision in `2026-03-26-multi-server-push-notifications-design.md` that kept `push_middleware_url` global — the per-connection model is preferred here because different BHNM servers may use different middleware instances. `AppDelegate.registerWithMiddleware` is updated to read `pushMiddlewareURL` from the active `SavedConnection` rather than the global AppStorage key.

**Tap-to-switch and push re-registration:** When the user confirms a server switch, the view writes the new UUID to the `netreo_active_connection_id` AppStorage key. This triggers `ContentView.onChange(of: activeSavedConnectionID)`. Implementors must verify (or add) a `registerWithMiddleware` call inside that handler, passing the newly active connection's `webhookSecret` and `pushMiddlewareURL`.

---

### 1.2 ServerConfigView (new)

A dedicated `Form`-based screen for adding or editing a single server connection.

**Navigation title:** `"Add Server"` (add mode) or the connection's name (edit mode).

**Icon header (top of form, above sections):**

```
[ Large rounded icon — SF Symbol in accent colour ]
      "Tap to customise"
```

Tapping opens a sheet (`IconPickerSheet`) with:
- A grid of curated SF Symbols (≈ 20, relevant to servers/networking: `server.rack`, `network`, `antenna.radiowaves.left.and.right`, `wifi`, `globe`, `cloud`, `lock.shield`, `building.2`, `cpu`, `externaldrive.connected.to.line.below`, etc.)
- A colour picker row (SwiftUI `ColorPicker` or a fixed palette of 8–10 accent colours)
- Live preview of the selected combination

**Section: Connection**

| Field | Type | Notes |
|---|---|---|
| Server Name | `TextField` | Required; used as display name in list |
| Server URL | `TextField` (URL keyboard) | Required; auto-prepends `https://` if scheme is absent |
| API Token | `SecureField` | Required |
| PIN / License ID | `SecureField` | Optional; labelled *(SaaS only)* |
| User Name | `TextField` | Required; used as ACK user; validated non-empty before save |

**Section: Push Notifications**

| Field | Type | Notes |
|---|---|---|
| Enable Push Notifications | `Toggle` | Initialised to `true` if existing connection has non-empty `pushMiddlewareURL` or `webhookSecret`; `false` for new servers |
| Middleware URL | `TextField` (URL keyboard) | Shown only when toggle is on |
| Webhook Secret | `SecureField` | Shown only when toggle is on |

`@State private var pushEnabled: Bool` drives toggle visibility. For new servers it defaults to `false`. For existing connections it is set in `.onAppear` / view init:

```swift
pushEnabled = !connection.pushMiddlewareURL.isEmpty || !connection.webhookSecret.isEmpty
```

The `||` is intentional: either field being non-empty is enough to show push fields (so a partially-configured connection is still editable). If both are empty the toggle starts off.

**Actions:**

- **Test & Save** (add mode) / **Save** (edit mode): runs connection test against `restful/devices/list`; on success saves `SavedConnection` and sets it as the active connection; on failure shows alert with diagnosis.
- **Delete** (edit mode only, destructive): confirmation dialog → removes from saved list; if active, clears active connection.

---

## 2. Model Changes — `SavedConnection`

Two new fields are added with backwards-compatible defaults (existing persisted data decodes without them):

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String
    var ackUser: String
    var webhookSecret: String = ""
    var pushMiddlewareURL: String = ""   // NEW — per-connection, replaces global push_middleware_url
    var symbol: String = "server.rack"  // NEW — SF Symbol name
    var accentColor: String = "#0A84FF" // NEW — hex accent colour
}
```

`push_middleware_url` from `UserDefaults`/`AppStorage` is migrated on first launch after update. Migration runs in `BeNeMApp`'s `init()` (before any view appears):

```swift
// In BeNeMApp.init()
migrateGlobalPushURLIfNeeded()

func migrateGlobalPushURLIfNeeded() {
    let ud = UserDefaults.standard
    guard let globalURL = ud.string(forKey: "push_middleware_url"), !globalURL.isEmpty else { return }
    let activeID = ud.string(forKey: "netreo_active_connection_id") ?? ""
    var connections = ud.loadSavedConnections()  // pre-existing helper in SavedConnection.swift
    if let idx = connections.firstIndex(where: { $0.id.uuidString == activeID }),
       connections[idx].pushMiddlewareURL.isEmpty {
        connections[idx].pushMiddlewareURL = globalURL
        ud.saveSavedConnections(connections)     // pre-existing helper in SavedConnection.swift
    }
    ud.removeObject(forKey: "push_middleware_url")
}
```

After migration, grep the entire codebase for all remaining references to `"push_middleware_url"` (including the `@AppStorage` declaration in `SettingsView` and any reads in `AppDelegate`) and remove them.

---

## 3. Compact Deep Link Format

### 3.1 Payload Structure

All configuration fields are packed into a single JSON object, zlib-compressed, then AES-256-GCM encrypted.

**JSON schema (before compression):**
```json
{
  "server":       "https://bhnm.example.com",
  "api_key":      "<plaintext API key>",
  "pin":          "<plaintext PIN or empty string>",
  "user":         "<ACK username>",
  "name":         "<display name>",
  "push_url":     "<middleware URL or empty string>",
  "push_secret":  "<plaintext webhook secret or empty string>",
  "symbol":       "server.rack",
  "color":        "#0A84FF"
}
```

**Encoding pipeline (Python script):**
```
JSON string → UTF-8 bytes → zlib.compress(level=9) → AES-256-GCM encrypt → base64url (no padding)
```

AES-GCM output layout: `nonce (12 bytes) ‖ ciphertext ‖ tag (16 bytes)` — same as existing individual-field encryption.

**Resulting URL:**
```
benem://configure?p=<base64url_blob>
```

Typical length: **~240–280 characters** (vs. ~450–550 for the old multi-param format).

### 3.2 DeepLinkHandler — Dual Format Support

`DeepLinkHandler.handle(url:)` detects the format from the query parameters:

- **New format**: single `p` parameter present → decrypt → zlib decompress → JSON decode → populate `PendingImport`
- **Old format**: `server` + `api_key` parameters present → existing individual-decrypt path (unchanged)

`PendingImport` gains three new fields with defaults matching `SavedConnection`:
- `symbol: String = "server.rack"`
- `accentColor: String = "#0A84FF"`
- `pushMiddlewareURL: String = ""`

`applyPendingImport()` is updated to write all three new fields into the upserted connection:
- `connection.pushMiddlewareURL = imp.pushMiddlewareURL` (replaces the current line that writes to the global `push_middleware_url` UserDefaults key — that global write is removed)
- `connection.symbol = imp.symbol`
- `connection.accentColor = imp.accentColor`

**Decoding pipeline (Swift):**
```
base64url → Data → AES-GCM.open (extracts nonce+ciphertext+tag) → zlib decompress → JSON decode
```

Zlib decompression uses `Compression` framework (`compression_decode_buffer` with `COMPRESSION_ZLIB`).

### 3.3 `generate_benem_link.py` Changes

**New arguments:**

| Flag | Default | Description |
|---|---|---|
| `--server-name` / `--name` | `""` | Display name; `--name` is a backwards-compatible alias |
| `--symbol` | `"server.rack"` | SF Symbol name |
| `--color` | `"#0A84FF"` | Accent colour (hex) |
| `--push-url` | `""` | Middleware URL — encrypted inside the `p` blob (unlike the old format where it was a plain-text query parameter) |
| `--push-secret` | `""` | Webhook secret (encrypted in payload) |
| `--qr` | off | If set, also saves a QR code PNG (`benem-link.png`) alongside URL output |
| `-i` / `--interactive` | off | Interactive mode: prompts for each field with current default shown; Enter accepts default |

**`--interactive` mode flow:**
```
BHNM Server URL []: https://bhnm.example.com
API Token []: ****
PIN / License ID (leave blank for none) []:
User Name [enter user name]: thomas
Server Name [bhnm.example.com]: Production BHNM
SF Symbol [server.rack]: building.2
Accent colour hex [#0A84FF]: #FF9F0A
Enable push notifications? [y/N]: y
  Middleware URL []: https://bhnm-apns.hurrikap.org
  Webhook Secret []: ****
Generate QR code? [y/N]: y

benem://configure?p=<blob>
QR code saved to benem-link.png
```

**Old `--name` alias** is preserved so existing scripts keep working.

**QR code generation** uses the `qrcode` Python package (optional dependency; script prints install hint if absent).

---

## 4. Migration & Backwards Compatibility

| Concern | Handling |
|---|---|
| Existing `SavedConnection` JSON in UserDefaults missing `symbol`/`accentColor`/`pushMiddlewareURL` | Swift `Codable` decodes missing keys to field defaults — no migration needed |
| Global `push_middleware_url` AppStorage key | Migrated to active connection's `pushMiddlewareURL` on first launch; global key cleared |
| Old `benem://configure?server=...&api_key=...` links | Handled by existing code path in `DeepLinkHandler`; no removal. `PendingImport.symbol`, `accentColor`, and `pushMiddlewareURL` remain at their defaults — no attempt is made to read those fields from old-format links. |
| Old `--name` flag in Python script | Aliased to `--server-name`; both accepted |

---

## 5. Out of Scope

- Universal Links / Associated Domains (no server infrastructure change required)
- External URL shortener integration
- Sharing the deep link via share sheet from within the app (future)
- Auto-discovery integration into the add-server flow (remains a separate Settings section)
