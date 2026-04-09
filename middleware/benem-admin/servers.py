import fcntl
import json
import os
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
    """Write servers list to servers.json with file locking."""
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    data = [
        {"id": s.id, "name": s.name, "url": s.url, "api_key": s.api_key, "pin": s.pin}
        for s in servers
    ]
    with open(path, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            f.seek(0)
            json.dump(data, f, indent=2)
            f.write("\n")
            f.truncate()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
