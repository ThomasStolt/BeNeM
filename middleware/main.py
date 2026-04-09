VERSION = "2.5.0"

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
import time
import incident_cache
import tactical_cache

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


def _server_config_for_api_key(api_key: str) -> dict | None:
    """Look up full server config by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return None


def _server_config_for_bhnm_url(bhnm_url: str) -> dict | None:
    """Look up full server config by BHNM URL from servers.json."""
    normalized = bhnm_url.rstrip("/")
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("url", "").rstrip("/") == normalized:
                    return s
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return None


def _resolve_server_config(request: Request) -> dict | None:
    """Resolve server config from X-Proxy-Token (api_key) or X-BHNM-Target (url)."""
    api_key = request.headers.get("X-Proxy-Token", "").strip()
    cfg = _server_config_for_api_key(api_key)
    if cfg:
        return cfg
    bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
    if bhnm_target:
        return _server_config_for_bhnm_url(bhnm_target)
    return None


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
    incident_cache.start_all()
    tactical_cache.start_all()
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
    cache_status = {}
    for sid, cached in incident_cache._cache.items():
        cache_status[sid] = {
            "active": len(cached.active_incidents),
            "closed": len(cached.closed_incidents),
            "age_seconds": round(time.time() - cached.last_updated) if cached.last_updated else None,
        }
    tactical_status = {}
    for sid, cached in tactical_cache._cache.items():
        tactical_status[sid] = {
            gt: {
                "groups": len(cached.data.get(gt, {})),
                "age_seconds": round(time.time() - cached.last_updated.get(gt, 0)) if cached.last_updated.get(gt) else None,
            }
            for gt in tactical_cache.GROUPING_TYPES
        }
    return {
        "status": "running",
        "version": VERSION,
        "registered_devices": len(tokens),
        "apns_environment": "per-device",
        "cache": cache_status,
        "tactical_cache": tactical_status,
    }


# ── Cached Incidents Endpoint ────────────────────────────────────────────────

@app.get("/api/v1/incidents")
@app.post("/api/v1/incidents")
async def cached_incidents(request: Request):
    """Return enriched incidents from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)

    # Resolve server: try api_key first, then BHNM URL from X-BHNM-Target header
    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = incident_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = incident_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = incident_cache.get_cached(server_id)
        if cached:
            return {
                "cache_age_seconds": round(time.time() - cached.last_updated),
                "active_incidents": cached.active_incidents,
                "closed_incidents": cached.closed_incidents,
            }

    # Cache cold or server not found — fetch live from BHNM.
    # The client sends a header-only GET (no form body), so we must build
    # the proper form-encoded POST that the BHNM incident API expects.
    # Note: X-Proxy-Token may be a webhook secret, not the BHNM api_key,
    # so we resolve the server config by API key OR BHNM URL to get the real credentials.
    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base)

    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key
    form = {"pwd": bhnm_api_key, "method": "getincidents"}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/api/incident_api.php"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    return Response(content=resp.content, status_code=resp.status_code,
                    headers={k: v for k, v in resp.headers.items()
                             if k.lower() not in HOP_BY_HOP_RESPONSE})


@app.post("/internal/cache/reload")
async def cache_reload(request: Request):
    """Trigger cache reload for a server. Called by admin portal."""
    try:
        body = await request.json()
    except Exception:
        body = {}
    server_id = body.get("server_id", "")
    if not server_id:
        raise HTTPException(status_code=400, detail="server_id is required")
    incident_cache.reload_server(server_id)
    tactical_cache.reload_server(server_id)
    return {"status": "ok", "server_id": server_id}


# ── Cached Tactical Overview Endpoint ──────────────────────────────────────

@app.get("/api/v1/tactical-overview")
async def cached_tactical_overview(request: Request, grouping_type: str = "category"):
    """Return tactical overview from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)

    if grouping_type not in ("category", "site", "app"):
        raise HTTPException(status_code=400, detail="grouping_type must be category, site, or app")

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = tactical_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = tactical_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = tactical_cache.get_cached(server_id, grouping_type)
        if cached:
            data, ts = cached
            return {
                "cache_age_seconds": round(time.time() - ts),
                "grouping_type": grouping_type,
                "data": data,
            }

    # Cache cold or server not found — fetch live from BHNM.
    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base)

    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key
    form = {"password": bhnm_api_key, "grouping_type": grouping_type}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/fw/index.php?r=restful/tactical-overview/data"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    return Response(content=resp.content, status_code=resp.status_code,
                    headers={k: v for k, v in resp.headers.items()
                             if k.lower() not in HOP_BY_HOP_RESPONSE})


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


@app.post("/api/proxy/maintenance/create")
async def proxy_maintenance_create(request: Request):
    print("[Proxy] Maintenance window create request")
    _verify_proxy_token(request)

    body_bytes = await request.body()
    parsed_body = parse_qs(body_bytes.decode("utf-8", errors="replace"))

    name = parsed_body.get("name", [""])[0].strip()
    duration_raw = parsed_body.get("duration", [""])[0].strip()
    comment = parsed_body.get("comment", [""])[0].strip()

    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    if not duration_raw:
        raise HTTPException(status_code=400, detail="duration is required")
    try:
        duration = int(duration_raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="duration must be an integer")
    if duration < 1:
        raise HTTPException(status_code=400, detail="duration must be >= 1")

    start_time = int(time.time()) + 900
    end_time = start_time + (duration * 60)

    # Resolve target BHNM server
    cfg = _resolve_server_config(request)
    if cfg:
        target_base = cfg.get("url", "").rstrip("/")
        api_key = cfg.get("api_key", "")
    else:
        target_base = _single_server_url()
        api_key = ""
        if not api_key:
            # Try to get api_key from the resolved server
            if target_base:
                try:
                    with open(SERVERS_JSON_PATH) as f:
                        for s in json.load(f):
                            if s.get("url", "").rstrip("/") == target_base:
                                api_key = s.get("api_key", "")
                                break
                except Exception:
                    pass

    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base)

    from urllib.parse import urlencode
    bhnm_body = urlencode({
        "password": api_key,
        "action": "new",
        "name": name,
        "start_time": str(start_time),
        "end_time": str(end_time),
        "comment": comment,
    })

    target = f"{target_base}/api/maint_window_api.php"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }
    forward_headers["content-type"] = "application/x-www-form-urlencoded"

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method="POST",
                url=target,
                headers=forward_headers,
                content=bhnm_body.encode("utf-8"),
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }
    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)


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
