import fcntl
import json
import os
from dataclasses import dataclass, field, fields
from typing import Optional


@dataclass
class Server:
    id: str
    name: str
    url: str
    api_key: str
    pin: str = ""
    cache_enabled: bool = True  # mirrors config.CACHE_ENABLED_DEFAULT in the middleware (ruling 2026-09-03: ON)
    cache_refresh_seconds: int = 120
    # S1 change 1a: the webhook secrets this server accepts. A list, because
    # rotation needs an overlap window. Seeded with the current global secret, so
    # the QR handed out is the one handed out today. Mirrors
    # config.server_accepted_secrets() in the middleware (separate app).
    webhook_secrets: list[str] = field(default_factory=list)


def load_servers() -> list[Server]:
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    with open(path) as f:
        data = json.load(f)
    # Ignore keys this dataclass does not declare. Server(**s) used to raise on
    # any new servers.json key, which would have taken the whole portal down the
    # moment the middleware started writing one.
    known = {f.name for f in fields(Server)}
    return [Server(**{k: v for k, v in s.items() if k in known}) for s in data]


def get_server(server_id: str) -> Optional[Server]:
    for s in load_servers():
        if s.id == server_id:
            return s
    return None


def save_servers(servers: list[Server]) -> None:
    """Write servers list to servers.json with file locking."""
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    data = [
        # webhook_secrets MUST be written back. Omitting it here would erase every
        # server's accepted list on the next portal save, and every registered
        # device would stop being paged with nothing on screen to say so.
        {"id": s.id, "name": s.name, "url": s.url, "api_key": s.api_key, "pin": s.pin,
         "cache_enabled": s.cache_enabled, "cache_refresh_seconds": s.cache_refresh_seconds,
         "webhook_secrets": list(s.webhook_secrets)}
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
