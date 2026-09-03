"""cache_enabled default: ON, decided in exactly one place (config)."""
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_cache_default.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_cache_default.json")

import json

import incident_cache
import tactical_cache
import threshold_cache
from config import server_cache_enabled


def test_absent_key_means_on_and_explicit_false_opts_out():
    assert server_cache_enabled({"id": "a"}) is True
    assert server_cache_enabled({"id": "a", "cache_enabled": False}) is False
    assert server_cache_enabled({"id": "a", "cache_enabled": True}) is True


def test_every_crawler_reads_the_same_default(tmp_path, monkeypatch):
    f = tmp_path / "servers.json"
    f.write_text(json.dumps([
        {"id": "nokey", "url": "http://a", "api_key": "k"},
        {"id": "off", "url": "http://b", "api_key": "k", "cache_enabled": False},
        {"id": "on", "url": "http://c", "api_key": "k", "cache_enabled": True},
    ]))
    # maintenance_cache imports threshold_cache._load_enabled_servers, so the
    # three modules below cover all four crawlers.
    for mod in (threshold_cache, incident_cache, tactical_cache):
        monkeypatch.setattr(mod, "SERVERS_JSON_PATH", str(f))
        assert sorted(s["id"] for s in mod._load_enabled_servers()) == ["nokey", "on"]
