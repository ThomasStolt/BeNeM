# Push Payload Specification

Defines every notification payload produced by `middleware/` and
consumed by `ios/` and `pwa/`. This is the contract between producer and
consumers — if you add a new payload type, update this file first.

---

## Webhook Input

BHNM sends a JSON POST to `middleware/webhook?secret=<value>` with:

```json
{
  "notification_type": "PROBLEM | RECOVERY | CONFIG_CHANGE | ACKNOWLEDGEMENT | DEACKNOWLEDGEMENT | WARNING | CRITICAL",
  "hostname": "device-name",
  "host_state": "UP | DOWN | UNREACHABLE",
  "site": "site-name",
  "service_desc": "service description",
  "output": "status output text",
  "incident_id": "42"
}
```

`hostname` is the only required field — a decoded body with an empty `hostname` is rejected `422`
(middleware 2.11.1+). The body may arrive form-encoded rather than JSON; the route falls back.

Those seven `notification_type` values are BHNM's documented `{NOTIFICATIONTYPE}` set (BHNM 26.3,
Alert Template Administration → Available Macros), not a BeNeM invention. `host_state` values are
BHNM's documented `{HOSTSTATE}` set.

BHNM's macro reference documents the fifth value as `UNACKNOWLEDGEMENT`; the wire carries
**`DEACKNOWLEDGEMENT`**. Accept both spellings.

Six of the seven are handled (middleware 2.13.0). `CONFIG_CHANGE` falls through to the PROBLEM
branch; handling it is an open spec item.

On an `ACKNOWLEDGEMENT`, BHNM sets `host_state` to the literal `ACKNOWLEDGEMENT` rather than a host
state; `primary_alarm_status` still carries the true `DOWN`. On a `DEACKNOWLEDGEMENT` it leaves
`host_state` at `DOWN`, which is why that type must never reach the problem branch.

The middleware transforms this into platform-specific payloads below.

---

## APNs Payload (iOS)

Sent via HTTP/2 to Apple Push Notification Service.

```json
{
  "aps": {
    "alert": { "title": "<title>", "body": "<body>" },
    "sound": "default"
  },
  "incident_id": "<id>"
}
```

### Title/Body construction by notification type

| `notification_type` | Title | Body |
|---|---|---|
| `PROBLEM` / `CRITICAL` / `WARNING` | `🔴 {hostname} — {host_state}` (DOWN/UNREACHABLE) or `⚠️ {hostname} — {host_state}`; from the second notice on, `— still {host_state} (notice {n})` where `{n}` is `notification_number` | `{service_desc \| output} \| Site: {site}` |
| `RECOVERY` | `Resolved: {hostname}` | `{service_desc \| "Host"} recovered. {output}` |
| `ACKNOWLEDGEMENT` | `Acknowledged: {hostname}` | `{output \| service_desc \| host_state}` |
| `DEACKNOWLEDGEMENT` / `UNACKNOWLEDGEMENT` | `Unacknowledged: {hostname}` | `{output \| primary_alarm_status}` |

### iOS deep link

Tapping the notification posts `Notification.Name.pushNotificationIncidentTapped`
via `NotificationCenter` with `incident_id` in `userInfo`. `ContentView` switches
to the Incidents tab and navigates to `IncidentDetailView`.

**Cold launch:** `AppDelegate.shared.pendingIncidentID` is read in `ContentView.onAppear`.

---

## Web Push Payload (PWA / Android)

Sent via VAPID-signed Web Push to the browser push service.

```json
{
  "title": "<title>",
  "body": "<body>",
  "incident_id": "<id>"
}
```

Title and body are constructed identically to the APNs payload above.

### PWA deep link

The service worker stores `incident_id` in the notification's `data` property.
On `notificationclick`, `sw.ts` focuses an existing client (or opens a new one)
and posts `{ type: 'navigate', url: '/incidents/{incident_id}' }`; `App.tsx`
reads `event.data.url` and routes to the `/incidents/:id` detail view.

---

## Adding a new notification type

1. Update this spec with the new payload shape
2. Implement in `middleware/main.py` (webhook handler)
3. Update `middleware/webpush.py` `build_payload()` if the Web Push shape changes
4. Update iOS `AppDelegate.swift` notification handler if new custom data fields are added
5. Update PWA `sw.ts` push event handler if new fields are added
