# PWA Settings — iOS Parity Design

**Date:** 2026-04-07
**Status:** Approved
**Approach:** Enhance existing ServerForm with conditional read-only mode (Approach A)

## Goal

Align the PWA settings screen with the iOS app's BHNM server configuration UX. QR-scanned servers lock their fields to read-only (except Server Name and Push toggle). Manual servers remain fully editable. Server switching requires confirmation. Save button tests connection before saving.

## Architecture

No new components. The existing `ServerForm.tsx` gains a read-only mode driven by `isQrProvisioned` on `ServerConfig`. Storage model gets three new fields. QR parser maps additional fields from the QR payload.

## Section 1: Storage Model Changes

### ServerConfig (serverStorage.ts)

Three new fields:

| Field | Type | Default | Sensitive | Purpose |
|---|---|---|---|---|
| `ackUser` | `string` | `""` | No | User name for incident ACK/UnACK operations |
| `bhnmUrl` | `string` | `""` | No | Direct BHNM server URL (display + X-BHNM-Target header) |
| `isQrProvisioned` | `boolean` | `false` | No | Whether server was added via QR scan; controls field editability |

`NewServerInput` gets the same three fields (all optional).

### BhnmConfig (config.ts)

Add `ackUser: string` and `bhnmUrl: string`, populated from the active server in `buildSnapshot()`.

### Migration

Existing servers get `ackUser: ""`, `bhnmUrl: ""`, `isQrProvisioned: false`. No migration code needed — the fields are optional with defaults. `loadServers()` already handles missing fields gracefully via object spread.

## Section 2: QR Parser Changes

### Field Mapping (qr-parser.ts)

Current → New mapping from QR JSON payload:

| QR Field | Current Target | New Target |
|---|---|---|
| `bhnm_url` | `baseUrl` | `bhnmUrl` |
| `middleware_url` | `pushMiddlewareUrl` | `baseUrl` |
| `user` | (not extracted) | `ackUser` |

If `middleware_url` is absent in the QR payload, fall back to `bhnm_url` as `baseUrl`.

### ParsedServerConfig

Updated interface:

```typescript
interface ParsedServerConfig {
  name: string;
  baseUrl: string;         // from middleware_url (or bhnm_url fallback)
  bhnmUrl: string;         // from bhnm_url
  apiKey: string;
  pin?: string;
  ackUser?: string;        // from user
  pushWebhookSecret?: string;
}
```

The `pushMiddlewareUrl` field is removed from `ParsedServerConfig` — `baseUrl` now always points to the middleware.

## Section 3: ServerForm UI Changes

### Read-Only Mode (QR-provisioned servers)

When `isQrProvisioned && editing`:
- **Editable:** Server Name (text input), Enable Push Notifications (toggle)
- **Read-only:** BHNM URL, Middleware URL, API Token, PIN / License ID, User Name, Webhook Secret
- Read-only fields rendered as styled text (not disabled inputs) with muted color
- Sensitive read-only fields fully masked: API Token as `••••••••`, PIN as `••••••`, Webhook Secret as `••••••••••••`
- Footer text: "Configured via QR code. Scan again to update."

### Manual Servers

All fields are editable text/password inputs, same as current behavior but with new fields added:
- BHNM URL (text input)
- Middleware URL (text input, replaces current "Push Middleware URL")
- User Name (text input, placeholder "For incident ACK/UnACK")
- Footer text: "Stored in your browser only."

### Field Order (both modes)

1. Server Name
2. BHNM URL
3. Middleware URL
4. API Token
5. PIN / License ID
6. User Name
7. Enable Push Notifications (toggle)
8. Webhook Secret

### Buttons

Single **Save** button (green) at bottom. Replaces current separate "Test Connection" and "Save" buttons.

**Delete Server** button (red outline) below Save. Edit mode only.

## Section 4: Save Button Behavior

### Flow

1. User taps Save
2. Button shows spinner with "Testing connection..."
3. POST to `/api/proxy/ha-status` with `X-Proxy-Token` header
4. **Success:** Save config, dismiss form, return to server list
5. **Failure:** Show red error banner below button, do NOT save, keep form open

### Disabled States

Save button is disabled when:
- Test in progress
- API Key is empty (manual servers only — QR servers always have one)
- Manual server with push enabled but Webhook Secret empty

### Delete Button

Shows confirmation dialog ("Delete [Server Name]?") before deleting. Same two-tap pattern currently used in the server list.

## Section 5: Server Switch Confirmation

When user taps an inactive server in the server list:

1. Dark overlay appears (semi-transparent black)
2. Dialog shows: server name, "Switch to this server?"
3. Two buttons: **Cancel** (secondary) and **Switch** (primary)
4. Switch calls `setActiveServer(id)` then triggers data refresh

Replaces current instant-switch-on-click behavior.

## Section 6: QR Confirm Screen Changes

### New Fields Displayed

The QR confirmation screen (`QRConfirmScreen`) now shows:
- Server Name
- BHNM URL (new)
- Middleware URL (new, labeled as such)
- API Token (masked)
- PIN (masked, if present)
- User Name (new, if present)
- Webhook Secret (masked, if present)

### Saving

When user confirms:
- Set `isQrProvisioned: true` on the server config
- Pass `ackUser` and `bhnmUrl` through to `addServer()` / `updateServer()`

### Duplicate Detection

Match by `bhnmUrl` (case-insensitive) instead of current `baseUrl` match. The BHNM URL uniquely identifies a server instance. Fall back to `baseUrl` for legacy QR codes that don't contain `bhnm_url`.

## Section 7: ACK/UnACK Integration

In `pwa/src/lib/api/incidents.ts`:
- `acknowledgeIncident()`: replace hardcoded `user: 'BeNeM PWA'` with `config.ackUser || 'BeNeM PWA'`
- `unacknowledgeIncident()`: same change

## Files Changed

| File | Change |
|---|---|
| `pwa/src/lib/serverStorage.ts` | Add `ackUser`, `bhnmUrl`, `isQrProvisioned` to `ServerConfig` and `NewServerInput` |
| `pwa/src/lib/config.ts` | Add `ackUser`, `bhnmUrl` to `BhnmConfig`, populate in `buildSnapshot()` |
| `pwa/src/lib/qr-parser.ts` | Map `bhnm_url` → `bhnmUrl`, `middleware_url` → `baseUrl`, `user` → `ackUser`; remove `pushMiddlewareUrl` from `ParsedServerConfig` |
| `pwa/src/features/settings/ServerForm.tsx` | Read-only mode for QR servers, new fields (BHNM URL, Middleware URL, User Name), single Save-with-test button, Delete button, masked sensitive values |
| `pwa/src/features/settings/SettingsScreen.tsx` | Server switch confirmation dialog, pass `isQrProvisioned` through QR flow |
| `pwa/src/features/settings/QRConfirmScreen.tsx` | Show new fields, set `isQrProvisioned: true`, duplicate detection by `bhnmUrl` |
| `pwa/src/lib/api/incidents.ts` | Use `config.ackUser` fallback to `'BeNeM PWA'` |

No middleware changes. No iOS changes. No new dependencies.
