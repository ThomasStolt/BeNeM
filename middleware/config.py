import os
from dotenv import load_dotenv

load_dotenv()  # loads .env from the working directory, no-op if absent

# APNs
APNS_KEY_FILE    = "/home/<your-username>/bhnm-apns/AuthKey_555235AFUU.p8"  # update path on Ubuntu
APNS_KEY_ID      = "555235AFUU"
APNS_TEAM_ID     = "8L27BJGYXP"
APNS_BUNDLE_ID   = "com.tstolt.bhnmmonitor"
APNS_USE_SANDBOX = True  # True = development/sandbox, False = production

# Server
MIDDLEWARE_PORT  = 8889

# Shared secret — loaded from the WEBHOOK_SECRET environment variable.
# Set it in .env (never commit that file) or via the system environment.
# Leave unset or empty to disable authentication (not recommended).
WEBHOOK_SECRET: str = os.environ.get("WEBHOOK_SECRET", "")
