# benem-admin/tests/test_crypto.py
import base64
import json
import os
import zlib
import pytest
from unittest.mock import patch

from crypto import encrypt_payload, load_key

VALID_KEY_HEX = "a" * 64  # 32 bytes as hex


def test_load_key_success():
    with patch.dict(os.environ, {"BENEM_SECRET_KEY": VALID_KEY_HEX}):
        key = load_key()
    assert key == bytes.fromhex(VALID_KEY_HEX)


def test_load_key_missing_raises():
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(ValueError, match="BENEM_SECRET_KEY"):
            load_key()


def test_load_key_wrong_length_raises():
    with patch.dict(os.environ, {"BENEM_SECRET_KEY": "abc"}):
        with pytest.raises(ValueError, match="64 hex"):
            load_key()


def test_encrypt_payload_returns_url_safe_base64():
    key = bytes.fromhex(VALID_KEY_HEX)
    blob = encrypt_payload({"hello": "world"}, key)
    # Must be URL-safe base64 (no +, /, =)
    assert "+" not in blob
    assert "/" not in blob
    assert "=" not in blob


def test_encrypt_payload_roundtrip():
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    key = bytes.fromhex(VALID_KEY_HEX)
    payload = {"bhnm_url": "https://bhnm.corp.com", "api_key": "secret123"}
    blob = encrypt_payload(payload, key)

    raw_bytes = base64.urlsafe_b64decode(blob + "==")
    nonce = raw_bytes[:12]
    ct = raw_bytes[12:]
    compressed = AESGCM(key).decrypt(nonce, ct, None)
    recovered = json.loads(zlib.decompress(compressed))
    assert recovered == payload


def test_encrypt_produces_different_ciphertext_each_call():
    key = bytes.fromhex(VALID_KEY_HEX)
    payload = {"x": 1}
    blob1 = encrypt_payload(payload, key)
    blob2 = encrypt_payload(payload, key)
    assert blob1 != blob2  # random nonce
