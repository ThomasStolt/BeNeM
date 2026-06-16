VERSION = "1.6.2"

import base64
import io
import os
import re
import subprocess
from dataclasses import dataclass
from html import escape
from urllib.parse import urlparse

import httpx
import pyotp
import qrcode
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from starlette.middleware.base import BaseHTTPMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from dotenv import load_dotenv

import auth
from auth import SESSION_COOKIE
from connection_test import run_test
from crypto import load_key, encrypt_payload
from log import append_entry, read_entries, count_entries, delete_entry, update_entry_user, get_entry
from push_db import get_registered_devices
from servers import load_servers, get_server, save_servers, Server
from sf_symbols import SF_SYMBOLS

load_dotenv()

MIDDLEWARE_URL = os.environ.get("MIDDLEWARE_URL", "")
MIDDLEWARE_INTERNAL_URL = os.environ.get("MIDDLEWARE_INTERNAL_URL", "http://benem-middleware:8889")
PUSH_SECRET = os.environ.get("WEBHOOK_SECRET", "")
PROXY_TOKEN = os.environ.get("PROXY_TOKEN", "")

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(docs_url=None, redoc_url=None)
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)


class CSRFMiddleware(BaseHTTPMiddleware):
    """Reject cross-origin POST/PUT/DELETE requests to admin endpoints.

    Defense-in-depth alongside SameSite=strict cookies.  Validates that the
    Origin or Referer header matches the Host header for state-changing methods.
    """
    SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}

    async def dispatch(self, request: Request, call_next):
        if request.method in self.SAFE_METHODS:
            return await call_next(request)
        # Only protect admin routes
        if not request.url.path.startswith("/admin"):
            return await call_next(request)
        origin = request.headers.get("origin", "")
        referer = request.headers.get("referer", "")
        host = request.headers.get("host", "")
        if origin:
            origin_host = urlparse(origin).netloc
            if origin_host != host:
                return JSONResponse({"detail": "CSRF check failed"}, status_code=403)
        elif referer:
            referer_host = urlparse(referer).netloc
            if referer_host != host:
                return JSONResponse({"detail": "CSRF check failed"}, status_code=403)
        # If neither header is present, allow (some browsers omit both for same-origin)
        return await call_next(request)


app.add_middleware(CSRFMiddleware)
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.exception_handler(RateLimitExceeded)
def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return templates.TemplateResponse(
        request,
        "login.html",
        {"error": "Too many attempts — please wait a minute and try again."},
        status_code=429,
    )


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/admin/health")
def health():
    return {"status": "running", "version": VERSION}


# ── Auth ──────────────────────────────────────────────────────────────────────

@app.get("/admin/login", response_class=HTMLResponse)
def login_page(request: Request):
    return templates.TemplateResponse(request, "login.html", {"error": None})


@app.post("/admin/login")
@limiter.limit("5/minute")
def login_submit(request: Request, code: str = Form(...)):
    if not auth.verify_totp(code):
        return templates.TemplateResponse(
            request,
            "login.html",
            {"error": "Incorrect code — try again."},
            status_code=200,
        )
    token = auth.create_session_token()
    resp = RedirectResponse("/admin/", status_code=302)
    resp.set_cookie(
        SESSION_COOKIE, token,
        max_age=auth.SESSION_MAX_AGE,
        httponly=True, secure=True, samesite="strict",
    )
    return resp


@app.post("/admin/logout")
def logout():
    resp = RedirectResponse("/admin/login", status_code=302)
    resp.delete_cookie(
        SESSION_COOKIE,
        httponly=True,
        secure=True,
        samesite="strict",
    )
    return resp


# ── Generate Link ─────────────────────────────────────────────────────────────

@dataclass
class _GenResult:
    url: str
    qr_b64: str


@dataclass
class _FormData:
    user: str
    symbol: str
    color: str


def _make_qr_b64(url: str) -> str:
    img = qrcode.make(url)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


@app.get("/admin/", response_class=HTMLResponse)
def generate_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    selected = servers[0] if servers else None
    return templates.TemplateResponse(request, "generate.html", {
        "active": "generate",
        "servers": servers,
        "selected_server": selected,
        "middleware_url": MIDDLEWARE_URL,
        "sf_symbols": SF_SYMBOLS,
        "form_data": None,
        "result": None,
    })


@app.get("/admin/server-url", response_class=HTMLResponse)
def server_url_fragment(request: Request, server_id: str = ""):
    """HTMX endpoint — returns updated URL field HTML for the selected server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse(
            '<input type="text" value="" readonly class="flex-1">'
        )
    url_attr = escape(server.url, quote=True)
    return HTMLResponse(
        f'<input type="text" value="{url_attr}" readonly class="flex-1">'
    )



@app.post("/admin/generate", response_class=HTMLResponse)
def generate_link(
    request: Request,
    server_id: str = Form(...),
    user: str = Form(""),
    symbol: str = Form("server.rack"),
    color: str = Form("#0A84FF"),
):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()

    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
        color = "#0A84FF"

    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    server = next((s for s in servers if s.id == server_id), None)
    if not server:
        return RedirectResponse("/admin/", status_code=302)

    key = load_key()
    payload = {
        "bhnm_url":       server.url,
        "middleware_url": MIDDLEWARE_URL,
        "notifications":  bool(MIDDLEWARE_URL),
        "api_key":        server.api_key,
        "pin":            server.pin,
        "user":           user,
        "name":           server.name,
        "push_secret":    PUSH_SECRET,
        "proxy_token":    PROXY_TOKEN,
        "symbol":         symbol,
        "color":          color,
    }
    blob = encrypt_payload(payload, key)
    url = f"benem://configure?p={blob}"
    qr_b64 = _make_qr_b64(url)
    append_entry(user, server.id, server.name, url)

    return templates.TemplateResponse(request, "generate.html", {
        "active": "generate",
        "servers": servers,
        "selected_server": server,
        "middleware_url": MIDDLEWARE_URL,
        "sf_symbols": SF_SYMBOLS,
        "form_data": _FormData(user=user, symbol=symbol, color=color),
        "result": _GenResult(url=url, qr_b64=qr_b64),
    })


LOG_PER_PAGE = 50


# ── Push Config ───────────────────────────────────────────────────────────────

@app.get("/admin/push", response_class=HTMLResponse)
def push_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    webhook_url = f"{MIDDLEWARE_URL}/webhook?secret=<your-secret>" if MIDDLEWARE_URL else ""
    return templates.TemplateResponse(request, "push.html", {
        "active": "push",
        "middleware_url": MIDDLEWARE_URL,
        "webhook_url": webhook_url,
        "devices": get_registered_devices(),
    })


# ── Log ───────────────────────────────────────────────────────────────────────

@app.get("/admin/log", response_class=HTMLResponse)
def log_page(request: Request, server_id: str = "", page: int = 1):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    filter_id = server_id or None
    entries = read_entries(server_id=filter_id, page=page, per_page=LOG_PER_PAGE)
    total = count_entries(server_id=filter_id)
    total_pages = max(1, (total + LOG_PER_PAGE - 1) // LOG_PER_PAGE)
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    return templates.TemplateResponse(request, "log.html", {
        "active": "log",
        "servers": servers,
        "server_id": server_id,
        "entries": entries,
        "page": page,
        "total_pages": total_pages,
    })


@app.get("/admin/log/show")
def log_show(request: Request, ts: str = ""):
    if not auth.is_authenticated(request):
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    entry = get_entry(ts)
    if not entry:
        return JSONResponse({"error": "not found"}, status_code=404)
    # Full link is no longer stored for security — return metadata only
    return JSONResponse({
        "user": entry.get("user", ""),
        "server_name": entry.get("server_name", ""),
        "link_hash": entry.get("link_hash", ""),
        "message": "Full link is no longer stored. Re-generate from the Generate page.",
    })


@app.post("/admin/log/edit", response_class=RedirectResponse)
def log_edit(request: Request, ts: str = Form(...), user: str = Form(...), page: int = Form(1), server_id: str = Form("")):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    update_entry_user(ts, user.strip())
    url = f"/admin/log?page={page}"
    if server_id:
        url += f"&server_id={server_id}"
    return RedirectResponse(url, status_code=303)


@app.post("/admin/log/delete", response_class=RedirectResponse)
def log_delete(request: Request, ts: str = Form(...), page: int = Form(1), server_id: str = Form("")):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    delete_entry(ts)
    url = f"/admin/log?page={page}"
    if server_id:
        url += f"&server_id={server_id}"
    return RedirectResponse(url, status_code=303)


# ── Settings ──────────────────────────────────────────────────────────────────

def _totp_qr_b64() -> str:
    secret = os.environ.get("TOTP_SECRET", "")
    if not secret:
        return ""
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name="admin", issuer_name="BeNeM Admin")
    img = qrcode.make(uri)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def _can_restart() -> bool:
    return os.path.exists("/var/run/docker.sock")


@app.get("/admin/settings", response_class=HTMLResponse)
def settings_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    return templates.TemplateResponse(request, "settings.html", {
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": _can_restart(),
        "restart_initiated": False,
        "servers": servers,
    })


@app.post("/admin/restart")
def restart_container(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    if not _can_restart():
        return RedirectResponse("/admin/settings", status_code=302)
    # Runs in background — this process will be killed momentarily
    subprocess.Popen(["docker", "restart", "benem-admin"])  # must match container_name in docker-compose.yml
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    return templates.TemplateResponse(request, "settings.html", {
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": True,
        "restart_initiated": True,
        "servers": servers,
    })


async def _notify_cache_reload(server_id: str) -> None:
    """Tell the middleware to reload cache config for a server."""
    try:
        headers = {"X-Proxy-Token": PROXY_TOKEN} if PROXY_TOKEN else {}
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(
                f"{MIDDLEWARE_INTERNAL_URL}/internal/cache/reload",
                json={"server_id": server_id},
                headers=headers,
            )
    except Exception as e:
        print(f"[Admin] Failed to notify middleware cache reload for {server_id}: {e}")


# ── Server Management (HTMX fragments) ────────────────────────────────────

@app.get("/admin/settings/servers/card", response_class=HTMLResponse)
def server_card_readonly(request: Request, server_id: str = ""):
    """Return a read-only server card fragment (HTMX)."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse("", status_code=404)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": server,
    })


@app.get("/admin/settings/servers/edit-form", response_class=HTMLResponse)
def server_edit_form(request: Request, server_id: str = ""):
    """Return an editable server card fragment (HTMX). Empty server_id = new server."""
    if not auth.is_authenticated(request):
        return HTMLResponse(
            '<div class="alert alert-red">Session expired — <a href="/admin/login" style="color:inherit;text-decoration:underline;">log in again</a>.</div>',
            status_code=401,
        )
    if server_id:
        server = get_server(server_id)
        if not server:
            return HTMLResponse("", status_code=404)
    else:
        server = Server(id="", name="", url="", api_key="", pin="")
    return templates.TemplateResponse(request, "_server_form.html", {
        "s": server,
        "is_new": not server_id,
    })


@app.post("/admin/settings/servers/add", response_class=HTMLResponse)
async def server_add(
    request: Request,
    id: str = Form(...),
    name: str = Form(...),
    url: str = Form(...),
    api_key: str = Form(...),
    pin: str = Form(""),
    cache_enabled: str = Form(""),
    cache_refresh_seconds: int = Form(120),
):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    id = id.strip()
    name = name.strip()
    url = url.strip().rstrip("/")
    api_key = api_key.strip()
    pin = pin.strip()
    cache_on = cache_enabled == "1"
    refresh = max(60, min(900, cache_refresh_seconds))
    if not id or not name or not url or not api_key:
        return HTMLResponse(
            '<div class="alert alert-red">All fields except PIN are required.</div>',
            status_code=422,
        )
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', id):
        return HTMLResponse(
            '<div class="alert alert-red">Server ID must contain only letters, numbers, hyphens, and underscores.</div>',
            status_code=422,
        )
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    if any(s.id == id for s in servers):
        return HTMLResponse(
            f'<div class="alert alert-red">Server ID "{escape(id)}" already exists.</div>',
            status_code=422,
        )
    new_server = Server(id=id, name=name, url=url, api_key=api_key, pin=pin,
                        cache_enabled=cache_on, cache_refresh_seconds=refresh)
    servers.append(new_server)
    save_servers(servers)
    await _notify_cache_reload(id)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": new_server,
    })


@app.post("/admin/settings/servers/edit", response_class=HTMLResponse)
async def server_edit(
    request: Request,
    original_id: str = Form(...),
    id: str = Form(...),
    name: str = Form(...),
    url: str = Form(...),
    api_key: str = Form(...),
    pin: str = Form(""),
    cache_enabled: str = Form(""),
    cache_refresh_seconds: int = Form(120),
):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    id = id.strip()
    name = name.strip()
    url = url.strip().rstrip("/")
    api_key = api_key.strip()
    pin = pin.strip()
    cache_on = cache_enabled == "1"
    refresh = max(60, min(900, cache_refresh_seconds))
    if not id or not name or not url or not api_key:
        return HTMLResponse(
            '<div class="alert alert-red">All fields except PIN are required.</div>',
            status_code=422,
        )
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', id):
        return HTMLResponse(
            '<div class="alert alert-red">Server ID must contain only letters, numbers, hyphens, and underscores.</div>',
            status_code=422,
        )
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    if id != original_id and any(s.id == id for s in servers):
        return HTMLResponse(
            f'<div class="alert alert-red">Server ID "{escape(id)}" already exists.</div>',
            status_code=422,
        )
    idx = next((i for i, s in enumerate(servers) if s.id == original_id), None)
    if idx is None:
        return HTMLResponse(
            '<div class="alert alert-red">Server not found.</div>',
            status_code=404,
        )
    servers[idx] = Server(id=id, name=name, url=url, api_key=api_key, pin=pin,
                          cache_enabled=cache_on, cache_refresh_seconds=refresh)
    save_servers(servers)
    await _notify_cache_reload(id)
    return templates.TemplateResponse(request, "_server_card.html", {
        "s": servers[idx],
    })


@app.post("/admin/settings/servers/delete", response_class=HTMLResponse)
async def server_delete(request: Request, server_id: str = Form(...)):
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    try:
        servers = load_servers()
    except FileNotFoundError:
        return HTMLResponse("")
    servers = [s for s in servers if s.id != server_id]
    save_servers(servers)
    await _notify_cache_reload(server_id)
    return HTMLResponse("")  # HTMX removes the card from DOM


@app.get("/admin/settings/server-health", response_class=HTMLResponse)
async def server_health(request: Request, id: str = ""):
    """Passive health check — one lightweight BHNM API call per server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(id)
    if not server:
        return HTMLResponse(
            '<span class="health-dot health-unknown" title="Server not found"></span>'
        )
    tls_verify = os.environ.get("BHNM_TLS_VERIFY", "true").lower() != "false"
    try:
        form: dict = {"pwd": server.api_key, "method": "getdevices", "max": "1"}
        if server.pin:
            form["pin"] = server.pin
        async with httpx.AsyncClient(timeout=5.0, verify=tls_verify) as client:
            resp = await client.post(
                f"{server.url.rstrip('/')}/api/incident_api.php", data=form
            )
        if resp.status_code == 200:
            return HTMLResponse(
                '<span class="health-dot health-ok" title="Connected"></span>'
            )
        else:
            return HTMLResponse(
                f'<span class="health-dot health-fail" title="HTTP {resp.status_code}"></span>'
            )
    except Exception as e:
        detail = str(e)[:80]
        return HTMLResponse(
            f'<span class="health-dot health-fail" title="{escape(detail)}"></span>'
        )


@app.post("/admin/settings/servers/test", response_class=HTMLResponse)
def server_test(request: Request, server_id: str = Form(...)):
    """Run detailed connection test (DNS → HTTPS → API auth) for a server."""
    if not auth.is_authenticated(request):
        return HTMLResponse("", status_code=401)
    server = get_server(server_id)
    if not server:
        return HTMLResponse('<div class="alert alert-red">Server not found.</div>')
    results = run_test(server.url, server.api_key, server.pin)
    return templates.TemplateResponse(request, "_server_test_results.html", {
        "results": results,
    })
