import json
import os
import pytest
from unittest.mock import patch

from servers import load_servers, get_server, Server

SAMPLE = [
    {"id": "prod", "name": "Production", "url": "https://bhnm.corp.com", "api_key": "abc", "pin": ""},
    {"id": "demo", "name": "Demo", "url": "https://bhnm.demo.com", "api_key": "xyz", "pin": "1234"},
]


def test_load_servers_returns_list(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        servers = load_servers()
    assert len(servers) == 2
    assert servers[0].id == "prod"
    assert servers[1].pin == "1234"


def test_get_server_found(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        s = get_server("demo")
    assert s is not None
    assert s.name == "Demo"


def test_get_server_not_found(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        s = get_server("nonexistent")
    assert s is None


def test_load_servers_file_missing():
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": "/nonexistent/servers.json"}):
        with pytest.raises(FileNotFoundError):
            load_servers()
