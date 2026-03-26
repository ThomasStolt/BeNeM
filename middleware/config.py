import os
import base64
from dotenv import load_dotenv

load_dotenv()  # loads .env from the working directory, no-op if absent

# APNs — all values come from environment variables
APNS_KEY_ID:   str = os.environ["APNS_KEY_ID"]
APNS_TEAM_ID:  str = os.environ["APNS_TEAM_ID"]
APNS_BUNDLE_ID: str = os.environ["APNS_BUNDLE_ID"]
APNS_USE_SANDBOX: bool = os.environ.get("APNS_USE_SANDBOX", "true").lower() == "true"

# Private key: stored as a base64-encoded string in APNS_PRIVATE_KEY_B64
# (avoids file mounting — works on any cloud/container platform)
APNS_PRIVATE_KEY: str = base64.b64decode(os.environ["APNS_PRIVATE_KEY_B64"]).decode()

# Server
MIDDLEWARE_PORT: int = int(os.environ.get("MIDDLEWARE_PORT", "8889"))
