import json
import os
from datetime import datetime, timezone
from typing import Optional

LOG_PATH = os.environ.get("LOG_PATH", "/app/log/admin.jsonl")


def append_entry(user: str, server_id: str, server_name: str, link: str) -> None:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "user": user,
        "server_id": server_id,
        "server_name": server_name,
        "link_prefix": link[:40],
    }
    with open(path, "a") as f:
        f.write(json.dumps(entry) + "\n")


def read_entries(server_id: Optional[str] = None, page: int = 1, per_page: int = 50) -> list[dict]:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    if not os.path.exists(path):
        return []
    entries = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                if server_id is None or e.get("server_id") == server_id:
                    entries.append(e)
            except json.JSONDecodeError:
                pass
    entries.reverse()  # newest first
    start = (page - 1) * per_page
    return entries[start : start + per_page]


def count_entries(server_id: Optional[str] = None) -> int:
    return len(read_entries(server_id=server_id, page=1, per_page=999999))
