VERSION = "2.0.0"

from contextlib import asynccontextmanager
import os
import httpx
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel

from config import MIDDLEWARE_PORT
from database import init_db, save_token, get_tokens_for_secret, get_all_tokens, delete_token
from apns import send_to_all

HOP_BY_HOP_REQUEST = {
    "host", "x-proxy-token", "connection", "keep-alive",
    "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade"
}
HOP_BY_HOP_RESPONSE = {
    "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"
}

BHNM_URL = os.getenv("BHNM_URL", "").rstrip("/")
BHNM_TLS_VERIFY = os.getenv("BHNM_TLS_VERIFY", "true").lower() != "false"
PROXY_SECRET = os.getenv("PROXY_SECRET", "")

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — per-device secret routing enabled")
    yield

app = FastAPI(lifespan=lifespan)


# ── Device Token Registration ─────────────────────────────────────────────────

class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"

@app.post("/register")
def register_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    save_token(body.token, body.device_name, active_secret)
    print(f"[Register] Token saved for: {body.device_name} (secret ...{active_secret[-8:]})")
    return {"status": "ok"}


# ── BHNM Webhook ──────────────────────────────────────────────────────────────

@app.post("/webhook")
async def receive_webhook(request: Request):
    secret = request.query_params.get("secret", "").strip()
    if not secret:
        raise HTTPException(status_code=400, detail="?secret= query parameter is required")

    payload = await request.json()

    notification_type = payload.get("notification_type", "PROBLEM")
    hostname          = payload.get("hostname", "Unknown device")
    host_state        = payload.get("host_state", "")
    site              = payload.get("site", "")
    service_desc      = payload.get("service_desc", "")
    output            = payload.get("output", "")
    incident_id       = payload.get("incident_id", "")

    # Build human-readable notification
    if notification_type == "RECOVERY":
        title = f"Resolved: {hostname}"
        body  = f"{service_desc or host_state} recovered. {output}".strip()
    elif notification_type == "ACKNOWLEDGEMENT":
        title = f"Acknowledged: {hostname}"
        body  = output or service_desc or host_state
    else:
        # PROBLEM, CRITICAL, WARNING
        emoji = "🔴" if host_state in ("DOWN", "UNREACHABLE") else "⚠️"
        title = f"{emoji} {hostname} — {host_state or notification_type}"
        body  = f"{service_desc or output or ''} | Site: {site}".strip(" |")

    print(f"[Webhook] {notification_type} — {hostname} — Incident {incident_id} (secret ...{secret[-8:]})")

    tokens = get_tokens_for_secret(secret)
    if not tokens:
        print("[Webhook] No registered devices for this secret.")
        return {"status": "no_devices"}

    stale = send_to_all(tokens, title, body, incident_id)
    for t in stale:
        delete_token(t)
        print(f"[Cleanup] Removed stale token ...{t[-8:]}")

    return {"status": "ok", "notified": len(tokens) - len(stale)}


# ── Health Check ──────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    tokens = get_all_tokens()
    import config
    return {
        "status": "running",
        "version": VERSION,
        "registered_devices": len(tokens),
        "apns_environment": "sandbox" if config.APNS_USE_SANDBOX else "production"
    }


# ── BHNM API Proxy (for BeNeM) ────────────────────────────────────────────────────

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    token = request.headers.get("X-Proxy-Token", "")
    if token != PROXY_SECRET:
        raise HTTPException(status_code=401, detail="Unauthorized")

    if not BHNM_URL:
        raise HTTPException(status_code=503, detail="BHNM_URL not configured")

    target = f"{BHNM_URL}/{path}"
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

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }

    return resp.content, resp.status_code, response_headers
