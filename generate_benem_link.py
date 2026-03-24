#!/usr/bin/env python3
"""Generate a benem:// deep-link URL for provisioning BeNeM app connections."""

import argparse
import base64
import os
import sys
from urllib.parse import quote

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("Error: 'cryptography' package not found. Install it with: pip install cryptography")
    sys.exit(1)


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
        print("Error: BENEM_SECRET_KEY environment variable is not set.")
        print("Set it to the same 64-character hex key embedded in your BeNeM build.")
        print("Example: export BENEM_SECRET_KEY=a1b2c3...  (64 hex chars)")
        sys.exit(1)
    if len(hex_key) != 64:
        print(f"Error: BENEM_SECRET_KEY must be 64 hex characters (32 bytes). Got {len(hex_key)} characters.")
        sys.exit(1)
    try:
        return bytes.fromhex(hex_key)
    except ValueError:
        print("Error: BENEM_SECRET_KEY contains non-hex characters.")
        sys.exit(1)


def encrypt(plaintext: str, key: bytes) -> str:
    """Encrypt plaintext with AES-256-GCM. Returns base64url-encoded nonce+ciphertext+tag."""
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode("utf-8"), None)  # ct includes 16-byte tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("--server",  required=True,  help="BHNM server URL (plain text, e.g. https://bhnm.example.com)")
    parser.add_argument("--api_key", required=True,  help="API key to encrypt")
    parser.add_argument("--pin",     default="",     help="PIN to encrypt (optional, omit for non-SaaS servers)")
    parser.add_argument("--user",    default="enter user name", help="ACK user name (plain text, optional)")
    args = parser.parse_args()

    key = load_key()

    enc_api_key = encrypt(args.api_key, key)
    enc_pin     = encrypt(args.pin, key)

    # Percent-encode plain-text fields (%20 for spaces, matching Swift URLComponents)
    server   = quote(args.server, safe=":/?#[]@!$&'()*+,;=")  # safe chars valid in URLs
    ack_user = quote(args.user, safe="")

    url = f"benem://configure?server={server}&api_key={enc_api_key}&pin={enc_pin}&ack_user={ack_user}"
    print(url)


if __name__ == "__main__":
    main()
