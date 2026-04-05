# SF Symbol Picker — Design Spec
**Date:** 2026-03-31
**Status:** Approved

---

## Goal

Replace the plain `<datalist>` input in `benem-admin/templates/generate.html` with a visual, interactive icon + colour picker that matches the BeNeM iOS app's "Customise Icon" screen.

---

## Scope

- **20 fixed SF Symbol icons** (same set as shown in the iOS app, no user-extensible list)
- **10 colour swatches** (same set as current; remove the free-form `<input type="color">` custom picker)
- **3 sections**: Preview, Icon grid, Colour swatches — in that order
- No search, no modal, no scrolling — all 20 icons visible at once, inline in the form

---

## Layout

Mirrors the iOS "Customise Icon" sheet:

```
┌─────────────────────────────────┐
│ Preview                         │
│         [icon in colour]        │
├─────────────────────────────────┤
│ Icon                            │
│  [■][■][■][■][■]               │
│  [■][■][■][■][■]               │
│  [■][■][■][■][■]               │
│  [■][■][■][■][■]               │
├─────────────────────────────────┤
│ Colour                          │
│  [●][●][●][●][●]               │
│  [●][●][●][●][●]               │
└─────────────────────────────────┘
```

- **Preview**: rounded square (like an iOS app icon) centred in a panel; background = accent colour; icon = white SVG
- **Icon grid**: 5 columns × 4 rows; selected cell has accent-coloured background + white icon; others show grey icon on dark background
- **Colour grid**: 5 columns × 2 rows of circles; selected has white border ring

---

## The 20 Symbols

| Name | Description |
|---|---|
| server.rack | Server rack (default) |
| globe | Globe with latitude lines |
| antenna.radiowaves.left.and.right | Antenna with signal waves |
| wifi | Wi-Fi signal arcs |
| globe.europe.africa | Globe — Europe/Africa view |
| cloud | Cloud shape |
| lock.shield | Shield with padlock |
| building.2 | Office building |
| cpu | CPU chip with pins |
| network | Tree/hub network topology |
| desktopcomputer | Desktop monitor |
| laptop | Laptop computer |
| iphone | iPhone outline |
| shield | Plain shield |
| bolt | Lightning bolt |
| chart.bar | Bar chart |
| checkmark.seal | Seal with checkmark |
| folder | Folder |
| gearshape | Gear / settings |
| house | House |

---

## The 10 Colours

Same as current swatches, in the same order:

`#0A84FF` · `#30D158` · `#FF9F0A` · `#FF453A` · `#64D2FF`
`#BF5AF2` · `#FF6961` · `#6E6ADB` · `#5AC8FA` · `#FFD60A`

---

## Icon Rendering

SVG paths are embedded directly in the HTML template using `<svg><defs><symbol>` declarations. Each icon is referenced via `<use href="#s-{name}">`. No external font, no image files, no JS library.

This approach:
- Works in all browsers
- Requires no server-side changes
- Keeps the template self-contained

---

## Interaction

- Clicking an icon cell: removes `.selected` from all cells, adds it to clicked cell, updates preview `<use href>` to point to new symbol
- Clicking a colour dot: removes `.selected` from all dots, adds it to clicked dot, updates preview background colour and selected icon-cell background
- Both selections write into hidden `<input type="hidden">` fields (`name="symbol"` and `name="color"`) so the existing form POST and backend remain unchanged

---

## Files Changed

| File | Change |
|---|---|
| `benem-admin/templates/generate.html` | Replace `<datalist>` input and swatch section with new picker UI |
| `benem-admin/sf_symbols.py` | No change — the 20 icons are hardcoded in the template; backend accepts any symbol name |
| `benem-admin/main.py` | No change needed — form fields keep same names |

---

## What Does NOT Change

- Form field names (`symbol`, `color`) — backend reads these unchanged
- Default values (`server.rack`, `#0A84FF`)
- All other form fields (Server, BHNM URL, Push Middleware URL, Username)
- The result / QR code section below the form
- Backend routes, encryption, APNs delivery

---

## Edge Cases

- The initial page load pre-selects the symbol and colour from `form_data` (re-render after POST error) or falls back to defaults. JS sets `.selected` on page load based on a data attribute.
- The free-form `<input type="color">` is removed; only the 10 fixed swatches remain (matching the iOS app which also has no free-form picker).
