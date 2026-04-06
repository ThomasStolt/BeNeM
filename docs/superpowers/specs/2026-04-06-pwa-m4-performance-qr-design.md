# PWA M4: Performance Charts + QR Scanning Design

**Date:** 2026-04-06
**Status:** approved
**Version:** 0.5.0
**Scope:** Two independent features delivered as a single milestone

## Context

PWA v0.4.0 (M3) shipped device list, device detail, and tactical overview.
Device detail includes a disabled "View Performance" placeholder. M4 fills
that gap with inline performance charts and adds QR-based server onboarding.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Chart library | Recharts | React-native, lightweight (~40KB), declarative composable API. Dataset sizes are small (~288 points/24h). |
| QR library | html5-qrcode | Handles camera lifecycle, permissions, BarcodeDetector where available. Customizable viewfinder. |
| QR encryption | AES-256-GCM (same as iOS) | Web Crypto API supports it natively. One QR format across both platforms. No iOS changes needed. |
| Performance UX | Inline in device detail | Matches iOS pattern. No separate route needed. Expandable category cards. |
| Architecture | Two independent feature modules | `features/performance/` and `features/scanner/`. Only overlap in App.tsx and Settings. |
| Auto-load heuristics | Deferred | iOS auto-loads latency/CPU on open. PWA loads on category expand only. Can add later. |
| Mini header chart | Deferred | iOS shows a small latency sparkline in the device header. Not in M4 scope. |

---

## Performance Charts

### Data Layer

**New API module:** `src/lib/api/performance.ts`

Three functions mirroring the iOS service layer:

**`fetchPerformanceCategories(config, deviceId)`**
- POST `restful/devices/performance-category`
- `deviceId` must be `deviceIndex` (not the `id` from `devices/find` — see
  `shared/BHNM_API_REFERENCE.md` "numeric IDs are not interchangeable")
- Returns `PerformanceCategory[]`
- Normalizes the special `{ id: "interfaces", cat: "Network" }` entry to
  `{ id: "interfaces", category: "Network" }`

**`fetchPerformanceInstances(config, deviceId, categoryId)`**
- POST `restful/devices/performance-instance-per-category`
- Returns `PerformanceInstance[]` with `title`, `unit`, `statGroup`, `key`,
  `valueKey`
- Filters out per-process metrics, swap, and raw-byte duplicates (same rules
  as iOS)

**`fetchTimeSeriesBatch(config, deviceName, statGroup, units, timeFrame)`**
- POST multipart/form-data to `restful/devices/timeseries-metrics`
- Returns all matching metrics in one API call (batch by statGroup+units)
- Parses `datapoints[0]` object (keys = Unix timestamp strings, values =
  metric value strings)
- Empty-unit handling: when `unit === ""`, sends the metric title as
  `metricFilterUnits`
- Fixed time frame: `timeFrameFilterBy=time_offset`,
  `timeFrameFilterValue=Last 24 Hours`
- `returnFormatFilterBy=average`

### Types

Added to `src/lib/api/types.ts`:

```typescript
interface PerformanceCategory {
  id: string | number
  category: string
}

interface PerformanceInstance {
  key: string
  title: string
  unit: string
  statGroup: string
  valueKey: 'value1' | 'value2'
}

interface TimeSeriesDataPoint {
  timestamp: number  // Unix seconds
  value: number
}

interface TimeSeriesResult {
  instanceDescr: string
  metricId: string
  datapoints: TimeSeriesDataPoint[]
}
```

### React Query Hooks

In `src/features/performance/usePerformance.ts`:

- **`usePerformanceCategories(deviceId)`** — fetches once, 5-minute stale time
- **`usePerformanceInstances(deviceId, categoryId)`** — fetches per category
  expansion, 5-minute stale time
- **`useTimeSeriesBatch(deviceName, statGroup, units)`** — 60-second stale
  time, matching iOS refresh cadence

### UI Components

**`PerformanceSection.tsx`** — container rendered in DeviceDetailScreen below
incidents. Header: "Performance · Last 24 Hours". Fetches categories on mount.
Renders a `MetricCard` per category. Categories sorted with latency first.

**`MetricCard.tsx`** — expandable card for one category.
- Collapsed: category name + metric count badge + chevron
- Expanded: fetches instances and timeseries data, renders `MetricChart`
  per unique statGroup+units combination
- States: loading spinner, error with retry, empty ("No data for the last
  24 hours")
- Dark card style: `bg-gray-800` rounded corners, consistent with existing
  PWA design

**`MetricChart.tsx`** — Recharts `LineChart` wrapper.
- X-axis: timestamps formatted as HH:MM, 6-hour stride marks
- Y-axis: auto-scaled with unit label (%, MB, Mbps, ms, s, etc.)
- Single series: solid line with gradient area fill
- Multi-series (CPU cores, interface in/out): multiple `<Line>` elements
  with legend, color palette
- Interface metrics: dual lines for value1 (in) and value2 (out)
- Touch/hover tooltip: exact value + formatted timestamp

### Device Detail Integration

`DeviceDetailScreen.tsx` changes:
- Remove the disabled "View Performance" placeholder button
- Add `<PerformanceSection deviceId={device.deviceIndex} deviceName={device.name} />`
  below the active incidents section

---

## QR Scanning

### Crypto Layer

**`src/lib/crypto.ts`** — AES-256-GCM decryption via Web Crypto API:

- Encryption key: 32-byte hex string provided as `VITE_QR_ENCRYPTION_KEY`
  build-time environment variable
- Import key via `crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['decrypt'])`
- Compact format blob layout: `[12-byte IV | ciphertext | 16-byte auth tag]`
- Decrypt: `crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertextWithTag)`
- Returns parsed JSON object

The key is not secret from the user (it's embedded in the iOS binary too) but
is kept out of source control via the env var.

### QR URL Parsing

**`src/lib/qr-parser.ts`**:

1. Parse URL string → validate `scheme === "benem"` and `host === "configure"`
2. **Compact format:** single `p` query parameter → base64 decode → decrypt →
   parse JSON → extract `{ bhnmURL, middlewareURL, apiKey, pin, pushSecret,
   name, ackUser, symbol, accentColor }`
3. **Legacy format:** individual `server`, `api_key`, `pin`, `name` query
   parameters, each individually AES-256 encrypted → decrypt each → assemble
4. Map parsed fields to `ServerConfig` for upsert into `serverStorage`

### Scanner UI

**`QRScannerOverlay.tsx`** — full-screen overlay component:
- Rendered conditionally from SettingsScreen (not a route)
- `Html5Qrcode` instance with `{ fps: 10, qrbox: 250 }`,
  `facingMode: 'environment'`
- Viewfinder frame with corner accents and "Point at a BeNeM QR code" label
- Cancel button dismisses overlay and stops camera
- On successful decode: stop scanner → parse URL → decrypt → show confirmation
- On unmount: clean up camera stream

**`QRConfirmScreen.tsx`** — confirmation after successful scan:
- Displays parsed server name, URL, masked API key, middleware URL
- "Add Server" button → upsert into `serverStorage`, auto test-connection
- "Cancel" button → return to settings
- If scanned URL matches an existing server by `baseUrl`, offer to update
  instead of adding a duplicate

### Settings Integration

`SettingsScreen.tsx` changes:
- Add "Scan QR Code" button next to existing "Add Manually" / "Add Server"
- Button hidden on devices without camera (`navigator.mediaDevices` check)
- Tapping opens `QRScannerOverlay`

### Error States

| State | Display | Action |
|---|---|---|
| Camera permission denied | Explanation + browser settings hint | "Enter Server Manually" button |
| Invalid QR code (not benem://) | "This doesn't look like a BeNeM configuration code" | "Try Again" button |
| Decryption failed | "Could not decrypt — key may not match" | "Enter Server Manually" button |
| No camera available | "Scan QR Code" button hidden entirely | Manual entry only |

---

## File Structure

### New Files

```
src/lib/api/performance.ts              — API functions
src/lib/crypto.ts                       — AES-256-GCM decrypt
src/lib/qr-parser.ts                    — benem:// URL parsing

src/features/performance/
  usePerformance.ts                     — React Query hooks
  PerformanceSection.tsx                — Expandable category cards container
  MetricCard.tsx                        — Single category card
  MetricChart.tsx                       — Recharts LineChart wrapper

src/features/scanner/
  QRScannerOverlay.tsx                  — Full-screen camera overlay
  QRConfirmScreen.tsx                   — Parsed server confirmation
```

### Modified Files

```
src/features/devices/DeviceDetailScreen.tsx  — Replace placeholder with PerformanceSection
src/features/settings/SettingsScreen.tsx     — Add Scan QR Code button + overlay
src/lib/api/types.ts                         — Add performance + QR types
package.json                                 — Add recharts, html5-qrcode
```

### No New Routes

Performance charts are inline in device detail. QR scanner is an overlay
from settings. No changes to `App.tsx` routing.

### Dependencies

| Package | Size (gzipped) | Purpose |
|---|---|---|
| `recharts` | ~40KB | Line charts with multi-series, tooltips, responsive |
| `html5-qrcode` | ~35KB | Camera QR scanning with BarcodeDetector fallback |

---

## Testing Strategy

**API functions** — unit tests with mocked fetch:
- Category parsing, Network normalization
- Instance filtering (per-process removal, swap, raw-byte dedup)
- Timeseries `datapoints[0]` parsing, string-to-number conversion
- Empty-unit substitution (title as metricFilterUnits)
- Batch response with multiple metrics → correct routing by instanceDescr

**Crypto** — unit test with known ciphertext + key → verify decryption
round-trip

**QR parser** — unit tests for:
- Compact format (base64 `p` param)
- Legacy format (individual encrypted params)
- Invalid URLs, non-benem schemes, malformed base64
- Missing required fields

**Components** — React Testing Library:
- Category expand/collapse toggle
- Loading, error, empty states per card
- Chart renders with mock timeseries data
- Scanner overlay open/close lifecycle
- Confirmation screen field display

**No E2E camera tests** — html5-qrcode owns the browser camera API.
We test the parse/decrypt/confirm layer.
