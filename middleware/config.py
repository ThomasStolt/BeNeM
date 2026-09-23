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

# Per-server caching (incidents, tactical, thresholds, maintenance map).
# ON by default (ruling 2026-09-03): the maintenance map and, later, the
# host_status overlay only exist for cached servers. A servers.json entry
# without the key, and the admin portal's new-server form, both mean ON.
# This is the ONLY place the default lives — every reader goes through
# server_cache_enabled(); benem-admin/servers.py mirrors it (separate app).
CACHE_ENABLED_DEFAULT: bool = True


def server_cache_enabled(server: dict) -> bool:
    return bool(server.get("cache_enabled", CACHE_ENABLED_DEFAULT))
DIAG_PROBE_INTERVAL: float = float(os.environ.get("DIAG_PROBE_INTERVAL", "15"))
DIAG_DOWN_THRESHOLD: int = int(os.environ.get("DIAG_DOWN_THRESHOLD", "2"))
BENEM_SECRET_KEY: str = os.environ.get("BENEM_SECRET_KEY", "")


def server_accepted_secrets(server: dict) -> list[str]:
    """Webhook secrets this server accepts (S1 change 1a).

    A list, not a value, because rotation needs an overlap window: the new secret
    and the old one are both accepted until every device has moved. 1a seeds each
    server's list with the current global secret, so the set of devices a webhook
    reaches is unchanged — the mechanism lands without the migration.
    Missing or malformed means an empty list, and the caller falls back to the
    pre-1a single-secret lookup rather than silently paging nobody.
    """
    raw = server.get("webhook_secrets") or []
    if not isinstance(raw, list):
        return []
    return [s for s in (str(x).strip() for x in raw) if s]


# M3 (2.20.0) — CLSD retention, per server, OFF by default.
# Behind a flag because turning it on before iOS 2.14.0 / PWA 0.19.0 are in the
# field would put closed rows into build 53's incident list, which applies NO
# status filter at all (IncidentListViewModel.filteredIncidents:69-102) and has
# no pill to hide them. A purely additive payload producing a visible behaviour
# change on a released client — see the filter design note, §4.
# Flipped ON in 2.20.1, after Thomas confirms `BeNeM/54` in the proxy log.
CLSD_RETENTION_DEFAULT: bool = False

# C15 — the cache holds twenty-four hours of incident data and no more.
RETENTION_SECONDS: float = 24 * 3600


def server_retain_closed(server: dict) -> bool:
    return bool(server.get("retain_closed", CLSD_RETENTION_DEFAULT))


# C19 (2.21.0) — two cadences, one of them new.
#
# `list_poll_seconds` is ADDED beside `cache_refresh_seconds`; nothing is
# renamed. `cache_refresh_seconds` keeps its present meaning as the ENRICHMENT
# cadence and stays the key in every servers.json in the field and in
# benem-admin's form. Renaming it to C6's `incident_polling_seconds` is deferred
# to a later migration that reads the old key and writes the new one, so a
# configured value cannot be lost in the change — ruled 2026-09-23 (Thomas).
#
# The BHNM cost, stated: ONE getincidents per server per interval — 120 calls an
# hour per server at the default, whatever the incident count. `_fetch_incidents`
# is one request returning the whole list; it does not scale with incidents.
# Enrichment is the N-call side and its cadence is untouched by this.
#
# The minimum is 15 s and not lower, because C7 rate-limits the on-demand
# Refresh to one per server per 30 s: a background poll faster than that would
# make the client's own trigger the slower of the two.
LIST_POLL_DEFAULT: int = 30
LIST_POLL_MIN: int = 15
LIST_POLL_MAX: int = 900


def server_list_poll_seconds(server: dict) -> int:
    raw = server.get("list_poll_seconds", LIST_POLL_DEFAULT)
    try:
        value = int(raw)
    except (TypeError, ValueError):
        # A misconfigured value falls back to the default rather than crashing
        # the loop for that server. The alternative is one bad character in
        # servers.json stopping the list poll with nothing on screen to say so.
        print(f"[Config] list_poll_seconds={raw!r} is not an integer — "
              f"using {LIST_POLL_DEFAULT}s")
        return LIST_POLL_DEFAULT
    return max(LIST_POLL_MIN, min(LIST_POLL_MAX, value))
