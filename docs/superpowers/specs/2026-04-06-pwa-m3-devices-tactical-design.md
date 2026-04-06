# M3: Devices + Tactical Drill-downs (v0.4.0) — Design Spec

> **Scope:** Device list with pagination and search, device detail screen,
> tactical overview group list views. No interfaces, no tap-group-to-device
> linkage (deferred).

## Architecture

### API Layer

**New module: `pwa/src/lib/api/devices.ts`**

Two endpoints:

| Function | BHNM Endpoint | Purpose |
|---|---|---|
| `fetchDevices(config, start, count)` | `POST restful/devices/list` | Paginated device list |
| `searchDevices(config, name)` | `POST restful/devices/find` | Search by name |

Both return `Device[]`. Parameters follow the existing `postForm` pattern
with `password` + optional `pin`.

**Device type:**

```typescript
interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
}
```

Parsed defensively from API response (array-unwrap, multi-field fallbacks)
following the pattern in `incidents.ts`.

**No new tactical endpoint needed** — `fetchTacticalOverview` already
returns per-group H/S/T/A data with configurable `groupingType`.

### Pagination Strategy (20K+ devices)

The device list must handle BHNM servers with 20,000+ devices without
accumulating data in memory.

- **Window-based pagination:** Display 50 devices per page with
  Previous / Next controls. Only one page of data is rendered at a time.
- **Per-page query keys:** `['devices', serverId, page]` — each page is
  an independent React Query entry. Old pages are cached but can be GC'd.
- **No accumulation:** Unlike infinite scroll, we never hold thousands of
  devices in the DOM or in state.
- **Search is server-side:** `devices/find` filters on the BHNM server,
  so the response is always small regardless of total device count.
- **Auto-refresh:** 120-second cycle with `RefreshCountdown`, same as
  incidents and dashboard.

### Routing

New routes inside `<AppLayout>`:

| Route | Component | Purpose |
|---|---|---|
| `/devices` | `DeviceListScreen` | Paginated device list + search |
| `/devices/:name` | `DeviceDetailScreen` | Device detail with incidents |
| `/tactical/:type` | `TacticalGroupListScreen` | Category/Site/BW group lists |

The `:type` param maps to `groupingType`: `category`, `site`, `bw` (mapped
to `app` for the API call).

## Device List Screen

**Route:** `/devices` (replaces `DevicesPlaceholder`)

### Header
- Title: "Devices"
- `RefreshCountdown` (120s interval)
- Page indicator: "Page 1 of N" (total derived from first response if
  the API provides it, otherwise just "Page N")

### Search Bar
- Text input at top of the list, debounced 300ms
- While searching: replaces paginated list with search results
- Clear button returns to paginated view
- Placeholder: "Search devices by name..."

### Device Rows
Each row displays:
- **Device name** (primary text)
- **IP address** (secondary text, monospace)
- **Category** (small badge/tag)
- **Alarm indicator** — colored dot: green (all OK), red (any critical),
  orange (any warning/unknown but no critical), blue (acknowledged only)

Tap navigates to `/devices/${encodeURIComponent(device.name)}`.

### Pagination Controls
- Previous / Next buttons at the bottom
- Disabled when at first/last page
- Page size: 50

### Empty States
- Not configured → "Add a server in Settings" with configure link
- Loading → spinner/skeleton
- No devices → "No devices found"
- No search results → "No devices matching '{query}'"

## Device Detail Screen

**Route:** `/devices/:name`

### Header
- Back link to `/devices`
- Device name as title

### Device Info Card
- IP address
- Model + Serial Number (if present)
- Category, Site
- Description (if present)

### Alarm Status Card
Reuses the color-coded badge pattern from `StatusCard`:
- H/S/T/A rows with OK/ACK/WARN/UN/CRIT counts
- Fetched via `fetchTacticalOverview` filtered... actually, the device
  list response itself may include alarm counts. If not, this card is
  omitted until a per-device status endpoint is identified.

**Decision:** Show device info from the list/find response. Alarm status
badges are deferred — the BHNM API doesn't expose per-device H/S/T/A
counts in the list/find endpoints. This can be added later when a suitable
endpoint is identified (e.g. `get-host-and-service-status`).

### Host Current Issues Card
- Filters the existing `useIncidents()` data by matching
  `incident.deviceName` to the current device name
- Renders each match as a `SwipeableIncidentRow`
- "No current issues" empty state if no matches
- No extra API call needed

### Performance Placeholder
- "View Performance" button, disabled
- Caption: "Available in v0.5.0"

## Tactical Overview Group List

**Route:** `/tactical/:type` where `:type` is `category`, `site`, or `bw`

Single component: `TacticalGroupListScreen`, parameterized by route param.

### Header
- Back link to `/` (dashboard)
- Title: "Categories" / "Sites" / "Business Workflows" based on type
- Filter toggle button (funnel icon) — hides all-green groups
- `RefreshCountdown` (120s)

### Group Rows
Each row displays:
- **Group name** (or "Unknown" if empty string)
- **Alarm rows:** four lines for Hosts / Services / Thresholds / Anomalies
- Each line shows 5 count badges: OK (green) / ACK (blue) / WARN (yellow)
  / UN (orange) / CRIT (red)
- Zero-value badges: grey text, no colored background (same pattern as
  `StatusCard` Badge component)

### Filter Toggle
- Default: show all groups
- When active: hide groups where all alarm counts across H/S/T/A are
  OK-only (zero warn + un + crit)
- Visual indicator on the filter button when active

### Data Fetching
- Uses existing `fetchTacticalOverview(config, groupingType)` from
  `tactical-overview.ts`
- React Query with key `['tactical-groups', serverId, groupingType]`
- 120-second refetch interval

### Empty States
- Not configured → settings link
- Loading → skeleton
- No groups → "No data available"
- All filtered → "All groups are healthy" (when filter hides everything)

## Component Reuse

| Existing Component | Reused In |
|---|---|
| `RefreshCountdown` | Device list header, tactical group list header |
| `EmptyState` | All new screens (loading, error, empty) |
| `SwipeableIncidentRow` | Device detail "Host Current Issues" |
| `SeverityBadge` | Device detail incidents |
| Badge pattern from `StatusCard` | Tactical group alarm rows |

## New Files

| File | Purpose |
|---|---|
| `pwa/src/lib/api/devices.ts` | Device API: fetchDevices, searchDevices, types |
| `pwa/src/lib/api/devices.test.ts` | Device API response parsing tests |
| `pwa/src/features/devices/DeviceListScreen.tsx` | Paginated device list + search |
| `pwa/src/features/devices/DeviceRow.tsx` | Single device row component |
| `pwa/src/features/devices/useDevices.ts` | React Query hook for paginated device list |
| `pwa/src/features/devices/useDeviceSearch.ts` | React Query hook for device search |
| `pwa/src/features/devices/DeviceDetailScreen.tsx` | Device detail with info + incidents |
| `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` | Device list tests |
| `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx` | Device detail tests |
| `pwa/src/features/tactical/TacticalGroupListScreen.tsx` | Group list view (shared by 3 routes) |
| `pwa/src/features/tactical/TacticalGroupRow.tsx` | Single group row with alarm badges |
| `pwa/src/features/tactical/useTacticalGroups.ts` | React Query hook for group data |
| `pwa/src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx` | Group list tests |

## Modified Files

| File | Changes |
|---|---|
| `pwa/src/App.tsx` | Add routes: `/devices/:name`, `/tactical/:type` |
| `pwa/src/features/devices/DevicesPlaceholder.tsx` | Deleted (replaced by DeviceListScreen) |
| `pwa/src/features/dashboard/DashboardScreen.tsx` | Update drill-down links to use `/tactical/:type` routes |
| `pwa/package.json` | Bump to 0.4.0 |
| `shared/feature-spec.md` | Mark M3 features as implemented |

## Out of Scope (Deferred)

- Device interfaces (network device port list)
- Tap tactical group → filtered device list
- Per-device alarm status badges (needs endpoint investigation)
- Performance charts (M4)
- Infinite scroll (window pagination is sufficient and memory-safe)
