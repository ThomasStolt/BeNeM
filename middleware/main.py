from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel

from config import MIDDLEWARE_PORT, WEBHOOK_SECRET
from database import init_db, save_token, get_all_tokens, delete_token
from apns import send_to_all

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print(f"[Startup] BHNM APNs middleware ready on port {MIDDLEWARE_PORT}")
    yield

app = FastAPI(lifespan=lifespan)


# ── Device Token Registration ─────────────────────────────────────────────────

class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"

@app.post("/register")
def register_token(body: TokenRegistration):
    save_token(body.token, body.device_name)
    print(f"[Register] Token saved for: {body.device_name}")
    return {"status": "ok"}


# ── BHNM Webhook ──────────────────────────────────────────────────────────────

@app.post("/webhook")
async def receive_webhook(request: Request, secret: str = ""):
    # Optional shared secret check
    if WEBHOOK_SECRET and secret != WEBHOOK_SECRET:
        raise HTTPException(status_code=403, detail="Invalid secret")

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

    print(f"[Webhook] {notification_type} — {hostname} — Incident {incident_id}")

    tokens = get_all_tokens()
    if not tokens:
        print("[Webhook] No registered devices.")
        return {"status": "no_devices"}

    stale = send_to_all(tokens, title, body)
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
        "registered_devices": len(tokens),
        "apns_environment": "sandbox" if config.APNS_USE_SANDBOX else "production"
    }
