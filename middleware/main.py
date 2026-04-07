VERSION = "2.4.0"

from contextlib import asynccontextmanager
import ipaddress
import json
import socket
from urllib.parse import parse_qs, urlparse
import httpx
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, field_validator

from config import MIDDLEWARE_PORT, VAPID_PUBLIC_KEY, BHNM_TLS_VERIFY, SERVERS_JSON_PATH, PROXY_TIMEOUT, PROXY_TOKEN
from database import init_db, save_token, get_tokens_for_secret, get_all_tokens, delete_token, \
    save_web_push_subscription, get_web_push_subscriptions_for_secret, delete_web_push_subscription
from apns import send_to_all
from webpush import send_web_push_to_all

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


def _verify_proxy_token(request: Request) -> None:
    """Validate X-Proxy-Token against PROXY_TOKEN env var or any api_key in servers.json.

    Raises HTTPException(401) if the token is missing or invalid.
    """
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token:
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")
    # Accept if it matches the global PROXY_TOKEN
    if PROXY_TOKEN and token == PROXY_TOKEN:
        return
    # Accept if it matches any api_key in servers.json
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == token:
                    return
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    raise HTTPException(status_code=401, detail="Invalid proxy token")


def _validate_proxy_target(target_url: str) -> None:
    """Block SSRF: only allow targets whose hostname is in servers.json or is non-private.

    Raises HTTPException(403) if the target resolves to a private/reserved IP range.
    """
    parsed = urlparse(target_url)
    hostname = parsed.hostname or ""

    # Collect allowed hostnames from servers.json
    allowed_hosts: set[str] = set()
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                url = s.get("url", "")
                if url:
                    h = urlparse(url).hostname
                    if h:
                        allowed_hosts.add(h.lower())
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass

    if hostname.lower() in allowed_hosts:
        return  # Explicitly configured — always allowed

    # Resolve hostname to IP(s) and block private/reserved ranges (RFC 1918,
    # loopback, link-local, metadata).  Resolving prevents DNS rebinding attacks
    # where a hostname initially points to a public IP but later resolves to an
    # internal address.
    try:
        infos = socket.getaddrinfo(hostname, None, proto=socket.IPPROTO_TCP)
    except socket.gaierror:
        raise HTTPException(status_code=403, detail="Proxy target hostname could not be resolved")
    for info in infos:
        ip_str = info[4][0]
        try:
            addr = ipaddress.ip_address(ip_str)
        except ValueError:
            continue
        if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_reserved:
            raise HTTPException(status_code=403, detail="Proxy target address is not allowed")


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

    @field_validator("token")
    @classmethod
    def token_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("token must not be empty")
        return v.strip()

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


# ── Web Push Subscription Registration ───────────────────────────────────────

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

class WebhookPayload(BaseModel):
    notification_type: str = "PROBLEM"
    hostname: str = "Unknown device"
    host_state: str = ""
    site: str = ""
    service_desc: str = ""
    output: str = ""
    incident_id: str = ""

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

@app.get("/vapid-key")
def get_vapid_key():
    import config
    if not config.VAPID_PUBLIC_KEY:
        raise HTTPException(status_code=404, detail="Web Push not configured")
    return {"publicKey": config.VAPID_PUBLIC_KEY}


# ── BHNM Webhook ──────────────────────────────────────────────────────────────

@app.post("/webhook")
async def receive_webhook(request: Request, payload: WebhookPayload):
    secret = request.query_params.get("secret", "").strip()
    if not secret:
        raise HTTPException(status_code=400, detail="?secret= query parameter is required")

    notification_type = payload.notification_type
    hostname          = payload.hostname
    host_state        = payload.host_state
    site              = payload.site
    service_desc      = payload.service_desc
    output            = payload.output
    incident_id       = payload.incident_id

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
    web_push_subs = get_web_push_subscriptions_for_secret(secret)

    if not tokens and not web_push_subs:
        print(f"[Webhook] No registered devices for this secret — nothing to notify.")
        return {"status": "ok", "notified": 0}

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


# ── BHNM Proxy — Dedicated Routes (cache-ready) ─────────────────────────────
# These explicit routes exist so the middleware can later add caching /
# cache-invalidation logic per endpoint.  For now they are thin pass-throughs.

async def _proxy_to_bhnm(request: Request, bhnm_path: str) -> Response:
    """Forward a form-encoded POST to the given BHNM path and return the response."""
    _verify_proxy_token(request)
    body = await request.body()

    # Resolve target BHNM server (same logic as the catch-all proxy)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        content_type = request.headers.get("content-type", "")
        if "application/x-www-form-urlencoded" in content_type:
            parsed_body = parse_qs(body.decode("utf-8", errors="replace"))
            api_key = parsed_body.get("password", [""])[0] or parsed_body.get("pwd", [""])[0]
            if api_key:
                target_base = _target_for_api_key(api_key)
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base)

    target = f"{target_base}/{bhnm_path.lstrip('/')}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method="POST",
                url=target,
                headers=forward_headers,
                content=body,
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError as exc:
        raise HTTPException(status_code=502, detail=f"Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }
    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)


@app.post("/api/proxy/incident/acknowledge")
async def proxy_incident_acknowledge(request: Request):
    print("[Proxy] ACK incident request")
    return await _proxy_to_bhnm(request, "/fw/index.php?r=restful/incident/acknowledge")


@app.post("/api/proxy/incident/unacknowledge")
async def proxy_incident_unacknowledge(request: Request):
    print("[Proxy] UnACK incident request")
    return await _proxy_to_bhnm(request, "/fw/index.php?r=restful/incident/unacknowledge")


@app.post("/api/proxy/ha-status")
async def proxy_ha_status(request: Request):
    print("[Proxy] HA status check")
    return await _proxy_to_bhnm(request, "/api/ha_status_api.php")


# ── BHNM API Proxy (for BeNeM) ────────────────────────────────────────────────────
# Target BHNM server is supplied per-request via X-BHNM-Target header.

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    _verify_proxy_token(request)
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
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base)

    target = f"{target_base}/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
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
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }

    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)
