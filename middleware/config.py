# APNs
APNS_KEY_FILE    = "/home/<your-username>/bhnm-apns/AuthKey_555235AFUU.p8"  # update path on Ubuntu
APNS_KEY_ID      = "555235AFUU"
APNS_TEAM_ID     = "8L27BJGYXP"
APNS_BUNDLE_ID   = "com.tstolt.bhnmmonitor"
APNS_USE_SANDBOX = True  # True = development/sandbox, False = production

# Server
MIDDLEWARE_PORT  = 8889

# Optional: shared secret BHNM sends as a query param for basic security
# Configure in BHNM webhook URL as: https://vpn.hurrikap.org:8889/webhook?secret=xxx
WEBHOOK_SECRET   = ""  # leave empty to disable
