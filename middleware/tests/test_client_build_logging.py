"""The client build number reaches the log on a path every client takes.

**This test exists because the gate it serves was measured and withdrawn.**
The M1-drop gate said *"`BeNeM/53` disappearing and only `BeNeM/54`+ remaining
is a measurement; a date is not"* — and on 2026-09-22 (handoff (f)22) the log it
named turned out to hold user-agents on exactly one path,
`[Proxy] REFUSED target not in servers.json`. **A refusal path.** A fleet of
working clients produces zero lines there, so the absence proved nothing: the
whole persisted log held nine such lines, the last from build 46, while build 54
had registered successfully the night before and appeared nowhere at all.

That is the repository's own doctrine failing on the gate for a breaking change
— an empty result that was never capable of being non-empty for the question
being asked. So the assertions below are in two halves, deliberately:

1. a request carrying `BeNeM/54` produces the line, and
2. **the same route, called without it, produces a DIFFERENT line** — which is
   what makes a later absence of `BeNeM/53` mean something rather than nothing.
"""
import os
import tempfile

_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
os.environ["DB_PATH"] = _tmp.name
_tmp.close()
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "dGVzdA==")
os.environ.setdefault("VAPID_PRIVATE_KEY", "")
os.environ.setdefault("VAPID_PUBLIC_KEY", "test-vapid-public-key")
os.environ.setdefault("VAPID_CONTACT_EMAIL", "mailto:test@test.com")

import json

import pytest
from fastapi.testclient import TestClient

from database import init_db
from main import app

client = TestClient(app)
SECRET = "a" * 64
API_KEY = "secret-key-123"

# The incidents route logs AFTER _verify_proxy_token, so the test has to present
# a real one. That ordering is the point of
# test_an_unauthenticated_caller_cannot_write_lines_into_the_log below.
INCIDENT_HDRS = {"X-Proxy-Token": API_KEY, "X-BHNM-Target": "https://bhnm.example.invalid"}

# The real thing, from the 13 Pro Max. URLSession sends no explicit User-Agent;
# this is its default, built from the bundle name and CFBundleVersion.
IOS_UA = "BeNeM/54 CFNetwork/3826.500.111 Darwin/24.6.0"


@pytest.fixture(autouse=True)
def _db():
    init_db()


@pytest.fixture(autouse=True)
def _servers(tmp_path):
    servers_file = tmp_path / "servers.json"
    servers_file.write_text(json.dumps([
        {"id": "lab", "name": "Lab", "url": "https://bhnm.example.invalid",
         "api_key": API_KEY},
    ]))
    import main as main_mod
    original_path, original_token = main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN
    main_mod.SERVERS_JSON_PATH = str(servers_file)
    main_mod.PROXY_TOKEN = ""
    yield
    main_mod.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = original_path, original_token


def _lines(capsys, prefix="[Client]"):
    return [ln for ln in capsys.readouterr().out.splitlines() if ln.startswith(prefix)]


def test_register_with_BeNeM_54_logs_the_build(capsys):
    r = client.post("/register",
                    json={"token": "ab" * 32, "device_name": "iPhone", "environment": "sandbox"},
                    headers={"X-Webhook-Token": SECRET, "User-Agent": IOS_UA})
    assert r.status_code == 200, r.text
    assert _lines(capsys) == ["[Client] BeNeM/54 on /register"]


def test_incidents_with_BeNeM_54_logs_the_build(capsys):
    # The cache is cold and the upstream is unresolvable, so this ends in a 502.
    # Beside the point: what matters is that the line appears on the route every
    # list load takes, which is why this route is here at all.
    client.get("/api/v1/incidents", headers={**INCIDENT_HDRS, "User-Agent": IOS_UA})
    assert _lines(capsys) == ["[Client] BeNeM/54 on /api/v1/incidents"]


def test_a_client_without_BeNeM_in_its_user_agent_logs_a_DIFFERENT_line(capsys):
    """**The half that makes a later absence mean something.** If every caller
    produced the same line, "no BeNeM/53 today" would be indistinguishable from
    "nothing called today" — which is precisely the defect (f)22 withdrew."""
    client.get("/api/v1/incidents",
               headers={**INCIDENT_HDRS,
                        "User-Agent": "Mozilla/5.0 (Linux; Android 14) Chrome/130"})
    assert _lines(capsys) == ["[Client] not-BeNeM on /api/v1/incidents"]


def test_the_line_carries_the_BUILD_and_NOTHING_else(capsys):
    """Not the raw header, and not a token.

    The CFNetwork and Darwin versions say which OS the phone runs, and the
    X-Webhook-Token / X-Proxy-Token headers are secrets. This service already
    rules that a *prefix* of a secret is a piece of the secret, so the line is
    checked against the whole value and against every fragment of it.
    """
    client.post("/register",
                json={"token": "cd" * 32, "device_name": "iPhone", "environment": "sandbox"},
                headers={"X-Webhook-Token": SECRET, "X-Proxy-Token": "p" * 40,
                         "User-Agent": IOS_UA})
    line = _lines(capsys)[0]
    assert line == "[Client] BeNeM/54 on /register"
    assert "CFNetwork" not in line and "Darwin" not in line
    for secret in (SECRET, "p" * 40):
        assert secret not in line
        assert secret[:8] not in line, "a prefix of a secret is a piece of the secret"


def test_an_unauthenticated_caller_cannot_write_lines_into_the_log(capsys):
    """The `/api/v1/incidents` line is emitted AFTER the proxy-token check, so a
    stranger cannot fill the log by asking. `/register` is deliberately the other
    way round in effect — it already refuses without X-Webhook-Token, before the
    handler body runs at all."""
    r = client.get("/api/v1/incidents", headers={"X-Proxy-Token": "wrong",
                                                 "User-Agent": IOS_UA})
    assert r.status_code == 401
    assert _lines(capsys) == []

    r = client.post("/register", json={"token": "ef" * 32, "device_name": "iPhone"},
                    headers={"User-Agent": IOS_UA})   # no X-Webhook-Token
    assert r.status_code == 400
    assert _lines(capsys) == []
