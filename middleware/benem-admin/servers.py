import fcntl
import json
import os
import tempfile
from dataclasses import dataclass
from typing import Optional


@dataclass
class Server:
    id: str
    name: str
    url: str
    api_key: str
    pin: str = ""


def load_servers() -> list[Server]:
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    with open(path) as f:
        data = json.load(f)
    return [Server(**s) for s in data]


def get_server(server_id: str) -> Optional[Server]:
    for s in load_servers():
        if s.id == server_id:
            return s
    return None


def save_servers(servers: list[Server]) -> None:
    """Atomically write servers list to servers.json with file locking."""
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    data = [
        {"id": s.id, "name": s.name, "url": s.url, "api_key": s.api_key, "pin": s.pin}
        for s in servers
    ]
    dir_path = os.path.dirname(path) or "."
    fd = os.open(path, os.O_RDWR | os.O_CREAT)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=dir_path, suffix=".tmp", delete=False
        ) as tmp:
            json.dump(data, tmp, indent=2)
            tmp.write("\n")
            tmp_path = tmp.name
        os.rename(tmp_path, path)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
