VERSION = "1.0.0"

import os
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv

import auth
from auth import SESSION_COOKIE

load_dotenv()

app = FastAPI(docs_url=None, redoc_url=None)
templates = Jinja2Templates(directory="templates")


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/admin/health")
def health():
    return {"status": "running", "version": VERSION}


# ── Auth ──────────────────────────────────────────────────────────────────────

@app.get("/admin/login", response_class=HTMLResponse)
def login_page(request: Request):
    return templates.TemplateResponse(request, "login.html", {"error": None})


@app.post("/admin/login")
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


# ── Generate Link (placeholder — full implementation in Task 8) ───────────────

@app.get("/admin/", response_class=HTMLResponse)
def generate_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    # Placeholder — full implementation added in Task 8
    return HTMLResponse("<html><body><h1>Generate Link — coming soon</h1></body></html>")
