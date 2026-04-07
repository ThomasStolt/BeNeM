import os
import base64
from dotenv import load_dotenv

load_dotenv()  # loads .env from the working directory, no-op if absent

# APNs — all values come from environment variables
APNS_KEY_ID:   str = os.environ["APNS_KEY_ID"]
APNS_TEAM_ID:  str = os.environ["APNS_TEAM_ID"]
APNS_BUNDLE_ID: str = os.environ["APNS_BUNDLE_ID"]

# Private key: stored as a base64-encoded string in APNS_PRIVATE_KEY_B64
# (avoids file mounting — works on any cloud/container platform)
APNS_PRIVATE_KEY: str = base64.b64decode(os.environ["APNS_PRIVATE_KEY_B64"]).decode()

# Web Push (VAPID) — optional; Web Push sending is disabled if not set
VAPID_PRIVATE_KEY: str = os.environ.get("VAPID_PRIVATE_KEY", "")
VAPID_PUBLIC_KEY: str = os.environ.get("VAPID_PUBLIC_KEY", "")
VAPID_CONTACT_EMAIL: str = os.environ.get("VAPID_CONTACT_EMAIL", "")

# Server
MIDDLEWARE_PORT: int = int(os.environ.get("MIDDLEWARE_PORT", "8889"))

# BHNM proxy
BHNM_TLS_VERIFY: bool = os.environ.get("BHNM_TLS_VERIFY", "true").lower() != "false"
SERVERS_JSON_PATH: str = os.environ.get("SERVERS_JSON_PATH", "/data/servers.json")
PROXY_TIMEOUT: float = 60.0  # seconds — BHNM can be slow for large queries
PROXY_TOKEN: str = os.environ.get("PROXY_TOKEN", "")
