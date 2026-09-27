import hashlib
import os
import secrets
import sqlite3
import time
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

        # App tokens (2026-09-27 design, app-token onboarding). The phone holds a
        # token and no BHNM credential; the token names a server here. Stored as a
        # sha256 so a copy of this file yields no usable token. One token per
        # PERSON, several devices: never bound to a device, because a reinstall
        # gets a new APNs token. Revocation only, no expiry (ruled 2026-09-27).
        conn.execute("""
            CREATE TABLE IF NOT EXISTS app_tokens (
                token_hash   TEXT PRIMARY KEY,
                server_id    TEXT NOT NULL,
                label        TEXT NOT NULL,
                issued_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_seen_at TIMESTAMP,
                revoked_at   TIMESTAMP
            )
        """)
        for table in ("device_tokens", "web_push_subscriptions"):
            try:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN app_token_hash TEXT NOT NULL DEFAULT ''")
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
               apns_environment: str = "production", server_id: str = "",
               app_token_hash: str = ""):
    with get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO device_tokens "
            "(token, device_name, active_secret, apns_environment, server_id, app_token_hash) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (token, device_name, active_secret, apns_environment, server_id, app_token_hash)
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
                               server_id: str = "", app_token_hash: str = ""):
    with get_conn() as conn:
        conn.execute(
            """INSERT INTO web_push_subscriptions
                   (endpoint, p256dh, auth, webhook_secret, server_id, app_token_hash)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(endpoint) DO UPDATE SET p256dh=?, auth=?, webhook_secret=?,
                   server_id=?, app_token_hash=?""",
            (endpoint, p256dh, auth, webhook_secret, server_id, app_token_hash,
             p256dh, auth, webhook_secret, server_id, app_token_hash),
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


def hash_app_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_app_token(server_id: str, label: str) -> str:
    """A new token for one person on one server. The plaintext is returned ONCE
    and never stored: the caller puts it in the QR and forgets it."""
    token = "bnm_" + secrets.token_urlsafe(32)
    with get_conn() as conn:
        conn.execute("INSERT INTO app_tokens (token_hash, server_id, label) VALUES (?, ?, ?)",
                     (hash_app_token(token), server_id, label))
    return token


def lookup_app_token(token: str) -> dict | None:
    """The token's row, or None if it was never issued. A REVOKED token is returned
    with revoked=True, so the caller can tell "revoked" from "unknown" — the app
    shows a different message for each (addition B)."""
    h = hash_app_token(token)
    with get_conn() as conn:
        row = conn.execute(
            "SELECT server_id, label, revoked_at, "
            "CAST(strftime('%s', COALESCE(last_seen_at, '1970-01-01')) AS INTEGER) "
            "FROM app_tokens WHERE token_hash = ?", (h,)).fetchone()
        if row is None:
            return None
        # ponytail: last_seen at most once a minute per token, so a list poll every
        # 30 s is not a write every 30 s.
        if row[2] is None and time.time() - row[3] > 60:
            conn.execute("UPDATE app_tokens SET last_seen_at = CURRENT_TIMESTAMP "
                         "WHERE token_hash = ?", (h,))
    return {"hash": h, "server_id": row[0], "label": row[1], "revoked": row[2] is not None}


def revoke_app_token(token_hash: str) -> bool:
    """Revoke one token. Its devices drop out of the next fan-out, because the
    fan-out joins on live tokens — nothing has to re-register."""
    with get_conn() as conn:
        cur = conn.execute("UPDATE app_tokens SET revoked_at = CURRENT_TIMESTAMP "
                           "WHERE token_hash = ? AND revoked_at IS NULL", (token_hash,))
    return cur.rowcount == 1


def get_tokens_for_servers(server_ids: list[str]) -> list[tuple[str, str]]:
    """(token, apns_environment) for every device registered with a LIVE app token
    of any of these servers — the by-server fan-out."""
    if not server_ids:
        return []
    placeholders = ",".join("?" for _ in server_ids)
    with get_conn() as conn:
        rows = conn.execute(
            f"SELECT d.token, d.apns_environment FROM device_tokens d "
            f"JOIN app_tokens a ON a.token_hash = d.app_token_hash "
            f"WHERE a.revoked_at IS NULL AND a.server_id IN ({placeholders}) ORDER BY d.id",
            tuple(server_ids)).fetchall()
    return [(r[0], r[1]) for r in rows]


def get_web_push_subscriptions_for_servers(server_ids: list[str]) -> list[dict]:
    """Web Push twin of get_tokens_for_servers."""
    if not server_ids:
        return []
    placeholders = ",".join("?" for _ in server_ids)
    with get_conn() as conn:
        rows = conn.execute(
            f"SELECT w.endpoint, w.p256dh, w.auth FROM web_push_subscriptions w "
            f"JOIN app_tokens a ON a.token_hash = w.app_token_hash "
            f"WHERE a.revoked_at IS NULL AND a.server_id IN ({placeholders}) ORDER BY w.id",
            tuple(server_ids)).fetchall()
    return [{"endpoint": r[0], "p256dh": r[1], "auth": r[2]} for r in rows]


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
