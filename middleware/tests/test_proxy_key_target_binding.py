"""A server's api_key may target ONLY that server (2.17.0).

The defect these tests exist for
--------------------------------
2.16.0 made servers.json the allowlist, which stopped an api_key being a relay to
the whole internet. It did NOT bind a key to a target: `_verify_proxy_token`
accepts any api_key and returns nothing about whose it is, the proxy took its
target straight from X-BHNM-Target, and `_validate_proxy_target` was a membership
test against the WHOLE allowlist. So key A + X-BHNM-Target B was relayed to B.

The sharp end was not the relay. `main.py`'s cold-cache fall-throughs read
`target_base` from the header while sending `server_cfg["api_key"]` — the CALLER's
credential. Key A with a wrong target made the middleware POST `pwd=<A's key>` to
B. The trigger is an ordinary misconfigured client, not an attacker: it is the
`vpn.hurrikap.org` shape of 2026-09-17, which leaked nothing only because that host
did not answer. Configured hosts answer.

See docs/evidence/2026-09-17-cross-server-key-reachability-defect.md.
"""
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_proxy_binding.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers_binding.json")

import json
import socket
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main as main_mod

KEY_A = "key-for-server-a"
KEY_B = "key-for-server-b"
URL_A = "https://a.example.com"
URL_B = "https://b.example.com:9443"

SERVERS = [
    {"id": "A", "name": "Server A", "url": URL_A, "api_key": KEY_A},
    {"id": "B", "name": "Server B", "url": URL_B, "api_key": KEY_B},
]

REFUSAL = "Proxy target is not a configured server."


@pytest.fixture(autouse=True)
def servers_file(tmp_path):
    f = tmp_path / "servers.json"
    f.write_text(json.dumps(SERVERS))
    original = main_mod.SERVERS_JSON_PATH
    main_mod.SERVERS_JSON_PATH = str(f)
    yield f
    main_mod.SERVERS_JSON_PATH = original


@pytest.fixture(autouse=True)
def no_operator_token(monkeypatch):
    """Default: no PROXY_TOKEN. The operator tests set it explicitly."""
    monkeypatch.setattr(main_mod, "PROXY_TOKEN", "")


@pytest.fixture
def no_dns(monkeypatch):
    """A refused target must never reach DNS — carried over from the allowlist tests."""
    def boom(*a, **kw):
        raise AssertionError(f"getaddrinfo was called with {a!r} — a refused target reached DNS")
    monkeypatch.setattr(socket, "getaddrinfo", boom)


def validate(url, token, ua="TestAgent/1.0"):
    class _Req:
        headers = {"user-agent": ua, "X-Proxy-Token": token}
    return main_mod._validate_proxy_target(url, _Req())


# ── THE TEST THAT WOULD HAVE CAUGHT THIS DEFECT ───────────────────────────────
# Named, per the ruling. Everything else here is coverage around it.

def test_key_a_may_not_target_server_b(no_dns):
    """**THE REGRESSION TEST.** Both servers are configured, so 2.16.0's allowlist
    passes both — this is exactly the case the allowlist cannot see. A key must
    reach its own server and no other."""
    with pytest.raises(HTTPException) as e:
        validate(URL_B, KEY_A)
    assert e.value.status_code == 403
    assert e.value.detail == REFUSAL


def test_key_a_may_target_server_a(no_dns):
    """The binding must not break the ordinary case."""
    assert validate(URL_A, KEY_A) is None
    assert validate(URL_B, KEY_B) is None


def test_binding_holds_for_equivalent_spellings(no_dns):
    """Normalisation applies to the caller's own URL too, or a trailing slash or a
    default port would refuse a client its own server."""
    for spelling in (URL_A, URL_A + "/", "https://A.EXAMPLE.COM", "https://a.example.com:443"):
        assert validate(spelling, KEY_A) is None, spelling


def test_unmatched_token_fails_closed(no_dns):
    """No PROXY_TOKEN set and a token matching no server: refused, not waved through.

    `_verify_proxy_token` should have rejected this first — but the validator must
    not depend on a check in another function to be safe.
    """
    for token in ("", "not-a-configured-key"):
        with pytest.raises(HTTPException) as e:
            validate(URL_A, token)
        assert e.value.status_code == 403


def test_validator_without_a_request_is_refused(no_dns):
    """No request means no token means no binding can be proved. Fail closed."""
    with pytest.raises(HTTPException) as e:
        main_mod._validate_proxy_target(URL_A, None)
    assert e.value.status_code == 403


def test_mismatch_logs_target_and_user_agent(capsys, no_dns):
    with pytest.raises(HTTPException):
        validate(URL_B, KEY_A, ua="BeNeM/36 CFNetwork/3860.700.1 Darwin/25.6.0")
    out = capsys.readouterr().out
    assert "REFUSED" in out
    assert "not owned by this key" in out, "the log must say WHY, or it cannot be triaged"
    assert "b.example.com" in out, "the log must carry the full target"
    assert "BeNeM/36 CFNetwork/3860.700.1 Darwin/25.6.0" in out, "the log must name the client"
    assert KEY_A not in out and KEY_B not in out, "a log line must never carry a key"


def test_mismatch_is_indistinguishable_from_unconfigured_in_the_RESPONSE(no_dns):
    """A caller must not be able to tell 'not yours' from 'not configured', or the
    endpoint becomes a way to enumerate the other configured servers. The log tells
    them apart; the response must not."""
    with pytest.raises(HTTPException) as mismatch:
        validate(URL_B, KEY_A)
    with pytest.raises(HTTPException) as unconfigured:
        validate("https://vpn.hurrikap.org:8888", KEY_A)
    assert mismatch.value.status_code == unconfigured.value.status_code == 403
    assert mismatch.value.detail == unconfigured.value.detail == REFUSAL
    assert "b.example.com" not in str(mismatch.value.detail)


# ── The operator token ────────────────────────────────────────────────────────

def test_operator_token_may_target_any_configured_server(monkeypatch, no_dns):
    monkeypatch.setattr(main_mod, "PROXY_TOKEN", "operator-" + "x" * 56)
    assert validate(URL_A, main_mod.PROXY_TOKEN) is None
    assert validate(URL_B, main_mod.PROXY_TOKEN) is None


def test_operator_token_is_still_bound_by_the_allowlist(monkeypatch, no_dns):
    """Multi-server, not any-server. 2.16.0 still applies to the operator."""
    monkeypatch.setattr(main_mod, "PROXY_TOKEN", "operator-" + "x" * 56)
    with pytest.raises(HTTPException) as e:
        validate("https://vpn.hurrikap.org:8888", main_mod.PROXY_TOKEN)
    assert e.value.status_code == 403


def test_operator_token_selection_is_logged(capsys, monkeypatch, no_dns):
    """Operator cross-server use must be visible, not indistinguishable from a client."""
    monkeypatch.setattr(main_mod, "PROXY_TOKEN", "operator-" + "x" * 56)
    validate(URL_B, main_mod.PROXY_TOKEN, ua="curl/8.7.1")
    out = capsys.readouterr().out
    assert "OPERATOR TOKEN" in out
    assert "b.example.com" in out
    assert "curl/8.7.1" in out
    assert main_mod.PROXY_TOKEN not in out, "the log must never carry the operator token"


# ── Duplicate api_keys ────────────────────────────────────────────────────────

def test_duplicate_api_keys_are_detected(servers_file, no_dns):
    """Under binding, a shared key binds by FILE ORDER — one operator's request
    routed to another's server and called correct. Refused, not warned."""
    servers_file.write_text(json.dumps([
        {"id": "A", "name": "A", "url": URL_A, "api_key": KEY_A},
        {"id": "B", "name": "B", "url": URL_B, "api_key": KEY_A},
    ]))
    with pytest.raises(main_mod._AmbiguousServers):
        main_mod._routing_servers()
    with pytest.raises(HTTPException) as e:
        validate(URL_A, KEY_A)
    assert e.value.status_code == 503, "ambiguous config must never look like a bad target"
    assert e.value.detail == "Server configuration unavailable"


def test_duplicate_detection_logs_fingerprints_not_keys(capsys, servers_file, no_dns):
    servers_file.write_text(json.dumps([
        {"id": "A", "name": "A", "url": URL_A, "api_key": KEY_A},
        {"id": "B", "name": "B", "url": URL_B, "api_key": KEY_A},
    ]))
    with pytest.raises(HTTPException):
        validate(URL_A, KEY_A)
    out = capsys.readouterr().out
    assert "CONFIG AMBIGUOUS" in out
    assert "CONFIG UNREADABLE" not in out, "two different incidents need two different lines"
    assert KEY_A not in out, "a duplicate must be named by fingerprint, never by value"
    assert main_mod.secret_fingerprint(KEY_A) in out


def test_empty_api_keys_are_not_duplicates_of_each_other(servers_file, no_dns):
    """A server with no api_key configured is not 'sharing' one. Two of them must not
    take proxy routing down for every server."""
    servers_file.write_text(json.dumps([
        {"id": "A", "name": "A", "url": URL_A, "api_key": KEY_A},
        {"id": "x", "name": "X", "url": "https://x.example.com", "api_key": ""},
        {"id": "y", "name": "Y", "url": "https://y.example.com"},
    ]))
    assert len(main_mod._routing_servers()) == 3
    assert validate(URL_A, KEY_A) is None


# ── Every proxy route, not just the catch-all ─────────────────────────────────

PROXY_ROUTES = [
    ("catch-all", "get", "/fw/index.php?r=restful/devices/list", {}),
    ("cached incidents", "get", "/api/v1/incidents", {}),
    ("cached tactical", "get", "/api/v1/tactical-overview?grouping_type=category", {}),
    ("cached thresholds", "get", "/api/v1/threshold-counts", {}),
    ("dedicated proxy route", "post", "/api/incident_api.php", {"data": "method=getincidents"}),
    ("maintenance window", "post", "/api/v1/maintenance/close", {"json": {"device_name": "d"}}),
]


@pytest.fixture
def no_background_caches(monkeypatch):
    """Silence the background cache loops.

    They issue their own outgoing requests on startup, which would land in the same
    capture list as the request under test and make `sent == []` unreadable. These
    tests are about the request path, not the caches.
    """
    for mod in (main_mod.incident_cache, main_mod.tactical_cache,
                main_mod.threshold_cache, main_mod.maintenance_cache):
        monkeypatch.setattr(mod, "start_all", lambda: None)
    monkeypatch.setattr(main_mod.diagnostics, "start_monitor", lambda *a, **kw: None)


def _capturing_client(sent, then):
    """A stand-in httpx.AsyncClient that records the outgoing call and then raises.

    Covers `.request` (catch-all, dedicated routes) and `.post` (the cached
    fall-throughs) — a fake missing one of them would look like "nothing was sent".
    """
    class _Capture:
        def __init__(self, *a, **kw): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): return False
        async def request(self, method=None, url=None, **kw):
            sent.append({"url": str(url), "body": kw.get("content", b"")})
            raise then
        async def post(self, url=None, **kw):
            sent.append({"url": str(url), "body": kw.get("content", kw.get("data", b""))})
            raise then
    return _Capture


@pytest.fixture
def client(monkeypatch, no_background_caches):
    """A TestClient whose outgoing HTTP is a tripwire: nothing may leave the process."""
    sent = []
    monkeypatch.setattr(main_mod.httpx, "AsyncClient",
                        _capturing_client(sent, AssertionError("an outgoing request was made")))
    with TestClient(main_mod.app, raise_server_exceptions=False) as c:
        c.sent = sent
        yield c


@pytest.mark.parametrize("name,method,path,kw", PROXY_ROUTES, ids=[r[0] for r in PROXY_ROUTES])
def test_every_proxy_route_refuses_a_target_the_key_does_not_own(client, name, method, path, kw):
    """Not just the catch-all. Every route that takes X-BHNM-Target must bind."""
    resp = getattr(client, method)(
        path, headers={"X-Proxy-Token": KEY_A, "X-BHNM-Target": URL_B}, **kw)
    assert resp.status_code == 403, f"{name} did not refuse: {resp.status_code} {resp.text[:200]}"
    assert resp.json()["detail"] == REFUSAL
    assert "b.example.com" not in resp.text, f"{name} echoed the target"
    assert client.sent == [], f"{name} sent a request before refusing"


# ── The leak itself: assert on the OUTGOING request, not the response ─────────

def test_cold_cache_path_never_sends_key_a_to_any_host_but_a(monkeypatch, no_background_caches):
    """**The leak, tested where it happens.**

    `/api/v1/incidents` on a cold cache builds `pwd=<server_cfg api_key>` and POSTs it
    to a header-supplied `target_base`. Asserting on the RESPONSE would pass even if
    the credential had already left the process — the client just sees an error. So
    this captures the outgoing request and asserts on its URL and its body.
    """
    sent = []
    monkeypatch.setattr(main_mod.httpx, "AsyncClient",
                        _capturing_client(sent, main_mod.httpx.ConnectError("stop here")))

    with TestClient(main_mod.app, raise_server_exceptions=False) as c:
        resp = c.get("/api/v1/incidents",
                     headers={"X-Proxy-Token": KEY_A, "X-BHNM-Target": URL_B})

    assert resp.status_code == 403
    assert sent == [], "the cold-cache path sent a request to a host the key does not own"

    # And the ordinary case still goes out, to A, carrying A's key — the binding must
    # close the leak without closing the feature.
    with TestClient(main_mod.app, raise_server_exceptions=False) as c:
        c.get("/api/v1/incidents", headers={"X-Proxy-Token": KEY_A, "X-BHNM-Target": URL_A})
    assert len(sent) == 1, "the legitimate cold-cache fetch did not happen"
    assert sent[0]["url"].startswith(URL_A), sent[0]["url"]
    body = sent[0]["body"]
    body = body.decode() if isinstance(body, bytes) else str(body)
    assert KEY_A in body, "fixture precondition: the caller's key is what gets sent"
    assert "b.example.com" not in sent[0]["url"]
