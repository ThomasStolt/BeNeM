import sqlite3
from contextlib import contextmanager

DB_PATH = "bhnm_apns.db"

def init_db():
    with get_conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS device_tokens (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token TEXT UNIQUE NOT NULL,
                device_name TEXT DEFAULT 'unknown',
                registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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

def save_token(token: str, device_name: str = "unknown"):
    with get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO device_tokens (token, device_name) VALUES (?, ?)",
            (token, device_name)
        )

def get_all_tokens() -> list[str]:
    with get_conn() as conn:
        rows = conn.execute("SELECT token FROM device_tokens").fetchall()
    return [r[0] for r in rows]

def delete_token(token: str):
    """Call this when APNs returns 410 Gone (token no longer valid)."""
    with get_conn() as conn:
        conn.execute("DELETE FROM device_tokens WHERE token = ?", (token,))
