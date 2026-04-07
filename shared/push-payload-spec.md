# Push Payload Specification

Defines every notification payload produced by `middleware/` and
consumed by `ios/` and `pwa/`. This is the contract between producer and
consumers — if you add a new payload type, update this file first.

---

## Webhook Input

BHNM sends a JSON POST to `middleware/webhook?secret=<value>` with:

```json
{
  "notification_type": "PROBLEM | RECOVERY | ACKNOWLEDGEMENT",
  "hostname": "device-name",
  "host_state": "DOWN | UNREACHABLE | UP | ...",
  "site": "site-name",
  "service_desc": "service description",
  "output": "status output text",
  "incident_id": "42"
}
```

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
| `PROBLEM` / `CRITICAL` / `WARNING` | `🔴 {hostname} — {host_state}` (DOWN/UNREACHABLE) or `⚠️ {hostname} — {host_state}` | `{service_desc \| output} \| Site: {site}` |
| `RECOVERY` | `Resolved: {hostname}` | `{service_desc \| host_state} recovered. {output}` |
| `ACKNOWLEDGEMENT` | `Acknowledged: {hostname}` | `{output \| service_desc \| host_state}` |

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
On `notificationclick`, the PWA navigates to `/incident/{incident_id}`.

---

## Adding a new notification type

1. Update this spec with the new payload shape
2. Implement in `middleware/main.py` (webhook handler)
3. Update `middleware/webpush.py` `build_payload()` if the Web Push shape changes
4. Update iOS `AppDelegate.swift` notification handler if new custom data fields are added
5. Update PWA `sw.ts` push event handler if new fields are added
