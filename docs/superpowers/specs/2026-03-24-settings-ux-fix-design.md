# Settings UX Fix — Design Spec

**Date:** 2026-03-24
**Status:** Approved

## Problem Summary

Three bugs affect the Settings screen:

1. **Navigation regression on URL clear** — Clearing the URL field causes the user to be kicked out of Settings and back to the Welcome screen.
2. **Mid-edit navigation to Dashboard** — Because Settings fields bind directly to `@AppStorage`, every keystroke triggers `updateAPIService()` in `ContentView`. When both URL and API key become non-empty, SwiftUI's `TabView` restructures (2→4 items) and resets to tab 0 (Dashboard).
3. **Test Connection doesn't validate API key** — `testConnection()` in `SettingsView` hits `/api.php` (legacy) or a versioned devices endpoint that is not what the app actually uses. It verifies reachability only, not credential validity.

A fourth minor inconsistency: `QuickConfigView` exposes the API key as plain text in a `TextField`.

---

## Design

### 1. SettingsView — Deferred Save with Explicit "Save" Button

**Local draft state:**
`SettingsView` introduces `@State` draft variables mirroring each `@AppStorage` key:

| Draft var | AppStorage key |
|---|---|
| `draftBaseURL` | `netreo_base_url` |
| `draftApiKey` | `netreo_api_key` |
| `draftPin` | `netreo_pin` |
| `draftAckUser` | `netreo_ack_user` |

All form fields bind to draft vars. On `onAppear`, drafts are initialised from AppStorage.

**Save button:**
A computed `hasUnsavedChanges` compares each draft to its AppStorage counterpart. When true, a "Save" button appears in the navigation toolbar. Tapping Save writes all drafts to AppStorage in one pass, which is the sole trigger for `updateAPIService()` in `ContentView`. No mid-edit reconnects, no tab jumps.

**Sliders and pickers** (timeout, retry count, refresh interval, API version) continue to bind directly to `@AppStorage` — they do not affect tab navigation and do not need deferral.

### 2. ContentView — Navigation Guard

A single targeted change: the `onChange(of: apiService == nil)` handler that sets `selectedTab = 0` is guarded to only fire when `selectedTab != 3`. Clearing credentials while on Settings leaves the user on Settings.

No other changes to `ContentView` or `updateAPIService()`.

### 3. SettingsView — Test Connection Uses Actual API

`testConnection()` is replaced. It instantiates a temporary `NetreoAPIService` using the **draft** credentials (so the user can test before saving) and calls `fetchDevices()` — the same endpoint the app uses at runtime (`/fw/index.php?r=restful/devices/list`). This validates both reachability and API key in one call.

Result messages:
- **Success:** "Connection successful — found N devices."
- **Auth failure (0 devices or HTTP 401/403):** "Authentication failed — check your API key and PIN."
- **Host not found / timeout / SSL:** existing descriptive error messages.

### 4. QuickConfigView — SecureField for API Key

The `TextField` for "API Key" in `QuickConfigView` is changed to `SecureField` to match `SettingsView` and avoid exposing the key on the Welcome screen.

---

## Files Changed

| File | Change |
|---|---|
| `BeNeM/Views/SettingsView.swift` | Draft state, Save button, new `testConnection()` |
| `BeNeM/ContentView.swift` | Navigation guard in `onChange(of: apiService == nil)` |
| `BeNeM/Views/QuickConfigView.swift` | `TextField` → `SecureField` for API key |

---

## Out of Scope

- Redesign of the Settings screen layout
- Validation feedback inline (e.g. red border on invalid URL) — not requested
- Persisting draft state across app restarts — not needed; AppStorage is the source of truth
