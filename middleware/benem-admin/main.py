VERSION = "1.3.0"

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
from servers import load_servers, get_server
from sf_symbols import SF_SYMBOLS

load_dotenv()

MIDDLEWARE_URL = os.environ.get("MIDDLEWARE_URL", "")
PUSH_SECRET = os.environ.get("WEBHOOK_SECRET", "")
PROXY_TOKEN = os.environ.get("PROXY_TOKEN", "")

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(docs_url=None, redoc_url=None)
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)
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
        f'<button type="button"'
        f' data-url="{url_attr}"'
        f' data-result="bhnm-test-result"'
        f' onclick="testReachability(this)"'
        f' class="btn btn-ghost btn-sm">Test</button>'
    )


@app.get("/admin/reachability-check")
async def reachability_check(request: Request, url: str = ""):
    if not auth.is_authenticated(request):
        return JSONResponse({"ok": False, "detail": "Not authenticated"}, status_code=401)
    if not url:
        return JSONResponse({"ok": False, "detail": "No URL provided"})

    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return JSONResponse({"ok": False, "detail": "Only http/https URLs are allowed"})

    # Restrict to hosts already configured in servers.json or MIDDLEWARE_URL
    try:
        allowed_hosts = {urlparse(s.url).hostname for s in load_servers()}
    except FileNotFoundError:
        allowed_hosts = set()
    if MIDDLEWARE_URL:
        allowed_hosts.add(urlparse(MIDDLEWARE_URL).hostname)
    allowed_hosts.discard(None)

    if parsed.hostname not in allowed_hosts:
        return JSONResponse({"ok": False, "detail": f"Host '{parsed.hostname}' is not in the configured server list"})

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(url)
        return JSONResponse({"ok": True, "detail": f"HTTP {resp.status_code}"})
    except httpx.HTTPError as e:
        print(f"[ReachabilityCheck] HTTP error for {parsed.hostname}: {e}")
        return JSONResponse({"ok": False, "detail": "Connection failed"})
    except Exception as e:
        print(f"[ReachabilityCheck] Unexpected error for {parsed.hostname}: {e}")
        return JSONResponse({"ok": False, "detail": "Connection failed"})


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


# ── Connection Test ───────────────────────────────────────────────────────────

LOG_PER_PAGE = 50


@app.get("/admin/test", response_class=HTMLResponse)
def test_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    return templates.TemplateResponse(request, "test.html", {
        "active": "test",
        "servers": servers,
        "selected_id": None,
        "results": None,
    })


@app.post("/admin/test", response_class=HTMLResponse)
def test_submit(request: Request, server_id: str = Form(...)):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    try:
        servers = load_servers()
    except FileNotFoundError:
        servers = []
    server = next((s for s in servers if s.id == server_id), None)
    results = run_test(server.url, server.api_key, server.pin) if server else []
    return templates.TemplateResponse(request, "test.html", {
        "active": "test",
        "servers": servers,
        "selected_id": server_id,
        "results": results,
    })


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
    if not entry or not entry.get("link"):
        return JSONResponse({"error": "not found or no full link stored"}, status_code=404)
    return JSONResponse({
        "url": entry["link"],
        "qr_b64": _make_qr_b64(entry["link"]),
        "user": entry.get("user", ""),
        "server_name": entry.get("server_name", ""),
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
    return templates.TemplateResponse(request, "settings.html", {
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": _can_restart(),
        "restart_initiated": False,
    })


@app.post("/admin/restart")
def restart_container(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    if not _can_restart():
        return RedirectResponse("/admin/settings", status_code=302)
    # Runs in background — this process will be killed momentarily
    subprocess.Popen(["docker", "restart", "benem-admin"])
    return templates.TemplateResponse(request, "settings.html", {
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": True,
        "restart_initiated": True,
    })
