# Push Payload Specification

Defines every notification payload type produced by `middleware/` and
consumed by `ios/` and `pwa/`. This is the contract between producer and
consumers — if you add a new payload type, update this file first.

## Payload template

### Type: [name]
**Trigger:** [what causes this notification]

```json
{
  "type": "[name]",
  "incident_id": "string",
  "severity": "critical | high | medium | low",
  "title": "string",
  "body": "string"
}
```

**iOS deep link:** `benem://[path]`
**PWA deep link:** `/[path]`

---

## Payload types

### Type: incident_opened
**Trigger:** New incident created in BHNM. Current APNs payload format in production.

```json
{
  "aps": {
    "alert": { "title": "string", "body": "string" },
    "sound": "default"
  },
  "incident_id": "<id>"
}
```

**iOS deep link:** tapping the notification posts `Notification.Name.pushNotificationIncidentTapped` via `NotificationCenter` with the `incident_id` in `userInfo`. `ContentView` switches to the Incidents tab and navigates to `IncidentDetailView`.

**PWA deep link:** `/incident/{incident_id}` (not yet implemented)

**Cold launch (iOS):** `AppDelegate.shared.pendingIncidentID` is read in `ContentView.onAppear`.
