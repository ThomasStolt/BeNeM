# API Proxy via bhnm-apns Middleware

**Date:** 2026-03-26
**Status:** Approved

## Problem

BeNeM communicates with BHNM servers directly from the iOS app. BHNM is typically deployed on a private corporate network with no internet access. Users on mobile networks or outside the corporate network cannot reach BHNM at all.

## Goal

Route all BHNM API calls through the `bhnm-apns` middleware, which is deployed on-premises with access to both the internet and the BHNM private network. The iPhone talks to the middleware; the middleware proxies requests to BHNM.

## Constraints

- One middleware instance per private network (one deployment per separate network).
- Credentials (`password`, `pin`) remain on the client and pass through transparently — the middleware does not hold or inspect them.
- Deployment must stay a single Docker container; no new services or ports.
- Push notification flow (`BHNM → middleware → APNs → iPhone`) is unchanged.
- The existing `webhookSecret` per `SavedConnection` is reused for proxy authentication — no new credential.

---

## Architecture

```
iPhone (BeNeM)
    │  HTTPS — all API calls + push registration
    ▼
bhnm-apns middleware  (Docker, on-premises, internet-accessible)
    │  HTTP/HTTPS — proxied API calls (same LAN)
    ▼
BHNM server  (private network)

BHNM server ──webhook──► middleware ──APNs──► iPhone   (unchanged)
```

Each `SavedConnection.baseURL` holds the middleware URL. The middleware resolves its BHNM target from `BHNM_URL` in `.env`. One middleware deployment serves one BHNM network.

---

## Components

### 1. iOS — `SavedConnection.swift`

Remove the `pushMiddlewareURL` field. `baseURL` now serves both roles: API proxy and push registration (`/register`).

```swift
struct SavedConnection: Codable, Identifiable {
    let id: UUID
    var name: String
    var symbol: String
    var accentColor: String
    var baseURL: String       // middleware URL — used for all communication
    var apiKey: String
    var pin: String
    var ackUser: String
    var webhookSecret: String // proxy auth + push routing secret
}
```

`webhookSecret` defaults to `""` for new connections. Existing persisted JSON that contains `pushMiddlewareURL` decodes cleanly — Swift ignores unknown keys. `saveConnection()` no longer writes `pushMiddlewareURL`.

In addition to removing `pushMiddlewareURL` from the struct, `saveConnection()` must also write `webhookSecret` to a standalone AppStorage key `netreo_webhook_secret`. `selectConnection(_:)` must also write this key when switching the active connection (not just on save). Both write paths are needed so `ContentView` always has an up-to-date value when the active connection changes (see Component 4).

### 2. iOS — `AppDelegate.swift`

The existing signature is kept (parameter labels unchanged):

```swift
func registerWithMiddleware(token: String, secret: String, middlewareURL: String)
```

Update all reads of `conn.pushMiddlewareURL` to `conn.baseURL`:

- **`activeConnectionPushCredentials()`** — returns `(conn.webhookSecret, conn.baseURL)` instead of `(conn.webhookSecret, conn.pushMiddlewareURL)`. This covers the cold-start APNs registration path (`didRegisterForRemoteNotificationsWithDeviceToken`).

- **`ContentView.onChange(activeConnectionID)`** — this observer is in `ContentView`, which already has `@AppStorage("netreo_active_connection_id")` driving this change. Pass `middlewareURL: conn.baseURL`:
  ```swift
  AppDelegate.shared?.registerWithMiddleware(
      token: cachedToken,
      secret: conn.webhookSecret,
      middlewareURL: conn.baseURL    // was: conn.pushMiddlewareURL
  )
  ```

### 3. iOS — `NetreoAPIConfiguration.swift`

Add `proxyToken` to the struct and initializer:

```swift
struct NetreoAPIConfiguration {
    let baseURL: String
    let apiKey: String
    let pin: String?
    let proxyToken: String     // from SavedConnection.webhookSecret
    let version: APIVersion
    let timeout: TimeInterval
    let retryCount: Int

    init(baseURL: String, apiKey: String, pin: String? = nil,
         proxyToken: String = "",
         version: APIVersion = .legacy,
         timeout: TimeInterval = 30,
         retryCount: Int = 3) { ... }
}
```

### 4. iOS — `ContentView.swift`

Add `@AppStorage("netreo_webhook_secret") private var webhookSecret = ""`. This key is written by both `saveConnection()` and `selectConnection(_:)` (see Component 1) so it stays current whenever the active connection changes or is edited.

`updateAPIService()` passes `proxyToken`:

```swift
NetreoAPIConfiguration(
    baseURL: baseURL,
    apiKey: apiKey,
    pin: pin.isEmpty ? nil : pin,
    proxyToken: webhookSecret
)
```

### 5. iOS — `NetreoAPIService.swift`

Add a single private helper:

```swift
private func addProxyToken(_ request: inout URLRequest) {
    guard !configuration.proxyToken.isEmpty else { return }
    request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
}
```

Call this helper in every method that constructs a `URLRequest` before passing it to `urlSession.data(for:)`.

### 6. iOS — `ServerConfigView.swift`

- Remove `draftPushURL` draft-state variable and its "Middleware URL" text field.
- Remove the `pushEnabled` Toggle. `webhookSecret` is now required for all API calls (not just push notifications). Display the "Webhook Secret" `SecureField` unconditionally in the server configuration section.
- `populateDrafts()` must unconditionally set `draftPushSecret = conn.webhookSecret` (was gated on `pushEnabled`).
- Rename the "Server URL" label to **"Middleware URL"** with hint: `e.g. https://bhnm-apns.yourcompany.com`.
- Remove all reads/writes of the `push_middleware_url` AppStorage key. Also audit `SettingsView.swift` for any remaining reference to this key and remove it.
- Update the `disabled(...)` condition on the Save/Test button to include `draftWebhookSecret.isEmpty`. **This is a forced migration:** existing connections with no webhook secret cannot be re-saved until the user adds one. This is intentional — a secret is required for the middleware to accept any API call. Document this in release notes.
- Update `testAndSave()` to manually add the `X-Proxy-Token` header (this request bypasses `NetreoAPIService`) and target the middleware's proxied BHNM path — `draftBaseURL/fw/index.php?r=restful/devices/list` — which is correct, since the middleware will proxy this to BHNM:
  ```swift
  request.setValue(draftWebhookSecret, forHTTPHeaderField: "X-Proxy-Token")
  ```
  If `draftWebhookSecret` is empty the button is disabled, so this line always has a non-empty value when reached. The test verifies the full chain: app → middleware → BHNM.

### 7. iOS — `DeepLinkHandler.swift`

Remove `pushMiddlewareURL` from `PendingImport`:

```swift
struct PendingImport {
    let server: String
    let key: String
    let pin: String
    let pushSecret: String
    // pushMiddlewareURL removed
}
```

Update `handleCompactPayload`:
- Remove the read of `"push_url"` from the payload dict.
- `PendingImport` is constructed without `pushMiddlewareURL`.

Update `applyPendingImport()`:
- Remove the write to `conn.pushMiddlewareURL`.
- `imp.server` continues to write to `conn.baseURL` (already done).

The legacy (non-compact) URL format is deprecated. `handle(url:)` may continue to parse it for backwards compatibility but the `push_url` field is ignored.

### 8. iOS — `AutoDiscoveryView.swift`

AutoDiscovery scans the local /24 subnet for BHNM servers via SNMP. The app's `baseURL` must be a middleware URL; AutoDiscovery cannot discover middleware instances.

- Remove (or disable) the "Connect" button that currently writes `baseURL = server.baseURL` directly.
- Display discovered servers as read-only with a label: "This is the BHNM server address. Enter your middleware URL in Settings."
- `NetworkDiscovery` itself is unchanged.

### 9. Middleware — `.env`

Add:

```
BHNM_URL=http://192.168.x.x        # no trailing slash; include port if non-standard
BHNM_TLS_VERIFY=true               # set to false if BHNM uses a self-signed certificate
```

The proxy strips any trailing slash from `BHNM_URL` at startup to prevent double-slash URLs.

### 10. Middleware — Catch-all proxy route (`bhnm-apns`)

Register specific routes (`/register`, `/webhook`) **before** the catch-all to ensure they take precedence:

```python
import os
import httpx

HOP_BY_HOP_REQUEST  = {"host", "x-proxy-token", "connection", "keep-alive",
                        "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade"}
HOP_BY_HOP_RESPONSE = {"connection", "keep-alive", "proxy-authenticate",
                        "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"}

BHNM_URL = os.getenv("BHNM_URL", "").rstrip("/")
BHNM_TLS_VERIFY = os.getenv("BHNM_TLS_VERIFY", "true").lower() != "false"

# Existing /register and /webhook routes are defined first (unchanged).
# The catch-all below matches everything else.

@app.route("/<path:path>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path):
    token = request.headers.get("X-Proxy-Token", "")
    if token != WEBHOOK_SECRET:
        return {"error": "Unauthorized"}, 401

    target = f"{BHNM_URL}/{path}"
    if request.query_string:
        target += f"?{request.query_string.decode()}"

    forward_headers = {
        k: v for k, v in request.headers
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY) as client:
        resp = await client.request(
            method=request.method,
            url=target,
            headers=forward_headers,
            content=await request.get_data(),
        )

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }

    return resp.content, resp.status_code, response_headers
```

Key properties:
- **Route priority:** `/register` and `/webhook` are defined first; the catch-all does not intercept them.
- **Authentication:** `X-Proxy-Token` checked against `WEBHOOK_SECRET`. Returns 401 if missing or wrong.
- **Hop-by-hop headers stripped** in both directions to prevent transport-layer failures.
- **TLS to BHNM:** controlled by `BHNM_TLS_VERIFY`. BHNM API responses do not include `Set-Cookie`; multi-value header collapsing is safe.
- **No route mapping:** all current and future BHNM endpoints work automatically.

---

## Data Flow

```
App builds URLRequest to middleware URL + BHNM path
        │
        ▼
addProxyToken injects X-Proxy-Token: <webhookSecret>
        │
        ▼
POST https://bhnm-apns.yourcompany.com/fw/index.php?r=restful/devices/list
Body: password=<apiKey>&pin=<pin>&...
        │
        ▼
Middleware authenticates X-Proxy-Token, strips hop-by-hop request headers
        │
        ▼
Middleware forwards to http://192.168.x.x/fw/index.php?r=restful/devices/list
        │
        ▼
BHNM responds → middleware strips hop-by-hop response headers → returns to app
```

---

## Authentication

| Leg | Mechanism |
|---|---|
| App → middleware | `X-Proxy-Token: <webhookSecret>` header |
| Middleware → BHNM | `password=<apiKey>` + `pin=<pin>` in request body (pass-through) |
| BHNM → middleware (webhook) | `?secret=<webhookSecret>` query param (unchanged) |

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Missing / wrong `X-Proxy-Token` | Middleware returns 401. App surfaces a connection error. |
| Empty `webhookSecret` at save time | Save/Test button disabled. User cannot save without a secret. |
| BHNM unreachable from middleware | `httpx` raises a connection error → middleware returns 502. App surfaces a connection error. |
| BHNM TLS error (self-signed cert) | Set `BHNM_TLS_VERIFY=false` in middleware `.env`. |
| BHNM returns non-200 | Response passed through as-is. App handles it as today. |

---

## Deep Link Provisioning (`generate_benem_link.py`)

The compact payload (`p=` format) currently encodes `server` (BHNM URL) and `push_url` (middleware URL) as separate fields. These collapse into one: `server` is the middleware URL.

**Changes to `generate_benem_link.py`:**
- Rename `--bhnm-server` to `--middleware-url`.
- Remove `--push_url` (redundant).
- Compact payload encodes: `server` (middleware URL), `key`, `pin`, `push_secret`.

**Changes to `DeepLinkHandler.swift`:** covered in Component 7 above.

Old links will import with `baseURL` set to the BHNM URL (not the middleware), which will not work. Users must regenerate links after updating.

---

## Migration

| Item | Action |
|---|---|
| `SavedConnection.pushMiddlewareURL` | Field removed. Existing persisted JSON decodes without it (Swift ignores unknown keys). No migration pass needed. |
| Existing `baseURL` (BHNM URL) | User must update to middleware URL in Settings. One-time manual step per connection. |
| `push_middleware_url` AppStorage key | Unused. Not actively removed; references in Settings views must be audited and removed. |
| `webhookSecret` | Already per-connection. Save button disabled until configured. |
| Existing deep links | Must be regenerated with `--middleware-url`. Old links import an incorrect `baseURL`. |

---

## Future: Smart Caching

The proxy function is the single insertion point for a caching layer:

- Check cache before forwarding to BHNM; populate on successful response.
- Cache selectively: incident lists and tactical overview are good candidates; time-series metrics are not.
- **On-device LLM prefetch:** the app sends an `X-Prefetch` hint header with predicted next requests; the middleware warms the cache proactively. No structural changes needed when this is added.

---

## Out of Scope

- Middleware holding BHNM credentials (pass-through only).
- Multiple BHNM servers per middleware instance.
- Response transformation or aggregation.
- Rate limiting.
- Smart caching (future, described above).
- AutoDiscovery discovering middleware instances.
