import os
import pyotp
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from fastapi import Request
from fastapi.responses import RedirectResponse

SESSION_COOKIE = "benem_admin_session"
SESSION_MAX_AGE = 28800  # 8 hours


def _serializer() -> URLSafeTimedSerializer:
    secret = os.environ.get("SESSION_SECRET", "")
    if not secret:
        raise RuntimeError(
            "SESSION_SECRET is not set. "
            "Add SESSION_SECRET to .env to enable session signing."
        )
    return URLSafeTimedSerializer(secret, salt="benem-admin-session")


def verify_totp(code: str) -> bool:
    secret = os.environ.get("TOTP_SECRET", "")
    if not secret:
        return False
    return pyotp.TOTP(secret).verify(code, valid_window=1)


def create_session_token() -> str:
    return _serializer().dumps({"ok": True})


def verify_session_token(token: str) -> bool:
    if not token:
        return False
    try:
        _serializer().loads(token, max_age=SESSION_MAX_AGE)
        return True
    except (BadSignature, SignatureExpired):
        return False


def is_authenticated(request: Request) -> bool:
    token = request.cookies.get(SESSION_COOKIE, "")
    return verify_session_token(token)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse("/admin/login", status_code=302)
