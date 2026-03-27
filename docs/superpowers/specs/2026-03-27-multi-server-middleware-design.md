# Spec: Multi-Server BHNM + Middleware Architecture

| Field | Value |
|---|---|
| Date | 2026-03-27 |
| Status | Approved |
| Affects | BeNeM iOS app, bhnm-apns middleware, generate_benem_link.py |

---

## Goal

Allow users to configure multiple BHNM server connections, each with its own BHNM URL and optional push-notification middleware. Switching connections updates all active credentials and push registration.

---

## Data Model — `SavedConnection`

Replace the current single `baseURL` field (which was the middleware URL) with two separate URL fields, and add a notifications toggle.

| Field | Type | Was | Notes |
|---|---|---|---|
| `bhnmURL` | String | new | Direct BHNM server URL, sent as `X-BHNM-Target` header |
| `middlewareURL` | String | `baseURL` | Push middleware base URL, used for all API proxy calls and `/register` |
| `notificationsEnabled` | Bool | new | Whether this connection registers for push notifications |
| `webhookSecret` | String | unchanged | Auth token for middleware proxy and push registration |
| `apiKey` | String | unchanged | BHNM API credential, sent in request body |
| `pin` | String | unchanged | Optional BHNM PIN |
| `ackUser` | String | unchanged | Username for ACK actions |
| `name`, `symbol`, `accentColor` | String | unchanged | Display fields |

### Migration

Existing connections have `baseURL` = old middleware URL, which maps to `middlewareURL`. `bhnmURL` defaults to `""`. `notificationsEnabled` defaults to `false` for migrated connections (since `bhnmURL` is unknown, push registration would be incomplete). It defaults to `true` only for newly created connections.

On app load, if the active connection has an empty `bhnmURL`, show an inline warning banner in the BHNM Servers section of Settings: "Tap to complete setup — BHNM URL required". The app must not attempt API calls with an empty `bhnmURL`.

---

## Networking — iOS App

### API Calls

All API calls (incidents, devices, ACK/UnACK, tactical, performance) are routed through the middleware, which proxies to BHNM:

```
Method + path → <middlewareURL>/<path>?<query>

Headers:
  X-Proxy-Token: <webhookSecret>    ← middleware auth (bearer style)
  X-BHNM-Target: <bhnmURL>          ← tells middleware which BHNM server to forward to

Body:
  password=<apiKey>&pin=<pin>&...   ← BHNM credentials, forwarded unchanged by middleware
```

No endpoint path changes are required — only the two additional headers are added to every request.

### Push Registration

```
POST <middlewareURL>/register
Headers:
  X-Webhook-Token: <webhookSecret>
Body JSON:
  { "token": "<apns_token>", "device_name": "<device_name>" }
```

Called on:
- App launch, if `notificationsEnabled` is `true` for the active connection.
- When switching to a connection that has `notificationsEnabled` set to `true`.

### Push Unregistration

```
DELETE <middlewareURL>/register
Headers:
  X-Webhook-Token: <webhookSecret>
Body JSON:
  { "token": "<apns_token>" }
```

Called when:
- User toggles `notificationsEnabled` OFF on the active connection.
- User switches away from a connection that had `notificationsEnabled` set to `true` (unregister from old middleware before registering with new).

---

## iOS App — Files Changed

### `SavedConnection.swift`

- Add `bhnmURL: String` (default `""`)
- Rename `baseURL` → `middlewareURL`
- Add `notificationsEnabled: Bool` (default `true`)
- Update `UserDefaults` encode/decode so new fields decode with defaults for backward compatibility (existing saved connections must load cleanly without migration errors)

### `NetreoAPIConfiguration.swift`

- Add `bhnmURL` field
- `baseURL` (used for building endpoint URLs) continues to point to `middlewareURL` — no endpoint path changes required
- All requests built by `NetreoAPIService` add two headers: `X-Proxy-Token` and `X-BHNM-Target`

### `NetreoAPIService.swift`

- Extend `addProxyToken(_:)` helper to also add `X-BHNM-Target: configuration.bhnmURL` header alongside the existing `X-Proxy-Token` header
- Every outbound request gains both headers; no other changes to request construction

### `ServerConfigView.swift`

UI redesigned into two sections.

**Section: "Connection"**

| Field | Control | Validation |
|---|---|---|
| Server Name | Text field | Required |
| BHNM URL | URL field | Required; auto-prepends `https://` if no scheme present |
| API Token | Secure field | Required |
| PIN / License ID | Secure field | Optional |
| User Name | Text field | Required |

**Section: "Push Notifications"** (always visible)

| Field | Control | Behaviour |
|---|---|---|
| Enable Push Notifications | Toggle | Controls whether this connection registers for push |
| Middleware URL | URL field | Auto-prepends `https://` if no scheme; greyed out when toggle is OFF |
| Webhook Secret | Secure field | Greyed out when toggle is OFF |

**Test & Save button:**

- Disabled if Server Name, BHNM URL, API Token, or User Name are empty.
- If `notificationsEnabled` is true, also disabled if Middleware URL or Webhook Secret are empty.
- Test action:
  - If notifications are enabled: hits `<middlewareURL>/fw/index.php?r=restful/devices/list` with both `X-Proxy-Token` and `X-BHNM-Target` headers.
  - If notifications are disabled: hits `<bhnmURL>/fw/index.php?r=restful/devices/list` directly (no middleware headers).

### `AppDelegate.swift`

- `registerWithMiddleware(token:secret:middlewareURL:)` — unchanged signature and logic
- New: `unregisterWithMiddleware(token:secret:middlewareURL:)` — sends `DELETE /register` with `X-Webhook-Token` header and JSON body `{ "token": "<apns_token>" }`
- `activeConnectionPushCredentials()` — reads `middlewareURL` and `webhookSecret` from the active connection (same logic; only the field name changes from `baseURL` to `middlewareURL`)
- On server switch:
  1. Call `unregisterWithMiddleware` for the old connection if `notificationsEnabled` was `true`.
  2. Call `registerWithMiddleware` for the new connection if `notificationsEnabled` is `true`.

### `DeepLinkHandler.swift`

**`PendingImport` struct additions:**

| Field | Type | Notes |
|---|---|---|
| `bhnmURL` | String | Decoded from `bhnm_url` key |
| `middlewareURL` | String | Decoded from `middleware_url` key |
| `notificationsEnabled` | Bool | Decoded from `notifications` key, default `true` |

**`handleCompactPayload` changes:**

- Read `bhnm_url` → `bhnmURL`
- Read `middleware_url` → `middlewareURL`
- Read `notifications` (bool, default `true`) → `notificationsEnabled`
- Backward compatibility: if the payload contains the old `server` key but no `bhnm_url`, treat `server` value as `middlewareURL` and leave `bhnmURL` empty (triggers migration banner on next launch)

**`applyPendingImport` changes:**

- Upsert match key: match existing connections by `bhnmURL` (case-insensitive). `middlewareURL` is intentionally not used as a match key since multiple connections may share the same middleware.
- Write `bhnmURL`, `middlewareURL`, and `notificationsEnabled` to the connection.
- Trigger push registration if `notificationsEnabled` is `true`.

### `SettingsView.swift`

- If the active connection has an empty `bhnmURL`, show an inline warning banner in the BHNM Servers section: **"Tap to complete setup — BHNM URL required"**
- Tapping the banner opens the edit view for that connection

---

## Middleware — `bhnm-apns`

### `main.py` — Proxy Route Changes

Current behaviour: reads `BHNM_URL` env var and `PROXY_SECRET` env var to authenticate and forward requests.

New behaviour: `BHNM_URL` and `PROXY_SECRET` are removed. The target BHNM server is determined per-request from the `X-BHNM-Target` header; any non-empty `X-Proxy-Token` is accepted.

**Security model:** The `X-Proxy-Token` value is a 32-character hex secret (128 bits of entropy) generated per connection. HTTPS provides transport security; the long secret provides authentication. The middleware does not validate the token against a registry — possession of the secret is the credential. This is intentional and sufficient for self-hosted deployments where the middleware is reachable only via HTTPS.

```python
HOP_BY_HOP_REQUEST = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade",
    "x-proxy-token", "x-bhnm-target",   # strip custom headers before forwarding
}

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token:
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")

    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        raise HTTPException(status_code=400, detail="X-BHNM-Target header is required")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")

    target = f"{target_base}/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY) as client:
        resp = await client.request(
            method=request.method,
            url=target,
            headers=forward_headers,
            content=await request.body(),
        )
    # return response as before
```

`X-BHNM-Target` is added to `HOP_BY_HOP_REQUEST` so it is stripped before the request is forwarded to BHNM.

### `main.py` — Unregister Endpoint

```python
@app.delete("/register")
def unregister_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    delete_token(body.token)
    print(f"[Unregister] Token removed: ...{body.token[-8:]} (secret ...{active_secret[-8:]})")
    return {"status": "ok"}
```

`TokenRegistration` is the same Pydantic model used by `POST /register`; only `token` is required for deletion.

### `.env` / `config.py` — Removed Variables

| Variable | Action | Reason |
|---|---|---|
| `BHNM_URL` | Remove | Target is now supplied per-request via `X-BHNM-Target` |
| `PROXY_SECRET` | Remove | Any non-empty `X-Proxy-Token` is accepted; the secret is managed per-connection on the iOS side |
| `BHNM_TLS_VERIFY` | Keep | Global TLS verification setting for all proxied backends |

### `.env.example`

Update to remove `BHNM_URL` and `PROXY_SECRET`. Add a comment explaining dynamic routing:

```
# BHNM_URL and PROXY_SECRET are no longer used.
# The target BHNM server is supplied per-request by the iOS app via X-BHNM-Target.
# The proxy token is supplied per-request via X-Proxy-Token.

BHNM_TLS_VERIFY=true
WEBHOOK_SECRET=your_webhook_secret_here
```

---

## `generate_benem_link.py`

### CLI Argument Changes

| Argument | Change | Notes |
|---|---|---|
| `--bhnm-url` | New (required) | Replaces `--middleware-url` as the required server argument; the direct BHNM server URL |
| `--middleware-url` | Now optional | Push middleware URL; omit if push notifications are not needed |
| `--notifications` / `--no-notifications` | New flag | Default: `true` |
| All other arguments | Unchanged | `--api_key`, `--pin`, `--user`, `--name`, `--push_secret`, `--symbol`, `--color` |

### Payload Keys

```json
{
  "bhnm_url": "https://vpn.hurrikap.org:8888",
  "middleware_url": "https://bhnm-apns.hurrikap.org",
  "notifications": true,
  "api_key": "...",
  "pin": "",
  "user": "Thomas",
  "name": "Customer A",
  "push_secret": "...",
  "symbol": "server.rack",
  "color": "#0A84FF"
}
```

The old payload key `server` (which held the middleware URL) is replaced by `bhnm_url` + `middleware_url`.

### Backward Compatibility

`DeepLinkHandler` must handle old links that contain `server` but no `bhnm_url`:
- Treat `server` value as `middlewareURL`
- Leave `bhnmURL` empty
- This triggers the migration banner on next launch, prompting the user to enter the BHNM URL

---

## Out of Scope

The following items are explicitly excluded from this change:

- Per-connection TLS verification toggle (global `BHNM_TLS_VERIFY` env var in the middleware is sufficient)
- Reordering connections in the UI
- Any change to incident or device parsing logic
- Any change to the APNs payload format
