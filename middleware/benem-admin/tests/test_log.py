import json
import os
from unittest.mock import patch

import pytest

from log import append_entry, read_entries, count_entries


def test_append_and_read(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("Thomas", "prod", "Production", "benem://configure?p=abc123longerthanforty")
        entries = read_entries()
    assert len(entries) == 1
    e = entries[0]
    assert e["user"] == "Thomas"
    assert e["server_id"] == "prod"
    assert e["link_prefix"].startswith("benem://configure?p=")
    assert len(e["link_prefix"]) <= 40


def test_read_entries_empty_when_no_file(tmp_path):
    log_path = str(tmp_path / "missing.jsonl")
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        entries = read_entries()
    assert entries == []


def test_read_entries_filtered_by_server(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("A", "prod", "Production", "benem://x")
        append_entry("B", "demo", "Demo", "benem://y")
        prod_only = read_entries(server_id="prod")
        all_entries = read_entries()
    assert len(prod_only) == 1
    assert prod_only[0]["server_id"] == "prod"
    assert len(all_entries) == 2


def test_read_entries_newest_first(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("first", "prod", "Production", "benem://a")
        append_entry("second", "prod", "Production", "benem://b")
        entries = read_entries()
    assert entries[0]["user"] == "second"


def test_count_entries(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("A", "prod", "Production", "benem://x")
        append_entry("B", "demo", "Demo", "benem://y")
        assert count_entries() == 2
        assert count_entries(server_id="prod") == 1
