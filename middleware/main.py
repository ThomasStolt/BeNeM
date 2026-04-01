VERSION = "2.2.0"

from contextlib import asynccontextmanager
import json
import os
from urllib.parse import parse_qs
import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from config import MIDDLEWARE_PORT
from database import init_db, save_token, get_tokens_for_secret, get_all_tokens, delete_token
from apns import send_to_all

HOP_BY_HOP_REQUEST = {
    "host", "x-proxy-token", "x-bhnm-target", "connection", "keep-alive",
    "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade"
}
HOP_BY_HOP_RESPONSE = {
    "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade",
    # httpx decompresses gzip automatically; strip these so Starlette sets
    # Content-Length from the actual (decompressed) body length.
    "content-encoding", "content-length",
}

BHNM_TLS_VERIFY = os.getenv("BHNM_TLS_VERIFY", "true").lower() != "false"
SERVERS_JSON_PATH = os.getenv("SERVERS_JSON_PATH", "/data/servers.json")


def _target_for_api_key(api_key: str) -> str:
    """Look up BHNM server URL by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s.get("url", "").rstrip("/")
    except Exception:
        pass
    return ""


def _single_server_url() -> str:
    """Return the URL of the only configured server, or '' if 0 or >1 servers."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            servers = json.load(f)
        if len(servers) == 1:
            return servers[0].get("url", "").rstrip("/")
    except Exception:
        pass
    return ""

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — dynamic multi-server routing enabled")
    yield

app = FastAPI(lifespan=lifespan)


# ── Device Token Registration ─────────────────────────────────────────────────

class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"
    environment: str = "production"

@app.post("/register")
def register_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    env = body.environment if body.environment in ("sandbox", "production") else "production"
    save_token(body.token, body.device_name, active_secret, env)
    print(f"[Register] Token saved for: {body.device_name} (APNs: {env})")
    return {"status": "ok"}


@app.delete("/register")
def unregister_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    delete_token(body.token)
    print(f"[Unregister] Token removed: ...{body.token[-8:]}")
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

    print(f"[Webhook] {notification_type} — {hostname} — Incident {incident_id}")

    tokens = get_tokens_for_secret(secret)
    if not tokens:
        print(f"[Webhook] Rejected: no registered devices for this secret.")
        raise HTTPException(status_code=403, detail="Forbidden: unknown secret")

    stale = await send_to_all(tokens, title, body, incident_id)
    for t in stale:
        delete_token(t)
        print(f"[Cleanup] Removed stale token ...{t[-8:]}")

    return {"status": "ok", "notified": len(tokens) - len(stale)}


# ── Health Check ──────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    tokens = get_all_tokens()
    return {
        "status": "running",
        "version": VERSION,
        "registered_devices": len(tokens),
        "apns_environment": "per-device"
    }


# ── BHNM API Proxy (for BeNeM) ────────────────────────────────────────────────────
# Target BHNM server is supplied per-request via X-BHNM-Target header.
# Any non-empty X-Proxy-Token is accepted — the secret itself is the credential.

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    # TODO: re-enable once BeNeM app sends X-Proxy-Token from the configured proxy_token
    # token = request.headers.get("X-Proxy-Token", "").strip()
    # if not token:
    #     raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")

    body = await request.body()

    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        content_type = request.headers.get("content-type", "")
        if "application/x-www-form-urlencoded" in content_type:
            parsed_body = parse_qs(body.decode("utf-8", errors="replace"))
            # fw/index.php uses "password", incident_api.php uses "pwd"
            api_key = parsed_body.get("password", [""])[0] or parsed_body.get("pwd", [""])[0]
            if api_key:
                target_base = _target_for_api_key(api_key)
    if not target_base:
        # Also check query params (some BHNM API calls pass password as ?password=...)
        api_key = request.query_params.get("password", "")
        if api_key:
            target_base = _target_for_api_key(api_key)
    if not target_base:
        # Fallback: if exactly one server is configured, use it (covers session-based requests)
        target_base = _single_server_url()
        if target_base:
            print(f"[Proxy] No target header/key found — falling back to single configured server")

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

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=60.0) as client:
            resp = await client.request(
                method=request.method,
                url=target,
                headers=forward_headers,
                content=body,
            )
    except httpx.TimeoutException:
        print(f"[Proxy] Timeout proxying {request.method} {target}")
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError as exc:
        print(f"[Proxy] Connection error proxying {request.method} {target}: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error proxying {request.method} {target}: {exc}")
        raise HTTPException(status_code=502, detail=f"Bad Gateway: {exc}")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }

    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)
