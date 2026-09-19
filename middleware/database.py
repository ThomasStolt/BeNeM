import os
import sqlite3
from contextlib import contextmanager

# /data is a Docker volume — falls back to local dir for bare-metal installs
DB_PATH = os.environ.get("DB_PATH", "/data/bhnm_apns.db")

def init_db():
    with get_conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS device_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token TEXT UNIQUE NOT NULL,
                device_name TEXT DEFAULT 'unknown',
                active_secret TEXT NOT NULL DEFAULT '',
                apns_environment TEXT NOT NULL DEFAULT 'production',
                server_id TEXT NOT NULL DEFAULT '',
                registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        # Migration: add active_secret to existing databases (silently ignored if already present)
        try:
            conn.execute("ALTER TABLE device_tokens ADD COLUMN active_secret TEXT NOT NULL DEFAULT ''")
        except Exception:
            pass  # Column already exists — safe to ignore
        # Migration: add apns_environment column
        try:
            conn.execute("ALTER TABLE device_tokens ADD COLUMN apns_environment TEXT NOT NULL DEFAULT 'production'")
        except Exception:
            pass  # Column already exists — safe to ignore
        # Migration (S1 1a): which server a registration belongs to. Recorded, not
        # yet used to filter — the fan-out is still driven by the accepted-secret
        # list, so behaviour is unchanged while every server shares one secret.
        try:
            conn.execute("ALTER TABLE device_tokens ADD COLUMN server_id TEXT NOT NULL DEFAULT ''")
        except Exception:
            pass  # Column already exists — safe to ignore

        conn.execute("""
            CREATE TABLE IF NOT EXISTS web_push_subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                endpoint TEXT UNIQUE NOT NULL,
                p256dh TEXT NOT NULL,
                auth TEXT NOT NULL,
                webhook_secret TEXT NOT NULL DEFAULT '',
                server_id TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        try:
            conn.execute("ALTER TABLE web_push_subscriptions ADD COLUMN server_id TEXT NOT NULL DEFAULT ''")
        except Exception:
            pass  # Column already exists — safe to ignore

        # C10 — an incident's alert_type never changes (Thomas, 2026-09-19: a host
        # incident is always a host incident; service and threshold are different
        # things that do not convert). It cannot be derived from the title either
        # — incident 25076 is titled "Application Service Wordpress" and its type
        # is `service`, so title parsing gets it wrong. So it is learned once from
        # a CONFIRMED detail call and kept, and keeping it across restarts is what
        # stops a restart being a cold start.
        conn.execute("""
            CREATE TABLE IF NOT EXISTS incident_types (
                server_id   TEXT NOT NULL,
                incident_id TEXT NOT NULL,
                alert_type  TEXT NOT NULL,
                last_seen   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (server_id, incident_id)
            )
        """)
        # Bounded by construction. Incident ids are not reused, so without this the
        # table only ever grows. 90 days is far longer than any incident this
        # project has seen stay open (the oldest in the lab opened 2026-05-20).
        try:
            conn.execute("DELETE FROM incident_types "
                         "WHERE last_seen < datetime('now', '-90 days')")
        except Exception:
            pass

@contextmanager
def get_conn():
    # Resolved per connection, not captured at import. DB_PATH used to bind at
    # module import, so the value depended on which module imported `database`
    # first — invisible in production (one path, set before anything runs) and a
    # collection error in tests the moment a new import edge appeared.
    # benem-admin/push_db.py:16 already does it this way; this is the same fix.
    conn = sqlite3.connect(os.environ.get("DB_PATH", DB_PATH))
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()

def save_token(token: str, device_name: str = "unknown", active_secret: str = "",
               apns_environment: str = "production", server_id: str = ""):
    with get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO device_tokens (token, device_name, active_secret, apns_environment, server_id) "
            "VALUES (?, ?, ?, ?, ?)",
            (token, device_name, active_secret, apns_environment, server_id)
        )

def get_tokens_for_secrets(secrets: list[str]) -> list[tuple[str, str]]:
    """Return all (token, apns_environment) pairs registered under ANY of these secrets.

    S1 1a: a server carries a list of accepted secrets, so a webhook that resolves
    to a server fans out to every device registered under any entry in that list.
    While each list holds only the seeded global secret this returns exactly what
    the single-secret lookup returned, which is what makes 1a shippable alone.
    """
    if not secrets:
        return []
    placeholders = ",".join("?" for _ in secrets)
    with get_conn() as conn:
        rows = conn.execute(
            # ORDER BY is explicit: without it SQLite returned rowid order, and a
            # fan-out bug that only ever served the first row stayed invisible
            # because that row was always the same device. id ascending = oldest
            # registration first.
            f"SELECT token, apns_environment FROM device_tokens WHERE active_secret IN ({placeholders}) "
            "ORDER BY id",
            tuple(secrets)
        ).fetchall()
    return [(r[0], r[1]) for r in rows]


def get_tokens_for_secret(secret: str) -> list[tuple[str, str]]:
    """Return all (token, apns_environment) pairs registered for the given webhook secret."""
    return get_tokens_for_secrets([secret])

def get_all_tokens() -> list[str]:
    """Return all registered device tokens regardless of secret (used by /health)."""
    with get_conn() as conn:
        rows = conn.execute("SELECT token FROM device_tokens").fetchall()
    return [r[0] for r in rows]

def delete_token(token: str):
    """Call this when APNs returns 410 Gone (token no longer valid)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))


def save_web_push_subscription(endpoint: str, p256dh: str, auth: str, webhook_secret: str = "",
                               server_id: str = ""):
    with get_conn() as conn:
        conn.execute(
            """INSERT INTO web_push_subscriptions (endpoint, p256dh, auth, webhook_secret, server_id)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(endpoint) DO UPDATE SET p256dh=?, auth=?, webhook_secret=?, server_id=?""",
            (endpoint, p256dh, auth, webhook_secret, server_id,
             p256dh, auth, webhook_secret, server_id),
        )


def get_web_push_subscriptions_for_secrets(secrets: list[str]) -> list[dict]:
    """Web Push subscriptions registered under ANY of these secrets. See
    get_tokens_for_secrets — same reasoning, same 1a invariant."""
    if not secrets:
        return []
    placeholders = ",".join("?" for _ in secrets)
    with get_conn() as conn:
        rows = conn.execute(
            f"SELECT endpoint, p256dh, auth FROM web_push_subscriptions "
            f"WHERE webhook_secret IN ({placeholders}) ORDER BY id",
            tuple(secrets),
        ).fetchall()
    return [{"endpoint": r[0], "p256dh": r[1], "auth": r[2]} for r in rows]


def get_web_push_subscriptions_for_secret(secret: str) -> list[dict]:
    """Return all Web Push subscriptions registered for the given webhook secret."""
    return get_web_push_subscriptions_for_secrets([secret])


def delete_web_push_subscription(endpoint: str):
    """Remove a Web Push subscription (called when push service returns 410 Gone)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM web_push_subscriptions WHERE endpoint = ?", (endpoint,))


# -- C10: incident type map ----------------------------------------------------

def load_incident_types() -> dict[tuple[str, str], str]:
    """Every remembered (server_id, incident_id) -> alert_type. Read once at
    startup; the working copy lives in memory in incident_cache."""
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT server_id, incident_id, alert_type FROM incident_types").fetchall()
    return {(r[0], str(r[1])): r[2] for r in rows}


def save_incident_type(server_id: str, incident_id: str, alert_type: str) -> None:
    """Remember a type learned from a CONFIRMED detail call. Never call this with
    a guessed or defaulted value — a persisted guess is a guess that outlives the
    process that made it."""
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO incident_types (server_id, incident_id, alert_type, last_seen) "
            "VALUES (?, ?, ?, CURRENT_TIMESTAMP) "
            "ON CONFLICT(server_id, incident_id) DO UPDATE SET "
            "alert_type = excluded.alert_type, last_seen = CURRENT_TIMESTAMP",
            (server_id, str(incident_id), alert_type))
