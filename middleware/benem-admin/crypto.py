import base64
import json
import os
import zlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
        raise ValueError("BENEM_SECRET_KEY is not set")
    if len(hex_key) != 64:
        raise ValueError(f"BENEM_SECRET_KEY must be 64 hex characters (32 bytes), got {len(hex_key)}")
    return bytes.fromhex(hex_key)


def encrypt_payload(payload: dict, key: bytes) -> str:
    """Pack payload → JSON → zlib compress → AES-256-GCM encrypt → base64url (no padding)."""
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, compressed, None)  # ct includes 16-byte GCM tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")
