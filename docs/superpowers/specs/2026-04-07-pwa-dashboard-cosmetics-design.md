# PWA Dashboard — iOS Cosmetics Parity Design

**Date:** 2026-04-07
**Status:** Approved
**Approach:** Incremental refactor of existing components (Approach A)

## Goal

Restyle the PWA dashboard to match the iOS app's visual design. Purely cosmetic — no data flow or API changes.

## Layout Order (top to bottom)

1. **Header** — connection badge (left), centered logo + "Home" + server name, circular refresh ring (right)
2. **Summary Cards** — Active Incidents (red/green) + Total Devices (blue), side by side
3. **Incident Ticker** — multi-line step-through card with page dots
4. **Heat Map 2x2** — Hosts / Services / Thresholds / Anomalies
5. **Drill Down** — Categories / Sites / Business Workflows with icons + chevrons

## Section 1: Header

**Current:** Left-aligned "Dashboard" + server name, text countdown + Settings link.

**New:**
- **Left:** `ConnectionBadge` — chain-link icon (two overlapping rounded rectangles rotated 45 degrees, matching iOS `ChainIcon`). Colors: green (connected), red (disconnected, broken + blinking), orange (checking, blinking), grey (unknown). Blinks at 700ms intervals when disconnected or checking. Tappable to trigger manual refresh.
- **Center:** BeNeM logo icon (blue rounded square with "B") + "Home" title (18px bold). Server name as subtitle below (small, muted).
- **Right:** `RefreshRing` — circular SVG countdown ring that depletes over 120 seconds. Shows spinner when loading. Tappable for immediate refresh. Matches iOS `AutoRefreshButton`.
- **No Settings link** in header — accessible via tab bar.

## Section 2: Summary Cards Row

New `SummaryCards` component — two side-by-side cards matching iOS `StatusCard`:

**Active Incidents card:**
- Warning triangle icon + count (24px bold)
- Color: red when count > 0, green when 0
- Border (1.5px) + box shadow tinted with the color
- Background: page background (`slate-950`)
- Corner radius: 14px
- Tappable — navigates to Incidents tab

**Total Devices card:**
- Network icon + count (24px bold)
- Color: always blue
- Same border/shadow/radius treatment
- Non-tappable

Device count: sum of all host counts from `useTacticalSummary()`.
Incident count: active incidents from `useIncidents()`.

## Section 3: Incident Ticker

Rewrite `IncidentTicker.tsx` — replace continuous horizontal scroll with iOS-style step-through:

**Layout (multi-line card):**
- Line 1: Severity badge (CRIT/MAJOR, colored pill) + Incident ID (muted) + page dots (right-aligned)
- Line 2: Incident summary text (13px, white)
- Line 3: Device name (muted) + alarm count badges (colored pills per severity)

**Behavior:**
- Shows one incident at a time
- Auto-advances every 4 seconds
- Slide + fade CSS transition between incidents
- Page dots show current position (active = sky blue, inactive = slate)
- Only critical and major incidents (same filter as current)
- "No critical or major incidents" message when empty

**Card styling:**
- Background: `slate-800`
- Border: 0.5px `slate-700`
- Corner radius: 12px
- Padding: 12px 14px

## Section 4: Heat Map 2x2

Restyle existing `StatusCard` component to match iOS `statBox`:

**Layout per card:**
- Title: centered, uppercase, bold, 11px, muted color (`slate-400`), letter-spacing 0.5px
- Count: centered, 21px, semibold
- Badge row: 5 equal-width pills
  - Non-zero: solid color background (green/blue/yellow/orange/red), white text (black on yellow), 9px font, semibold, rounded 8px
  - Zero: grey text (`slate-600`), no background, subtle border outline (0.5px `slate-700`), rounded 8px

**Card styling:**
- Background: `slate-800` (lighter than page)
- Border: 0.5px `slate-700`
- Corner radius: 13px
- Padding: 13px vertical, 10px horizontal

**Grid:** 2 columns, 8px gap.

Props and data unchanged — visual-only refactor.

## Section 5: Drill Down Links

Replace 3-column text grid with full-width stacked rows matching iOS `tacticalRow`:

**Each row:**
- Colored icon left (Categories = purple, Sites = blue, Business Workflows = green)
- Title: 15px semibold, white
- Chevron arrow right, muted
- Background: `slate-800`, corner radius 10px, border 0.5px `slate-700`
- Padding: 14px

**Section heading:** "Drill Down" — 16px semibold, left-aligned, 12px margin below.

**Stack:** Vertical, 10px gap.

Navigation links unchanged: `/tactical/category`, `/tactical/site`, `/tactical/bw`.

## Files Changed

| File | Action | Change |
|---|---|---|
| `pwa/src/features/dashboard/DashboardScreen.tsx` | Modify | New layout order, new header with connection badge + refresh ring, integrate SummaryCards |
| `pwa/src/features/dashboard/StatusCard.tsx` | Modify | Restyle to iOS statBox (centered title/count, solid badge pills, lighter background) |
| `pwa/src/features/dashboard/IncidentTicker.tsx` | Rewrite | Step-through with page dots, multi-line card, slide+fade transition, 4s auto-advance |
| `pwa/src/features/dashboard/SummaryCards.tsx` | Create | Active Incidents + Total Devices row |
| `pwa/src/components/ConnectionBadge.tsx` | Create | Chain-link SVG icon, color states, blink animation, tappable |
| `pwa/src/components/RefreshRing.tsx` | Create | Circular SVG countdown ring, spinner when loading, tappable |
| `pwa/src/components/RefreshCountdown.tsx` | Keep | Still used by other screens; dashboard switches to RefreshRing |

**No data flow changes.** All existing hooks and API calls unchanged.
