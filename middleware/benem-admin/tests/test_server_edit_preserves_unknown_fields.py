"""A portal save must not erase the fields the portal does not show.

**This was found on 2026-09-22 while trying to turn `retain_closed` on, and it
is worse than the flag it was found under.**

`servers.py` gets this right twice over: `save_servers` writes `webhook_secrets`
and `retain_closed` back explicitly, each with a comment saying why, and
`load_servers` already ignores keys the dataclass does not declare so the portal
survives the middleware inventing new ones. `test_servers.py` proves the
round-trip through those two functions.

**The HTTP handlers never reach them.** `server_edit` and `server_add` built a
FRESH `Server(...)` out of the form fields alone, so the defaults took over for
everything the form does not carry:

    servers[idx] = Server(id=id, name=name, url=url, api_key=api_key, pin=pin,
                          cache_enabled=cache_on, cache_refresh_seconds=refresh)
                          # webhook_secrets -> []      retain_closed -> False

Renaming a server in the portal therefore wiped that server's accepted webhook
secrets — S1 change 1a's whole fan-out — and every registered device on it would
have stopped being paged, with nothing on screen to say so. `retain_closed` went
off in the same stroke. The round-trip test passed the entire time, because it
tested the layer underneath the one with the bug.

So this tests the **handler**, not `save_servers`. It is the generalisation as
well as the specific fix: the assertion is that a field the form does not carry
survives an edit, whatever that field is — including one added after this was
written, which is the case `load_servers` was already hardened for.
"""
import json
import os

import pyotp
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

SECRET = pyotp.random_base32()
os.environ.setdefault("TOTP_SECRET", SECRET)
os.environ.setdefault("SESSION_SECRET", "test-session-secret-32-chars-min!")
os.environ.setdefault("BENEM_SECRET_KEY", "a" * 64)
os.environ.setdefault("SERVERS_JSON_PATH", "/nonexistent/servers.json")

from main import app  # noqa: E402

client = TestClient(app, follow_redirects=False)

SECRET_A = "a" * 64
SECRET_B = "b" * 64


@pytest.fixture
def servers_file(tmp_path, monkeypatch):
    """One server carrying everything the edit form does NOT show."""
    path = tmp_path / "servers.json"
    path.write_text(json.dumps([{
        "id": "ThomasLabServer",
        "name": "Thomas' Lab Server",
        "url": "https://bhnm.example.invalid",
        "api_key": "key-123",
        "pin": "",
        "cache_enabled": True,
        "cache_refresh_seconds": 120,
        "webhook_secrets": [SECRET_A, SECRET_B],
        "retain_closed": True,
    }], indent=2) + "\n")
    monkeypatch.setenv("SERVERS_JSON_PATH", str(path))
    return path


@pytest.fixture(scope="module")
def session():
    # Module-scoped: /admin/login is rate-limited to 5 per minute per client, and
    # logging in once per test blew through it when the whole suite ran together.
    code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        resp = client.post("/admin/login", data={"code": code})
    assert resp.status_code == 302
    cookie = resp.cookies.get("benem_admin_session")
    assert cookie is not None
    return {"benem_admin_session": cookie}


def _read(path):
    return json.loads(path.read_text())[0]


def test_renaming_a_server_keeps_its_webhook_secrets_and_retain_closed(servers_file, session):
    """The measured defect, at the layer it actually lives in.

    Only `name` changes. Everything the form does not carry must come back
    exactly as it went in.
    """
    before = _read(servers_file)

    resp = client.post("/admin/settings/servers/edit", cookies=session, data={
        "original_id": "ThomasLabServer",
        "id": "ThomasLabServer",
        "name": "Thomas Lab Server RENAMED",
        "url": "https://bhnm.example.invalid",
        "api_key": "key-123",
        "pin": "",
        "cache_enabled": "1",
        "cache_refresh_seconds": "120",
    })
    assert resp.status_code == 200, resp.text

    after = _read(servers_file)
    assert after["name"] == "Thomas Lab Server RENAMED", "the form field DID change"
    assert after["webhook_secrets"] == [SECRET_A, SECRET_B], (
        "an edit erased the accepted webhook secrets — every device on this "
        "server stops being paged, with nothing on screen to say so"
    )
    assert after["retain_closed"] is True, "an edit silently turned CLSD retention off"
    # And nothing else moved either.
    for key in ("id", "url", "api_key", "pin", "cache_enabled", "cache_refresh_seconds"):
        assert after[key] == before[key], f"{key} changed on a name-only edit"


def test_a_field_the_form_does_not_carry_survives_whatever_it_is(servers_file, session):
    """The general case, not just today's two fields.

    `load_servers` already drops keys the dataclass does not declare, so a key
    the middleware invents tomorrow is not the concern here — a declared field
    the FORM does not carry is. This asserts the handler preserves every such
    field by construction rather than by a list somebody has to remember to
    extend.
    """
    from servers import Server, load_servers

    form_fields = {"id", "name", "url", "api_key", "pin",
                   "cache_enabled", "cache_refresh_seconds"}
    from dataclasses import fields as dc_fields
    non_form = {f.name for f in dc_fields(Server)} - form_fields
    assert non_form, "if the form covers every field this test is meaningless"

    original = {f: getattr(load_servers()[0], f) for f in non_form}

    resp = client.post("/admin/settings/servers/edit", cookies=session, data={
        "original_id": "ThomasLabServer",
        "id": "ThomasLabServer",
        "name": "Renamed Again",
        "url": "https://bhnm.example.invalid",
        "api_key": "key-123",
        "pin": "",
        "cache_enabled": "1",
        "cache_refresh_seconds": "120",
    })
    assert resp.status_code == 200, resp.text

    after = load_servers()[0]
    for f in sorted(non_form):
        assert getattr(after, f) == original[f], f"{f} did not survive the edit"


def test_changing_the_id_carries_the_fields_to_the_new_id(servers_file, session):
    """The id is editable, so the preserved fields have to follow it.

    A lookup keyed on the NEW id would find nothing and quietly fall back to the
    defaults — the same defect wearing the rename as a disguise.
    """
    resp = client.post("/admin/settings/servers/edit", cookies=session, data={
        "original_id": "ThomasLabServer",
        "id": "ThomasLabServerV2",
        "name": "Thomas' Lab Server",
        "url": "https://bhnm.example.invalid",
        "api_key": "key-123",
        "pin": "",
        "cache_enabled": "1",
        "cache_refresh_seconds": "120",
    })
    assert resp.status_code == 200, resp.text

    after = _read(servers_file)
    assert after["id"] == "ThomasLabServerV2"
    assert after["webhook_secrets"] == [SECRET_A, SECRET_B]
    assert after["retain_closed"] is True


def test_a_newly_added_server_still_gets_the_safe_defaults(servers_file, session):
    """`server_add` has no existing record to preserve, and must not acquire one.

    It shares the defect's shape — a fresh `Server(...)` from form fields — but
    for an ADD that is correct. The point of asserting it is that a fix to
    `server_edit` must not be copy-pasted into `server_add` and hand a brand-new
    server another server's secrets.
    """
    resp = client.post("/admin/settings/servers/add", cookies=session, data={
        "id": "BrandNew",
        "name": "Brand New",
        "url": "https://new.example.invalid",
        "api_key": "key-999",
        "pin": "",
        "cache_enabled": "1",
        "cache_refresh_seconds": "120",
    })
    assert resp.status_code == 200, resp.text

    rows = {s["id"]: s for s in json.loads(servers_file.read_text())}
    assert rows["BrandNew"]["webhook_secrets"] == [], "a new server starts with none"
    assert rows["BrandNew"]["retain_closed"] is False, "and with retention OFF"
    assert rows["ThomasLabServer"]["webhook_secrets"] == [SECRET_A, SECRET_B], (
        "adding a server must not disturb an existing one"
    )
