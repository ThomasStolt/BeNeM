# M1: Web Push + Incidents (v0.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Web Push notification delivery to the middleware and push reception + deep-linking + incident UX polish to the PWA, bringing BeNeM's lighthouse feature — timely incident alerts — to Android users.

**Architecture:** The middleware gains a `webpush.py` sender (using `pywebpush` + VAPID) alongside the existing `apns.py`. A new `/register-webpush` endpoint stores browser push subscriptions keyed by webhook secret, and the `/webhook` handler fans out to both APNs and Web Push. The PWA gets a custom service worker (via `vite-plugin-pwa` injectManifest) that handles `push` and `notificationclick` events, a push registration module that subscribes via `pushManager.subscribe()` and posts to the middleware, and Settings UI for configuring the webhook secret and push toggle. Incident detail gains fetch-on-demand for deep-link cold-starts, and ACK/UnACK gets toast feedback.

**Tech Stack:** Python/FastAPI + pywebpush (middleware), React 18 + TypeScript + vite-plugin-pwa + Workbox (PWA), Vitest (PWA tests), pytest (middleware tests)

**Spec:** `docs/superpowers/specs/2026-04-06-pwa-feature-parity-design.md` § M1

---

## File Structure

### Middleware (`middleware/`)

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `config.py` | Add VAPID env var loading |
| Modify | `requirements.txt` | Add `pywebpush`, `pytest` |
| Modify | `.env.example` | Document VAPID env vars |
| Modify | `database.py` | Add `web_push_subscriptions` table + CRUD |
| Create | `webpush.py` | VAPID Web Push sender (parallel to `apns.py`) |
| Modify | `main.py` | Add `/register-webpush`, `GET /vapid-key`, update `/webhook` |
| Create | `test_database.py` | Tests for new DB functions |
| Create | `test_webpush.py` | Tests for Web Push sender |
| Create | `test_endpoints.py` | Tests for new endpoints |

### PWA (`pwa/`)

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `package.json` | Version bump 0.2.0, add `workbox-precaching` dev dep |
| Modify | `vite.config.ts` | Switch to `injectManifest` strategy |
| Create | `src/sw.ts` | Custom service worker: push + notificationclick handlers |
| Create | `src/lib/pushRegistration.ts` | Subscribe/unsubscribe push, POST to middleware |
| Create | `src/lib/pushRegistration.test.ts` | Tests for push registration logic |
| Modify | `src/features/settings/settingsStorage.ts` | Add webhook secret + push state storage |
| Modify | `src/features/settings/__tests__/settingsStorage.test.ts` | Tests for new storage functions |
| Modify | `src/lib/config.ts` | Add `webhookSecret` to `BhnmConfig` |
| Modify | `src/lib/config.test.ts` | Test webhookSecret in config |
| Modify | `src/features/settings/SettingsScreen.tsx` | Webhook secret field + push notifications section |
| Create | `src/components/Toast.tsx` | Toast/snackbar notification component |
| Create | `src/components/__tests__/Toast.test.tsx` | Toast tests |
| Modify | `src/features/incidents/IncidentDetailScreen.tsx` | Fetch-on-demand + toast on ACK/UnACK |
| Modify | `src/App.tsx` | SW `postMessage` listener for deep-link navigation |
| Modify | `src/features/incidents/IncidentListScreen.tsx` | Toast on swipe ACK/UnACK |

---

## Task 1: Middleware — VAPID Configuration

**Files:**
- Modify: `middleware/config.py`
- Modify: `middleware/requirements.txt`
- Modify: `middleware/.env.example`

- [ ] **Step 1: Add pywebpush and pytest to requirements.txt**

```
fastapi[standard]
httpx[http2]
PyJWT
cryptography
uvicorn
python-dotenv
pywebpush
pytest
pytest-asyncio
httpx
```

Note: `httpx` is already an indirect dep but we add it explicitly for test imports.

- [ ] **Step 2: Add VAPID env vars to config.py**

Add after the existing APNs config block (after line 17):

```python
# Web Push (VAPID) — optional; Web Push sending is disabled if not set
VAPID_PRIVATE_KEY: str = os.environ.get("VAPID_PRIVATE_KEY", "")
VAPID_PUBLIC_KEY: str = os.environ.get("VAPID_PUBLIC_KEY", "")
VAPID_CONTACT_EMAIL: str = os.environ.get("VAPID_CONTACT_EMAIL", "")
```

- [ ] **Step 3: Add VAPID vars to .env.example**

Add after the APNs block (after `APNS_PRIVATE_KEY_B64=`):

```bash
# ── Web Push (VAPID) — for PWA push notifications ───────────────────────────
# Generate VAPID key pair once:
#   python -c "from pywebpush import webpush; from py_vapid import Vapid; v = Vapid(); v.generate_keys(); print('PRIVATE:', v.private_pem()); print('PUBLIC:', v.public_key)"
# Or use: npx web-push generate-vapid-keys
VAPID_PRIVATE_KEY=
VAPID_PUBLIC_KEY=
VAPID_CONTACT_EMAIL=mailto:admin@example.com
```

- [ ] **Step 4: Commit**

```bash
cd middleware
git add config.py requirements.txt .env.example
git commit -m "feat(middleware): add VAPID config and pywebpush dependency for Web Push"
```

---

## Task 2: Middleware — Web Push Subscriptions Database

**Files:**
- Modify: `middleware/database.py`
- Create: `middleware/test_database.py`

- [ ] **Step 1: Write failing tests for web push subscription CRUD**

Create `middleware/test_database.py`:

```python
import os
import tempfile
import pytest

# Point DB at a temp file before importing database module
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()

from database import (
    init_db,
    save_web_push_subscription,
    get_web_push_subscriptions_for_secret,
    delete_web_push_subscription,
)


@pytest.fixture(autouse=True)
def _setup_db():
    """Re-init DB before each test."""
    init_db()
    yield


def test_save_and_get_subscription():
    save_web_push_subscription(
        endpoint="https://push.example.com/abc",
        p256dh="test-p256dh-key",
        auth="test-auth-secret",
        webhook_secret="secret-123",
    )
    subs = get_web_push_subscriptions_for_secret("secret-123")
    assert len(subs) == 1
    assert subs[0]["endpoint"] == "https://push.example.com/abc"
    assert subs[0]["p256dh"] == "test-p256dh-key"
    assert subs[0]["auth"] == "test-auth-secret"


def test_upsert_replaces_keys():
    save_web_push_subscription("https://push.example.com/abc", "old-p256dh", "old-auth", "secret-1")
    save_web_push_subscription("https://push.example.com/abc", "new-p256dh", "new-auth", "secret-1")
    subs = get_web_push_subscriptions_for_secret("secret-1")
    assert len(subs) == 1
    assert subs[0]["p256dh"] == "new-p256dh"
    assert subs[0]["auth"] == "new-auth"


def test_different_secrets_isolated():
    save_web_push_subscription("https://push.example.com/a", "k1", "a1", "secret-A")
    save_web_push_subscription("https://push.example.com/b", "k2", "a2", "secret-B")
    assert len(get_web_push_subscriptions_for_secret("secret-A")) == 1
    assert len(get_web_push_subscriptions_for_secret("secret-B")) == 1
    assert len(get_web_push_subscriptions_for_secret("secret-C")) == 0


def test_delete_subscription():
    save_web_push_subscription("https://push.example.com/del", "k", "a", "secret-1")
    assert len(get_web_push_subscriptions_for_secret("secret-1")) == 1
    delete_web_push_subscription("https://push.example.com/del")
    assert len(get_web_push_subscriptions_for_secret("secret-1")) == 0
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd middleware
pip install pywebpush pytest pytest-asyncio
pytest test_database.py -v
```

Expected: `ImportError` — `save_web_push_subscription` does not exist yet.

- [ ] **Step 3: Add web_push_subscriptions table and CRUD to database.py**

Add the table creation inside `init_db()`, after the `device_tokens` table and its migrations:

```python
        conn.execute("""
            CREATE TABLE IF NOT EXISTS web_push_subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                endpoint TEXT UNIQUE NOT NULL,
                p256dh TEXT NOT NULL,
                auth TEXT NOT NULL,
                webhook_secret TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
```

Add these functions after the existing `delete_token()` function:

```python
def save_web_push_subscription(endpoint: str, p256dh: str, auth: str, webhook_secret: str = ""):
    with get_conn() as conn:
        conn.execute(
            """INSERT INTO web_push_subscriptions (endpoint, p256dh, auth, webhook_secret)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(endpoint) DO UPDATE SET p256dh=?, auth=?, webhook_secret=?""",
            (endpoint, p256dh, auth, webhook_secret, p256dh, auth, webhook_secret),
        )


def get_web_push_subscriptions_for_secret(secret: str) -> list[dict]:
    """Return all Web Push subscriptions registered for the given webhook secret."""
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT endpoint, p256dh, auth FROM web_push_subscriptions WHERE webhook_secret = ?",
            (secret,),
        ).fetchall()
    return [{"endpoint": r[0], "p256dh": r[1], "auth": r[2]} for r in rows]


def delete_web_push_subscription(endpoint: str):
    """Remove a Web Push subscription (called when push service returns 410 Gone)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM web_push_subscriptions WHERE endpoint = ?", (endpoint,))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd middleware
pytest test_database.py -v
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd middleware
git add database.py test_database.py
git commit -m "feat(middleware): add web_push_subscriptions table and CRUD functions"
```

---

## Task 3: Middleware — Web Push Sender

**Files:**
- Create: `middleware/webpush.py`
- Create: `middleware/test_webpush.py`

- [ ] **Step 1: Write failing tests for Web Push sender**

Create `middleware/test_webpush.py`:

```python
import os
import pytest
from unittest.mock import patch, MagicMock

# Ensure VAPID config is set for tests
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "")

from webpush import build_payload, send_web_push_to_all


def test_build_payload_all_fields():
    payload = build_payload("Server Down", "core-switch-01 unreachable", "42", "critical")
    assert payload["title"] == "Server Down"
    assert payload["body"] == "core-switch-01 unreachable"
    assert payload["incident_id"] == "42"
    assert payload["severity"] == "critical"


def test_build_payload_missing_optional():
    payload = build_payload("Alert", "Something happened", "", "")
    assert payload["title"] == "Alert"
    assert payload["body"] == "Something happened"
    assert payload["incident_id"] == ""
    assert payload["severity"] == ""


@pytest.mark.asyncio
async def test_send_web_push_to_all_returns_gone_endpoints():
    subscriptions = [
        {"endpoint": "https://push.example.com/ok", "p256dh": "k1", "auth": "a1"},
        {"endpoint": "https://push.example.com/gone", "p256dh": "k2", "auth": "a2"},
    ]

    def mock_webpush_send(subscription_info, data, vapid_private_key, vapid_claims):
        if subscription_info["endpoint"] == "https://push.example.com/gone":
            from pywebpush import WebPushException
            response = MagicMock()
            response.status_code = 410
            raise WebPushException("Gone", response=response)

    with patch("webpush.webpush_send", side_effect=mock_webpush_send):
        gone = await send_web_push_to_all(subscriptions, "Title", "Body", "99")

    assert gone == ["https://push.example.com/gone"]


@pytest.mark.asyncio
async def test_send_web_push_disabled_when_no_vapid_key():
    """When VAPID keys are not configured, send_web_push_to_all should return empty (no-op)."""
    subscriptions = [
        {"endpoint": "https://push.example.com/x", "p256dh": "k", "auth": "a"},
    ]
    # With empty VAPID_PRIVATE_KEY (default in test env), should skip sending
    gone = await send_web_push_to_all(subscriptions, "Title", "Body", "1")
    assert gone == []
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd middleware
pytest test_webpush.py -v
```

Expected: `ModuleNotFoundError: No module named 'webpush'`.

- [ ] **Step 3: Create webpush.py**

Create `middleware/webpush.py`:

```python
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
            webpush_send(
                subscription_info=subscription_info,
                data=payload,
                vapid_private_key=VAPID_PRIVATE_KEY,
                vapid_claims=vapid_claims,
            )
            print(f"[WebPush] Sent to {sub['endpoint'][:50]}...")
        except WebPushException as e:
            status = getattr(e.response, "status_code", 0) if e.response else 0
            if status == 410:
                gone_endpoints.append(sub["endpoint"])
                print(f"[WebPush] Subscription expired (410): {sub['endpoint'][:50]}...")
            else:
                print(f"[WebPush] Failed ({status}): {e}")
        except Exception as e:
            print(f"[WebPush] Error: {e}")

    return gone_endpoints
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd middleware
pytest test_webpush.py -v
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd middleware
git add webpush.py test_webpush.py
git commit -m "feat(middleware): add Web Push sender with VAPID signing"
```

---

## Task 4: Middleware — Endpoints and Webhook Integration

**Files:**
- Modify: `middleware/main.py`
- Create: `middleware/test_endpoints.py`

- [ ] **Step 1: Write failing tests for new endpoints**

Create `middleware/test_endpoints.py`:

```python
import os
import tempfile

# Set up test env before imports
_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")  # base64("test")
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "test-vapid-public-key")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "mailto:test@test.com")

import pytest
from fastapi.testclient import TestClient
from database import init_db, get_web_push_subscriptions_for_secret
from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _setup_db():
    init_db()
    yield


def test_register_webpush_creates_subscription():
    resp = client.post(
        "/register-webpush",
        json={
            "endpoint": "https://fcm.googleapis.com/fcm/send/abc123",
            "p256dh": "test-public-key",
            "auth": "test-auth-secret",
        },
        headers={"X-Webhook-Token": "my-webhook-secret"},
    )
    assert resp.status_code == 201
    subs = get_web_push_subscriptions_for_secret("my-webhook-secret")
    assert len(subs) == 1
    assert subs[0]["endpoint"] == "https://fcm.googleapis.com/fcm/send/abc123"


def test_register_webpush_upsert_returns_200():
    client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k1", "auth": "a1"},
        headers={"X-Webhook-Token": "secret"},
    )
    resp = client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k2", "auth": "a2"},
        headers={"X-Webhook-Token": "secret"},
    )
    assert resp.status_code == 200
    subs = get_web_push_subscriptions_for_secret("secret")
    assert len(subs) == 1
    assert subs[0]["p256dh"] == "k2"


def test_register_webpush_requires_webhook_token():
    resp = client.post(
        "/register-webpush",
        json={"endpoint": "https://push.example.com/x", "p256dh": "k", "auth": "a"},
    )
    assert resp.status_code == 400


def test_vapid_key_endpoint():
    resp = client.get("/vapid-key")
    assert resp.status_code == 200
    data = resp.json()
    assert data["publicKey"] == "test-vapid-public-key"


def test_vapid_key_returns_404_when_not_configured():
    """When VAPID_PUBLIC_KEY is empty, /vapid-key should return 404."""
    import config
    original = config.VAPID_PUBLIC_KEY
    config.VAPID_PUBLIC_KEY = ""
    try:
        resp = client.get("/vapid-key")
        assert resp.status_code == 404
    finally:
        config.VAPID_PUBLIC_KEY = original
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd middleware
pytest test_endpoints.py -v
```

Expected: failures — endpoints don't exist yet.

- [ ] **Step 3: Add imports to main.py**

Add to the import block at the top of `main.py` (after the existing database imports):

```python
from database import init_db, save_token, get_tokens_for_secret, get_all_tokens, delete_token, \
    save_web_push_subscription, get_web_push_subscriptions_for_secret, delete_web_push_subscription
from apns import send_to_all
from webpush import send_web_push_to_all
from config import MIDDLEWARE_PORT, VAPID_PUBLIC_KEY
```

This replaces the existing two import lines:
```python
from database import init_db, save_token, get_tokens_for_secret, get_all_tokens, delete_token
from apns import send_to_all
```

Also add to the top-level imports:

```python
from config import MIDDLEWARE_PORT, VAPID_PUBLIC_KEY
```

This replaces the existing:
```python
from config import MIDDLEWARE_PORT
```

- [ ] **Step 4: Add /register-webpush endpoint**

Add after the `/register` DELETE endpoint (after line 89) and before the webhook section:

```python
# ── Web Push Subscription Registration ───────────────────────────────────────

class WebPushRegistration(BaseModel):
    endpoint: str
    p256dh: str
    auth: str

@app.post("/register-webpush", status_code=201)
def register_webpush(body: WebPushRegistration, request: Request, response: Response):
    webhook_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not webhook_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    existing = get_web_push_subscriptions_for_secret(webhook_secret)
    is_update = any(s["endpoint"] == body.endpoint for s in existing)
    save_web_push_subscription(body.endpoint, body.p256dh, body.auth, webhook_secret)
    if is_update:
        response.status_code = 200
    print(f"[WebPush] Subscription {'updated' if is_update else 'registered'}: {body.endpoint[:50]}...")
    return {"status": "ok"}
```

- [ ] **Step 5: Add GET /vapid-key endpoint**

Add after `/register-webpush`:

```python
@app.get("/vapid-key")
def get_vapid_key():
    if not VAPID_PUBLIC_KEY:
        raise HTTPException(status_code=404, detail="Web Push not configured")
    return {"publicKey": VAPID_PUBLIC_KEY}
```

- [ ] **Step 6: Update /webhook to send Web Push alongside APNs**

Replace the webhook handler body (the section after `tokens = get_tokens_for_secret(secret)`) with code that also sends Web Push. Replace lines 125–135 in `main.py`:

Old code:
```python
    tokens = get_tokens_for_secret(secret)
    if not tokens:
        print(f"[Webhook] Rejected: no registered devices for this secret.")
        raise HTTPException(status_code=403, detail="Forbidden: unknown secret")

    stale = await send_to_all(tokens, title, body, incident_id)
    for t in stale:
        delete_token(t)
        print(f"[Cleanup] Removed stale token ...{t[-8:]}")

    return {"status": "ok", "notified": len(tokens) - len(stale)}
```

New code:
```python
    tokens = get_tokens_for_secret(secret)
    web_push_subs = get_web_push_subscriptions_for_secret(secret)

    if not tokens and not web_push_subs:
        print(f"[Webhook] Rejected: no registered devices for this secret.")
        raise HTTPException(status_code=403, detail="Forbidden: unknown secret")

    # Send APNs
    apns_stale = await send_to_all(tokens, title, body, incident_id) if tokens else []
    for t in apns_stale:
        delete_token(t)
        print(f"[Cleanup] Removed stale APNs token ...{t[-8:]}")

    # Send Web Push
    webpush_gone = await send_web_push_to_all(web_push_subs, title, body, incident_id) if web_push_subs else []
    for endpoint in webpush_gone:
        delete_web_push_subscription(endpoint)
        print(f"[Cleanup] Removed expired Web Push subscription: {endpoint[:50]}...")

    notified = (len(tokens) - len(apns_stale)) + (len(web_push_subs) - len(webpush_gone))
    return {"status": "ok", "notified": notified}
```

- [ ] **Step 7: Add Response import**

`Response` is already imported from `fastapi.responses`. Verify the existing import line includes it. It does (line 10): `from fastapi.responses import Response`. Good — no change needed.

But `Response` from `fastapi` is also needed for the `/register-webpush` endpoint's `response` parameter. Add to the fastapi import line:

Old:
```python
from fastapi import FastAPI, Request, HTTPException
```

New:
```python
from fastapi import FastAPI, Request, HTTPException, Response as FastAPIResponse
```

Wait — actually FastAPI's dependency injection for `Response` uses `from fastapi import Response`. But there's already `from fastapi.responses import Response` on line 10. These are different classes. The DI `Response` parameter needs the starlette one. Actually, FastAPI supports using `response: Response` as a parameter where `Response` is from `starlette.responses` (which `fastapi.responses.Response` is). So the existing import works. Use it directly:

Change the endpoint signature to use the already-imported `Response`:

```python
@app.post("/register-webpush", status_code=201)
def register_webpush(body: WebPushRegistration, request: Request, response: Response):
```

This works because `Response` is already imported from `fastapi.responses`.

- [ ] **Step 8: Run tests to verify they pass**

```bash
cd middleware
pytest test_endpoints.py -v
```

Expected: All 5 tests PASS.

- [ ] **Step 9: Commit**

```bash
cd middleware
git add main.py test_endpoints.py
git commit -m "feat(middleware): add /register-webpush, /vapid-key endpoints and Web Push webhook delivery"
```

---

## Task 5: PWA — Settings Storage for Webhook Secret and Push State

**Files:**
- Modify: `pwa/src/features/settings/settingsStorage.ts`
- Modify: `pwa/src/features/settings/__tests__/settingsStorage.test.ts`
- Modify: `pwa/src/lib/config.ts`
- Modify: `pwa/src/lib/config.test.ts`

- [ ] **Step 1: Write failing tests for new storage functions**

Add to the bottom of `pwa/src/features/settings/__tests__/settingsStorage.test.ts`:

```typescript
import {
  loadWebhookSecret,
  saveWebhookSecret,
  clearWebhookSecret,
  loadPushEnabled,
  savePushEnabled,
} from '../settingsStorage';

describe('webhookSecret', () => {
  beforeEach(() => localStorage.clear());

  it('returns null when not set', () => {
    expect(loadWebhookSecret()).toBeNull();
  });

  it('saves and loads', () => {
    saveWebhookSecret('abc123');
    expect(loadWebhookSecret()).toBe('abc123');
  });

  it('trims whitespace', () => {
    saveWebhookSecret('  abc  ');
    expect(loadWebhookSecret()).toBe('abc');
  });

  it('clears', () => {
    saveWebhookSecret('abc');
    clearWebhookSecret();
    expect(loadWebhookSecret()).toBeNull();
  });
});

describe('pushEnabled', () => {
  beforeEach(() => localStorage.clear());

  it('defaults to false when not set', () => {
    expect(loadPushEnabled()).toBe(false);
  });

  it('saves true and loads', () => {
    savePushEnabled(true);
    expect(loadPushEnabled()).toBe(true);
  });

  it('saves false and loads', () => {
    savePushEnabled(true);
    savePushEnabled(false);
    expect(loadPushEnabled()).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd pwa
npx vitest run src/features/settings/__tests__/settingsStorage.test.ts
```

Expected: `loadWebhookSecret is not exported` error.

- [ ] **Step 3: Add webhook secret and push state to settingsStorage.ts**

Add to the bottom of `pwa/src/features/settings/settingsStorage.ts`:

```typescript
const WEBHOOK_SECRET_KEY = 'benem:webhook-secret';
const PUSH_ENABLED_KEY = 'benem:push-enabled';

export function loadWebhookSecret(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(WEBHOOK_SECRET_KEY);
}

export function saveWebhookSecret(value: string): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(WEBHOOK_SECRET_KEY, value.trim());
}

export function clearWebhookSecret(): void {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(WEBHOOK_SECRET_KEY);
}

export function loadPushEnabled(): boolean {
  if (typeof window === 'undefined') return false;
  return window.localStorage.getItem(PUSH_ENABLED_KEY) === 'true';
}

export function savePushEnabled(enabled: boolean): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(PUSH_ENABLED_KEY, String(enabled));
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd pwa
npx vitest run src/features/settings/__tests__/settingsStorage.test.ts
```

Expected: All tests PASS.

- [ ] **Step 5: Write failing test for webhookSecret in config**

Add to `pwa/src/lib/config.test.ts`:

```typescript
import { loadWebhookSecret } from '../features/settings/settingsStorage';

// Add this test case inside the existing describe block or at the end:
it('includes webhookSecret from localStorage', () => {
  localStorage.setItem('benem:webhook-secret', 'my-secret');
  notifyConfigChanged();
  const config = getSnapshotForTest();
  expect(config.webhookSecret).toBe('my-secret');
});

it('webhookSecret is undefined when not set', () => {
  localStorage.removeItem('benem:webhook-secret');
  notifyConfigChanged();
  const config = getSnapshotForTest();
  expect(config.webhookSecret).toBeUndefined();
});
```

- [ ] **Step 6: Run test to verify it fails**

```bash
cd pwa
npx vitest run src/lib/config.test.ts
```

Expected: `webhookSecret` does not exist on type `BhnmConfig`.

- [ ] **Step 7: Add webhookSecret to BhnmConfig**

In `pwa/src/lib/config.ts`, add to the `BhnmConfig` interface:

```typescript
export interface BhnmConfig {
  /** Base URL the client should hit. `/bhnm` in both dev (Vite proxy) and prod (Caddy handle_path). */
  baseUrl: string;
  apiKey: string;
  pin?: string;
  webhookSecret?: string;
  isConfigured: boolean;
}
```

Add the import at the top alongside the existing imports:

```typescript
import { loadApiKey, loadPin, loadWebhookSecret } from '../features/settings/settingsStorage';
```

This replaces:
```typescript
import { loadApiKey } from '../features/settings/settingsStorage';
import { loadPin } from '../features/settings/settingsStorage';
```

Update `buildSnapshot()` to include `webhookSecret`:

```typescript
function buildSnapshot(): BhnmConfig {
  const storedKey = loadApiKey();
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  const envPin = (import.meta.env.VITE_BHNM_PIN as string | undefined) ?? '';
  const apiKey = storedKey && storedKey.length > 0 ? storedKey : envKey;
  const storedPin = loadPin();
  const pin = storedPin && storedPin.length > 0 ? storedPin : (envPin.length > 0 ? envPin : undefined);
  const storedSecret = loadWebhookSecret();
  const webhookSecret = storedSecret && storedSecret.length > 0 ? storedSecret : undefined;
  return {
    baseUrl: '/bhnm',
    apiKey,
    pin,
    webhookSecret,
    isConfigured: apiKey.length > 0,
  };
}
```

- [ ] **Step 8: Run all config tests**

```bash
cd pwa
npx vitest run src/lib/config.test.ts
```

Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
cd pwa
git add src/features/settings/settingsStorage.ts \
        src/features/settings/__tests__/settingsStorage.test.ts \
        src/lib/config.ts src/lib/config.test.ts
git commit -m "feat(pwa): add webhook secret and push state to settings storage and config"
```

---

## Task 6: PWA — Custom Service Worker

**Files:**
- Modify: `pwa/package.json` (add `workbox-precaching` dev dep)
- Modify: `pwa/vite.config.ts`
- Create: `pwa/src/sw.ts`

- [ ] **Step 1: Install workbox-precaching**

```bash
cd pwa
npm install -D workbox-precaching
```

- [ ] **Step 2: Create the custom service worker**

Create `pwa/src/sw.ts`:

```typescript
/// <reference lib="webworker" />
declare const self: ServiceWorkerGlobalScope;

import { precacheAndRoute } from 'workbox-precaching';

// Workbox precache manifest — injected by vite-plugin-pwa at build time
precacheAndRoute(self.__WB_MANIFEST);

// ── Push Notification Handler ───────────────────────────────────────────────

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data: { title?: string; body?: string; incident_id?: string; severity?: string };
  try {
    data = event.data.json();
  } catch {
    data = { title: 'BeNeM', body: event.data.text() };
  }

  const title = data.title ?? 'BeNeM';
  const body = data.body ?? '';

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-96.png',
      data: { incident_id: data.incident_id },
      tag: data.incident_id ? `incident-${data.incident_id}` : undefined,
    }),
  );
});

// ── Notification Click — Deep-link to Incident Detail ───────────────────────

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const incidentId = event.notification.data?.incident_id;
  const targetUrl = incidentId ? `/incident/${incidentId}` : '/';

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        // If the PWA is already open, focus it and navigate
        for (const client of windowClients) {
          if (new URL(client.url).origin === self.location.origin) {
            client.focus();
            client.postMessage({ type: 'navigate', url: targetUrl });
            return;
          }
        }
        // Otherwise open a new window
        return self.clients.openWindow(targetUrl);
      }),
  );
});
```

- [ ] **Step 3: Update vite.config.ts to use injectManifest**

Replace the `VitePWA({...})` plugin config in `pwa/vite.config.ts`:

Old:
```typescript
      VitePWA({
        registerType: 'autoUpdate',
        includeAssets: ['icons/*'],
        manifest: {
          name: 'BeNeM',
          short_name: 'BeNeM',
          description: 'BHNM incident monitoring',
          theme_color: '#0f172a',
          background_color: '#0f172a',
          display: 'standalone',
          start_url: '/',
          icons: [],
        },
        workbox: {
          globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        },
      }),
```

New:
```typescript
      VitePWA({
        strategies: 'injectManifest',
        srcDir: 'src',
        filename: 'sw.ts',
        registerType: 'autoUpdate',
        includeAssets: ['icons/*'],
        manifest: {
          name: 'BeNeM',
          short_name: 'BeNeM',
          description: 'BHNM incident monitoring',
          theme_color: '#0f172a',
          background_color: '#0f172a',
          display: 'standalone',
          start_url: '/',
          icons: [],
        },
        injectManifest: {
          globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        },
      }),
```

- [ ] **Step 4: Verify the build succeeds**

```bash
cd pwa
npm run build
```

Expected: Build succeeds, `dist/sw.js` is generated with Workbox precache manifest injected.

- [ ] **Step 5: Commit**

```bash
cd pwa
git add src/sw.ts vite.config.ts package.json package-lock.json
git commit -m "feat(pwa): add custom service worker with push and notificationclick handlers"
```

---

## Task 7: PWA — Push Registration Module

**Files:**
- Create: `pwa/src/lib/pushRegistration.ts`
- Create: `pwa/src/lib/pushRegistration.test.ts`

- [ ] **Step 1: Write failing tests**

Create `pwa/src/lib/pushRegistration.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { urlBase64ToUint8Array } from './pushRegistration';

describe('urlBase64ToUint8Array', () => {
  it('converts a base64url string to Uint8Array', () => {
    // "AAAA" in base64 is [0, 0, 0]
    const result = urlBase64ToUint8Array('AAAA');
    expect(result).toBeInstanceOf(Uint8Array);
    expect(result.length).toBe(3);
    expect(result[0]).toBe(0);
  });

  it('handles base64url padding', () => {
    // base64url uses - and _ instead of + and /
    const result = urlBase64ToUint8Array('AQID');
    expect(result[0]).toBe(1);
    expect(result[1]).toBe(2);
    expect(result[2]).toBe(3);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd pwa
npx vitest run src/lib/pushRegistration.test.ts
```

Expected: `urlBase64ToUint8Array` is not exported.

- [ ] **Step 3: Create pushRegistration.ts**

Create `pwa/src/lib/pushRegistration.ts`:

```typescript
/**
 * Convert a VAPID public key from base64url to Uint8Array
 * (required by pushManager.subscribe).
 */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

/**
 * Fetch the VAPID public key from the middleware.
 */
export async function fetchVapidKey(baseUrl: string): Promise<string> {
  const resp = await fetch(`${baseUrl}/vapid-key`);
  if (!resp.ok) throw new Error(`Failed to fetch VAPID key: HTTP ${resp.status}`);
  const data = await resp.json();
  return data.publicKey;
}

export type PushState =
  | { status: 'unsupported' }
  | { status: 'denied' }
  | { status: 'unregistered' }
  | { status: 'registered'; endpoint: string }
  | { status: 'error'; message: string };

/**
 * Get the current push registration state.
 */
export function getPushState(): PushState {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    return { status: 'unsupported' };
  }
  if (Notification.permission === 'denied') {
    return { status: 'denied' };
  }
  return { status: 'unregistered' };
}

/**
 * Subscribe to Web Push and register with the middleware.
 * Returns the push subscription endpoint on success.
 */
export async function subscribeToPush(
  baseUrl: string,
  webhookSecret: string,
): Promise<string> {
  // 1. Request notification permission
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    throw new Error('Notification permission denied');
  }

  // 2. Get VAPID key
  const vapidKey = await fetchVapidKey(baseUrl);

  // 3. Get service worker registration
  const swReg = await navigator.serviceWorker.ready;

  // 4. Subscribe to push
  const subscription = await swReg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidKey),
  });

  const subJson = subscription.toJSON();
  if (!subJson.endpoint || !subJson.keys?.p256dh || !subJson.keys?.auth) {
    throw new Error('Invalid push subscription — missing keys');
  }

  // 5. Register with middleware
  const resp = await fetch(`${baseUrl}/register-webpush`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Token': webhookSecret,
    },
    body: JSON.stringify({
      endpoint: subJson.endpoint,
      p256dh: subJson.keys.p256dh,
      auth: subJson.keys.auth,
    }),
  });

  if (!resp.ok) {
    throw new Error(`Push registration failed: HTTP ${resp.status}`);
  }

  return subJson.endpoint;
}

/**
 * Unsubscribe from Web Push.
 */
export async function unsubscribeFromPush(): Promise<void> {
  const swReg = await navigator.serviceWorker.ready;
  const subscription = await swReg.pushManager.getSubscription();
  if (subscription) {
    await subscription.unsubscribe();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd pwa
npx vitest run src/lib/pushRegistration.test.ts
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd pwa
git add src/lib/pushRegistration.ts src/lib/pushRegistration.test.ts
git commit -m "feat(pwa): add push registration module with VAPID subscribe/unsubscribe"
```

---

## Task 8: PWA — Settings Screen: Webhook Secret + Push Notifications UI

**Files:**
- Modify: `pwa/src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Add imports to SettingsScreen.tsx**

Add these imports at the top:

```typescript
import {
  loadApiKey, saveApiKey, clearApiKey,
  loadPin, savePin, clearPin,
  loadWebhookSecret, saveWebhookSecret, clearWebhookSecret,
  loadPushEnabled, savePushEnabled,
} from './settingsStorage';
import { subscribeToPush, unsubscribeFromPush, getPushState, type PushState } from '../../lib/pushRegistration';
```

Replace the existing import:
```typescript
import { loadApiKey, saveApiKey, clearApiKey, loadPin, savePin, clearPin } from './settingsStorage';
```

- [ ] **Step 2: Add webhook secret state and push state**

Add inside `SettingsScreen()`, after the existing state declarations (after `testError` state):

```typescript
  const [webhookSecret, setWebhookSecret] = useState<string>(() => loadWebhookSecret() ?? '');
  const [pushEnabled, setPushEnabled] = useState<boolean>(() => loadPushEnabled());
  const [pushState, setPushState] = useState<PushState>(getPushState);
  const [pushLoading, setPushLoading] = useState(false);
```

- [ ] **Step 3: Update onSave to include webhook secret**

Replace the `onSave` handler:

```typescript
  const onSave = (event: FormEvent) => {
    event.preventDefault();
    saveApiKey(apiKey);
    savePin(pin);
    saveWebhookSecret(webhookSecret);
    notifyConfigChanged();
    setApiKey(loadApiKey() ?? '');
    setPin(loadPin() ?? '');
    setWebhookSecret(loadWebhookSecret() ?? '');
    setStatusMessage('Saved.');
    setTestState('idle');
    setTestResult(null);
  };
```

- [ ] **Step 4: Update onClear to include webhook secret and push state**

Replace the `onClear` handler:

```typescript
  const onClear = () => {
    clearApiKey();
    clearPin();
    clearWebhookSecret();
    savePushEnabled(false);
    notifyConfigChanged();
    setApiKey('');
    setPin('');
    setWebhookSecret('');
    setPushEnabled(false);
    setStatusMessage('Cleared.');
    setTestState('idle');
    setTestResult(null);
  };
```

- [ ] **Step 5: Add push toggle handler**

Add after `onTestConnection`:

```typescript
  const onTogglePush = async () => {
    if (pushLoading) return;
    setPushLoading(true);
    try {
      if (pushEnabled) {
        await unsubscribeFromPush();
        savePushEnabled(false);
        setPushEnabled(false);
        setPushState({ status: 'unregistered' });
      } else {
        if (!webhookSecret) {
          setPushState({ status: 'error', message: 'Webhook secret is required for push notifications' });
          return;
        }
        const endpoint = await subscribeToPush(config.baseUrl, webhookSecret);
        savePushEnabled(true);
        setPushEnabled(true);
        setPushState({ status: 'registered', endpoint });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Push registration failed';
      setPushState({ status: 'error', message: msg });
      if (pushEnabled) {
        savePushEnabled(false);
        setPushEnabled(false);
      }
    } finally {
      setPushLoading(false);
    }
  };

  const onReRegisterPush = async () => {
    if (!webhookSecret) return;
    setPushLoading(true);
    try {
      await unsubscribeFromPush();
      const endpoint = await subscribeToPush(config.baseUrl, webhookSecret);
      savePushEnabled(true);
      setPushEnabled(true);
      setPushState({ status: 'registered', endpoint });
    } catch (err) {
      setPushState({ status: 'error', message: err instanceof Error ? err.message : 'Re-registration failed' });
    } finally {
      setPushLoading(false);
    }
  };
```

- [ ] **Step 6: Add Webhook Secret field to the Connection section**

Add after the PIN `</div>` (after the PIN input section, before the closing `</div>` of the bg-slate-900 container):

```tsx
            {/* Webhook Secret */}
            <div className="p-3 border-t border-slate-800">
              <label htmlFor="webhook-secret" className="block text-xs text-slate-400 mb-1.5">
                Webhook Secret <span className="text-slate-600">(for push notifications)</span>
              </label>
              <input
                id="webhook-secret"
                type="password"
                autoComplete="off"
                spellCheck={false}
                placeholder="Same secret as in BHNM webhook URL"
                value={webhookSecret}
                onChange={(e) => setWebhookSecret(e.target.value)}
                className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
              />
            </div>
```

- [ ] **Step 7: Add Push Notifications section**

Add after the Save/Clear buttons section and status message, before the About section:

```tsx
        {/* Push Notifications */}
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">Push Notifications</div>
          <div className="bg-slate-900 rounded-lg overflow-hidden">
            {/* Enable/disable toggle */}
            <div className="p-3 flex items-center justify-between">
              <div>
                <div className="text-sm font-medium">Push Notifications</div>
                <div className="text-xs text-slate-500 mt-0.5">
                  {pushState.status === 'unsupported' && 'Not supported in this browser'}
                  {pushState.status === 'denied' && 'Permission denied — enable in browser settings'}
                  {pushState.status === 'unregistered' && 'Not registered'}
                  {pushState.status === 'registered' && 'Registered and active'}
                  {pushState.status === 'error' && pushState.message}
                </div>
              </div>
              <button
                type="button"
                onClick={onTogglePush}
                disabled={pushLoading || pushState.status === 'unsupported' || pushState.status === 'denied'}
                className={`relative w-11 h-6 rounded-full transition-colors ${
                  pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
                } disabled:opacity-50 disabled:cursor-not-allowed`}
                role="switch"
                aria-checked={pushEnabled}
              >
                <span
                  className={`block w-5 h-5 rounded-full bg-white shadow transition-transform ${
                    pushEnabled ? 'translate-x-5.5' : 'translate-x-0.5'
                  }`}
                  style={{ transform: pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
                />
              </button>
            </div>

            {/* Re-register button */}
            {pushEnabled && (
              <div className="p-3 border-t border-slate-800">
                <button
                  type="button"
                  onClick={onReRegisterPush}
                  disabled={pushLoading}
                  className="w-full text-sm text-slate-400 hover:text-white py-1 disabled:opacity-50"
                >
                  {pushLoading ? 'Registering...' : 'Re-register Push Subscription'}
                </button>
              </div>
            )}
          </div>
        </div>
```

- [ ] **Step 8: Update version display**

In the About section, change version from `0.1.1` to `0.2.0`:

Old:
```tsx
              <dd>0.1.1</dd>
```

New:
```tsx
              <dd>0.2.0</dd>
```

- [ ] **Step 9: Verify the build**

```bash
cd pwa
npm run typecheck
```

Expected: No type errors.

- [ ] **Step 10: Commit**

```bash
cd pwa
git add src/features/settings/SettingsScreen.tsx
git commit -m "feat(pwa): add webhook secret field and push notifications toggle to settings"
```

---

## Task 9: PWA — Toast Component

**Files:**
- Create: `pwa/src/components/Toast.tsx`
- Create: `pwa/src/components/__tests__/Toast.test.tsx`

- [ ] **Step 1: Write failing test**

Create `pwa/src/components/__tests__/Toast.test.tsx`:

```typescript
import { render, screen, act } from '@testing-library/react';
import { Toast, type ToastMessage } from '../Toast';

describe('Toast', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders nothing when message is null', () => {
    const { container } = render(<Toast message={null} onDismiss={() => {}} />);
    expect(container.firstChild).toBeNull();
  });

  it('renders success message', () => {
    const msg: ToastMessage = { text: 'Acknowledged!', type: 'success' };
    render(<Toast message={msg} onDismiss={() => {}} />);
    expect(screen.getByText('Acknowledged!')).toBeInTheDocument();
  });

  it('renders error message', () => {
    const msg: ToastMessage = { text: 'Failed', type: 'error' };
    render(<Toast message={msg} onDismiss={() => {}} />);
    expect(screen.getByText('Failed')).toBeInTheDocument();
  });

  it('auto-dismisses after timeout', () => {
    const onDismiss = vi.fn();
    const msg: ToastMessage = { text: 'Done', type: 'success' };
    render(<Toast message={msg} onDismiss={onDismiss} />);

    act(() => {
      vi.advanceTimersByTime(3000);
    });

    expect(onDismiss).toHaveBeenCalledOnce();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd pwa
npx vitest run src/components/__tests__/Toast.test.tsx
```

Expected: `Cannot find module '../Toast'`.

- [ ] **Step 3: Create Toast.tsx**

Create `pwa/src/components/Toast.tsx`:

```typescript
import { useEffect } from 'react';

export interface ToastMessage {
  text: string;
  type: 'success' | 'error';
}

interface ToastProps {
  message: ToastMessage | null;
  onDismiss: () => void;
  durationMs?: number;
}

export function Toast({ message, onDismiss, durationMs = 3000 }: ToastProps) {
  useEffect(() => {
    if (!message) return;
    const timer = setTimeout(onDismiss, durationMs);
    return () => clearTimeout(timer);
  }, [message, onDismiss, durationMs]);

  if (!message) return null;

  const bgClass = message.type === 'success'
    ? 'bg-emerald-600'
    : 'bg-red-600';

  return (
    <div
      className={`fixed bottom-4 left-4 right-4 z-50 ${bgClass} text-white text-sm font-medium px-4 py-3 rounded-lg shadow-lg text-center`}
      role="status"
      aria-live="polite"
    >
      {message.text}
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd pwa
npx vitest run src/components/__tests__/Toast.test.tsx
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd pwa
git add src/components/Toast.tsx src/components/__tests__/Toast.test.tsx
git commit -m "feat(pwa): add Toast component for success/error feedback"
```

---

## Task 10: PWA — Incident Detail Fetch-on-Demand + ACK Toast

**Files:**
- Modify: `pwa/src/features/incidents/IncidentDetailScreen.tsx`
- Modify: `pwa/src/lib/api/incidents.ts`
- Modify: `pwa/src/lib/api/types.ts`

The current `IncidentDetailScreen` relies on the full incident list being cached via `useIncidents()`. When a push notification deep-links to `/incident/:id` on a cold start, the list hasn't loaded yet and the user sees "Incident not found." We need to:
1. If the incident isn't in the cached list, show a loading state while the list fetches.
2. Add toast feedback for ACK/UnACK success.

- [ ] **Step 1: Update IncidentDetailScreen with toast and improved loading**

Replace the full content of `pwa/src/features/incidents/IncidentDetailScreen.tsx`:

```typescript
import { useState, useCallback } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { useConfig } from '../../lib/config';
import { acknowledgeIncident, unacknowledgeIncident } from '../../lib/api/incidents';
import { SeverityBadge } from './SeverityBadge';
import { Toast, type ToastMessage } from '../../components/Toast';

function formatTimestamp(d: Date): string {
  return d.toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  }) + ' · ' + d.toLocaleTimeString('en-US', {
    hour: '2-digit', minute: '2-digit', hour12: false,
  });
}

function formatDuration(start: Date): string {
  const diffMs = Date.now() - start.getTime();
  const min = Math.floor(diffMs / 60_000);
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  const remainMin = min % 60;
  if (hr < 24) return `${hr}h ${remainMin}m`;
  const days = Math.floor(hr / 24);
  return `${days}d ${hr % 24}h`;
}

const STATUS_CLASSES: Record<string, string> = {
  active: 'bg-amber-500/20 text-amber-400',
  acknowledged: 'bg-emerald-500/20 text-emerald-400',
  resolved: 'bg-slate-500/20 text-slate-400',
  closed: 'bg-slate-500/20 text-slate-400',
};

export function IncidentDetailScreen() {
  const { id } = useParams();
  const { data: incidents, isLoading, isFetching } = useIncidents();
  const config = useConfig();
  const queryClient = useQueryClient();
  const [isAcking, setIsAcking] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const dismissToast = useCallback(() => setToast(null), []);

  const incident = incidents?.find((i) => i.incidentId === id);

  // Still loading the incident list (cold start / deep-link)
  if (isLoading || (isFetching && !incident)) {
    return (
      <div className="p-6">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <p className="mt-4 text-slate-400">Loading incident...</p>
      </div>
    );
  }

  if (!incident) {
    return (
      <div className="p-6">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <p className="mt-4 text-slate-400">Incident not found.</p>
      </div>
    );
  }

  const isAcked = incident.status === 'acknowledged';

  const handleToggleAck = async () => {
    setIsAcking(true);
    setToast(null);
    try {
      if (isAcked) {
        await unacknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Unacknowledged', type: 'success' });
      } else {
        await acknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Acknowledged', type: 'success' });
      }
      await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    } catch (err) {
      setToast({ text: err instanceof Error ? err.message : 'ACK failed', type: 'error' });
    } finally {
      setIsAcking(false);
    }
  };

  return (
    <div className="min-h-full">
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <h1 className="text-lg font-semibold">{incident.displayId}</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      {/* Status banner */}
      <div className="px-4 py-3 bg-slate-900 border-b border-slate-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SeverityBadge severity={incident.severity} />
          <span className={`text-xs px-2 py-0.5 rounded ${STATUS_CLASSES[incident.status] ?? ''}`}>
            {incident.incidentState}
          </span>
        </div>
        <button
          type="button"
          onClick={handleToggleAck}
          disabled={isAcking}
          className={isAcked
            ? 'px-4 py-2 rounded border border-slate-600 text-sm text-slate-300 hover:bg-slate-800 disabled:opacity-50'
            : 'px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm font-semibold text-white disabled:opacity-50'
          }
        >
          {isAcking ? '...' : isAcked ? 'Unacknowledge' : 'Acknowledge'}
        </button>
      </div>

      <div className="p-4 space-y-3">
        {/* Summary */}
        <div>
          <div className="text-sm font-semibold">{incident.summary}</div>
        </div>

        {/* Device info card */}
        <div className="bg-slate-900 rounded-lg p-3">
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
            <dt className="text-slate-500">Device</dt>
            <dd className="font-medium">{incident.deviceName ?? 'Unknown'}</dd>
            <dt className="text-slate-500">IP</dt>
            <dd className="font-mono">{incident.deviceIp ?? '—'}</dd>
          </dl>
        </div>

        {/* Timing card */}
        <div className="bg-slate-900 rounded-lg p-3">
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
            <dt className="text-slate-500">Created</dt>
            <dd>{formatTimestamp(incident.startTime)}</dd>
            <dt className="text-slate-500">Duration</dt>
            <dd>{formatDuration(incident.startTime)}</dd>
            <dt className="text-slate-500">Incident ID</dt>
            <dd className="font-mono text-xs">{incident.incidentId}</dd>
          </dl>
        </div>

        {/* ACK info card — only when acknowledged */}
        {isAcked && incident.acknowledgedBy && (
          <div className="bg-slate-900 rounded-lg p-3 border-l-2 border-emerald-500">
            <div className="text-xs text-emerald-400 font-semibold mb-2">ACKNOWLEDGED</div>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
              <dt className="text-slate-500">By</dt>
              <dd>{incident.acknowledgedBy}</dd>
            </dl>
          </div>
        )}
      </div>

      <Toast message={toast} onDismiss={dismissToast} />
    </div>
  );
}
```

Key changes from the original:
- Added `isFetching` from `useIncidents()` — shows "Loading incident..." when list is still fetching on deep-link
- Replaced `error` state with `toast` state using the Toast component
- ACK/UnACK success now shows toast feedback ("Acknowledged" / "Unacknowledged")
- ACK failure shows error toast instead of inline error div

- [ ] **Step 2: Verify typecheck passes**

```bash
cd pwa
npm run typecheck
```

Expected: No errors.

- [ ] **Step 3: Run existing IncidentDetailScreen tests**

```bash
cd pwa
npx vitest run src/features/incidents/__tests__/IncidentDetailScreen.test.tsx
```

Expected: Tests pass (the changes are additive — existing behavior preserved).

- [ ] **Step 4: Commit**

```bash
cd pwa
git add src/features/incidents/IncidentDetailScreen.tsx
git commit -m "feat(pwa): add fetch-on-demand for deep-linked incidents and ACK toast feedback"
```

---

## Task 11: PWA — Service Worker Message Listener for Deep-Link Navigation

**Files:**
- Modify: `pwa/src/App.tsx`

When a push notification is clicked while the PWA is already open, the service worker sends a `postMessage({ type: 'navigate', url })` to the client. The app needs to listen for this and navigate via React Router.

- [ ] **Step 1: Update App.tsx with SW message listener**

Replace the full content of `pwa/src/App.tsx`:

```typescript
import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';

export default function App() {
  const navigate = useNavigate();

  // Listen for navigation messages from the service worker (push notification clicks)
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;

    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'navigate' && typeof event.data.url === 'string') {
        navigate(event.data.url);
      }
    };

    navigator.serviceWorker.addEventListener('message', handler);
    return () => navigator.serviceWorker.removeEventListener('message', handler);
  }, [navigate]);

  return (
    <div className="min-h-full">
      <IOSRedirectBanner />
      <Routes>
        <Route path="/" element={<IncidentListScreen />} />
        <Route path="/settings" element={<SettingsScreen />} />
        <Route path="/incident/:id" element={<IncidentDetailScreen />} />
      </Routes>
    </div>
  );
}
```

- [ ] **Step 2: Verify typecheck**

```bash
cd pwa
npm run typecheck
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
cd pwa
git add src/App.tsx
git commit -m "feat(pwa): add service worker message listener for push notification deep-links"
```

---

## Task 12: Version Bump + Feature Spec + Docs

**Files:**
- Modify: `pwa/package.json`
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Bump package.json version**

In `pwa/package.json`, change:

Old:
```json
  "version": "0.1.1",
```

New:
```json
  "version": "0.2.0",
```

- [ ] **Step 2: Update feature-spec.md**

Add a new feature entry at the bottom of `shared/feature-spec.md`:

```markdown

### Feature: Push Notifications (Web Push)
**Status:** shipped-ios, shipped-pwa
**API:** Middleware `/register-webpush`, `/vapid-key`, `/webhook`

#### Behaviour (both platforms)
- Incident webhook triggers push notification to all registered devices
- Notification shows incident title, body, and severity
- Tapping notification deep-links to incident detail
- Expired/invalid subscriptions cleaned up on 410 Gone

#### iOS-specific
- APNs with Time Sensitive entitlement support
- Custom `benem://` deep-link scheme

#### PWA-specific
- v0.2.0: VAPID Web Push via service worker
- Deep-link via `/incident/{id}` route
- Settings toggle for enable/disable, re-register button
- Requires webhook secret matching BHNM webhook configuration
- No Time Sensitive / Critical Alerts (Web Push API limitation)
```

- [ ] **Step 3: Run full test suites**

```bash
cd pwa && npm run test && npm run typecheck
cd ../middleware && pytest -v
```

Expected: All tests pass on both sides.

- [ ] **Step 4: Run production build**

```bash
cd pwa && npm run build
```

Expected: Build succeeds, `dist/` contains `sw.js` with push handlers.

- [ ] **Step 5: Commit**

```bash
git add pwa/package.json shared/feature-spec.md
git commit -m "docs: bump PWA to v0.2.0 and update feature spec with Web Push"
```

---

## Self-Review Checklist

### Spec Coverage

| Spec Requirement | Task |
|---|---|
| VAPID configuration (.env vars) | Task 1 |
| `web_push_subscriptions` SQLite table | Task 2 |
| `POST /register-webpush` endpoint | Task 4 |
| `webpush.py` sender with pywebpush | Task 3 |
| Webhook handler calls both APNs + Web Push | Task 4 |
| 410 Gone cleanup for expired subscriptions | Task 3 + Task 4 |
| Service worker push event handler | Task 6 |
| Service worker notificationclick handler | Task 6 |
| `postMessage` for client-side navigation | Task 6 + Task 11 |
| Request `Notification.permission` | Task 7 |
| `pushManager.subscribe()` with VAPID key | Task 7 |
| POST subscription to `/register-webpush` | Task 7 |
| Store subscription state in localStorage | Task 5 |
| Settings → Push toggle + status + re-register | Task 8 |
| Deep-link from push lands on detail screen | Task 6 + Task 10 + Task 11 |
| Handle incident list not loaded (fetch on demand) | Task 10 |
| Toast/snackbar for ACK/UnACK feedback | Task 9 + Task 10 |
| Feature spec update | Task 12 |

### No gaps found.

### Type Consistency

- `WebPushRegistration` (Pydantic model in main.py) fields: `endpoint`, `p256dh`, `auth` — matches `save_web_push_subscription()` parameters and `subscribeToPush()` POST body.
- `PushState` union type used consistently in `pushRegistration.ts` and `SettingsScreen.tsx`.
- `ToastMessage` type used consistently in `Toast.tsx` and `IncidentDetailScreen.tsx`.
- `BhnmConfig.webhookSecret` added in Task 5, consumed in Task 8.
- `get_web_push_subscriptions_for_secret()` return type `list[dict]` with keys `endpoint`, `p256dh`, `auth` — matches what `send_web_push_to_all()` expects.
