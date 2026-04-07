import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Optional

LOG_PATH = os.environ.get("LOG_PATH", "/app/log/admin.jsonl")


def append_entry(user: str, server_id: str, server_name: str, link: str) -> None:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Store a truncated prefix and hash — never persist the full encrypted link
    link_hash = hashlib.sha256(link.encode()).hexdigest()[:16]
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "user": user,
        "server_id": server_id,
        "server_name": server_name,
        "link_prefix": link[:40],
        "link_hash": link_hash,
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
    path = os.environ.get("LOG_PATH", LOG_PATH)
    if not os.path.exists(path):
        return 0
    count = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if server_id is None:
                count += 1
            else:
                try:
                    if json.loads(line).get("server_id") == server_id:
                        count += 1
                except json.JSONDecodeError:
                    pass
    return count


def get_entry(ts: str) -> Optional[dict]:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get("ts") == ts:
                    return entry
            except json.JSONDecodeError:
                pass
    return None


def _read_all_lines() -> list[str]:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [l for l in f if l.strip()]


def _write_all_lines(lines: list[str]) -> None:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    with open(path, "w") as f:
        for line in lines:
            if not line.endswith("\n"):
                line += "\n"
            f.write(line)


def delete_entry(ts: str) -> bool:
    lines = _read_all_lines()
    new_lines = []
    removed = False
    for line in lines:
        try:
            entry = json.loads(line.strip())
            if not removed and entry.get("ts") == ts:
                removed = True
                continue
        except json.JSONDecodeError:
            pass
        new_lines.append(line)
    if removed:
        _write_all_lines(new_lines)
    return removed


def update_entry_user(ts: str, new_user: str) -> bool:
    lines = _read_all_lines()
    updated = False
    for i, line in enumerate(lines):
        try:
            entry = json.loads(line.strip())
            if not updated and entry.get("ts") == ts:
                entry["user"] = new_user
                lines[i] = json.dumps(entry) + "\n"
                updated = True
        except json.JSONDecodeError:
            pass
    if updated:
        _write_all_lines(lines)
    return updated
