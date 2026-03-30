import os
import pytest
import pyotp
from unittest.mock import patch

from auth import verify_totp, create_session_token, verify_session_token

SECRET = pyotp.random_base32()


def test_verify_totp_valid():
    code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_totp(code) is True


def test_verify_totp_invalid_code():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_totp("000000") is False


def test_verify_totp_missing_secret():
    with patch.dict(os.environ, {}, clear=True):
        assert verify_totp("123456") is False


def test_session_token_roundtrip():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        token = create_session_token()
        assert verify_session_token(token) is True


def test_session_token_tampered():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        token = create_session_token()
        tampered = token[:-4] + "xxxx"
        assert verify_session_token(tampered) is False


def test_session_token_empty():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_session_token("") is False
