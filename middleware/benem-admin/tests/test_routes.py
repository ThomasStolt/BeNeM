import os
import pyotp
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

SECRET = pyotp.random_base32()

# Set env before importing main
os.environ.setdefault("TOTP_SECRET", SECRET)
os.environ.setdefault("BENEM_SECRET_KEY", "a" * 64)
os.environ.setdefault("SERVERS_JSON_PATH", "/nonexistent/servers.json")

from main import app

client = TestClient(app, follow_redirects=False)


def test_get_login_returns_200():
    resp = client.get("/admin/login")
    assert resp.status_code == 200
    assert b"code" in resp.content.lower() or b"totp" in resp.content.lower() or b"sign" in resp.content.lower()


def test_post_login_invalid_code_returns_200_with_error():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        resp = client.post("/admin/login", data={"code": "000000"})
    assert resp.status_code == 200
    assert b"incorrect" in resp.content.lower() or b"invalid" in resp.content.lower() or b"wrong" in resp.content.lower()


def test_post_login_valid_code_redirects_to_generate():
    valid_code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        resp = client.post("/admin/login", data={"code": valid_code})
    assert resp.status_code == 302
    assert resp.headers["location"] == "/admin/"
    # Verify session cookie attributes
    set_cookie = resp.headers.get("set-cookie", "")
    assert "benem_admin_session" in set_cookie
    assert "HttpOnly" in set_cookie
    assert "SameSite=strict" in set_cookie.lower() or "samesite=strict" in set_cookie.lower()


def test_protected_generate_route_redirects_unauthenticated():
    resp = client.get("/admin/")
    assert resp.status_code == 302
    assert "/admin/login" in resp.headers["location"]


def test_logout_redirects_to_login():
    resp = client.post("/admin/logout")
    assert resp.status_code == 302
    assert "/admin/login" in resp.headers["location"]
