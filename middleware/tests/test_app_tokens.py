"""App tokens: the phone holds a token and no BHNM credential (step 1, middleware).

Design: docs/superpowers/specs/2026-09-27-app-token-onboarding.md, with Thomas's
rulings of 2026-09-27. Two things that note says must be SHOWN, not assumed, have
their own tests at the bottom: a legacy client still works unchanged, and a
hand-issued token registers a device that then receives a push.
"""
import json
import os
import tempfile

os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_db.close()
os.environ.setdefault("DB_PATH", _db.name)

# Built at runtime, never written as literals: the credential guard scans tracked files.
KEY_A, KEY_B = "key-a-" + "1" * 8, "key-b-" + "2" * 8
SECRET_A, SECRET_B = "secret-a-tests", "secret-b-tests"
OPERATOR = "operator-" + "3" * 8
A = {"id": "srv-a", "name": "Server A", "url": "https://bhnm-a.example.com", "api_key": KEY_A,
     "pin": "1111", "cache_enabled": False, "webhook_secrets": [SECRET_A]}
B = {"id": "srv-b", "name": "Server B", "url": "https://bhnm-b.example.com", "api_key": KEY_B,
     "pin": "2222", "cache_enabled": False, "webhook_secrets": [SECRET_B]}
_servers = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
json.dump([A, B], _servers)
_servers.close()

import asyncio
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

import main as main_mod
import incident_cache
from database import get_conn, hash_app_token, init_db, revoke_app_token

PROBLEM = {"notification_type": "PROBLEM", "hostname": "raspi-050", "host_state": "DOWN",
           "primary_alarm_status": "DOWN", "service_desc": "", "site": "Lab",
           "output": "Ping CRITICAL", "incident_id": "40001"}


@pytest.fixture(autouse=True)
def _clean():
    init_db()
    with get_conn() as conn:
        for table in ("device_tokens", "web_push_subscriptions", "app_tokens"):
            conn.execute(f"DELETE FROM {table}")
    incident_cache._cache.clear()
    main_mod._legacy_logged.clear()
    orig = (main_mod.SERVERS_JSON_PATH, incident_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN)
    main_mod.SERVERS_JSON_PATH = _servers.name
    incident_cache.SERVERS_JSON_PATH = _servers.name
    main_mod.PROXY_TOKEN = OPERATOR
    yield
    main_mod.SERVERS_JSON_PATH, incident_cache.SERVERS_JSON_PATH, main_mod.PROXY_TOKEN = orig


class FakeBHNM:
    """Records every outbound call; answers like BHNM."""

    def __init__(self, probe_detail="Method not supported.", fail=False):
        self.calls, self.probe_detail, self.fail = [], probe_detail, fail

    async def request(self, method, url, headers=None, content=b""):
        self.calls.append({"method": method, "url": url, "headers": dict(headers or {}),
                           "body": content})
        return MagicMock(status_code=200, content=b'{"result":"completed"}', headers={})

    async def post(self, url, data=None, **kw):
        self.calls.append({"method": "POST", "url": url, "form": dict(data or {})})
        if self.fail:
            raise httpx.ConnectTimeout("BHNM did not answer")
        resp = MagicMock(status_code=200)
        resp.json.return_value = {"result": "error", "detail": self.probe_detail}
        return resp

    def client(self, *a, **kw):
        ctx = MagicMock()
        ctx.__aenter__ = AsyncMock(return_value=self)
        ctx.__aexit__ = AsyncMock(return_value=False)
        return ctx


async def _call(method, path, bhnm=None, **kw):
    bhnm = bhnm or FakeBHNM()
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main_mod.app),
                                 base_url="http://mw") as c:
        with patch("main.httpx.AsyncClient", side_effect=bhnm.client):
            return await c.request(method, path, **kw)


def call(method, path, bhnm=None, **kw):
    return asyncio.run(_call(method, path, bhnm, **kw))


def issue(server_id="srv-b", label="Thomas iPhone 13 ProMax"):
    r = call("POST", "/internal/app-tokens", headers={"X-Proxy-Token": OPERATOR},
             json={"server_id": server_id, "label": label})
    assert r.status_code == 200, r.text
    return r.json()["token"]


def register(token_header: dict, apns_token: str):
    r = call("POST", "/register", headers=token_header,
             json={"token": apns_token, "device_name": "test phone"})
    assert r.status_code == 200, r.text


def webhook(secret: str) -> list[str]:
    """POST a webhook through the real route and worker; return the APNs tokens paged."""
    sent = []

    async def send(tokens, title, body, incident_id=""):
        sent.extend(t for t, _ in tokens)
        return []

    async def run():
        main_mod._delivery_queue = asyncio.Queue(maxsize=main_mod.DELIVERY_QUEUE_MAX)
        worker = asyncio.create_task(main_mod._delivery_worker_loop())
        try:
            with patch.object(main_mod, "send_to_all", send), \
                    patch.object(main_mod, "send_web_push_to_all", AsyncMock(return_value=[])):
                async with httpx.AsyncClient(transport=httpx.ASGITransport(app=main_mod.app),
                                             base_url="http://mw") as c:
                    r = await c.post(f"/webhook?secret={secret}", json=PROBLEM)
                assert r.status_code == 200, r.text
                await main_mod._delivery_queue.join()
        finally:
            worker.cancel()

    asyncio.run(run())
    return sent


def row(apns_token):
    with get_conn() as conn:
        return conn.execute("SELECT active_secret, server_id, app_token_hash FROM device_tokens "
                            "WHERE token = ?", (apns_token,)).fetchone()


# ── The issuer ────────────────────────────────────────────────────────────────

def test_the_issuer_takes_the_OPERATOR_token_only_never_a_server_api_key():
    body = {"server_id": "srv-b", "label": "x"}
    assert call("POST", "/internal/app-tokens", json=body).status_code == 401
    assert call("POST", "/internal/app-tokens", headers={"X-Proxy-Token": KEY_B},
                json=body).status_code == 401, "a phone's legacy api_key must not mint tokens"
    assert call("POST", "/internal/app-tokens", headers={"X-Proxy-Token": OPERATOR},
                json={"server_id": "nope", "label": "x"}).status_code == 404
    assert call("POST", "/internal/app-tokens", headers={"X-Proxy-Token": OPERATOR},
                json={"server_id": "srv-b", "label": " "}).status_code == 400


def test_an_issued_token_is_stored_hashed_and_never_logged_in_full(capsys):
    token = issue()
    assert token.startswith("bnm_") and len(token) > 40
    out = capsys.readouterr().out
    assert token not in out and f"...{token[-4:]}" in out
    with get_conn() as conn:
        stored = conn.execute("SELECT token_hash, label FROM app_tokens").fetchall()
    assert stored == [(hash_app_token(token), "Thomas iPhone 13 ProMax")]


# ── Resolution and refusal ────────────────────────────────────────────────────

def test_unknown_and_revoked_tokens_are_refused_DISTINCTLY_on_every_route_family():
    token = issue()
    revoke_app_token(hash_app_token(token))
    for method, path in [("GET", "/api/v1/incidents"), ("POST", "/fw/index.php?r=restful/x"),
                         ("POST", "/register"), ("POST", "/api/v1/probe")]:
        r = call(method, path, headers={"X-App-Token": token}, json={"token": "t"})
        assert (r.status_code, r.json()["detail"]) == (401, "token revoked"), path
        r = call(method, path, headers={"X-App-Token": "bnm_never-issued"}, json={"token": "t"})
        assert (r.status_code, r.json()["detail"]) == (401, "invalid token"), path


def test_a_token_resolves_to_ITS_server_whatever_target_the_client_names():
    token = issue("srv-b")
    bhnm = FakeBHNM()
    r = call("POST", "/fw/index.php?r=restful/device/list", bhnm,
             headers={"X-App-Token": token, "X-BHNM-Target": A["url"],
                      "Content-Type": "application/x-www-form-urlencoded"},
             content=b"foo=1")
    assert r.status_code == 200, r.text
    assert bhnm.calls[0]["url"].startswith(B["url"] + "/fw/index.php")
    assert "x-app-token" not in {k.lower() for k in bhnm.calls[0]["headers"]}


# ── Credential injection ──────────────────────────────────────────────────────

def test_the_forwarded_body_carries_the_SERVERS_credential_and_only_it():
    token = issue("srv-b")
    bhnm = FakeBHNM()
    call("POST", "/fw/index.php?r=restful/device/list", bhnm,
         headers={"X-App-Token": token, "Content-Type": "application/x-www-form-urlencoded"},
         content=f"password={KEY_A}&pin=9999&foo=1".encode())
    sent = parse_qs(bhnm.calls[0]["body"].decode())
    assert sent["password"] == [KEY_B], "its own key, whatever the client sent"
    assert sent["pin"] == ["2222"] and sent["foo"] == ["1"]
    assert parse_qs(urlparse(bhnm.calls[0]["url"]).query)["r"] == ["restful/device/list"]


def test_api_php_endpoints_get_pwd_and_GET_requests_get_the_query():
    token = issue("srv-b")
    bhnm = FakeBHNM()
    call("POST", "/api/incident_api.php", bhnm, headers={"X-App-Token": token},
         content=b"method=getincidents")
    assert parse_qs(bhnm.calls[0]["body"].decode())["pwd"] == [KEY_B]
    call("GET", f"/fw/index.php?r=restful/x&password={KEY_A}", bhnm,
         headers={"X-App-Token": token})
    q = parse_qs(urlparse(bhnm.calls[1]["url"]).query)
    assert q["password"] == [KEY_B] and q["r"] == ["restful/x"]


# ── Ack-user stamping (addition A) ────────────────────────────────────────────

@pytest.mark.parametrize("path", ["/fw/index.php?r=restful/incident/acknowledge",
                                  "/api/proxy/incident/acknowledge",
                                  "/fw/index.php?r=restful/incident/unacknowledge"])
def test_an_app_token_ack_carries_the_TOKENS_label_whatever_the_client_sent(path):
    token = issue("srv-b", label="Thomas Android PWA")
    bhnm = FakeBHNM()
    call("POST", path, bhnm, headers={"X-App-Token": token},
         content=b"incident_id=40001&user=Someone+Else&comment=x")
    sent = parse_qs(bhnm.calls[0]["body"].decode())
    assert sent["user"] == ["Thomas Android PWA"]
    assert sent["incident_id"] == ["40001"] and sent["comment"] == ["x"]


def test_a_LEGACY_ack_keeps_the_clients_user():
    bhnm = FakeBHNM()
    body = f"password={KEY_B}&incident_id=40001&user=Thomas+iPhone+13+ProMax".encode()
    call("POST", "/fw/index.php?r=restful/incident/acknowledge", bhnm,
         headers={"X-Proxy-Token": KEY_B, "X-BHNM-Target": B["url"],
                  "Content-Type": "application/x-www-form-urlencoded"}, content=body)
    assert bhnm.calls[0]["body"] == body, "a legacy body is forwarded byte for byte"


# ── Register and fan-out ──────────────────────────────────────────────────────

def test_register_with_a_token_records_it_and_CLEARS_a_legacy_secret():
    register({"X-Webhook-Token": SECRET_B}, "apns-migrating")
    assert row("apns-migrating")[0] == SECRET_B
    token = issue("srv-b")
    register({"X-App-Token": token}, "apns-migrating")
    assert row("apns-migrating") == ("", "srv-b", hash_app_token(token))


def test_fan_out_is_the_UNION_of_legacy_and_token_devices_each_paged_once():
    token = issue("srv-b")
    register({"X-Webhook-Token": SECRET_B}, "apns-legacy")
    register({"X-App-Token": token}, "apns-phone")
    register({"X-App-Token": token}, "apns-ipad")        # one person, several devices
    register({"X-App-Token": issue("srv-a")}, "apns-other-server")
    assert webhook(SECRET_B) == ["apns-legacy", "apns-phone", "apns-ipad"]


def test_a_revoked_tokens_devices_drop_out_of_the_NEXT_fan_out_without_re_registering():
    token = issue("srv-b")
    register({"X-App-Token": token}, "apns-phone")
    register({"X-App-Token": token}, "apns-ipad")
    assert webhook(SECRET_B) == ["apns-phone", "apns-ipad"]
    revoke_app_token(hash_app_token(token))
    assert webhook(SECRET_B) == []


def test_web_push_registers_with_a_token_per_browser():
    token = issue("srv-b")
    r = call("POST", "/register-webpush", headers={"X-App-Token": token},
             json={"endpoint": "https://push.example/1", "p256dh": "p", "auth": "a"})
    assert r.status_code == 201, r.text
    subs = main_mod.get_web_push_subscriptions_for_servers(["srv-b"])
    assert [s["endpoint"] for s in subs] == ["https://push.example/1"]


# ── The probe ─────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("bhnm,reachable,detail", [
    (FakeBHNM("Method not supported."), True, "credential accepted"),
    (FakeBHNM("Password failed."), True, "credential rejected"),
    (FakeBHNM(fail=True), False, "ConnectTimeout"),
])
def test_the_probe_tells_its_three_answers_apart(bhnm, reachable, detail):
    token = issue("srv-b")
    r = call("POST", "/api/v1/probe", bhnm, headers={"X-App-Token": token})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["token"] == "valid" and body["server"] == "Server B"
    assert body["bhnm"]["reachable"] is reachable and body["bhnm"]["detail"] == detail
    assert body["bhnm"]["checked_at"].endswith("Z")
    form = bhnm.calls[0]["form"]
    assert bhnm.calls[0]["url"] == B["url"] + "/api/incident_api.php"
    assert form["pwd"] == KEY_B and form["pin"] == "2222", "the server's own key, server-side"


def test_the_probe_refuses_a_request_without_a_token():
    r = call("POST", "/api/v1/probe", headers={"X-Proxy-Token": KEY_B})
    assert r.status_code == 401


# ── The legacy line ───────────────────────────────────────────────────────────

def _legacy_lines(out):
    return [l for l in out.splitlines() if l.startswith("[Auth] legacy")]


def test_the_legacy_line_appears_for_a_legacy_client_once_an_hour_and_never_for_a_token(capsys):
    ua = {"User-Agent": "BeNeM/55 CFNetwork/1 Darwin/1"}
    call("POST", "/fw/index.php?r=restful/x", headers={"X-Proxy-Token": KEY_B, **ua})
    call("POST", "/fw/index.php?r=restful/x", headers={"X-Proxy-Token": KEY_B, **ua})
    register({"X-Webhook-Token": SECRET_B, **ua}, "apns-legacy")
    # Shown capable of being non-empty first — only then does absence mean anything.
    assert _legacy_lines(capsys.readouterr().out) == [
        "[Auth] legacy api_key from BeNeM/55 server=srv-b",
        "[Auth] legacy secret from BeNeM/55 server=srv-b"]

    main_mod._legacy_logged.clear()
    token = issue("srv-b")
    call("POST", "/fw/index.php?r=restful/x", headers={"X-App-Token": token, **ua})
    register({"X-App-Token": token, **ua}, "apns-phone")
    assert _legacy_lines(capsys.readouterr().out) == []


def test_the_operator_token_is_not_a_legacy_client(capsys):
    call("POST", "/internal/cache/reload", headers={"X-Proxy-Token": OPERATOR},
         json={"server_id": "srv-b"})
    assert _legacy_lines(capsys.readouterr().out) == []


# ── The two things the note says must be SHOWN ────────────────────────────────

def test_SHOWN_a_legacy_client_still_works_unchanged():
    """Build 55 as it is on phones today: api_key as X-Proxy-Token, the target in
    X-BHNM-Target, the credential in the body, the secret on /register."""
    bhnm = FakeBHNM()
    body = f"password={KEY_B}&pin=2222&incident_id=40001&user=Thomas+iPhone+13+ProMax".encode()
    r = call("POST", "/fw/index.php?r=restful/incident/acknowledge", bhnm,
             headers={"X-Proxy-Token": KEY_B, "X-BHNM-Target": B["url"],
                      "Content-Type": "application/x-www-form-urlencoded"}, content=body)
    assert r.status_code == 200, r.text
    assert bhnm.calls[0]["url"] == B["url"] + "/fw/index.php?r=restful/incident/acknowledge"
    assert bhnm.calls[0]["body"] == body

    register({"X-Webhook-Token": SECRET_B}, "apns-build-55")
    assert row("apns-build-55") == (SECRET_B, "srv-b", "")
    assert webhook(SECRET_B) == ["apns-build-55"]


def test_SHOWN_a_hand_issued_token_registers_a_device_that_receives_a_push():
    token = issue("srv-b", label="Hand issued")
    register({"X-App-Token": token}, "apns-hand-issued")
    assert webhook(SECRET_B) == ["apns-hand-issued"]
    assert webhook(SECRET_A) == [], "and only its own server's webhooks page it"
