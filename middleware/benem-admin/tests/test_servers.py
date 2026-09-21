import json
import os
import pytest
from unittest.mock import patch

from servers import load_servers, get_server, save_servers, Server

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


# ── S1 change 1a — per-server accepted secrets ───────────────────────────────

def test_webhook_secrets_survive_a_round_trip(tmp_path, monkeypatch):
    """The paging-killer this guards: save_servers used to rebuild each entry from
    a fixed key list, so a portal save would have erased every accepted list and
    silently stopped paging every registered device."""
    path = tmp_path / "servers.json"
    path.write_text('[]')
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))

    save_servers([Server(id="lab", name="Lab", url="https://lab", api_key="k",
                         webhook_secrets=["seeded-global", "new-per-server"])])
    reloaded = load_servers()
    assert reloaded[0].webhook_secrets == ["seeded-global", "new-per-server"]


def test_load_ignores_keys_the_dataclass_does_not_declare(tmp_path, monkeypatch):
    """Server(**s) used to raise on any unknown key, which would have taken the
    portal down the moment servers.json grew a field."""
    path = tmp_path / "servers.json"
    path.write_text('[{"id":"lab","name":"Lab","url":"https://lab","api_key":"k",'
                    '"some_future_field":"whatever"}]')
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))
    assert load_servers()[0].id == "lab"


def test_a_server_without_a_list_defaults_to_empty(tmp_path, monkeypatch):
    path = tmp_path / "servers.json"
    path.write_text('[{"id":"lab","name":"Lab","url":"https://lab","api_key":"k"}]')
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))
    assert load_servers()[0].webhook_secrets == []


def test_retain_closed_survives_a_round_trip(tmp_path, monkeypatch):
    """Same trap as webhook_secrets, one field along: the flag is set by hand for
    middleware 2.20.1 and nothing in the portal edits it, so an omission here
    would turn CLSD retention back off on the next unrelated portal save — with
    nothing on screen to say so."""
    path = tmp_path / "servers.json"
    path.write_text('[]')
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))

    save_servers([Server(id="lab", name="Lab", url="https://lab", api_key="k",
                         retain_closed=True)])
    assert load_servers()[0].retain_closed is True


def test_retain_closed_defaults_to_OFF(tmp_path, monkeypatch):
    path = tmp_path / "servers.json"
    path.write_text('[{"id":"lab","name":"Lab","url":"https://lab","api_key":"k"}]')
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))
    assert load_servers()[0].retain_closed is False
