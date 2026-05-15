# iOS Alignment: Reliable Server Name + PWA-Style Refresh Ring

**Date:** 2026-05-12
**Platform:** iOS (`ios/`)
**Status:** Approved design — ready for implementation plan

## Motivation

The PWA shows the active BHNM server name in the header of all four main
screens (Home, Incidents, Devices, Settings) and renders a 40 px refresh ring
with an inline M:SS countdown. The iOS app should match this.

Investigation against the current iOS source (not the changelog) found:

- **Server name:** all four iOS toolbars already render
  `logo + title + activeServerName` (e.g. `DashboardView.swift:71-87`). The
  subtitle is hidden because the AppStorage key it reads,
  `netreo_active_connection_name`, is only written when
  `activeConnectionID` resolves to a saved connection. On legacy /
  single-server / migrated / QR-imported-not-activated configs it does not
  resolve, so `ContentView.swift:132` clears the key and nothing rewrites it
  → the subtitle is blank on every screen. Confirmed by the user: blank
  everywhere.
- **Refresh ring:** `AutoRefreshButton` already has an M:SS countdown and a
  counter-clockwise drain, but it is 32 px and uses system grays + accent
  color. The PWA `RefreshRing` is 40 px with a cleaner ring + centered
  countdown.

These are therefore a **bug fix** and a **visual restyle**, not new features.

## Part 1 — Reliable active server name (Approach B: centralized resolver)

### Root cause

`netreo_active_connection_name` is written in only two places, both of which
require `activeConnectionID` to match a saved connection:

- `ContentView.swift:132-135` (`handleConnectionChange`): clears the key, then
  writes the name only if the new `activeConnectionID` resolves.
- `ContentView.swift:182-185` (`updateAPIService`, called on startup/onAppear):
  writes the name only if a saved connection matches `activeConnectionID`.

When `activeConnectionID` is empty or stale, the key stays cleared and the
`if !activeServerName.isEmpty` guard in all four toolbars hides the subtitle.

### Design

Introduce one resolver that produces the best display name from the available
state, with a deterministic fallback chain. Both write sites call it. The four
views are **not** touched — they keep reading
`@AppStorage("netreo_active_connection_name")`.

```swift
// New free function (or UserDefaults extension), e.g. in ContentView.swift
// or a small Models/ActiveServerName.swift
func resolveActiveServerName(
    connections: [SavedConnection],
    activeConnectionID: String,
    middlewareURL: String,   // netreo_base_url
    bhnmURL: String,         // netreo_bhnm_url
    apiKey: String           // netreo_api_key
) -> String
```

Fallback chain (first non-empty wins):

1. `connections.first { $0.id.uuidString == activeConnectionID }?.name`
2. `connections.first { $0.apiKey == apiKey && $0.middlewareURL == middlewareURL }?.name`
   — matches the active running config to a saved connection when the active
   ID was never set (legacy / migrated configs)
3. If `connections.count == 1` → `connections[0].name`
4. Host component of `bhnmURL` via `URLComponents` (e.g. `bhnm.example.com`)
5. Host component of `middlewareURL`
6. `"BeNeM"` (guaranteed non-empty final fallback)

Note: `SavedConnection.apiKey` is Keychain-backed and may be empty in the
decoded struct unless `.load()` was applied, so step 2 is best-effort.
Steps 3–6 guarantee a non-empty result regardless, so the subtitle is never
blank for a working config.

### Write-site changes

- **`updateAPIService()`** (`ContentView.swift`): this path already early-returns
  when `baseURL`/`apiKey` are empty, so it is only reached with a working
  config. Replace the `if let active = connections.first(where:)` block with a
  call to `resolveActiveServerName(...)` and always write the (non-empty) result
  to `netreo_active_connection_name`.
- **`handleConnectionChange`** (`ContentView.swift`): when the new state has a
  working config (new ID resolves, or `baseURL`/`apiKey` are still non-empty),
  write the resolved name instead of relying solely on ID match. Only
  `removeObject` the key when there is genuinely **no** active config (active
  connection deleted and nothing configured) — preserving today's correct
  "disconnected → no subtitle" behavior.

### Behavior after fix

- Any working configuration (named, legacy single-server, migrated, or
  QR-imported) shows a server name on all four screens, on cold launch and
  after switching.
- A truly unconfigured app (navigates to Settings) still shows no subtitle.

### Out of scope

- No changes to the four toolbar views or their layout.
- No rename of the legacy `netreo_*` AppStorage keys.
- No migration of stored connection data.

## Part 2 — Refresh ring restyle (PWA shape, iOS-adaptive colors)

Single-file change to `ios/BeNeM/Views/AutoRefreshButton.swift`. Every screen
that uses `AutoRefreshButton` (Home, Incidents, Devices) picks it up
automatically. Settings has no auto-refresh and is unaffected — consistent with
the PWA hiding the ring on Settings.

### Changes

| Aspect | Current | Target |
|---|---|---|
| Size | `frame(width: 32, height: 32)` | `frame(width: 40, height: 40)` |
| Track | `Color(.systemGray4)`, lineWidth 2 | `Color(.systemGray4)`, lineWidth 2 (kept — adaptive) |
| Progress arc | `Color.accentColor`, lineWidth 2, round cap, rot −90, `.linear(1s)` | unchanged (already matches PWA shape & counter-clockwise drain) |
| Countdown font | `size 9, bold, monospaced`, `Color(.systemGray3)` | `size 9, bold, monospaced`, `Color.secondary` (adaptive) + `.kerning(-0.3)` to approximate PWA `letter-spacing: -0.03em` |
| Loading state | `ProgressView().scaleEffect(0.7)` | `ProgressView().scaleEffect(0.8)` (slightly larger for the 40 px frame) |

Net effect: same visual language as the PWA ring (larger, crisp thin ring,
centered tight monospace countdown) while colors adapt to iOS light/dark mode
and use the app accent — per the user's explicit choice ("PWA shape, but iOS
adaptive colours").

### Out of scope

- The PWA's spinning partial-arc loading indicator (keep iOS `ProgressView`).
- Any change to refresh interval, tap-to-refresh behavior, or the
  `ConnectionBadgeButton` / `ChainIcon`.

## Risks & verification

- **Low blast radius.** Part 1 touches only `ContentView.swift` (+ optionally
  one new small file); Part 2 touches only `AutoRefreshButton.swift`.
- **Verify Part 1** by launching the app on (a) a single legacy/migrated
  config and (b) a multi-server config: server name must appear on all four
  screens on cold launch and after a server switch; unconfigured app shows no
  subtitle.
- **Verify Part 2** visually in iOS light and dark mode: 40 px ring, centered
  M:SS countdown, drains counter-clockwise over the interval; tap refreshes.
- `xcodebuild` is the source of truth for compilation (SourceKit reports
  false positives in this project — per `ios/CLAUDE.md`).

## Feature spec impact

`shared/feature-spec.md` already documents the unified header and RefreshRing
under **Navigation (Tab Bar)** as `shipped-pwa`/`shipped-ios`. After
implementation, add an iOS-specific note that the active server name is
resolved with a fallback chain (not solely by `activeConnectionID`) and that
the iOS ring uses adaptive colors with PWA proportions.
