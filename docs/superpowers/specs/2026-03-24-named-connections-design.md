# Named Connections & Stale API Service Fix

**Date:** 2026-03-24
**Status:** Approved

## Overview

Two related changes:

1. **Named connections** — users can save, switch, rename, and delete BHNM server configurations by name. A successful Test Connection is the only save path; the existing Save toolbar button is removed.
2. **Stale API service fix** — all ViewModels hold a stale `apiService` reference after a connection switch. The fix is applied to `IncidentListViewModel`, `DeviceListViewModel`, and `TacticalViewModel`, and their host views.

---

## Data Model

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String       // "" is the canonical empty value — never nil
    var ackUser: String   // "" is the canonical empty value — never nil
}
```

- Stored as a JSON array in `UserDefaults` under key `saved_connections`.
- Encoded/decoded with `JSONEncoder` / `JSONDecoder`.
- A small `UserDefaults` extension handles load/save.
- `""` (empty string) is the canonical representation of an absent PIN or ACK User throughout the entire stack — in `SavedConnection`, in `@AppStorage`, and in draft state. No nil-vs-empty ambiguity exists.

---

## SettingsView — Draft State

```swift
@State private var draftName     = "New BHNM Connection"
@State private var draftBaseURL  = ""
@State private var draftApiKey   = ""
@State private var draftPin      = ""
@State private var draftAckUser  = ""
@State private var activeSavedID: UUID? = nil   // nil = unsaved draft
@State private var savedConnections: [SavedConnection] = []
```

### On `.onAppear`

1. Load `saved_connections` from `UserDefaults` into `savedConnections`.
2. Pre-fill the five draft fields from the current `@AppStorage` values.
3. Set `activeSavedID` to the `id` of the **first** saved connection whose `baseURL`, `apiKey`, `pin`, **and** `ackUser` all exactly match the current `@AppStorage` values (string equality, all four fields). If duplicates exist (dedup is out of scope), the first match wins. If no match, `activeSavedID = nil`.
4. If `activeSavedID` is set, also fill `draftName` from that connection's `name`.

The existing **Save toolbar button is removed**. `testConnection()` is the only save path.

---

## SettingsView — UI

### "Connection" section (conditional)

Shown **only when `savedConnections.count >= 2`**. Visibility is driven reactively by the `@State var savedConnections` array — not a computed property reading `UserDefaults` — so it updates instantly when a connection is saved or deleted.

Contains a single `Menu`-backed picker row:
- Label: **"Server"**
- Value: if `activeSavedID != nil`, show the matched connection's name; otherwise show `draftName`
- Chevron indicator

The menu lists all saved connection names, then a `Divider()`, then **+ New Connection**.

> **Draft discard policy:** selecting any picker entry immediately overwrites all draft fields with no confirmation alert. Since there is no Save button, unsubmitted edits are never committed — they are intentionally discardable.

### "BHNM Server" section

| Row | Element | Notes |
|---|---|---|
| 1 | Name text field | Default `"New BHNM Connection"`; renaming takes effect on next successful test |
| 2 | Base URL field | Existing |
| 3 | API Key secure field | Existing |
| 4 | PIN secure field | Placeholder: "SaaS only" |
| 5 | ACK User field | Existing |
| — | Action row | **Test Connection** (left, flex) \| **🗑** (right, only when `activeSavedID != nil`) |

**Test Connection disable condition:**
```swift
draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || isTesting
```
`draftName` must be non-empty to prevent a nameless entry being saved or an empty alert message being shown.

---

## Behaviour

### Selecting a saved connection from the picker

1. Fill all five draft fields from the saved connection (including `draftName`).
2. Set `activeSavedID` to that connection's `id`.
3. Automatically call `testConnection()`.

### Selecting **+ New Connection**

1. Clear all five draft fields; set `draftName = "New BHNM Connection"`.
2. Set `activeSavedID = nil`.
3. Do **not** auto-test (fields are empty).

### `testConnection()` — success (HTTP 200 **and** deviceCount > 0)

1. **Upsert** into `savedConnections`:
   - If `activeSavedID` matches an existing entry → update all five fields in place.
   - Otherwise → append a new `SavedConnection` with a fresh `UUID`.
2. Persist `savedConnections` to `UserDefaults`.
3. Set `activeSavedID` to the upserted connection's `id`.
4. Write `netreo_base_url`, `netreo_api_key`, `netreo_pin`, and `netreo_ack_user` to `@AppStorage`.
   - `netreo_ack_user` is not observed by `ContentView.updateAPIService()` (it's not part of `NetreoAPIService`) — writing it has no side effect beyond persisting the value.
   - If the four keys already contain identical values (e.g. a name-only rename), `@AppStorage` onChange does **not** fire — correct, the active service already has the right credentials.
5. Show success alert: `"Connected — \(deviceCount) device(s) found. '\(draftName)' saved."`

> **"Connected — no devices found" (HTTP 200, deviceCount = 0):** does **not** upsert or write `@AppStorage`. Shows the existing warning alert only.

### `testConnection()` — failure

Show error alert as today. Dismiss → user edits fields → retry.

### Tap 🗑 (delete)

1. Show a confirmation alert: *"Delete '\(draftName)'?"* with a destructive **Delete** action and a **Cancel** action.
2. The `@AppStorage` writes happen **inside the destructive action handler** (after the user taps Delete), not before the alert is presented. This prevents the credentials being cleared — and `ContentView` navigating to `WelcomeView` — before the user confirms.
3. On confirm (inside the handler):
   - Remove from `savedConnections`, persist to `UserDefaults`.
   - Set `activeSavedID = nil`.
   - Keep draft fields populated (user can see what was deleted and re-save if desired).
   - If no remaining connections remain → clear `netreo_base_url`, `netreo_api_key`, `netreo_pin`, `netreo_ack_user` in `@AppStorage`. This sets `apiService = nil` in `ContentView` → `WelcomeView` shown. Intended.
   - If remaining connections exist → do **not** auto-switch or auto-test. The picker is still visible; the user chooses their next step.

### Edit Name field directly

Stored in `draftName`. Takes effect on next successful `testConnection()`. No immediate action.

---

## Stale API Service Fix

### Problem

`NetreoAPIService` is a class. ViewModels hold it as `private let` (or `private var` without any view calling `updateAPIService()`). When `ContentView` recreates `NetreoAPIService` after a settings change, `@StateObject` instances inside `DashboardView`, `IncidentListView`, and `DeviceListView` retain stale service references.

### ViewModels in scope

| ViewModel | Current | Fix |
|---|---|---|
| `IncidentListViewModel` | `private var` + `updateAPIService()` exists | No ViewModel change — just wire the call site |
| `DeviceListViewModel` | `private let`, no method | `let` → `var`, add `updateAPIService()` |
| `TacticalViewModel` | `private let`, no method | `let` → `var`, add `updateAPIService()` |

**`DeviceListViewModel` addition:**
```swift
func updateAPIService(_ newService: NetreoAPIService) {
    apiService = newService
    Task { await loadDevices(limit: currentLimit) }
}
```

**`TacticalViewModel` addition:**
```swift
func updateAPIService(_ newService: NetreoAPIService) {
    apiService = newService
    Task { await load() }
}
```

### Views in scope

`apiService` is a plain `let` stored property on each view struct. When `ContentView` rebuilds (because its `@State var apiService` changed), SwiftUI re-evaluates each child view's body and updates the `let` property. `.onChange(of: ObjectIdentifier(apiService))` detects the identity change and fires. `ObjectIdentifier` wraps a class instance address and is `Equatable`, making it compatible with `.onChange(of:)`.

**`IncidentListView`:**
```swift
.onChange(of: ObjectIdentifier(apiService)) { _, _ in
    viewModel.updateAPIService(apiService)
}
```

**`DeviceListView`:**
```swift
.onChange(of: ObjectIdentifier(apiService)) { _, _ in
    viewModel.updateAPIService(apiService)
}
```

**`DashboardView`** — owns three ViewModels:
```swift
.onChange(of: ObjectIdentifier(apiService)) { _, _ in
    incidentViewModel.updateAPIService(apiService)
    deviceViewModel.updateAPIService(apiService)
    categoryViewModel.updateAPIService(apiService)
}
```

### Views NOT in scope

- **`GroupListView`** — instantiated as a `NavigationLink` destination at tap-time, using `DashboardView`'s current `apiService` struct property. Gets a fresh `TacticalViewModel` with the current service on every navigation push. No fix needed.
- **`DeviceDetailViewModel`** — created fresh on each `NavigationLink` push. No fix needed.

---

## Out of Scope

- Reordering saved connections.
- Per-connection API version / timeout / retry settings (those remain global `@AppStorage`).
- iCloud sync of saved connections.
- Export / import of connection configs.
- Duplicate detection (two connections with identical credentials are allowed).
