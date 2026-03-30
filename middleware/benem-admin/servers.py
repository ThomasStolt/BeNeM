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
