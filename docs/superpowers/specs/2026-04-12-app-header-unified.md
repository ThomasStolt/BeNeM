# Spec: Unified App Header with Countdown RefreshRing

**Date:** 2026-04-12  
**Status:** approved  
**Scope:** `pwa/src/components/` + all four main screens

---

## Summary

Two related improvements shipped together:

1. **`RefreshRing` countdown** — the circular refresh ring on the Dashboard grows from 28 px to 40 px and displays the remaining seconds until the next auto-refresh as a `M:SS` countdown centred inside the ring.
2. **Unified `AppHeader`** — a new shared header component replaces the four bespoke `<header>` blocks across Home, Incidents, Devices, and Settings, giving every screen the same layout: connection badge · B-icon + title + server name · refresh ring (or spacer).

---

## 1. `RefreshRing` Update

**File:** `src/components/RefreshRing.tsx`

### Changes

- `size` constant changes from `28` to `40`. All geometry (radius, stroke width, circumference, dashoffset) is derived from `size`, so scaling is automatic.
- A countdown label is rendered centred inside the SVG:
  - `remaining = Math.max(0, intervalMs - elapsed)` (milliseconds)
  - Format: `${Math.floor(remaining / 60_000)}:${String(Math.floor((remaining % 60_000) / 1_000)).padStart(2, '0')}` → e.g. `2:00`, `1:18`, `0:09`, `0:00`
  - Colour: `#64748b` (slate-500), `font-size: 9px`, `font-weight: 700`
  - Hidden while `isLoading` (spinning arc replaces the ring; no countdown shown during a live fetch)
- No prop changes — same interface as today.

### Implementation note

Use a `<text>` SVG element (or an absolutely-positioned `<span>`) centred at `size/2, size/2`. SVG `<text>` with `text-anchor="middle"` and `dominant-baseline="central"` is the cleanest approach and avoids the stacking context issues of absolute positioning inside a `<button>`.

---

## 2. `AppHeader` Component

**File:** `src/components/AppHeader.tsx` (new)

### Props

```ts
interface AppHeaderProps {
  title: string;
  isLoading?: boolean;    // drives connection badge + ring loading state
  isError?: boolean;      // drives connection badge disconnected state
  dataUpdatedAt?: number; // if > 0, shows RefreshRing; omit for Settings
  intervalMs?: number;    // refresh interval in ms, defaults to 120_000
  onRefresh?: () => void; // called when ring is tapped; omit for Settings
}
```

### Layout

```
[ ConnectionBadge ]  [ B · Title · ServerName ]  [ RefreshRing | spacer ]
     left                    center                      right
```

- **Left:** `<ConnectionBadge status={derivedStatus} onRetry={onRefresh} />`
- **Center:** blue "B" badge (20 × 20 px, sky-600 rounded) + bold title + `config.serverName` in slate-500 below (omitted when blank)
- **Right:** `<RefreshRing … />` when `dataUpdatedAt > 0`; otherwise `<div className="w-10" />` spacer (40 px wide to balance the layout)

### Connection status derivation

Computed inline from props — no local state required:

```ts
const derivedStatus: ConnectionStatus =
  !config.isConfigured  ? 'disconnected' :
  isLoading             ? 'checking'     :
  isError               ? 'disconnected' :
  dataUpdatedAt > 0     ? 'connected'    :
                          'unknown';
```

Settings (no `dataUpdatedAt`, no `isLoading`, configured) → `'unknown'` (neutral grey badge).  
Not configured → `'disconnected'` on any screen.

### Internal dependencies

- `useConfig()` from `src/lib/config.ts` — for `serverName` and `isConfigured`
- `ConnectionBadge` from `src/components/ConnectionBadge.tsx`
- `RefreshRing` from `src/components/RefreshRing.tsx`

---

## 3. Screen Updates

### `DashboardScreen`

**File:** `src/features/dashboard/DashboardScreen.tsx`

- Replace the inline `<header>` block with `<AppHeader title="Home" isLoading={isLoading} isError={isError} dataUpdatedAt={dataUpdatedAt} onRefresh={handleRefresh} />`
- Remove the `connectionStatus` `useState` and `derivedStatus` inline logic (now inside `AppHeader`).
- `dataUpdatedAt` is already destructured from `useTacticalSummary()`.

### `IncidentListScreen`

**File:** `src/features/incidents/IncidentListScreen.tsx`

- Add `dataUpdatedAt` to the destructured result of `useIncidents()`.
- Replace `<header>` + plain Refresh `<button>` with `<AppHeader title="Incidents" isLoading={isLoading} isError={isError} dataUpdatedAt={dataUpdatedAt} onRefresh={onRefresh} />`.

### `DeviceListScreen`

**File:** `src/features/devices/DeviceListScreen.tsx`

- Replace `<header>` + `<RefreshCountdown>` with `<AppHeader title="Devices" isLoading={isLoading} isError={isError} dataUpdatedAt={dataUpdatedAt} onRefresh={handleRefresh} />`.
- Remove `RefreshCountdown` import.

### `SettingsScreen`

**File:** `src/features/settings/SettingsScreen.tsx`

- Replace the centered `<header>` with `<AppHeader title="Settings" />`.
- No `dataUpdatedAt`, no `onRefresh` — ring is hidden, spacer shown.

---

## 4. Files Affected

| File | Action |
|---|---|
| `src/components/RefreshRing.tsx` | Modify — resize to 40 px, add countdown SVG text |
| `src/components/__tests__/RefreshRing.test.tsx` | Modify — update size assertions, add countdown test |
| `src/components/AppHeader.tsx` | Create — unified header component |
| `src/components/__tests__/AppHeader.test.tsx` | Create — tests for all connection status states and ring visibility |
| `src/features/dashboard/DashboardScreen.tsx` | Modify — use AppHeader, remove inline connection state |
| `src/features/incidents/IncidentListScreen.tsx` | Modify — use AppHeader, add dataUpdatedAt |
| `src/features/devices/DeviceListScreen.tsx` | Modify — use AppHeader, remove RefreshCountdown import |
| `src/features/settings/SettingsScreen.tsx` | Modify — use AppHeader |

---

## 5. Out of Scope

- No changes to `RefreshCountdown` (used on Tactical screens — outside this spec).
- No changes to screen-specific data fetching logic.
- No changes to `ConnectionBadge` internals.
