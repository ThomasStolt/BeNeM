import os
import sqlite3
from dataclasses import dataclass

DB_PATH = os.environ.get("APNS_DB_PATH", "/data/bhnm_apns.db")


@dataclass
class DeviceToken:
    token: str
    device_name: str
    registered_at: str


def get_registered_devices() -> list[DeviceToken]:
    path = os.environ.get("APNS_DB_PATH", DB_PATH)
    if not os.path.exists(path):
        return []
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        rows = conn.execute(
            "SELECT token, device_name, registered_at FROM device_tokens ORDER BY registered_at DESC"
        ).fetchall()
        conn.close()
        return [DeviceToken(token=r[0], device_name=r[1], registered_at=r[2] or "") for r in rows]
    except Exception:
        return []
