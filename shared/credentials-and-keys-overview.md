# BeNeM — Credentials, Keys & Tokens Overview

> Seed document for a PowerPoint presentation explaining all secrets in the BeNeM + bhnm-apns system.

---

## System Overview

```
┌──────────────┐     benem:// QR code      ┌──────────────────┐
│  BeNeM Admin │  ─────────────────────►   │   BeNeM iOS App  │
│  (Web Portal)│                            │   (iPhone)       │
└──────┬───────┘                            └────┬────────┬────┘
       │                                         │        │
       │ same server                   /register │        │ BHNM API proxy
       ▼                                         ▼        ▼
┌──────────────────────────────────────────────────────────────┐
│                    bhnm-apns Middleware                       │
│                    (Docker on VPS)                            │
└──────┬──────────────────────────────┬────────────────────────┘
       │                              │
       │ APNs (HTTP/2)                │ BHNM API
       ▼                              ▼
┌──────────────┐              ┌──────────────┐
│  Apple Push  │              │  BHNM Server │
│  Notification│              │  (on-prem)   │
│  Service     │              │              │
└──────────────┘              └──────────────┘
```

---

## 1. Apple Push Notification Keys

These credentials allow the middleware to send push notifications to iPhones via Apple's APNs service.

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **APNs Auth Key (.p8)** | Private key for signing APNs JWT tokens | Middleware `.env` as `APNS_PRIVATE_KEY_B64` (base64-encoded) | Apple Developer Portal → Keys → New Key → APNs |
| **APNs Key ID** | Identifies which .p8 key is being used (10 chars) | Middleware `.env` as `APNS_KEY_ID` | Shown when creating the key in Apple Developer Portal |
| **APNs Team ID** | Your Apple Developer Team identifier (10 chars) | Middleware `.env` as `APNS_TEAM_ID` | Apple Developer Portal → Membership |
| **APNs Bundle ID** | The app's bundle identifier | Middleware `.env` as `APNS_BUNDLE_ID` | Must match Xcode project: `com.tstolt.benem` |

**Important:** The .p8 key must be configured as **"Sandbox & Production"** in Apple Developer Portal. A sandbox-only key cannot send to TestFlight/App Store devices.

**Flow:**
```
Middleware uses .p8 key + Key ID + Team ID
    → signs a JWT token
    → sends notification to APNs with JWT + device token
    → APNs delivers to iPhone
```

---

## 2. APNs Device Token

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **APNs Device Token** | 64-char hex string identifying one iPhone for push | Middleware DB (`device_tokens.token`) + iOS memory | iOS generates it automatically when app registers for push |

**Not a secret** — useless without the .p8 key. Changes on app reinstall or iOS update.

Each token is stored with an **environment** (`sandbox` or `production`):
- Xcode/Debug builds → `sandbox` → routed to `api.sandbox.push.apple.com`
- TestFlight/App Store builds → `production` → routed to `api.push.apple.com`

---

## 3. Webhook Secret

The shared secret linking a BHNM server to its registered devices.

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **Webhook Secret** | 64-char hex string (256-bit) | 3 places (see below) | `openssl rand -hex 32` |

**Lives in three places:**

| Location | File / Field | How It Gets There |
|---|---|---|
| **BHNM Server** | Webhook URL: `https://middleware/webhook?secret=<THIS>` | Admin configures it manually in BHNM |
| **Middleware DB** | `device_tokens.active_secret` column | iOS/PWA app sends it during `/register` |
| **iOS App** | `SavedConnection.webhookSecret` (in UserDefaults) | QR code (`push_secret` field) or manual entry in Settings |
| **PWA** | `server.pushWebhookSecret` (in localStorage) | QR code or manual entry in Settings |
| **BeNeM Admin** | `.env` as `WEBHOOK_SECRET` | Default secret embedded in generated QR codes |

**There is no global `WEBHOOK_SECRET` in the middleware runtime.** The `.env` variable is only read by the BeNeM Admin portal for QR code generation. The middleware itself routes purely by the per-device `active_secret` stored in SQLite.

**Flow:**
```
BHNM incident → webhook POST to middleware with ?secret=ABC
    → middleware looks up all device tokens WHERE active_secret = 'ABC'
    → sends push to only those matching devices
```

This enables **per-server routing**: each BHNM server has its own secret, so only devices connected to that server receive its alerts.

---

## 4. BHNM API Key

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **API Key** | Password for authenticating BHNM API calls | iOS App: `SavedConnection.apiKey` | Created in BHNM admin panel |
| **PIN** (optional) | Additional auth factor for some BHNM APIs | iOS App: `SavedConnection.pin` | Created in BHNM admin panel |

**Lives in:**

| Location | File / Field |
|---|---|
| **iOS App** | `SavedConnection.apiKey` and `.pin` (UserDefaults JSON) |
| **Middleware** | `servers.json` (for admin portal server connectivity tests and proxy target resolution) |
| **QR Code Payload** | `api_key` and `pin` fields (AES-256-GCM encrypted) |

**Flow:**
```
iOS app sends BHNM API request with password=<apiKey> in POST body
    → if middleware configured: proxied via middleware (X-BHNM-Target header)
    → if direct: sent straight to BHNM server
```

---

## 5. Deep Link Encryption Key

The AES-256-GCM key used to encrypt/decrypt `benem://configure?p=...` QR code payloads.

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **Encryption Key** | 64-char hex string (256-bit AES key) | 2 places (see below) | `openssl rand -hex 32` |

**Lives in:**

| Location | File / Variable |
|---|---|
| **Middleware** | `.env` → `BENEM_SECRET_KEY` (read by `benem-admin/crypto.py`) |
| **iOS App** | `BeNeM/Secrets.swift` → `Secrets.encryptionKey` (hardcoded at build time) |

**These two values MUST match exactly**, otherwise the iOS app cannot decrypt QR code payloads.

**Flow:**
```
BeNeM Admin portal encrypts payload with BENEM_SECRET_KEY
    → generates QR code with benem://configure?p=<encrypted blob>
    → user scans QR with iPhone camera
    → BeNeM app decrypts with Secrets.encryptionKey
    → extracts: BHNM URL, API key, PIN, webhook secret, etc.
```

**What's inside the encrypted payload:**

| Field | Purpose |
|---|---|
| `bhnm_url` | Direct BHNM server URL |
| `middleware_url` | Push middleware URL |
| `api_key` | BHNM API key (encrypted!) |
| `pin` | BHNM PIN (encrypted!) |
| `user` | Default ACK username |
| `name` | Server display name |
| `push_secret` | Webhook secret for push registration |
| `proxy_token` | Token for API proxy requests (currently unused by iOS app) |
| `symbol` | SF Symbol icon name |
| `color` | Accent color hex code |
| `notifications` | Push notifications enabled (true/false) |

---

## 6. Proxy Token

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **Proxy Token** | Auth token for BHNM API proxy requests via middleware | Middleware `.env` as `PROXY_TOKEN` | `openssl rand -hex 32` |

**Status: Authentication temporarily disabled (April 2026).** A proper implementation is planned in `docs/superpowers/plans/2026-04-07-proxy-auth-hardening.md`. The plan adds a per-server `proxy_token` field to `servers.json` and validates `X-Proxy-Token` against it.

**Current state:**
- The QR code includes a `proxy_token` field (generated by BeNeM Admin)
- The iOS app does **not** parse `proxy_token` from QR — it reuses `webhookSecret` as the proxy token
- The PWA does **not** send an `X-Proxy-Token` header
- `SavedConnection` has no `proxyToken` field; `ContentView.swift` passes `webhookSecret` to `NetreoAPIConfiguration.proxyToken`

All three gaps are addressed in the hardening plan.

---

## 7. Admin Portal Authentication

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **TOTP Secret** | Base32 secret for time-based one-time passwords | Middleware `.env` as `TOTP_SECRET` | `python -c "import pyotp; print(pyotp.random_base32())"` |
| **Session Secret** | Signs admin portal session cookies | Middleware `.env` as `SESSION_SECRET` | `openssl rand -hex 32` |

**TOTP flow:**
```
Admin opens https://middleware/admin/
    → enters 6-digit code from Google Authenticator / 1Password
    → middleware validates against TOTP_SECRET
    → session cookie set (signed with SESSION_SECRET, valid 8 hours)
```

**Note:** `SESSION_SECRET` falls back to `BENEM_SECRET_KEY` if not set. Both should be configured independently.

**Rate limiting:** 5 login attempts per minute per IP address.

---

## 8. Caddy Basic Auth (optional)

| Credential | What It Is | Where It Lives | How It's Generated |
|---|---|---|---|
| **Basic Auth User** | HTTP basic auth username for `/admin` | Middleware environment as `$BASIC_AUTH_USER` | Manual |
| **Basic Auth Hash** | bcrypt hash of the password | Middleware environment as `$BASIC_AUTH_HASH` | `caddy hash-password` |

This is an **additional layer** on top of TOTP — Caddy enforces HTTP basic auth before the request even reaches the admin portal.

---

## Summary: Where Each Secret Lives

```
┌─────────────────────────────────────────────────────────────────────┐
│                        MIDDLEWARE SERVER                             │
│                                                                     │
│  .env file:                                                         │
│  ├── APNS_KEY_ID .............. Apple Push Key identifier            │
│  ├── APNS_TEAM_ID ............ Apple Developer Team ID              │
│  ├── APNS_BUNDLE_ID .......... App bundle ID                        │
│  ├── APNS_PRIVATE_KEY_B64 .... APNs .p8 key (base64)        🔴     │
│  ├── BENEM_SECRET_KEY ........ AES encryption key            🔴     │
│  ├── SESSION_SECRET .......... Admin session cookie signer   🟡     │
│  ├── TOTP_SECRET ............. Admin TOTP authenticator      🟡     │
│  ├── WEBHOOK_SECRET .......... Default secret for QR gen     🟡     │
│  ├── PROXY_TOKEN ............. API proxy token (disabled)    ⚪     │
│  └── DOMAIN .................. Public domain name            ⚪     │
│                                                                     │
│  servers.json:                                                      │
│  ├── api_key ................. BHNM API key per server       🔴     │
│  └── pin ..................... BHNM PIN per server            🟡     │
│                                                                     │
│  SQLite DB (device_tokens):                                         │
│  ├── token ................... APNs device token             ⚪     │
│  ├── active_secret ........... Webhook secret per device     🟡     │
│  └── apns_environment ........ sandbox / production          ⚪     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        iOS APP (BeNeM)                               │
│                                                                     │
│  Secrets.swift (hardcoded at build):                                │
│  └── encryptionKey ........... AES key (= BENEM_SECRET_KEY)  🔴    │
│                                                                     │
│  UserDefaults (SavedConnection JSON):                               │
│  ├── apiKey .................. BHNM API key                  🔴     │
│  ├── pin ..................... BHNM PIN                       🟡     │
│  ├── webhookSecret ........... Webhook secret                🟡     │
│  ├── middlewareURL ........... Middleware URL                 ⚪     │
│  ├── bhnmURL ................. Direct BHNM server URL        ⚪     │
│  └── ackUser ................. ACK username                   ⚪     │
│                                                                     │
│  Entitlements:                                                      │
│  ├── BeNeM.entitlements ...... aps-environment = development        │
│  └── BeNeM.release.entitlements  aps-environment = production       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

🔴 = Critical (compromise = full access)
🟡 = High (compromise = partial access)
⚪ = Low / not a secret
```

---

## Known Naming Inconsistencies

| Concept | Middleware Name | iOS App Name | QR Payload Name | Notes |
|---|---|---|---|---|
| Webhook secret | `WEBHOOK_SECRET` (env) / `active_secret` (DB) | `webhookSecret` | `push_secret` | 3 different names for the same value |
| Encryption key | `BENEM_SECRET_KEY` | `Secrets.encryptionKey` | — | OK — different contexts |
| Middleware URL | `MIDDLEWARE_URL` (env) | `middlewareURL` / `baseURL` (JSON key) | `middleware_url` | `baseURL` is a legacy JSON key for backward compat |
| BHNM URL | `url` (servers.json) | `bhnmURL` | `bhnm_url` | Consistent enough |
| API key | `api_key` (servers.json) | `apiKey` | `api_key` | Swift camelCase vs Python snake_case — expected |
| Proxy token | `PROXY_TOKEN` (env) | `proxyToken` (config) / `webhookSecret` (reused!) | `proxy_token` | iOS app ignores `proxy_token` from QR; reuses webhookSecret |

---

## Credential Lifecycle

| Event | What Happens |
|---|---|
| **New BHNM server added** | Generate webhook secret → configure in BHNM webhook URL + BeNeM app (or QR code) |
| **New iPhone onboarded** | Scan QR code → app decrypts → stores credentials → registers push token with middleware |
| **App launched** | APNs device token sent to middleware `/register` with webhook secret + environment |
| **Incident occurs** | BHNM → webhook → middleware matches secret → sends APNs to matching devices |
| **APNs key rotated** | Generate new .p8 in Apple Developer → update `APNS_KEY_ID` + `APNS_PRIVATE_KEY_B64` in `.env` → restart container |
| **Encryption key rotated** | Update `BENEM_SECRET_KEY` in `.env` + `Secrets.encryptionKey` in iOS → rebuild app + regenerate all QR codes |
| **Webhook secret rotated** | Update in BHNM webhook URL + BeNeM app settings (or new QR code) → devices re-register on next app launch |
