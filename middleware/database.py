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

        conn.execute("""
            CREATE TABLE IF NOT EXISTS web_push_subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                endpoint TEXT UNIQUE NOT NULL,
                p256dh TEXT NOT NULL,
                auth TEXT NOT NULL,
                webhook_secret TEXT NOT NULL DEFAULT '',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()

def save_token(token: str, device_name: str = "unknown", active_secret: str = "", apns_environment: str = "production"):
    with get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO device_tokens (token, device_name, active_secret, apns_environment) VALUES (?, ?, ?, ?)",
            (token, device_name, active_secret, apns_environment)
        )

def get_tokens_for_secret(secret: str) -> list[tuple[str, str]]:
    """Return all (token, apns_environment) pairs registered for the given webhook secret."""
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT token, apns_environment FROM device_tokens WHERE active_secret = ?",
            (secret,)
        ).fetchall()
    return [(r[0], r[1]) for r in rows]

def get_all_tokens() -> list[str]:
    """Return all registered device tokens regardless of secret (used by /health)."""
    with get_conn() as conn:
        rows = conn.execute("SELECT token FROM device_tokens").fetchall()
    return [r[0] for r in rows]

def delete_token(token: str):
    """Call this when APNs returns 410 Gone (token no longer valid)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))


def save_web_push_subscription(endpoint: str, p256dh: str, auth: str, webhook_secret: str = ""):
    with get_conn() as conn:
        conn.execute(
            """INSERT INTO web_push_subscriptions (endpoint, p256dh, auth, webhook_secret)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(endpoint) DO UPDATE SET p256dh=?, auth=?, webhook_secret=?""",
            (endpoint, p256dh, auth, webhook_secret, p256dh, auth, webhook_secret),
        )


def get_web_push_subscriptions_for_secret(secret: str) -> list[dict]:
    """Return all Web Push subscriptions registered for the given webhook secret."""
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT endpoint, p256dh, auth FROM web_push_subscriptions WHERE webhook_secret = ?",
            (secret,),
        ).fetchall()
    return [{"endpoint": r[0], "p256dh": r[1], "auth": r[2]} for r in rows]


def delete_web_push_subscription(endpoint: str):
    """Remove a Web Push subscription (called when push service returns 410 Gone)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM web_push_subscriptions WHERE endpoint = ?", (endpoint,))
