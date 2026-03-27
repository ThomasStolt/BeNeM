# Settings — "Add Server" Button in BHNM Servers Section

**Date:** 2026-03-27
**Status:** Approved

---

## Goal

Add a persistent "Add Server" row at the bottom of the BHNM Servers section in `SettingsView`, so users can add a new connection without reaching for the navigation bar `+` button.

---

## Current Behaviour

- When `savedConnections` is **empty**: the section shows a single "Add BHNM Server" `Button` (blue, with a `plus.circle.fill` icon) and nothing else.
- When `savedConnections` is **non-empty**: the section shows only the server rows. There is no in-section affordance to add a server; the only entry point is the `+` in the navigation bar toolbar.

---

## New Behaviour

The `if savedConnections.isEmpty { ... } else { ... }` branch is replaced with a unified layout:

1. **Server rows** — `ForEach(savedConnections)` rendered as before (active row green-subtitled, tap-to-switch confirmation, swipe-to-edit). When the list is empty this block renders nothing.
2. **"Add Server" row** — always present at the bottom of the section. Tapping navigates to `ServerConfigView(existingConnection: nil)`, identical to the toolbar `+`.

The toolbar `+` button is retained.

---

## UI Spec

### "Add BHNM Server" row

```
[ ⊕ ]  Add BHNM Server
```

- Label text: **"Add BHNM Server"** (unchanged from current empty-state label)
- System image: `plus.circle.fill`
- Foreground colour: `.accentColor` (iOS blue)
- Font: `.body` (default list row size)
- Tap action: `navigateToAdd = true` (existing `@State` bool that drives `.navigationDestination(isPresented: $navigateToAdd)`)
- No swipe actions, no disclosure chevron

### Section layout (servers present)

```
┌─ BHNM Servers ──────────────────────────┐
│  🖥  Production                          │
│     Active · bhnm-apns.example.com  🟢   │
├──────────────────────────────────────────┤
│  🖥  Staging                             │
│     staging.example.com                  │
├──────────────────────────────────────────┤
│  ⊕  Add BHNM Server          (blue)     │
└──────────────────────────────────────────┘
```

### Section layout (no servers)

```
┌─ BHNM Servers ──────────────────────────┐
│  ⊕  Add BHNM Server          (blue)     │
└──────────────────────────────────────────┘
```

---

## File Changed

| File | Change |
|---|---|
| `BeNeM/Views/SettingsView.swift` | Replace `if isEmpty / else` branch with `ForEach` + unconditional Add row |

No other files are affected.

---

## Out of Scope

- Reordering servers
- Any change to the confirmation dialog, swipe-to-edit, or active server styling
