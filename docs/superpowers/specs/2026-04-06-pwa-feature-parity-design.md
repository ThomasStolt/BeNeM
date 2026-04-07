# PWA Feature Parity Design

**Date:** 2026-04-06
**Status:** approved
**Scope:** Full feature parity between iOS and PWA, delivered in 4 milestones

## Context

BeNeM PWA v0.1.1 is shipped with incident list, incident detail, ACK/UnACK,
and basic settings. The goal is to bring the PWA to full feature parity with
the iOS app, except where browser platform limitations prevent it.

## Platform Exclusions

Features that cannot be implemented in the PWA due to browser limitations:

- **Time Sensitive / Critical Alerts** — Web Push API does not support iOS
  interrupt levels
- **`benem://` custom URL scheme** — PWA uses HTTPS routes instead

## Milestone Overview

```
M1 (0.2.0): Web Push + Incidents polish
M2 (0.3.0): Navigation + Dashboard + Multi-Server Management
M3 (0.4.0): Tactical Overview + Device List/Detail/Search
M4 (0.5.0): Performance Charts + QR Scanning
```

## Shared Patterns

- React Query for server state (established in v0.1.0)
- Tailwind CSS for styling (established in v0.1.0)
- localStorage for config (upgraded to multi-server in M2)
- Bottom tab bar navigation (introduced in M2)
- Auto-refresh: 120-second cycle with visual countdown indicator (shared
  component across all tabs)

---

## M1: Web Push + Incidents (v0.2.0)

Push notifications are the lighthouse feature — the primary reason BeNeM
exists on both iOS and Android. This milestone adds Web Push delivery to
the middleware and push reception + deep-linking to the PWA.

### Middleware Changes

**VAPID configuration** (new `.env` vars):
- `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` — generated once
- `VAPID_CONTACT_EMAIL` — required by Web Push spec

**Database** — new `web_push_subscriptions` table:
- `endpoint` (string) — browser push service URL
- `p256dh` (string) — client public key
- `auth` (string) — auth secret
- `webhook_secret` (string) — ties subscription to a BHNM webhook source
- `created_at` (datetime)

Stored in the same SQLite database, separate table from APNs tokens.

**New endpoint** — `POST /register-webpush`:
- Accepts `{ endpoint, p256dh, auth }` + `X-Webhook-Token` header
- Upserts by endpoint (re-registration replaces keys)
- Returns 201 (new) or 200 (updated)

**Notification sending** — new `webpush.py` alongside existing `apns.py`:
- Webhook handler calls both APNs and Web Push senders for matching
  webhook secret
- Uses `pywebpush` library for VAPID signing and delivery
- Handles 410 Gone (expired subscriptions) — same cleanup pattern as APNs
- Payload: `{ incident_id, title, body, severity }`

### PWA Service Worker

**Push event handler:**
- Listens for `push` event in the service worker
- Extracts `{ title, body, incident_id, severity }` from payload
- Shows a browser `Notification` with title, body, and icon/badge
- Stores `incident_id` in notification data for click handling

**Notification click handler:**
- Focuses or opens the PWA window
- Navigates to `/incident/{incident_id}` (deep-link to incident detail)
- If app is already open, uses `postMessage` for client-side navigation

### PWA Registration Flow

On first load (or Settings save):
1. Request `Notification.permission` from the user
2. Subscribe via `pushManager.subscribe()` with the VAPID public key
3. POST subscription to middleware `/register-webpush`
4. Store subscription state in localStorage

**Settings → Push Notifications section:**
- Toggle to enable/disable
- Status indicator (registered / not registered / permission denied)
- Re-register button for troubleshooting

### Incident View Polish

- Deep-link from push notification lands correctly on detail screen
- Handle case where incident list hasn't loaded yet (fetch on demand)
- Add toast/snackbar for ACK/UnACK success feedback

---

## M2: Navigation + Dashboard + Multi-Server (v0.3.0)

### Bottom Tab Bar

Persistent bottom navigation with 3 tabs mirroring iOS:

| Tab | Icon | Route | Content |
|---|---|---|---|
| Dashboard | Home | `/` | Status cards, incident ticker, drill-downs |
| Incidents | Bell/Alert | `/incidents` | Incident list (moved from `/`) |
| Devices | Server/Monitor | `/devices` | Device list (placeholder until M3) |

- Active tab highlighted with accent color
- Tab bar visible on all top-level screens
- Detail screens render above the tab bar
- Nested routes: `/incidents/:id`, `/devices/:id`

### Dashboard Screen

**Status Cards** — H/S/T/A summary:
- Four cards: Hosts / Services / Thresholds / Anomalies aggregate counts
- Color-coded: green (ok), blue (ack), yellow (warn), orange (unknown),
  red (critical)
- Data: `POST restful/tactical-overview/data` with `grouping_type=category`,
  summing all category rows to produce the aggregate counts

**Incident Ticker:**
- Horizontal auto-scrolling strip showing latest critical/major incidents
- Tap navigates to incident detail
- Uses existing React Query incident data cache

**Drill-Down Links:**
- Three buttons: Categories, Sites, Business Workflows
- Navigate to tactical overview screens (built in M3, placeholder in M2)

**Auto-refresh countdown** — 120-second cycle with visual indicator in header.
Shared component reused across all tabs.

### Multi-Server Management

**Data model** (`ServerConfig`):
```typescript
{
  id: string           // uuid
  name: string
  baseUrl: string
  apiKey: string
  pin?: string
  pushEnabled: boolean
  pushMiddlewareUrl?: string
  pushWebhookSecret?: string
  isActive: boolean
}
```

Stored as JSON array in localStorage under `benem_servers`.

**Settings screen redesign:**
- Server list at top — name, URL, connection status indicator per server
- Tap to edit, swipe to delete
- "Add Server" button opens add/edit form
- Active server has checkmark; tap another to switch
- Test Connection per server (existing `ha_status` endpoint)
- Push settings move inside per-server config

**API client update:**
- `getActiveServer()` reads active server config
- All API calls use active server's credentials
- Switching servers triggers data re-fetch and Web Push re-registration

---

## M3: Tactical Overview + Devices (v0.4.0)

### Tactical Overview

Three views from Dashboard drill-downs, same component with different
`grouping_type`:

| View | `grouping_type` | Route |
|---|---|---|
| Categories | `category` | `/tactical/category` |
| Sites | `site` | `/tactical/site` |
| Business Workflows | `app` | `/tactical/bw` |

**Group List View** (mirrors iOS `GroupListView`):
- Each row: group name, DEVICES badge (blue outlined), H/S/T/A alarm rows
- Badge colors: Green / Blue / Yellow / Orange / Red
- Zero-value badges: grey text, no background
- Alternating row backgrounds (light gray tint every second row)
- Empty group names displayed as "Unknown"
- Filter button (funnel icon) hides all-green groups
- Tap group → filtered device list

**API:** `POST restful/tactical-overview/data` with `grouping_type` param.
Fields: `*_ok_count`, `*_ack_count`, `*_warn_count`, `*_un_count`,
`*_crit_count`. Anomalies use `anom_threshold_*` prefix.

### Device List

**Main list** (Devices tab):
- Paginated: 50 per page, infinite scroll or "Load more"
- API: `POST restful/devices/list` with `recordStart`/`recordCount`
- Each row: device name, IP, type icon, alarm status
- Tap → device detail

**Search:**
- Search bar at top, debounced 300ms
- API: `POST restful/devices/find` with `name` param
- Results replace paginated list while searching
- Clear search returns to paginated view

**Filtered list** (from tactical):
- Category: `POST restful/category/device-list` with `id`
- Site: `POST restful/site/device-list` with `id`
- Same row layout, back navigation to group list

### Device Detail

**Route:** `/devices/:id`

**Header** — device name, type icon, IP, model/serial

**Alarm Status** — H/S/T/A badges (reused component from tactical rows)

**Active Incidents** — incidents for this device:
- Reuses `SwipeableIncidentRow` component
- Tap → incident detail

**Interfaces** (network devices only):
- Interface list with status indicators
- Name, speed, admin/oper status

**Performance link** — "View Performance" button (placeholder until M4)

---

## M4: Performance Charts + QR Scanning (v0.5.0)

### Performance Charts

**Route:** `/devices/:id/performance`

**Chart library:** Recharts (React-native, lightweight, Tailwind-friendly).
Chart.js as fallback.

**Category picker:**
- Dropdown fetching categories via `POST restful/devices/performance-category`
- Selecting a category fetches instances via
  `POST restful/devices/performance-instance-per-category`

**Time frame:** Fixed 24-hour window. No selector needed — all charts show
"Last 24 Hours".

**Chart rendering:**
- Line chart: time on X-axis, metric value on Y-axis
- Multiple series for batch metrics (e.g. CPU cores), labeled by
  `instanceDescr`
- Interface metrics: separate in/out lines (`value1`/`value2`)
- Y-axis label shows unit (%, MB, Mbps, ms, etc.)
- Touch/hover tooltip: exact value + timestamp

**Data fetching:**
- `POST restful/devices/timeseries-metrics` with `metricFilterStatGroup`,
  `metricFilterUnits`, `timeFrameFilterBy=time_offset`,
  `timeFrameFilterValue=Last 24 Hours`
- Batch fetching: single call per statGroup+units returns all matching
  metrics (same as iOS `fetchTimeSeriesBatch`)
- Empty-unit handling: use metric title as `metricFilterUnits`, corrected
  by `instanceDescr` parenthetical
- React Query caching with 60-second stale time

### QR Scanning

**Route:** `/scan` (accessible from Settings)

**Camera API:**
- `navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })`
  for rear camera
- QR decoding: `jsQR` library, or native `BarcodeDetector` API where
  available (Chrome Android)
- Full-screen overlay with viewfinder frame and cancel button

**Scan flow:**
1. Tap "Scan QR Code" in Settings
2. Camera opens with viewfinder
3. On decode, parse URL for server config (base URL, API key, PIN)
4. Confirmation screen: "Add this server?" with parsed values
5. On confirm, add to server list, optionally set active
6. Auto test-connection after adding

**No AES-GCM decryption** — plain URL parameters. The QR generator may need
a `--format=pwa` flag for unencrypted URLs, or a separate simple generator.

**Permission handling:**
- Camera denied → message explaining how to enable in browser settings
- Manual entry always available as fallback
