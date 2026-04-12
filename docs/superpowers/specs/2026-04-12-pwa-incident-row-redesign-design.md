# PWA Incident Row Redesign

**Date:** 2026-04-12
**Status:** Approved

## Goal

Bring the PWA incident list row to iOS parity: two-row layout with incident ID, scrolling title, status badge, scrolling device name, compact duration, and 5-colour alarm dots. Continuous-loop overflow-only marquee replaces text truncation.

---

## Components

### 1. `OverflowMarquee` (`src/components/OverflowMarquee.tsx`)

A generic, reusable scroll component. Accepts:

| Prop | Type | Default |
|---|---|---|
| `text` | `string` | required |
| `className` | `string?` | — |
| `speed` | `number` (px/s) | `40` |

**Behaviour:**
- Mounts with a `ResizeObserver` on the clip container.
- Compares `scrollWidth` vs `clientWidth` of a hidden measurement span.
- **No overflow** → renders static text, no animation.
- **Overflow detected** → renders two copies of the text side-by-side (separated by a `48 px` gap), animates `translateX` from `0` to `−50%` at `linear infinite`. Duration = `(textWidth + gap) / speed` seconds.
- Re-evaluates on every `ResizeObserver` callback (handles font load, window resize, container reflow).
- Edge fade: `mask-image: linear-gradient(to right, transparent 0%, black 4%, black 96%, transparent 100%)` on the clip container.
- `prefers-reduced-motion`: animation disabled; text clips silently.

### 2. `StatusBadge` (`src/features/incidents/StatusBadge.tsx`)

Replaces `SeverityBadge` on the incident row. Maps incident state to a pill:

| Condition | Label | Colour |
|---|---|---|
| `status === 'active'` | `OPEN` | red (`#dc2626`) |
| `status === 'acknowledged'` | `ACKD` | blue (`#2563eb`) |
| `status === 'resolved'` or `'closed'`, or `incidentState === 'ALARMS CLEARED'` | `CLRD` | green (`#16a34a`) |

White text, `border-radius: 4px`, `font-size: 10px`, `font-weight: 700`.

---

## `IncidentRow` redesign (`src/features/incidents/IncidentRow.tsx`)

### Layout

```
┌──────────────────────────────────────────────────────┐
│ #24327   [scrolling incident title ................] │  ← row 1
│ [OPEN]  [scrolling device name ....]  3h  R O Y G B │  ← row 2
└──────────────────────────────────────────────────────┘
```

**Row 1** — `display: flex`, `align-items: baseline`, `gap: 8px`
- `#ID` — `font-size: 12px`, `font-weight: 600`, `color: slate-500`, fixed width (`flex-shrink: 0`)
- `OverflowMarquee` for `incident.summary` — `font-size: 13px`, `font-weight: 600`, `color: slate-100`

**Row 2** — `display: flex`, `align-items: center`, `gap: 7px`
- `StatusBadge`
- `OverflowMarquee` for `incident.deviceName ?? incident.deviceIp ?? 'Unknown'` — `font-size: 11px`, `color: slate-400`
- Compact duration (e.g. `3h`, `2d`, `now`) — `font-size: 11px`, `color: slate-500`, `flex-shrink: 0`
- `AlarmBadges` — unchanged component, `flex-shrink: 0`

### Duration format

`formatDuration(startTime: Date): string` — strips the `" ago"` suffix used in the current `relativeTime()` helper:

| Elapsed | Output |
|---|---|
| < 1 min | `now` |
| < 60 min | `15m` |
| < 24 h | `3h` |
| ≥ 24 h | `2d` |

### Removed
- `SeverityBadge` no longer rendered on the row.
- `✓` ACK prefix — replaced by the `ACKD` status badge.

---

## Scope

- **New file:** `src/components/OverflowMarquee.tsx` + matching test
- **New file:** `src/features/incidents/StatusBadge.tsx` + matching test
- **Modified:** `src/features/incidents/IncidentRow.tsx` — full rewrite of layout
- **Unchanged:** `SwipeableIncidentRow.tsx`, `IncidentListScreen.tsx`, `IncidentDetailScreen.tsx`, `AlarmBadges.tsx`, `useIncidents.ts`, all API/hook files

---

## Out of scope

- Filter badges (Critical / Major / Ack quick-filters) — deferred
- Incident detail screen improvements (primary alarms, state log) — separate spec
- `DeviceRow` refactor to reuse `OverflowMarquee` — separate task
