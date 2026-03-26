# Multi-Server Push Notification Routing

**Date:** 2026-03-26
**Status:** Approved

## Problem

BeNeM supports multiple BHNM servers via `SavedConnection`, but push notification settings (`push_middleware_url`, `push_middleware_secret`) are global. When two servers both send webhooks to the same middleware, the iPhone receives notifications from both — even when the user is only actively monitoring one server.

## Goal

A device only receives push notifications from the server it is currently connected to. Switching servers must immediately update routing with no manual steps.

## Constraints

- Multiple iPhones can be connected to the same server simultaneously — all should receive notifications for that server.
- A single device is always active on exactly one server at a time.
- The middleware (`bhnm-apns`) can be modified.
- `push_middleware_url` remains a global setting (one middleware instance serves all servers).

## Chosen Approach: Active-Secret Tracking

Each `SavedConnection` stores its own webhook secret. The middleware tracks one `active_secret` per device. Incoming webhooks are only forwarded to devices whose `active_secret` matches the webhook's secret.

---

## Architecture

```
BHNM Server A (secret_A) ──► /webhook?secret=secret_A ──► middleware ──► iPhones with active_secret=secret_A
BHNM Server B (secret_B) ──► /webhook?secret=secret_B ──► middleware ──► iPhones with active_secret=secret_B
```

---

## Components

### 1. `SavedConnection` (iOS — `SavedConnection.swift`)

Add one field:

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var pin: String
    var ackUser: String
    var webhookSecret: String   // "" = push notifications disabled for this server
}
```

The global `push_middleware_secret` AppStorage key is deprecated. Existing installations migrate gracefully: if a connection has no `webhookSecret`, it defaults to `""` (no push notifications) until the user enters one.

### 2. `SettingsView` (iOS — `SettingsView.swift`)

- Remove the global "Webhook Secret" field from the Push Notifications section.
- Add a "Webhook Secret" field inside the BHNM Server section, below ACK User.
- The field loads/saves from `draftWebhookSecret` draft state, persisted into `SavedConnection.webhookSecret` on successful test/save.
- The Push Notifications section retains only the Middleware URL field.

### 3. `AppDelegate` (iOS — `AppDelegate.swift`)

Update `registerWithMiddleware(token:)` to accept a secret parameter:

```swift
func registerWithMiddleware(token: String, secret: String)
```

- If `secret` is empty, skip registration (log a message).
- Pass the secret as `X-Webhook-Token` header (existing behaviour, now per-connection).
- Cache the most recently received APNs device token in a property so it can be used when re-registering after a server switch.

### 4. Server-Switch Re-Registration (iOS — `ContentView` or new `PushRegistrationService`)

Observe `netreo_active_connection_id` changes. On change:

1. Load the new `SavedConnection` from UserDefaults.
2. Read its `webhookSecret`.
3. Call `AppDelegate.shared.registerWithMiddleware(token: cachedToken, secret: newSecret)`.

This ensures the middleware is updated immediately when the user switches servers.

### 5. Middleware — `/register` endpoint (`bhnm-apns`)

**Current behaviour:** stores `{token, device_name}`.

**New behaviour:** upsert `{token, device_name, active_secret}` where `active_secret` is taken from the `X-Webhook-Token` header of the registration request.

```
POST /register
Header: X-Webhook-Token: <secret>
Body: { "token": "...", "device_name": "..." }
```

- If a record for this token already exists → update `active_secret` and `device_name`.
- If not → insert new record.

### 6. Middleware — `/webhook` endpoint (`bhnm-apns`)

**Current behaviour:** forward to all registered tokens.

**New behaviour:** forward only to tokens where `active_secret == secret` (the secret from the query parameter).

```
POST /webhook?secret=<secret>
```

Filter: `SELECT token FROM devices WHERE active_secret = ?`

---

## Data Flow: Server Switch

```
User selects Server B in Settings
        │
        ▼
ContentView.onChange(netreo_active_connection_id)
        │
        ▼
Load SavedConnection for Server B → webhookSecret = secret_B
        │
        ▼
AppDelegate.registerWithMiddleware(token: cachedToken, secret: secret_B)
        │
        ▼
POST /register  (X-Webhook-Token: secret_B)
        │
        ▼
Middleware upserts: { token: cachedToken, active_secret: secret_B }
        │
        ▼
Server A webhooks → filtered out (active_secret ≠ secret_A)
Server B webhooks → forwarded ✓
```

---

## Error Handling

- **Registration fails (network error):** Log the error. The app does not retry automatically — the next app launch will re-register. This is acceptable: the user has switched servers and is actively using it; a missed registration is a rare edge case.
- **Empty webhookSecret:** Skip registration silently. No push notifications for that server. The user can add a secret later in Settings.
- **Middleware returns non-200:** Log the status code. No user-facing error (push notifications are non-critical).

---

## Migration

- Existing `SavedConnection` records decode without `webhookSecret` → Swift default value `""` → no push notifications until user configures a secret.
- The global `push_middleware_secret` AppStorage key is ignored after this change. No active migration needed; the key simply becomes unused.

---

## Out of Scope

- Unregister endpoint: not needed. Re-registration with a new secret implicitly deactivates the old one.
- Per-server middleware URL: not needed. One middleware instance handles all servers.
- Notification Service Extension: not needed with server-side filtering.
