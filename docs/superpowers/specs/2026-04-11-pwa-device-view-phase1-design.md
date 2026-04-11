# PWA Device View — Phase 1 Alignment with iOS

**Date:** 2026-04-11
**Scope:** Phase 1 of 2. Aligns the PWA device list and device detail header/sections with the iOS native app.
**Phase 2** (Server Utilization + Pinned Interfaces) is a separate spec.

---

## Goals

- Device list rows feel as information-dense as iOS: type icon, alarm badges, scrolling incident ticker.
- Device detail header matches iOS layout: icon + info + mini latency chart + alarm summary bar.
- Device type icons are visually identical across iOS and PWA.
- Canonical icon source lives in `shared/icons/` as SVG files.

---

## 1. Shared Icon Assets (`shared/icons/`)

Create SVG files that are the single design source for device type icons. iOS keeps its existing Canvas drawing (which already matches visually). The PWA consumes these SVGs directly.

### Files

| File | Icon |
|---|---|
| `shared/icons/device-linux.svg` | Tux penguin (body, belly, head, eyes, beak, feet) |
| `shared/icons/device-windows.svg` | Four-pane Windows logo |
| `shared/icons/device-router.svg` | Rounded rectangle with four-directional arrows |
| `shared/icons/device-switch.svg` | Circle background with bidirectional swap arrows |
| `shared/icons/device-unknown.svg` | Desktop computer outline |

SVGs are monochrome (`currentColor`) so consumers control color via CSS. Viewbox: `0 0 24 24`.

---

## 2. Data Layer Changes

### 2.1 Add `status` to `Device` type

The raw `restful/devices/list` API response includes a `status` field that `parseDevice()` currently ignores. Add it.

```ts
// src/lib/api/devices.ts
export type DeviceStatus = 'up' | 'down' | 'warning' | 'critical' | 'unknown' | 'maintenance';

export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
  deviceIndex: string;
  status: DeviceStatus;          // NEW — parsed from raw `status` field
}
```

`parseDevice()` maps the raw string to `DeviceStatus`; unknown values fall back to `'unknown'`.

### 2.2 Derive per-device alarm data from incidents

No new API calls. The `useIncidents()` hook already fetches all incidents. Introduce a utility:

```ts
// src/lib/deviceAlarms.ts
export interface DeviceAlarmSummary {
  counts: AlarmCounts;           // aggregated from all incidents for this device
  activeSummaries: string[];     // summary strings for active/unacknowledged incidents
}

export function buildDeviceAlarmMap(
  incidents: Incident[]
): Map<string, DeviceAlarmSummary>
```

Keyed by `deviceName`. Called once per incidents refresh; result passed down as a prop or via context to avoid re-computation in every row.

**Alarm count mapping** (incident status/severity → AlarmCounts key, per device):
- `status === 'acknowledged'` (any severity) → `blue`
- `status === 'active'` + severity `critical` → `red`
- `status === 'active'` + severity `major` or `minor` → `orange`
- `status === 'active'` + severity `warning` → `yellow`
- `status === 'resolved'` or `'closed'` → `green`

Incidents are matched to a device by `incident.deviceName === device.name`.

**Active summaries** (for ticker): incidents where `status === 'active'`, sorted severity descending (critical first), `summary` field only.

### 2.3 Device type classification

Add a pure function (no API call):

```ts
// src/lib/deviceType.ts
export type DeviceTypeClass = 'linux' | 'windows' | 'router' | 'switch' | 'unknown';

export function classifyDevice(device: Device): DeviceTypeClass
```

Classification rules mirror iOS `DeviceTypeClass`:
- `category` or `description` contains `linux` → `'linux'`
- Contains `windows` → `'windows'`
- Contains `router` → `'router'`
- Contains `switch` → `'switch'`
- Otherwise → `'unknown'`

---

## 3. `DeviceTypeIcon` Component (`pwa/src/components/DeviceTypeIcon.tsx`)

Single React component used by both `DeviceRow` and `DeviceDetailScreen`. Imports the SVGs from `shared/icons/` (via Vite's `?react` SVG import).

```tsx
<DeviceTypeIcon
  type={DeviceTypeClass}
  status={DeviceStatus}
  size={40 | 52}           // list rows use 40, detail header uses 52
/>
```

**Icon background color** by status:

| Status | Color |
|---|---|
| `up` | `#0284c7` (blue) |
| `down` | `#dc2626` (red) |
| `critical` | `#dc2626` (red) |
| `warning` | `#d97706` (amber) |
| `maintenance` | `#6b7280` (grey) |
| `unknown` | `#374151` (dark grey) |

Icon SVG is white (`currentColor: white`) inside a rounded square (`border-radius: 10px`).

---

## 4. Device List Row (`DeviceRow.tsx`)

### Layout

Three-column flex row, fixed height (no layout shift between devices with/without incidents):

```
[Icon 40px] [Left info flex:1] [Right column flex:1]
```

**Left info column** (vertically centered):
- Device name (14px bold, truncated)
- IP address (11px monospace, slate-400)
- Category · Site (11px, slate-400)

**Right column** (flex-col, space-between, align right):
- Top: `AlarmBadges` (existing component, reused as-is)
- Bottom: incident ticker OR invisible spacer (same height as ticker, `h-[14px]`)

**Ticker** (bottom of right column, visible only when `activeSummaries.length > 0`):
- CSS marquee animation, continuous scroll
- Width: full right column (~50% of card minus icon)
- Edge fade via `mask-image` gradient
- Text color: severity of worst active incident (`red-400` for critical, `yellow-300` for warning, `orange-400` for minor)
- Format: `"Summary one · Summary two · Summary one · …"` (duplicated for seamless loop)

---

## 5. Device Detail Screen — Header Card

Replaces the current flat heading + info card.

### Header card layout (single `bg-slate-800` rounded card)

Three-column flex row, items stretch to equal height:

```
[Icon 52px] [Info col flex:0_0_38%] [Latency chart flex:1]
```

**Icon column**: `DeviceTypeIcon` at size 52, status-colored, top-aligned.

**Info column**:
- Device name (15px bold, truncated with ellipsis)
- IP address (11px monospace, slate-400)
- Category with folder icon (11px, slate-400)
- Site with home icon (11px, slate-400)
- Status pill: colored dot + status label (10px, e.g. `● UP` in green)

**Latency chart column** (fills remaining width):
- Label: "Latency" (10px, slate-500, right-aligned)
- SVG area+line chart, height fills the card, width fills the column
- Y-axis labels: max value top-left, `0` bottom-left (8px, slate-500)
- Last-value dot at rightmost point
- Current value (12px bold, sky-400) right-aligned below chart
- If no latency data available: column is hidden (info column expands to fill)
- Data source: the first instance from the `Latency` performance category, fetched eagerly when the detail view mounts (same fetch path as `PerformanceSection`, just triggered immediately rather than on user tap)

### Alarm summary bar

Directly below the header card, four equal columns, no card background:

```
12        3         1         2
HEALTHY   ACK      WARNING   CRITICAL
```

- Numbers: 26px bold, color-coded (green-500 / blue-400 / yellow-300 / red-400)
- Labels: 9px semibold, letter-spacing, same color
- Vertical dividers (`border-left: 1px solid slate-700`) between columns
- Data source: `buildDeviceAlarmMap()` for this device, mapped as:
  - HEALTHY → `counts.green`
  - ACK → `counts.blue`
  - WARNING → `counts.yellow + counts.orange`
  - CRITICAL → `counts.red`

### Maintenance Window card

`bg-slate-800` rounded card below the alarm bar:

```
[  + Create Maintenance Window  ]
```

Tapping opens the existing `MaintenanceDialog`. No change to dialog itself.

---

## 6. Collapsible Sections

Both sections use the same collapsible pattern: header row with chevron, animated expand/collapse.

### 6.1 Host Information (closed by default)

Collapsible card. When expanded, shows:

| Label | Value |
|---|---|
| Current State | Status string, color-coded |
| Type | Description field |
| Category | With folder icon |
| Site | With home icon |
| Model | If present |
| Serial Number | If present |
| UID | deviceIndex |

Each row is a label/value pair (`InfoRow` — already exists in `DeviceDetailScreen`).

### 6.2 Current Issues (expanded by default)

Collapsible card. Badge on header showing active incident count (red pill).

**When empty:** "No current issues" with checkmark icon, slate-400.

**When populated:** Incident table (no external scroll, just stacked rows):

| Column | Content |
|---|---|
| TYPE (80px) | `SeverityBadge` (existing component) |
| DESCRIPTION (flex) | `incident.summary`, 2-line clamp |
| DURATION (56px) | Time elapsed since `startTime`, right-aligned |

Dividers between rows. Data source: incidents filtered by device name (same as today, no change to fetch logic).

---

## 7. Component & File Map

| New / Changed | Path | Notes |
|---|---|---|
| New SVGs | `shared/icons/device-*.svg` | 5 files, `currentColor`, `0 0 24 24` viewBox |
| New | `pwa/src/components/DeviceTypeIcon.tsx` | Wraps SVGs, applies status color |
| New | `pwa/src/lib/deviceAlarms.ts` | `buildDeviceAlarmMap()` utility |
| New | `pwa/src/lib/deviceType.ts` | `classifyDevice()` utility |
| Changed | `pwa/src/lib/api/devices.ts` | Add `DeviceStatus` type + `status` field to `Device` |
| Changed | `pwa/src/features/devices/DeviceRow.tsx` | New layout: icon + alarm badges + ticker |
| Changed | `pwa/src/features/devices/DeviceListScreen.tsx` | Pass `deviceAlarmMap` down to rows |
| Changed | `pwa/src/features/devices/DeviceDetailScreen.tsx` | New header card + alarm bar + collapsible sections |

---

## 8. What Is NOT in Phase 1

- Server Utilization section (CPU/Memory/Disk) → Phase 2
- Pinned Interfaces section → Phase 2
- Performance section changes → Phase 2
- iOS Canvas drawing changes → none (iOS keeps existing implementation)

---

## 9. Open Questions

None — all design decisions confirmed during brainstorming session on 2026-04-11.
