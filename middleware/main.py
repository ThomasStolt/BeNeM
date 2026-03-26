from contextlib import asynccontextmanager
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

from config import MIDDLEWARE_PORT, WEBHOOK_SECRET
from database import init_db, save_token, get_all_tokens, delete_token
from apns import send_to_all

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    auth_status = "enabled" if WEBHOOK_SECRET else "DISABLED (no secret set)"
    print(f"[Startup] BHNM APNs middleware ready on port {MIDDLEWARE_PORT} — auth: {auth_status}")
    yield

app = FastAPI(lifespan=lifespan)

_token_header = APIKeyHeader(name="X-Webhook-Token", auto_error=False)

def require_auth(token: str = Depends(_token_header)) -> None:
    """Validates the X-Webhook-Token header. No-op when WEBHOOK_SECRET is unset."""
    if WEBHOOK_SECRET and token != WEBHOOK_SECRET:
        raise HTTPException(status_code=401, detail="Unauthorized")


# ── Device Token Registration ─────────────────────────────────────────────────

class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"

@app.post("/register", dependencies=[Depends(require_auth)])
def register_token(body: TokenRegistration):
    save_token(body.token, body.device_name)
    print(f"[Register] Token saved for: {body.device_name}")
    return {"status": "ok"}


# ── BHNM Webhook ──────────────────────────────────────────────────────────────

@app.post("/webhook", dependencies=[Depends(require_auth)])
async def receive_webhook(request: Request):

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
        "registered_devices": len(tokens),
        "apns_environment": "sandbox" if config.APNS_USE_SANDBOX else "production"
    }
