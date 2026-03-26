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
        # Fall back to reading directly from Secrets.swift in the repo
        secrets_path = os.path.join(os.path.dirname(__file__), "BeNeM", "Secrets.swift")
        try:
            with open(secrets_path) as f:
                for line in f:
                    if "encryptionKey" in line and "=" in line:
                        hex_key = line.split('"')[1]
                        break
        except FileNotFoundError:
            pass

    if not hex_key:
        print("Error: Could not find the encryption key.")
        print("Either set BENEM_SECRET_KEY or ensure BeNeM/Secrets.swift exists.")
        sys.exit(1)
    if len(hex_key) != 64:
        print(f"Error: Key must be 64 hex characters (32 bytes). Got {len(hex_key)} characters.")
        sys.exit(1)
    try:
        return bytes.fromhex(hex_key)
    except ValueError:
        print("Error: Key contains non-hex characters.")
        sys.exit(1)


def encrypt(plaintext: str, key: bytes) -> str:
    """Encrypt plaintext with AES-256-GCM. Returns base64url-encoded nonce+ciphertext+tag."""
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext.encode("utf-8"), None)  # ct includes 16-byte tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")


def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("--bhnm-server",  required=True,  dest="server", help="BHNM server URL (plain text, e.g. https://bhnm.example.com)")
    parser.add_argument("--api_key",     required=True,  help="API key to encrypt")
    parser.add_argument("--pin",         default="",     help="PIN to encrypt (optional, omit for non-SaaS servers)")
    parser.add_argument("--user",        default="enter user name", help="ACK user name (plain text, optional)")
    parser.add_argument("--name",        default="",               help="Connection name shown in the app (plain text, optional)")
    parser.add_argument("--push_url",    default="",               help="Push notification middleware URL (plain text, optional, e.g. https://bhnm-apns.hurrikap.org)")
    parser.add_argument("--push_secret", default="",               help="Push notification webhook secret to encrypt (optional)")
    args = parser.parse_args()

    key = load_key()

    enc_api_key = encrypt(args.api_key, key)
    enc_pin     = encrypt(args.pin, key)

    # Percent-encode plain-text fields (%20 for spaces, matching Swift URLComponents)
    server   = quote(args.server, safe="")  # encode ALL chars including structural URL delimiters
    ack_user = quote(args.user, safe="")

    url = f"benem://configure?server={server}&api_key={enc_api_key}&pin={enc_pin}&ack_user={ack_user}"
    if args.name:
        url += f"&name={quote(args.name, safe='')}"
    if args.push_url:
        url += f"&push_url={quote(args.push_url, safe='')}"
    if args.push_secret:
        url += f"&push_secret={encrypt(args.push_secret, key)}"
    print(url)


if __name__ == "__main__":
    main()
