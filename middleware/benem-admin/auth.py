import os
import pyotp
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from fastapi import Request
from fastapi.responses import RedirectResponse

SESSION_COOKIE = "benem_admin_session"
SESSION_MAX_AGE = 86400  # 24 hours


def _serializer() -> URLSafeTimedSerializer:
    # SESSION_SECRET is preferred. BENEM_SECRET_KEY is accepted as a fallback for
    # deployments that haven't yet added a dedicated SESSION_SECRET to .env.
    secret = os.environ.get("SESSION_SECRET") or os.environ.get("BENEM_SECRET_KEY")
    if not secret:
        raise RuntimeError(
            "Neither SESSION_SECRET nor BENEM_SECRET_KEY is set. "
            "Set SESSION_SECRET in .env to enable session signing."
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
