# API Proxy via bhnm-apns Middleware

**Date:** 2026-03-26
**Status:** Approved

## Problem

BeNeM communicates with BHNM servers directly from the iOS app. BHNM is typically deployed on a private corporate network with no internet access. Users on mobile networks or outside the corporate network cannot reach BHNM at all.

## Goal

Route all BHNM API calls through the `bhnm-apns` middleware, which is deployed on-premises with access to both the internet and the BHNM private network. The iPhone talks to the middleware; the middleware proxies requests to BHNM.

## Constraints

- One middleware instance per private network (Scenario 2: separate deployments for separate networks).
- Credentials (`password`, `pin`) remain on the client and pass through transparently — the middleware does not hold or inspect them.
- Deployment must stay a single Docker container; no new services or ports.
- Push notification flow (`BHNM → middleware → APNs → iPhone`) is unchanged.
- The existing `webhookSecret` per `SavedConnection` (from the multi-server push notification design) is reused for proxy authentication — no new credential.

---

## Architecture

```
iPhone (BeNeM)
    │  HTTPS — all API calls + push registration
    ▼
bhnm-apns middleware  (Docker, on-premises, internet-accessible)
    │  HTTP — proxied API calls (same LAN)
    ▼
BHNM server  (private network)

BHNM server ──webhook──► middleware ──APNs──► iPhone   (unchanged)
```

Each `SavedConnection` stores the middleware URL as its `baseURL`. The middleware knows its BHNM target via `BHNM_URL` in `.env`. One middleware deployment serves one BHNM network.

---

## Components

### 1. iOS — `NetreoAPIService.swift`

Add a single private helper that injects an `X-Proxy-Token` header on every outgoing `URLRequest`:

```swift
private func addProxyToken(_ request: inout URLRequest) {
    if !configuration.proxyToken.isEmpty {
        request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
    }
}
```

Call this helper in every method that constructs a `URLRequest` before passing it to `urlSession.data(for:)`.

`configuration.proxyToken` is read from the active `SavedConnection.webhookSecret`. No new field is needed — `webhookSecret` already exists per connection.

### 2. iOS — `NetreoAPIConfiguration.swift`

Add one computed property:

```swift
var proxyToken: String { webhookSecret }
```

No structural changes. `baseURL` continues to hold whichever URL the user has configured — it now points to the middleware instead of BHNM directly.

### 3. iOS — Settings UX

- Rename the "Server URL" input label to **"Middleware URL"**.
- Add a subtitle hint: `e.g. https://bhnm-apns.yourcompany.com`
- Remove the `push_middleware_url` field from the Push Notifications section — it is now redundant. The middleware URL is `baseURL`.
- No new fields or screens required.

### 4. Middleware — `.env`

Add one variable:

```
BHNM_URL=http://192.168.x.x
```

This is the address of the BHNM server on the local network, reachable from the middleware container.

### 5. Middleware — Catch-all proxy route (`bhnm-apns`)

Add a catch-all route that handles any request not matching `/register` or `/webhook`:

```python
@app.route("/<path:path>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path):
    token = request.headers.get("X-Proxy-Token", "")
    if token != WEBHOOK_SECRET:
        return {"error": "Unauthorized"}, 401

    target = f"{BHNM_URL}/{path}"
    if request.query_string:
        target += f"?{request.query_string.decode()}"

    async with httpx.AsyncClient() as client:
        resp = await client.request(
            method=request.method,
            url=target,
            headers={k: v for k, v in request.headers if k.lower() != "host"},
            content=await request.get_data(),
        )

    return resp.content, resp.status_code, dict(resp.headers)
```

Key properties:
- **Authentication:** `X-Proxy-Token` checked against `WEBHOOK_SECRET` (existing env var). Returns 401 if missing or wrong.
- **Transparent:** path, query string, method, body, and headers are forwarded unchanged.
- **Response:** status code, headers, and body returned as-is to the client.
- **No route mapping:** all current and future BHNM endpoints work automatically.

---

## Data Flow

```
App builds URLRequest to middleware URL + BHNM path
        │
        ▼
Adds X-Proxy-Token: <webhookSecret> header
        │
        ▼
POST https://bhnm-apns.yourcompany.com/fw/index.php?r=restful/devices/list
        │
        ▼
Middleware authenticates X-Proxy-Token
        │
        ▼
Middleware forwards to http://192.168.x.x/fw/index.php?r=restful/devices/list
        │
        ▼
BHNM responds → middleware returns response to app
```

---

## Authentication

| Leg | Mechanism |
|---|---|
| App → middleware | `X-Proxy-Token: <webhookSecret>` header |
| Middleware → BHNM | `password=<apiKey>` + `pin=<pin>` in request body (pass-through from app) |
| BHNM → middleware (webhook) | `?secret=<webhookSecret>` query param (unchanged) |

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Missing / wrong `X-Proxy-Token` | Middleware returns 401. App surfaces a connection error. |
| BHNM unreachable from middleware | `httpx` raises a connection error → middleware returns 502. App surfaces a connection error. |
| BHNM returns non-200 | Response passed through as-is. App handles it as today. |
| Empty `webhookSecret` | No `X-Proxy-Token` header sent. Middleware returns 401. User must configure a webhook secret in Settings. |

---

## Migration

- **Existing users:** Update `baseURL` per `SavedConnection` to the middleware URL. The BHNM URL moves to `BHNM_URL` in the middleware `.env`. One-time manual reconfiguration.
- **`push_middleware_url` AppStorage key:** Deprecated and removed from the Settings UI. The value in `baseURL` is now used for all communication. No data migration needed — the key simply becomes unused.
- **`webhookSecret`:** Already required by the multi-server push notification design. Users who have not yet set one will get 401 errors and must configure it in Settings before API calls work through the middleware.
- **Deep link provisioning (`generate_benem_link.py`):** The `--bhnm-server` parameter now accepts the middleware URL. The `--push_url` parameter is removed (redundant). Update the script and its documentation.

---

## Future: Smart Caching

The proxy function is the single insertion point for a caching layer. When caching is added:

- Check an in-memory or Redis cache before forwarding to BHNM.
- Populate cache on successful BHNM response.
- Cache selectively — incident lists and tactical overview are good candidates; time-series metrics are not (high volume, low reuse).

**On-device LLM prefetch (future):** The app observes navigation patterns and predicts which requests the user is likely to make next. It sends an `X-Prefetch` hint header alongside real requests. The middleware warms the cache proactively before the user navigates. Nothing is built now; the architecture supports it without structural changes.

---

## Out of Scope

- Middleware holding BHNM credentials (pass-through only).
- Multiple BHNM servers per middleware instance (one deployment per network).
- Response transformation or aggregation at the middleware layer.
- Rate limiting (can be added later via a middleware library).
- Smart caching (future, described above).
