# Middleware Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all issues identified in the middleware code review — from critical (open proxy) to low (magic numbers, sequential delivery).

**Architecture:** All changes are within `middleware/`. No iOS or PWA changes needed. The proxy auth fix relies on the iOS app already sending `X-Proxy-Token` on every proxied request (confirmed in `NetreoAPIService.swift:54-60`). Proxy token validation uses `servers.json` as the source of truth — each server entry gains an optional `proxy_token` field.

**Tech Stack:** Python 3, FastAPI, Pydantic, httpx, pywebpush, SQLite, pytest

---

### Task 1: Re-enable Proxy Authentication (Critical)

**Files:**
- Modify: `middleware/main.py:267-299`
- Modify: `middleware/servers.json.example`
- Modify: `middleware/.env.example:65-69`
- Create: `middleware/test_proxy_auth.py`

The iOS app sends `X-Proxy-Token` = webhook secret when middleware is configured. The catch-all proxy must validate this token against `servers.json`. Each server entry has an `api_key` — we validate that the request's `X-Proxy-Token` matches a known `api_key` from any configured server. This avoids adding a new field — the api_key already serves as the shared credential.

However, looking at the iOS code: `proxyToken` is set to `webhookSecret`, not `api_key`. The webhook secret is the per-device secret used for push routing, not stored in `servers.json`. So we need a dedicated `proxy_token` field in `servers.json`, and the iOS app's webhook secret must match it.

Simplest correct approach: accept any non-empty `X-Proxy-Token` that matches any server's `api_key` in `servers.json`, OR if a `PROXY_TOKEN` env var is set, accept that value. This keeps backward compatibility with the existing `.env.example` PROXY_TOKEN field.

- [ ] **Step 1: Write the failing test**

```python
# test_proxy_auth.py
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_proxy_auth.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers.json")

import json
import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def setup_servers(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([
        {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com", "api_key": "secret-key-123"}
    ]))
    os.environ["SERVERS_JSON_PATH"] = str(servers_file)
    os.environ.pop("PROXY_TOKEN", None)
    yield
    os.environ.pop("PROXY_TOKEN", None)


def _get_client():
    """Re-import to pick up env changes."""
    import importlib
    import main as main_mod
    importlib.reload(main_mod)
    return TestClient(main_mod.app)


def test_proxy_rejects_missing_token():
    client = _get_client()
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code == 401


def test_proxy_rejects_wrong_token():
    client = _get_client()
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "wrong", "X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code == 401


def test_proxy_accepts_matching_api_key():
    client = _get_client()
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "secret-key-123", "X-BHNM-Target": "https://bhnm.example.com"})
    # Will fail to connect to upstream, but should NOT be 401
    assert resp.status_code != 401


def test_proxy_accepts_env_proxy_token():
    os.environ["PROXY_TOKEN"] = "env-token-456"
    client = _get_client()
    resp = client.get("/fw/index.php?r=restful/device/list",
                      headers={"X-Proxy-Token": "env-token-456", "X-BHNM-Target": "https://bhnm.example.com"})
    assert resp.status_code != 401
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd middleware && python -m pytest test_proxy_auth.py -v`
Expected: `test_proxy_rejects_missing_token` and `test_proxy_rejects_wrong_token` FAIL (currently return 502, not 401)

- [ ] **Step 3: Implement proxy token validation**

In `main.py`, add a validation function and call it at the top of the catch-all proxy handler. Replace the commented-out TODO block:

```python
# At module level, after SERVERS_JSON_PATH
PROXY_TOKEN = os.getenv("PROXY_TOKEN", "")

def _valid_proxy_token(token: str) -> bool:
    """Check token against PROXY_TOKEN env var or any api_key in servers.json."""
    if PROXY_TOKEN and token == PROXY_TOKEN:
        return True
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == token:
                    return True
    except Exception:
        pass
    return False
```

In the catch-all `proxy()` function, replace the commented-out TODO with:

```python
token = request.headers.get("X-Proxy-Token", "").strip()
if not token or not _valid_proxy_token(token):
    raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")
```

Also add the same check to `_proxy_to_bhnm()` for the dedicated proxy routes:

```python
async def _proxy_to_bhnm(request: Request, bhnm_path: str) -> Response:
    """Forward a form-encoded POST to the given BHNM path and return the response."""
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token or not _valid_proxy_token(token):
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")
    # ... rest unchanged
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd middleware && python -m pytest test_proxy_auth.py -v`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py middleware/test_proxy_auth.py
git commit -m "fix(middleware): re-enable proxy authentication via X-Proxy-Token"
```

---

### Task 2: Add Pydantic Model for Webhook Payload (High)

**Files:**
- Modify: `middleware/main.py:124-175`
- Modify: `middleware/test_endpoints.py`

- [ ] **Step 1: Write the failing test**

Add to `test_endpoints.py`:

```python
def test_webhook_rejects_non_json(client):
    resp = client.post("/webhook?secret=testsecret", content=b"not json",
                       headers={"Content-Type": "application/json"})
    assert resp.status_code == 422


def test_webhook_accepts_valid_payload(client):
    # Register a device first so the secret is known
    client.post("/register",
                json={"token": "aabbccdd" * 8},
                headers={"X-Webhook-Token": "testsecret"})
    resp = client.post("/webhook?secret=testsecret",
                       json={
                           "notification_type": "PROBLEM",
                           "hostname": "switch-01",
                           "host_state": "DOWN",
                           "site": "HQ",
                           "output": "unreachable",
                           "incident_id": "42"
                       })
    assert resp.status_code == 200


def test_webhook_accepts_minimal_payload(client):
    client.post("/register",
                json={"token": "11223344" * 8},
                headers={"X-Webhook-Token": "testsecret2"})
    resp = client.post("/webhook?secret=testsecret2",
                       json={"hostname": "router-01"})
    assert resp.status_code == 200
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd middleware && python -m pytest test_endpoints.py -v -k webhook`
Expected: FAIL — `test_webhook_rejects_non_json` returns 500 (unhandled JSON parse error), not 422

- [ ] **Step 3: Add Pydantic model and use it**

In `main.py`, add the model after `WebPushRegistration`:

```python
class WebhookPayload(BaseModel):
    notification_type: str = "PROBLEM"
    hostname: str = "Unknown device"
    host_state: str = ""
    site: str = ""
    service_desc: str = ""
    output: str = ""
    incident_id: str = ""
```

Change the webhook handler signature from `async def receive_webhook(request: Request)` to:

```python
@app.post("/webhook")
async def receive_webhook(request: Request, payload: WebhookPayload):
    secret = request.query_params.get("secret", "").strip()
    if not secret:
        raise HTTPException(status_code=400, detail="?secret= query parameter is required")

    # Use validated model fields directly
    notification_type = payload.notification_type
    hostname          = payload.hostname
    host_state        = payload.host_state
    site              = payload.site
    service_desc      = payload.service_desc
    output            = payload.output
    incident_id       = payload.incident_id

    # ... rest of handler unchanged from "Build human-readable notification" onward
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd middleware && python -m pytest test_endpoints.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py middleware/test_endpoints.py
git commit -m "fix(middleware): add Pydantic model for webhook payload validation"
```

---

### Task 3: Fix Webhook 403 for Unknown Secret (Medium)

**Files:**
- Modify: `middleware/main.py:158-160`
- Modify: `middleware/test_endpoints.py`

The webhook currently returns 403 when no devices are registered for a secret. This is wrong — a valid secret with zero registered devices should succeed with `notified: 0`.

- [ ] **Step 1: Write the failing test**

Add to `test_endpoints.py`:

```python
def test_webhook_returns_200_for_unknown_secret(client):
    """A valid-shaped secret with no registered devices should return 200, not 403."""
    resp = client.post("/webhook?secret=no-devices-yet",
                       json={"hostname": "switch-01", "host_state": "DOWN"})
    assert resp.status_code == 200
    assert resp.json()["notified"] == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd middleware && python -m pytest test_endpoints.py::test_webhook_returns_200_for_unknown_secret -v`
Expected: FAIL — returns 403

- [ ] **Step 3: Remove the 403 gate**

In `main.py`, replace:

```python
    if not tokens and not web_push_subs:
        print(f"[Webhook] Rejected: no registered devices for this secret.")
        raise HTTPException(status_code=403, detail="Forbidden: unknown secret")
```

With:

```python
    if not tokens and not web_push_subs:
        print(f"[Webhook] No registered devices for this secret — nothing to notify.")
        return {"status": "ok", "notified": 0}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd middleware && python -m pytest test_endpoints.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py middleware/test_endpoints.py
git commit -m "fix(middleware): return 200 with notified:0 instead of 403 for no-device webhooks"
```

---

### Task 4: Add Logging for servers.json Errors (Medium)

**Files:**
- Modify: `middleware/main.py:34-55`

- [ ] **Step 1: Add logging to `_target_for_api_key` and `_single_server_url`**

Replace both functions:

```python
def _target_for_api_key(api_key: str) -> str:
    """Look up BHNM server URL by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s.get("url", "").rstrip("/")
    except FileNotFoundError:
        print(f"[Config] servers.json not found at {SERVERS_JSON_PATH}")
    except json.JSONDecodeError as e:
        print(f"[Config] servers.json is not valid JSON: {e}")
    except Exception as e:
        print(f"[Config] Error reading servers.json: {e}")
    return ""


def _single_server_url() -> str:
    """Return the URL of the only configured server, or '' if 0 or >1 servers."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            servers = json.load(f)
        if len(servers) == 1:
            return servers[0].get("url", "").rstrip("/")
    except FileNotFoundError:
        print(f"[Config] servers.json not found at {SERVERS_JSON_PATH}")
    except json.JSONDecodeError as e:
        print(f"[Config] servers.json is not valid JSON: {e}")
    except Exception as e:
        print(f"[Config] Error reading servers.json: {e}")
    return ""
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `cd middleware && python -m pytest -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add middleware/main.py
git commit -m "fix(middleware): log servers.json errors instead of silently swallowing them"
```

---

### Task 5: Make webpush Truly Async (Medium)

**Files:**
- Modify: `middleware/webpush.py:15-57`

`pywebpush.webpush()` is synchronous and blocks the event loop. Wrap it with `asyncio.to_thread`.

- [ ] **Step 1: Modify `send_web_push_to_all` to use `asyncio.to_thread`**

```python
import asyncio
import json
from pywebpush import webpush as webpush_send, WebPushException
from config import VAPID_PRIVATE_KEY, VAPID_PUBLIC_KEY, VAPID_CONTACT_EMAIL


def build_payload(title: str, body: str, incident_id: str, severity: str) -> dict:
    return {
        "title": title,
        "body": body,
        "incident_id": incident_id,
        "severity": severity,
    }


def _send_one(subscription_info: dict, data: str, vapid_claims: dict) -> None:
    """Blocking call — run via asyncio.to_thread."""
    webpush_send(
        subscription_info=subscription_info,
        data=data,
        vapid_private_key=VAPID_PRIVATE_KEY,
        vapid_claims=vapid_claims,
    )


async def send_web_push_to_all(
    subscriptions: list[dict],
    title: str,
    body: str,
    incident_id: str = "",
    severity: str = "",
) -> list[str]:
    """Send Web Push to all subscriptions. Returns list of endpoints to remove (410 Gone)."""
    if not VAPID_PRIVATE_KEY:
        return []

    payload = json.dumps(build_payload(title, body, incident_id, severity))
    vapid_claims = {"sub": VAPID_CONTACT_EMAIL}
    gone_endpoints: list[str] = []

    for sub in subscriptions:
        subscription_info = {
            "endpoint": sub["endpoint"],
            "keys": {"p256dh": sub["p256dh"], "auth": sub["auth"]},
        }
        try:
            await asyncio.to_thread(_send_one, subscription_info, payload, vapid_claims)
            print(f"[WebPush] Sent to {sub['endpoint'][:50]}...")
        except WebPushException as e:
            status = getattr(e.response, "status_code", 0) if e.response else 0
            if status == 0 and "410" in str(e):
                status = 410
            if status == 410:
                gone_endpoints.append(sub["endpoint"])
                print(f"[WebPush] Subscription expired (410): {sub['endpoint'][:50]}...")
            else:
                print(f"[WebPush] Failed ({status}): {e}")
        except Exception as e:
            print(f"[WebPush] Error: {e}")

    return gone_endpoints
```

- [ ] **Step 2: Run existing webpush tests**

Run: `cd middleware && python -m pytest test_webpush.py -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add middleware/webpush.py
git commit -m "fix(middleware): make webpush delivery truly async with asyncio.to_thread"
```

---

### Task 6: Parallelize APNs Delivery + Shared Client (Low)

**Files:**
- Modify: `middleware/apns.py`

Two changes: use `asyncio.gather` for parallel delivery, and create the httpx client once per batch instead of per notification.

- [ ] **Step 1: Rewrite apns.py**

```python
import asyncio
import time
import jwt
import httpx
from config import APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID

APNS_HOSTS = {
    "sandbox": "api.sandbox.push.apple.com",
    "production": "api.push.apple.com",
}

APNS_TIMEOUT = 10.0
JWT_REFRESH_SECONDS = 3300  # refresh after 55 min (APNs requires < 60 min)

_jwt_token = None
_jwt_issued_at = 0


def _get_jwt() -> str:
    global _jwt_token, _jwt_issued_at
    now = int(time.time())
    if _jwt_token is None or (now - _jwt_issued_at) > JWT_REFRESH_SECONDS:
        _jwt_token = jwt.encode(
            {"iss": APNS_TEAM_ID, "iat": now},
            APNS_PRIVATE_KEY,
            algorithm="ES256",
            headers={"kid": APNS_KEY_ID}
        )
        _jwt_issued_at = now
    return _jwt_token


async def _send_one(
    client: httpx.AsyncClient,
    device_token: str,
    title: str,
    body: str,
    incident_id: str,
    environment: str,
) -> tuple[str, bool, int]:
    """Send to one device. Returns (token, success, status_code)."""
    host = APNS_HOSTS.get(environment, APNS_HOSTS["production"])
    url = f"https://{host}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {_get_jwt()}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default"
        }
    }
    if incident_id:
        payload["incident_id"] = incident_id
    try:
        r = await client.post(url, json=payload, headers=headers, timeout=APNS_TIMEOUT)
        success = r.status_code == 200
        if not success:
            print(f"[APNs] Failed ({r.status_code}) via {environment}: {r.text}")
        return device_token, success, r.status_code
    except Exception as e:
        print(f"[APNs] Error: {e}")
        return device_token, False, 0


async def send_to_all(tokens: list[tuple[str, str]], title: str, body: str, incident_id: str = "") -> list[str]:
    """Send to all (token, environment) pairs. Returns list of tokens to remove (410 Gone)."""
    if not tokens:
        return []

    stale_tokens = []
    async with httpx.AsyncClient(http2=True) as client:
        results = await asyncio.gather(*[
            _send_one(client, token, title, body, incident_id, env)
            for token, env in tokens
        ])
    for token, success, status in results:
        if status == 410:
            stale_tokens.append(token)
        elif success:
            print(f"[APNs] Sent to ...{token[-8:]}")
    return stale_tokens
```

- [ ] **Step 2: Run all tests**

Run: `cd middleware && python -m pytest -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add middleware/apns.py
git commit -m "perf(middleware): parallelize APNs delivery with shared httpx client"
```

---

### Task 7: Add Token Format Validation (Low)

**Files:**
- Modify: `middleware/main.py` (Pydantic models)
- Modify: `middleware/test_endpoints.py`

- [ ] **Step 1: Write failing tests**

Add to `test_endpoints.py`:

```python
def test_register_rejects_empty_token(client):
    resp = client.post("/register",
                       json={"token": ""},
                       headers={"X-Webhook-Token": "secret"})
    assert resp.status_code == 422


def test_webpush_rejects_empty_endpoint(client):
    resp = client.post("/register-webpush",
                       json={"endpoint": "", "p256dh": "key", "auth": "auth"},
                       headers={"X-Webhook-Token": "secret"})
    assert resp.status_code == 422
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd middleware && python -m pytest test_endpoints.py -v -k "empty"`
Expected: FAIL — returns 200/201 (empty strings accepted)

- [ ] **Step 3: Add validators**

Update the Pydantic models in `main.py`:

```python
from pydantic import BaseModel, field_validator

class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"
    environment: str = "production"

    @field_validator("token")
    @classmethod
    def token_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("token must not be empty")
        return v.strip()


class WebPushRegistration(BaseModel):
    endpoint: str
    p256dh: str
    auth: str

    @field_validator("endpoint")
    @classmethod
    def endpoint_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("endpoint must not be empty")
        return v.strip()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd middleware && python -m pytest test_endpoints.py -v`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add middleware/main.py middleware/test_endpoints.py
git commit -m "fix(middleware): validate token and endpoint are non-empty"
```

---

### Task 8: Extract Magic Numbers to Named Constants (Low)

**Files:**
- Modify: `middleware/main.py:223,311`

- [ ] **Step 1: Add constants and replace inline values**

At the top of `main.py`, after imports:

```python
PROXY_TIMEOUT = 60.0  # seconds — BHNM can be slow for large queries
```

Replace both occurrences of `timeout=60.0` in `_proxy_to_bhnm` and the catch-all proxy with `timeout=PROXY_TIMEOUT`.

- [ ] **Step 2: Run all tests**

Run: `cd middleware && python -m pytest -v`
Expected: All PASS

- [ ] **Step 3: Commit**

```bash
git add middleware/main.py
git commit -m "refactor(middleware): extract timeout magic numbers to named constants"
```

---

### Task 9: Update middleware CLAUDE.md (High)

**Files:**
- Modify: `middleware/CLAUDE.md`

- [ ] **Step 1: Update the Endpoints table**

Replace the existing endpoints table with:

```markdown
| Endpoint | Purpose | Consumer |
|---|---|---|
| `POST /register` | Register an APNs device token (with `active_secret` from `X-Webhook-Token` header) | iOS app |
| `DELETE /register` | Unregister an APNs device token | iOS app |
| `POST /register-webpush` | Register a Web Push subscription (with webhook secret from `X-Webhook-Token` header) | PWA |
| `GET /vapid-key` | Return the VAPID public key for Web Push subscription | PWA |
| `POST /webhook` | Receive a BHNM incident event and fan out push notifications | BHNM |
| `GET /health` | Health check — returns version and registered device count | Ops |
| `POST /api/proxy/incident/acknowledge` | Proxy incident acknowledge to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `POST /api/proxy/incident/unacknowledge` | Proxy incident unacknowledge to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `POST /api/proxy/ha-status` | Proxy HA status check to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `{path:path}` | Catch-all BHNM API proxy (auth via `X-Proxy-Token`, target via `X-BHNM-Target` or `servers.json` lookup) | iOS app, PWA |
```

- [ ] **Step 2: Update "Web Push (future)" in Deployment facts**

Change:
```
- **Web Push (future):** VAPID key pair, to be injected via environment variable
```
To:
```
- **Web Push:** VAPID key pair, configured via `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_CONTACT_EMAIL` env vars
```

- [ ] **Step 3: Add `webpush.py` to the Project Structure table**

Add row:
```
| `webpush.py` | Web Push delivery: VAPID-signed push via `pywebpush`, stale subscription detection. |
```

- [ ] **Step 4: Update intro paragraph**

Change "and forwards them as push notifications to registered iPhone devices" to "and forwards them as push notifications to registered iOS devices (APNs) and Android/web users (Web Push)."

- [ ] **Step 5: Commit**

```bash
git add middleware/CLAUDE.md
git commit -m "docs(middleware): update CLAUDE.md with current endpoints and Web Push status"
```
