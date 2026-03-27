#!/usr/bin/env python3
"""Generate a benem:// deep-link URL for provisioning BeNeM app connections."""

import argparse
import base64
import getpass
import os
import sys
import zlib
import json
from urllib.parse import quote

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("Error: 'cryptography' package not found. Install with: pip install cryptography")
    sys.exit(1)


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
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
        print(f"Error: Key must be 64 hex characters (32 bytes). Got {len(hex_key)}.")
        sys.exit(1)
    try:
        return bytes.fromhex(hex_key)
    except ValueError:
        print("Error: Key contains non-hex characters.")
        sys.exit(1)


def encrypt_payload(payload: dict, key: bytes) -> str:
    """Pack payload dict → JSON → zlib compress → AES-256-GCM encrypt → base64url."""
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, compressed, None)  # ct includes 16-byte tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")


def prompt(label: str, default: str = "", secret: bool = False) -> str:
    """Prompt the user for input, showing the default. Returns default on empty input."""
    display_default = "****" if secret and default else (default or "")
    suffix = f" [{display_default}]" if display_default else " []"
    if secret:
        value = getpass.getpass(f"{label}{suffix}: ")
    else:
        value = input(f"{label}{suffix}: ").strip()
    return value if value else default


def interactive_mode() -> dict:
    """Walk the user through each field interactively."""
    print("\nBeNeM Link Generator — Interactive Mode")
    print("=" * 42)
    print("Press Enter to accept the default shown in [brackets].\n")

    server = prompt("Middleware URL")
    if not server:
        print("Error: Server URL is required.")
        sys.exit(1)
    if not server.startswith("http://") and not server.startswith("https://"):
        server = "https://" + server

    api_key = prompt("API Token", secret=True)
    if not api_key:
        print("Error: API Token is required.")
        sys.exit(1)

    pin = prompt("PIN / License ID (leave blank for none)", secret=True)
    user = prompt("User Name", default="enter user name")

    # Default server name to hostname
    from urllib.parse import urlparse
    default_name = urlparse(server).hostname or server
    name = prompt("Server Name", default=default_name)

    symbol = prompt("SF Symbol", default="server.rack")
    color = prompt("Accent colour (hex)", default="#0A84FF")

    push_secret = prompt("Webhook Secret", secret=True)

    return {
        "server": server,
        "api_key": api_key,
        "pin": pin,
        "user": user,
        "name": name,
        "push_secret": push_secret,
        "symbol": symbol,
        "color": color,
    }


def save_qr(url: str, path: str = "benem-link.png") -> None:
    try:
        import qrcode  # type: ignore
    except ImportError:
        print("QR code skipped — install with: pip install qrcode[pil]")
        return
    img = qrcode.make(url)
    img.save(path)
    print(f"QR code saved to {path}")


def main():
    parser = argparse.ArgumentParser(description="Generate a benem:// configuration URL.")
    parser.add_argument("-i", "--interactive", action="store_true",
                        help="Interactive mode: prompt for each field")
    parser.add_argument("--middleware-url", dest="server",
                        help="Middleware URL (e.g. https://bhnm-apns.yourcompany.com)")
    parser.add_argument("--api_key", help="API token")
    parser.add_argument("--pin", default="", help="PIN / License ID (SaaS only, optional)")
    parser.add_argument("--user", default="enter user name", help="ACK user name")
    parser.add_argument("--server-name", "--name", dest="name", default="",
                        help="Connection display name (--name accepted for backwards compat)")
    parser.add_argument("--symbol", default="server.rack", help="SF Symbol name")
    parser.add_argument("--color", default="#0A84FF", help="Accent colour (hex)")
    parser.add_argument("--push-secret", dest="push_secret", default="",
                        help="Push webhook secret (encrypted in payload)")
    parser.add_argument("--qr", action="store_true",
                        help="Also save a QR code PNG (benem-link.png)")
    args = parser.parse_args()

    if args.interactive:
        payload = interactive_mode()
        generate_qr = prompt("\nGenerate QR code? [y/N]").lower() == "y"
    else:
        if not args.server or not args.api_key:
            parser.error("--middleware-url and --api_key are required (or use -i for interactive mode)")
        server = args.server
        if not server.startswith("http://") and not server.startswith("https://"):
            server = "https://" + server
        payload = {
            "server":      server,
            "api_key":     args.api_key,
            "pin":         args.pin,
            "user":        args.user,
            "name":        args.name,
            "push_secret": args.push_secret,
            "symbol":      args.symbol,
            "color":       args.color,
        }
        generate_qr = args.qr

    key = load_key()
    blob = encrypt_payload(payload, key)
    url = f"benem://configure?p={blob}"
    print(url)

    if generate_qr:
        save_qr(url)


if __name__ == "__main__":
    main()
