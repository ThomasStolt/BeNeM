# Proxy Auth Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add consistent, mandatory `X-Proxy-Token` authentication to all middleware proxy routes, with both iOS and PWA clients sending the correct header on every request.

**Architecture:** The middleware validates `X-Proxy-Token` on every proxied request against a per-server `proxy_token` field in `servers.json`. Both clients (iOS, PWA) send the token from their stored server configuration. The BHNM API key (`password` form field) authenticates the request with BHNM itself; `X-Proxy-Token` authenticates the request with the *middleware*. These are intentionally separate credentials — the proxy token is a shared secret between the client and middleware, while the API key is a BHNM credential.

**Tech Stack:** Python/FastAPI (middleware), Swift/SwiftUI (iOS), TypeScript/React (PWA)

---

## Background & Root Cause

On 2026-04-07, commit `8efc2a7` re-enabled `X-Proxy-Token` validation in the middleware after it had been disabled since `ddeb526` (2026-03-31). This broke both apps because:

1. **Middleware** validated `X-Proxy-Token` against `api_key` in `servers.json` — but clients send a *different* value (`webhookSecret` / `pushWebhookSecret`), not the BHNM API key.
2. **PWA** never sends `X-Proxy-Token` at all — only `Content-Type` is set in `postForm()`.
3. **iOS** sends `webhookSecret` as `X-Proxy-Token`, but this value may differ from `api_key` in `servers.json`.

The commit was reverted (proxy auth disabled) as an emergency fix. This plan implements proxy auth properly.

## Design Decisions

1. **Separate `proxy_token` field in `servers.json`** — not reusing `api_key`. The proxy token is a middleware-level credential; the API key is a BHNM credential. Mixing them conflates two trust boundaries.

2. **`proxy_token` in `servers.json` is the source of truth** — the middleware reads it there. The admin portal generates QR codes embedding it. Clients receive it via QR deep link or manual entry.

3. **iOS `webhookSecret` becomes the proxy token** — it already serves this role (sent as `X-Proxy-Token`). The field label in the UI and the `SavedConnection` property name stay as-is for backwards compatibility. The deep link handler will also parse the `proxy_token` field from QR payloads and store it as `webhookSecret`.

4. **PWA `pushWebhookSecret` becomes the proxy token** — same concept. `postForm()` gains a `headers` parameter; callers pass the webhook secret as `X-Proxy-Token`.

5. **Fallback for PROXY_TOKEN env var** — kept as a global override for testing / single-server setups.

## File Map

| File | Action | Responsibility |
|---|---|---|
| `middleware/main.py` | Modify | Add `_valid_proxy_token()`, enforce on all proxy routes |
| `middleware/test_proxy_auth.py` | Create | Tests for proxy auth validation |
| `pwa/src/lib/api/client.ts` | Modify | Accept optional `headers` param in `postForm()` |
| `pwa/src/lib/api/incidents.ts` | Modify | Pass `X-Proxy-Token` header |
| `pwa/src/lib/api/devices.ts` | Modify | Pass `X-Proxy-Token` header |
| `pwa/src/lib/api/tactical.ts` | Modify | Pass `X-Proxy-Token` header |
| `pwa/src/lib/api/performance.ts` | Modify | Pass `X-Proxy-Token` header |
| `pwa/src/lib/config.ts` | Modify | Expose `proxyToken` in `BhnmConfig` (mapped from `pushWebhookSecret`) |
| `ios/BeNeM/Services/DeepLinkHandler.swift` | Modify | Parse `proxy_token` from QR payload, store as `webhookSecret` |
| `shared/push-payload-spec.md` | Modify | Document `proxy_token` field in QR payload spec |

---

## Task 1: Middleware — Add `proxy_token` to `servers.json` validation

**Files:**
- Modify: `middleware/main.py:30-33` (add `PROXY_TOKEN` constant and `_valid_proxy_token()`)
- Create: `middleware/test_proxy_auth.py`

- [ ] **Step 1: Write failing tests for proxy token validation**

Create `middleware/test_proxy_auth.py`:

```python
"""Tests for X-Proxy-Token proxy authentication."""
import json
import os
import tempfile
import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def servers_file(tmp_path):
    """Create a temporary servers.json with known proxy_token values."""
    path = tmp_path / "servers.json"
    path.write_text(json.dumps([
        {
            "id": "test-server",
            "name": "Test",
            "url": "https://bhnm.example.com",
            "api_key": "the-bhnm-api-key",
            "pin": "",
            "proxy_token": "secret-proxy-token-123",
        },
        {
            "id": "second-server",
            "name": "Second",
            "url": "https://bhnm2.example.com",
            "api_key": "another-api-key",
            "pin": "",
            "proxy_token": "second-proxy-token-456",
        },
    ]))
    return str(path)


@pytest.fixture()
def client(servers_file, monkeypatch):
    """TestClient with servers.json pointed at temp file."""
    monkeypatch.setenv("SERVERS_JSON_PATH", servers_file)
    monkeypatch.setenv("PROXY_TOKEN", "")
    monkeypatch.setenv("APNS_KEY_ID", "test")
    monkeypatch.setenv("APNS_TEAM_ID", "test")
    monkeypatch.setenv("APNS_BUNDLE_ID", "com.test")
    monkeypatch.setenv("APNS_PRIVATE_KEY_B64", "dGVzdA==")
    # Re-import to pick up env changes
    import importlib
    import main as main_mod
    importlib.reload(main_mod)
    return TestClient(main_mod.app)


def test_proxy_rejects_missing_token(client):
    """Request without X-Proxy-Token → 401."""
    resp = client.post(
        "/api/incident_api.php",
        data={"password": "the-bhnm-api-key", "method": "getIncidentList"},
    )
    assert resp.status_code == 401
    assert "X-Proxy-Token" in resp.json()["detail"]


def test_proxy_rejects_wrong_token(client):
    """Request with invalid X-Proxy-Token → 401."""
    resp = client.post(
        "/api/incident_api.php",
        headers={"X-Proxy-Token": "wrong-token"},
        data={"password": "the-bhnm-api-key", "method": "getIncidentList"},
    )
    assert resp.status_code == 401


def test_proxy_accepts_valid_proxy_token(client):
    """Request with valid proxy_token from servers.json → forwarded (502 expected since BHNM is not reachable)."""
    resp = client.post(
        "/api/incident_api.php",
        headers={
            "X-Proxy-Token": "secret-proxy-token-123",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
        data={"password": "the-bhnm-api-key", "method": "getIncidentList"},
    )
    # 502 = middleware tried to reach BHNM (auth passed); not 401
    assert resp.status_code != 401


def test_proxy_accepts_second_server_token(client):
    """Proxy token from any configured server is accepted."""
    resp = client.post(
        "/api/incident_api.php",
        headers={
            "X-Proxy-Token": "second-proxy-token-456",
            "X-BHNM-Target": "https://bhnm2.example.com",
        },
        data={"password": "another-api-key"},
    )
    assert resp.status_code != 401


def test_proxy_accepts_env_token(client, monkeypatch, servers_file):
    """PROXY_TOKEN env var is accepted as a global override."""
    monkeypatch.setenv("PROXY_TOKEN", "env-override-token")
    import importlib
    import main as main_mod
    importlib.reload(main_mod)
    c = TestClient(main_mod.app)
    resp = c.post(
        "/api/incident_api.php",
        headers={
            "X-Proxy-Token": "env-override-token",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
        data={"password": "the-bhnm-api-key"},
    )
    assert resp.status_code != 401


def test_proxy_rejects_api_key_as_proxy_token(client):
    """api_key must NOT be accepted as a proxy token — they are separate credentials."""
    resp = client.post(
        "/api/incident_api.php",
        headers={
            "X-Proxy-Token": "the-bhnm-api-key",
            "X-BHNM-Target": "https://bhnm.example.com",
        },
        data={"password": "the-bhnm-api-key"},
    )
    assert resp.status_code == 401


def test_dedicated_proxy_route_requires_token(client):
    """Dedicated proxy routes (/api/proxy/*) also require X-Proxy-Token."""
    resp = client.post(
        "/api/proxy/incident/acknowledge",
        data={"password": "the-bhnm-api-key", "incident_id": "1"},
    )
    assert resp.status_code == 401


def test_non_proxy_routes_skip_auth(client):
    """Non-proxy routes (health, register, webhook) do NOT require X-Proxy-Token."""
    resp = client.get("/health")
    assert resp.status_code == 200

    resp = client.post(
        "/register",
        json={"token": "abc123", "device_name": "Test"},
        headers={"X-Webhook-Token": "some-secret"},
    )
    assert resp.status_code == 200
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd middleware && python3 -m pytest test_proxy_auth.py -v`
Expected: Most tests FAIL — proxy auth is currently disabled, so missing/wrong token requests pass through.

- [ ] **Step 3: Add `proxy_token` field to `servers.json` on the server**

Update the live `servers.json` to include `proxy_token` for each server. The value should match what the iOS app currently has as its webhook secret for that server. SSH to the server and edit `/data/servers.json` (inside the Docker volume):

```json
[
  {
    "id": "SaaS Demo Server",
    "name": "SaaS Demo Server",
    "url": "https://portal-netreo-ash-np2.onbmc.com/",
    "api_key": "ay8zFclU3ypmkby7peBoSicmJcgu3PUddLMeIMmFS904Se2Jf51PLDS91ST",
    "pin": "1523959604",
    "proxy_token": "<VALUE_FROM_IOS_APP_WEBHOOK_SECRET_FOR_THIS_SERVER>"
  },
  {
    "id": "Thomas Lab Server",
    "name": "Thomas' Lab Server",
    "url": "https://vpn.hurrikap.org:8888",
    "api_key": "ThisIsAPassword",
    "pin": "",
    "proxy_token": "<VALUE_FROM_IOS_APP_WEBHOOK_SECRET_FOR_THIS_SERVER>"
  }
]
```

**Important:** Ask the user what the webhook secret values are for each server in the iOS app. These become the `proxy_token` values. If they are the same as `api_key`, that's fine — but they are stored separately.

- [ ] **Step 4: Implement `_valid_proxy_token()` in middleware**

In `middleware/main.py`, after the `PROXY_TIMEOUT` line (currently line 31), add:

```python
PROXY_TOKEN = os.getenv("PROXY_TOKEN", "")

def _valid_proxy_token(token: str) -> bool:
    """Check token against PROXY_TOKEN env var or any proxy_token in servers.json."""
    if PROXY_TOKEN and token == PROXY_TOKEN:
        return True
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("proxy_token") and s["proxy_token"] == token:
                    return True
    except Exception as exc:
        print(f"[Auth] Failed to read {SERVERS_JSON_PATH}: {exc}")
    return False
```

**Key difference from the reverted code:** This checks `s.get("proxy_token")`, NOT `s.get("api_key")`. The proxy token and API key are separate credentials.

- [ ] **Step 5: Add auth check to `_proxy_to_bhnm()`**

In `middleware/main.py`, in `_proxy_to_bhnm()`, before `body = await request.body()`:

```python
async def _proxy_to_bhnm(request: Request, bhnm_path: str) -> Response:
    """Forward a form-encoded POST to the given BHNM path and return the response."""
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token or not _valid_proxy_token(token):
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")

    body = await request.body()
```

- [ ] **Step 6: Add auth check to catch-all `proxy()`**

In `middleware/main.py`, in `proxy()`, before `body = await request.body()`:

```python
@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token or not _valid_proxy_token(token):
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")

    body = await request.body()
```

Update the comment above to:
```python
# ── BHNM API Proxy (for BeNeM) ────────────────────────────────────────────────────
# Target BHNM server is supplied per-request via X-BHNM-Target header.
# X-Proxy-Token is validated against PROXY_TOKEN env var or servers.json proxy_token fields.
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd middleware && python3 -m pytest test_proxy_auth.py -v`
Expected: ALL tests PASS.

- [ ] **Step 8: Commit**

```bash
git add middleware/main.py middleware/test_proxy_auth.py
git commit -m "feat(middleware): add proxy auth via per-server proxy_token in servers.json

Validates X-Proxy-Token header against proxy_token field in servers.json
(not api_key). Falls back to PROXY_TOKEN env var for global override."
```

---

## Task 2: PWA — Send `X-Proxy-Token` on all API requests

**Files:**
- Modify: `pwa/src/lib/api/client.ts:7-19`
- Modify: `pwa/src/lib/config.ts:4-13`
- Modify: `pwa/src/lib/api/incidents.ts` (all `postForm` calls)
- Modify: `pwa/src/lib/api/devices.ts` (all `postForm` calls)
- Modify: `pwa/src/lib/api/tactical.ts` (all `postForm` calls)
- Modify: `pwa/src/lib/api/performance.ts` (all `postForm` calls)

- [ ] **Step 1: Add `proxyToken` to `BhnmConfig`**

In `pwa/src/lib/config.ts`, add `proxyToken` to the interface and `buildSnapshot()`:

```typescript
export interface BhnmConfig {
  serverId: string;
  serverName: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  webhookSecret?: string;
  proxyToken?: string;        // ← ADD: sent as X-Proxy-Token to middleware
  pushMiddlewareUrl?: string;
  isConfigured: boolean;
}
```

In `buildSnapshot()`, map it:
```typescript
  return {
    serverId: server.id,
    serverName: server.name,
    baseUrl: server.baseUrl,
    apiKey: server.apiKey,
    pin: server.pin,
    webhookSecret: server.pushWebhookSecret,
    proxyToken: server.pushWebhookSecret,  // ← ADD: same value as webhookSecret
    pushMiddlewareUrl: server.pushMiddlewareUrl,
    isConfigured: server.apiKey.length > 0,
  };
```

- [ ] **Step 2: Add optional `headers` parameter to `postForm()`**

In `pwa/src/lib/api/client.ts`:

```typescript
export async function postForm(
  baseUrl: string,
  path: string,
  params: Record<string, string>,
  extraHeaders?: Record<string, string>,
): Promise<unknown> {
  const body = new URLSearchParams(params).toString();
  let response: Response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        ...extraHeaders,
      },
      body,
    });
```

- [ ] **Step 3: Create a helper to build proxy headers**

In `pwa/src/lib/api/client.ts`, add after `postForm`:

```typescript
/** Build X-Proxy-Token + X-BHNM-Target headers for proxied requests. */
export function proxyHeaders(
  proxyToken?: string,
  bhnmTarget?: string,
): Record<string, string> | undefined {
  if (!proxyToken) return undefined;
  const h: Record<string, string> = { 'X-Proxy-Token': proxyToken };
  if (bhnmTarget) h['X-BHNM-Target'] = bhnmTarget;
  return h;
}
```

- [ ] **Step 4: Update all API modules to pass proxy headers**

For each API module, add the proxy headers to every `postForm` call. The pattern is the same — import `proxyHeaders` from `client.ts` and pass `config.proxyToken` as the token.

Example for `pwa/src/lib/api/incidents.ts` — find every `postForm(config.baseUrl, ...)` call and add the headers parameter:

```typescript
import { postForm, proxyHeaders } from './client';

// In every function that calls postForm:
const raw = await postForm(
  config.baseUrl,
  '/api/incident_api.php',
  params,
  proxyHeaders(config.proxyToken),
);
```

Repeat for:
- `pwa/src/lib/api/devices.ts` — all `postForm` calls
- `pwa/src/lib/api/tactical.ts` — all `postForm` calls
- `pwa/src/lib/api/performance.ts` — all `postForm` calls

**Check every file for `postForm(` calls and add the headers parameter to each one.**

- [ ] **Step 5: Verify build passes**

Run: `cd pwa && npm run build`
Expected: No TypeScript errors, clean build.

- [ ] **Step 6: Commit**

```bash
git add pwa/src/lib/api/client.ts pwa/src/lib/config.ts pwa/src/lib/api/incidents.ts pwa/src/lib/api/devices.ts pwa/src/lib/api/tactical.ts pwa/src/lib/api/performance.ts
git commit -m "feat(pwa): send X-Proxy-Token header on all proxied API requests

Adds proxyToken to BhnmConfig (mapped from pushWebhookSecret) and passes
it as X-Proxy-Token via postForm's new extraHeaders parameter."
```

---

## Task 3: iOS — Parse `proxy_token` from QR deep links

**Files:**
- Modify: `ios/BeNeM/Services/DeepLinkHandler.swift`

The iOS app already sends `webhookSecret` as `X-Proxy-Token` (line 57 of `NetreoAPIService.swift`). The only gap is that `DeepLinkHandler` doesn't parse the `proxy_token` field from QR code payloads — it only reads `push_secret`.

- [ ] **Step 1: Read DeepLinkHandler to find the compact payload parsing**

Read `ios/BeNeM/Services/DeepLinkHandler.swift` and locate where `push_secret` is parsed in the compact format handler. The `proxy_token` field should take precedence over `push_secret` when present (since the admin portal now sends both).

- [ ] **Step 2: Update `PendingImport` parsing to prefer `proxy_token`**

In the compact payload handler, after parsing `push_secret`, add a fallback:

```swift
// proxy_token takes precedence over push_secret when present
let pushSecret = str("proxy_token").isEmpty ? str("push_secret") : str("proxy_token")
```

Use this `pushSecret` value when constructing `PendingImport`.

- [ ] **Step 3: Build and deploy to verify**

Run: `./build_and_deploy.sh`
Expected: Clean build, no regressions.

- [ ] **Step 4: Commit**

```bash
git add ios/BeNeM/Services/DeepLinkHandler.swift
git commit -m "fix(ios): parse proxy_token from QR deep links, fall back to push_secret"
```

---

## Task 4: Deployment & Verification

This task covers the deployment sequence. **Order matters** — clients must be updated before the middleware enforces auth.

- [ ] **Step 1: Deploy PWA with X-Proxy-Token support**

On the server, rebuild and restart the PWA container:
```bash
cd ~/BeNeM && docker compose up -d --build benem-pwa
```

Verify PWA loads and can fetch data (proxy auth is still disabled at this point).

- [ ] **Step 2: Update `servers.json` with `proxy_token` fields**

On the server, edit `/data/servers.json` to add `proxy_token` to each server entry. The values must match what the iOS app and PWA send as their webhook secret.

- [ ] **Step 3: Deploy iOS with `proxy_token` deep link support**

Build and deploy to TestFlight or the test device. This step is only needed if users will re-scan QR codes. The existing iOS app already sends `webhookSecret` as `X-Proxy-Token`, so it works without a new build as long as the `proxy_token` in `servers.json` matches the app's stored webhook secret.

- [ ] **Step 4: Deploy middleware with proxy auth enabled**

On the server, rebuild and restart the middleware:
```bash
cd ~/BeNeM && docker compose up -d --build bhnm-apns
```

- [ ] **Step 5: Verify iOS app loads data**

Open BeNeM on iOS. Incidents, devices, and tactical overview should all load without 401 errors.

- [ ] **Step 6: Verify PWA loads data**

Open BeNeM PWA in a browser. Incidents, devices, and tactical overview should all load without 401 errors.

- [ ] **Step 7: Verify unauthenticated requests are rejected**

From the server, test that missing/wrong tokens are rejected:
```bash
# No token → 401
curl -sk -o /dev/null -w '%{http_code}' -X POST https://bhnm-apns.hurrikap.org/api/incident_api.php -d 'password=test'

# Wrong token → 401
curl -sk -o /dev/null -w '%{http_code}' -X POST https://bhnm-apns.hurrikap.org/api/incident_api.php -H 'X-Proxy-Token: wrong' -d 'password=test'
```

Expected: Both return `401`.

- [ ] **Step 8: Commit deployment notes**

```bash
git add middleware/main.py
git commit -m "deploy(middleware): enable proxy auth with per-server proxy_token validation"
```

---

## Rollback Plan

If proxy auth breaks in production after deployment:

1. SSH to server
2. Comment out the two auth checks in `/app/main.py` inside the container:
   ```bash
   docker exec bhnm-apns-bhnm-apns-1 sed -i 's/^    if not token or not _valid_proxy_token/    # if not token or not _valid_proxy_token/' /app/main.py
   ```
3. Restart: `docker restart bhnm-apns-bhnm-apns-1`

This disables auth without a full redeploy.
