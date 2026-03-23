# Settings UX Fix — Design Spec

**Date:** 2026-03-24
**Status:** Approved

## Problem Summary

Three bugs affect the Settings screen:

1. **Navigation regression on URL clear** — Clearing the URL field causes the user to be kicked out of Settings and back to the Welcome screen. Root cause: `ContentView`'s `onChange(of: apiService == nil)` unconditionally sets `selectedTab = 0`, even when the user is on the Settings tab. Fix requires **both** §1 (deferred save prevents mid-edit triggers) and §2 (navigation guard for the case when credentials are intentionally cleared and saved).

2. **Mid-edit navigation to Dashboard (Settings only)** — Settings fields bind directly to `@AppStorage`. Every keystroke calls `updateAPIService()` in `ContentView`. When both URL and API key become non-empty mid-typing, SwiftUI's `TabView` restructures (from 2 to 4 items) and resets to tab 0 (Dashboard). Note: `QuickConfigView` (Welcome screen) also writes directly to AppStorage — this is intentional, since being taken to the Dashboard after entering credentials on the Welcome screen is the desired flow.

3. **Test Connection hits wrong endpoint** — `testConnection()` in `SettingsView` constructs endpoints based on the API version picker (`/api.php` for legacy, `/api/v1/devices`, etc.). These endpoints are not what the app uses at runtime. The app exclusively calls `/fw/index.php?r=restful/devices/list` regardless of the version picker. `QuickConfigView.testConnection()` already uses the correct path via `NetreoAPIService.fetchDevices()` — that function is in scope only to note it does not need changes.

A fourth minor inconsistency: `QuickConfigView` exposes API key and PIN as plain text `TextField`s.

---

## Design

### 1. SettingsView — Deferred Save with Explicit "Save" Button

**Local draft state:**
`SettingsView` introduces `@State` draft variables for the four text fields:

| Draft var | AppStorage key |
|---|---|
| `draftBaseURL` | `netreo_base_url` |
| `draftApiKey` | `netreo_api_key` |
| `draftPin` | `netreo_pin` |
| `draftAckUser` | `netreo_ack_user` |

`draftAckUser` is included for UX consistency (uniform behaviour across all text fields), not to prevent reconnects — `netreo_ack_user` has no `onChange` handler in `ContentView` and never triggered a tab jump.

`isTesting` remains a plain `@State` variable. It is not a draft field and is not included in `hasUnsavedChanges`.

All four text fields bind to their draft vars. Sliders (`refreshInterval`, `timeout`, `retryCount`) and the API version `Picker` continue to bind directly to `@AppStorage` — they do not affect tab navigation and do not need deferral. After deferred save, `ContentView`'s `onChange(of: pin)` still fires correctly when Save writes `draftPin` to `netreo_pin` in AppStorage — the handler is not redundant and must not be removed.

On `onAppear`, all four draft vars are initialised from their AppStorage counterparts. If the user navigates to `AutoDiscoveryView` (a `NavigationLink` destination within Settings) and AutoDiscovery writes a new URL to `netreo_base_url`, `onAppear` re-fires when the user returns — this re-initialises `draftBaseURL` from AppStorage, picking up the discovery result. Any unsaved draft edits made before navigating to AutoDiscovery are silently discarded at that point. This is acceptable UX.

**Save button:**
A computed `hasUnsavedChanges` compares the four draft vars to their AppStorage counterparts (slider/picker values are excluded — they are saved immediately and never pending). When `hasUnsavedChanges` is true, a "Save" button appears in the navigation toolbar. Tapping Save writes all four drafts to AppStorage in one synchronous pass. This is the sole moment that `updateAPIService()` is triggered for URL/key/pin changes — no mid-edit reconnects, no tab jumps.

**Discard behaviour:** Navigating away from Settings without tapping Save silently discards draft edits. On next visit, `onAppear` re-initialises drafts from AppStorage. No discard confirmation dialog is shown.

**Round-trip safety after Save:** If the user clears the URL in Settings (navigation guard §2 keeps them on the Settings tab), re-enters credentials, and taps Save: AppStorage is updated → `updateAPIService()` fires → `apiService` becomes non-nil → `CustomTabBar` re-renders with 4 tabs (since `isConfigured: apiService != nil` becomes true) → `selectedTab` remains 3 → Settings is correctly highlighted in the 4-tab layout. No navigation occurs.

### 2. ContentView — Navigation Guard

One line change: the `onChange(of: apiService == nil)` handler is guarded to only redirect when the user is not on the Settings tab.

```swift
// Before
.onChange(of: apiService == nil) { _, isNil in
    if isNil { selectedTab = 0 }
}

// After
.onChange(of: apiService == nil) { _, isNil in
    if isNil && selectedTab != 3 { selectedTab = 0 }
}
```

All six existing `onChange` handlers (`baseURL`, `apiKey`, `pin`, `apiVersionString`, `timeout`, `retryCount`) are retained unchanged. No changes to `updateAPIService()`.

### 3. SettingsView — Test Connection Uses Actual API Endpoint

`testConnection()` is rewritten. It makes a direct HTTP call to the same endpoint the app uses at runtime:

- **URL:** `POST <draftBaseURL>/fw/index.php?r=restful/devices/list`
- **Body (form-urlencoded):** `password=<draftApiKey>` and, if non-empty, `pin=<draftPin>`
- **Credentials:** draft vars (not AppStorage) so the user can test before saving
- **Timeout:** capped at 15 s (same as current implementation)

The raw HTTP status code is read to distinguish failure modes:

| Condition | Alert message |
|---|---|
| HTTP 200, ≥1 device in response | "Connection successful — found N devices." |
| HTTP 200, 0 devices | "Connected, but no devices found. Check API key permissions." |
| HTTP 401 or 403 | "Authentication failed — check your API key and PIN." |
| HTTP 404 | "Endpoint not found — check the base URL." |
| HTTP 5xx | "Server error (HTTP N)." |
| Other HTTP | "Unexpected response (HTTP N)." |
| Network errors (host, timeout, SSL) | Existing descriptive messages retained from current implementation. The German string `"(nicht lesbar)"` in the current implementation is replaced with `"(unreadable)"`. |

To determine device count from the HTTP 200 response body, the same two-shape JSON parsing logic used by `NetreoAPIService.fetchDevices()` is applied: first check for `{"devices":[...]}` at the top level; if absent, check `{"data":{"devices":[...]}}`. The count of parsed device entries determines which 200-case message is shown.

The Test Connection button disabled predicate uses draft vars:
`.disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || isTesting)`

All internal references inside `testConnection()` use `draftBaseURL`, `draftApiKey`, and `draftPin` — not the AppStorage properties.

`QuickConfigView.testConnection()` is already correct (calls `NetreoAPIService.fetchDevices()` against the right endpoint) and is not changed.

### 4. QuickConfigView — SecureField for API Key and PIN

Two changes in `QuickConfigView.swift` only:
- "API Key" `TextField` → `SecureField`
- "PIN" `TextField` → `SecureField`

`SettingsView` already uses `SecureField` for both fields and needs no changes for this item. `QuickConfigView`'s direct `@AppStorage` bindings are retained — immediate writes are the correct behaviour on the Welcome screen.

---

## Files Changed

| File | Change |
|---|---|
| `BeNeM/Views/SettingsView.swift` | Draft state for 4 text fields; Save toolbar button; rewritten `testConnection()` using draft vars and correct endpoint |
| `BeNeM/ContentView.swift` | Navigation guard: `if isNil && selectedTab != 3` |
| `BeNeM/Views/QuickConfigView.swift` | `TextField` → `SecureField` for API key and PIN |

---

## Out of Scope

- Redesign of the Settings screen layout
- Inline validation feedback (e.g. red border on invalid URL)
- Persisting draft state across app restarts
- Deferred save in `QuickConfigView` — immediate AppStorage write is correct there
- Discard confirmation dialog — silent discard on navigate-away is acceptable
