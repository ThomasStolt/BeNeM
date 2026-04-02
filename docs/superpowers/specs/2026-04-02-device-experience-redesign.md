# Device Experience Redesign — Design Spec

**Date:** 2026-04-02
**Target BHNM version:** 26.1.02+
**Scope:** Phase 1 (Foundation) + Phase 2 (UI). Phase 3 (Caching Middleware) deferred.

## Context

BHNM 26.1.01/26.1.02 introduced several API enhancements:
- `model` and `serial_number` fields in `/devices/list`
- Record-count pagination (`recordStart`/`recordCount`) on `/devices/list`
- Optional interface details (`include_interface_details=1`) on `/devices/list`
- `UID` (root_id) and `GUID` (globally unique identifier) across all device endpoints

BeNeM currently uses IP as the device identifier, fetches all devices in a single unpaginated call, and has a basic device detail view. This redesign rebuilds the device experience for large-scale environments (4,000–13,000 devices).

## Phase 1: Foundation — Data Model & API Layer

### NetreoDevice Model

Replace the current model (which uses IP as `id` and has a catch-all `additionalProperties` dict) with explicit typed fields:

| Field | Type | Source | Notes |
|---|---|---|---|
| `id` | `String` | `UID` from API | Primary identifier, replaces IP |
| `uid` | `String` | `UID` | Same as id, explicit alias |
| `guid` | `String` | `GUID` | Globally unique: `netreo-PIN-rootId` (On-Prem) |
| `devIndex` | `String` | `dev_index` | Legacy index, still used by some endpoints |
| `name` | `String` | `name` | Device hostname |
| `ip` | `String` | `ip` | IP address |
| `description` | `String` | `description` | SNMP sysDescr or similar |
| `category` | `String` | `category` | Device category name |
| `site` | `String` | `site` | Site name |
| `model` | `String?` | `model` | Hardware model, nullable |
| `serialNumber` | `String?` | `serial_number` | Manufacturer serial, nullable |
| `poll` | `Bool` | `poll` | Whether device is polled |
| `monitor` | `Bool` | `monitor` | Whether device is monitored |
| `snmpVersion` | `String?` | `snmp_version` | SNMP version |
| `createTime` | `String?` | `create_time` | When device was added |
| `status` | `DeviceStatus` | derived | up/down/warning/critical/unknown/maintenance |

Drop `additionalProperties`, `hostname`, `deviceType`, `lastUpdated`, `siteID`, `categoryID`, `snmpCommunity`, `isActive` — these were artifacts of the old model that don't match actual API responses.

### Device Type Classification

New enum for icon selection, derived from `description` and `category`:

```swift
enum DeviceTypeClass: String {
    case linux
    case windows
    case router
    case switchDevice  // 'switch' is a Swift keyword
    case unknown
}
```

Classification logic:
- `description` contains "Linux" → `.linux`
- `description` contains "Windows" → `.windows`
- `description` contains "Router" or category suggests router → `.router`
- Category is "Network Infrastructure" / "Switches" or description suggests switch → `.switchDevice`
- Fallback → `.unknown`

### NetreoAPIService Changes

**Paginated device list:**
```swift
func fetchDevices(recordStart: Int = 0, recordCount: Int = 50) async throws -> (devices: [NetreoDevice], totalRecords: Int)
```
- Calls `POST /fw/index.php?r=restful/devices/list` with pagination params
- Parses `{totalRecords, displayRecords, devices:[]}` wrapper
- Default page size: 50

**Server-side search:**
```swift
func searchDevices(query: String) async throws -> [NetreoDevice]
```
- Calls `POST /fw/index.php?r=restful/devices/find` with `name=<query>`
- Supports substring matching (confirmed via testing)
- Returns array of matching devices

**Category/site device lists (no pagination):**
```swift
func fetchDevicesForCategory(id: String) async throws -> [NetreoDevice]
func fetchDevicesForSite(id: String) async throws -> [NetreoDevice]
```
- Calls `/category/device-list` or `/site/device-list`
- Returns plain array (no pagination support on these endpoints — confirmed via testing)
- Acceptable: categories/sites naturally scope to manageable sizes

**Interface details (on-demand):**
```swift
func fetchInterfaces(deviceName: String) async throws -> [DeviceInterface]
```
- Calls `/devices/find` with `name=<exactDeviceName>` and `include_interface_details=1` (if supported), or falls back to fetching from `/devices/list` with `include_interface_details=1` and `recordCount=1` filtered by name
- Only called when device detail view needs interface data for routers/switches
- Note: Needs testing whether `/devices/find` supports `include_interface_details` parameter

**Response parsing:**
- Handle both wrapped `{totalRecords, displayRecords, devices:[]}` and plain array responses
- Parse `UID`, `GUID`, `model`, `serial_number` from all device responses
- Note: `totalRecords` comes as String from API, `displayRecords` as Int — handle both

## Phase 2: UI

### Device List View

**Two modes:**

1. **Browse mode** — Paginated list with optional category/site filter
   - Global: `/devices/list` with pagination, infinite scroll / load-more
   - From tactical drill-down: `/category/device-list` or `/site/device-list` (no pagination, naturally scoped)
   - Total device count shown in header (from `totalRecords`)

2. **Search mode** — Server-side substring search
   - Search bar at top of device list
   - Debounced input (300ms) → `/devices/find`
   - Results replace browse list while searching
   - Minimum 2 characters before search fires

**Device list row:**
```
[Type Icon]  Device Name
             IP Address  •  Category  •  Site
```
- Small device type icon (Linux/Windows/Router/Switch) on left
- Device name prominent, metadata as secondary line
- Tap navigates to Device Detail View

**Navigation:**
- `NavigationLink(value:)` pattern, consistent with tactical views
- Auto-refresh via `AutoRefreshButton` (120s), re-fetches current page

### Device Detail View

**Layout (top to bottom):**

#### 1. Header
- Large centered device type icon (green, matching BHNM dashboard style)
- Device name in accent color
- Metadata line: type/description, IP, category, site — with small icons

#### 2. Alarm Summary Bar
Four columns: HEALTHY (green) / ACK (blue) / WARNING (yellow) / CRITICAL (red)
- Values from host and service status counts
- Zero values in muted/grey text

#### 3. Host Information (collapsible, collapsed by default)
Table layout showing:
- Current State (with colored badge: UP green, DOWN red, etc.)
- Type of Device
- Category, Site
- Model (new), Serial Number (new)
- Description
- UID

#### 4. Current Issues
- Badge count in header
- Each issue: type (Host/Service/Threshold), description, duration
- Data from incident detail API for this device
- Empty state: "No current issues" with green checkmark

#### 5. Performance Section (context-dependent by device type)

**Linux / Windows servers:**
- **CPU card:** Current percentage + 24h sparkline chart
- **Memory card:** Current percentage + 24h sparkline chart
- **Disk section:** Horizontal bar per mount point (used/free with percentages)
- Data: `get-time-series-metrics` with `statGroup=CPU|Memory|Disk`, `timeFrame=Last 24 Hours`

**Routers / Switches:**
- **Pinned Interfaces** (user-configured, see below)
  - Each: bandwidth sparkline + in/out %, errors in/out, speed in/out
- **Top 5 by Bandwidth** (auto-calculated)
  - Single API call: `get-time-series-metrics` with `statGroup=bandwidth`, `groupFilterBy=device`
  - Returns all interfaces — sort by latest value, take top 5
  - Excludes interfaces already shown in Pinned section
- **All Interfaces** (collapsed by default)
  - Full list of active interfaces
  - Each row has a pin action
  - Shows name, status, speed, bandwidth in/out, errors in/out

**Data loading strategy:**
1. Header + host info render immediately from passed `NetreoDevice`
2. Concurrent async fetches for: alarm counts, current issues, performance metrics
3. Each section has independent loading state
4. All metrics use `Last 24 Hours` time frame

### Pinned Interfaces

**Storage:**
```
UserDefaults key: "pinned_interfaces_<UID>"
Value: [String] — array of interface keys from performance-instance-per-category
```

**Interactions:**
- Pin: tap pin icon in All Interfaces section → appears in Pinned section
- Unpin: swipe left or tap unpin in Pinned section
- Order: pinned in order added (most recent last)

**Scope:** Device-local (on iPhone). No iCloud sync for now.

## API Endpoint Reference

| Function | Method | Endpoint | Pagination | Response |
|---|---|---|---|---|
| Device list | POST | `/fw/index.php?r=restful/devices/list` | Yes (`recordStart`/`recordCount`) | `{totalRecords, displayRecords, devices:[]}` |
| Device search | POST | `/fw/index.php?r=restful/devices/find` | No (substring filter) | Array |
| Category devices | POST | `/fw/index.php?r=restful/category/device-list` | No | Array |
| Site devices | POST | `/fw/index.php?r=restful/site/device-list` | No | Array |
| Perf categories | POST | `/fw/index.php?r=restful/devices/performance-category` | No | Array |
| Perf instances | POST | `/fw/index.php?r=restful/devices/performance-instance-per-category` | No | Array |
| Time-series metrics | POST | `/fw/index.php?r=restful/devices/get-time-series-metrics` | No | `{metrics:[]}` |

All endpoints include `UID`, `GUID` in device responses (BHNM 25.4.01+).
`model`, `serial_number` included in device list responses (BHNM 26.1.01+).

## Findings from API Testing

| Test | Result |
|---|---|
| `/devices/find` substring matching | Works — "raspi" returns all raspi-* devices |
| `/category/device-list` pagination | Not supported — `recordStart`/`recordCount` ignored |
| `/site/device-list` pagination | Not supported — params ignored |
| `totalRecords` type | String (e.g., `"52"`), `displayRecords` is Int |
| Interface tags ("Dashboard Zoom") via API | Not available — no tag endpoint exists |
| `include_interface_details` response | `snmp_index`, `description`, `mac_address`, `interface_ip` — no tags |

## Explicitly Deferred

- **Phase 3: Caching middleware** — API proxy for large environments (saved to project memory)
- **Topology view** — mapping device connectivity via interface IPs
- **Non-published `timeseries-metrics` endpoint** — has speed data but percentage bug; published endpoint sufficient
- **Uptime percentages** — shown in BHNM UI, need to verify API availability
- **Top Process info** — shown in BHNM CPU/Memory cards, likely not available via API
- **Dashboard Zoom tag filtering** — until BMC exposes tags via API
- **iCloud sync for pinned interfaces**

## Minimum BHNM Version

**26.1.02** — no backwards compatibility. Users must upgrade.
