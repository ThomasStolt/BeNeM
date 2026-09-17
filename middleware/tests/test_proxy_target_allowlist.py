"""servers.json is the ALLOWLIST, not a bypass list.

The defect these tests exist for: `_validate_proxy_target` used to consult
servers.json only as a fast path, then fall through to "resolves to a non-private
address, therefore allowed". Any api_key holder could relay to any public host on
the internet from the VPS's IP — and `_verify_proxy_token` accepts any api_key in
servers.json, which ships on phones and in onboarding QR codes.

See docs/superpowers/specs/2026-09-17-proxy-target-allowlist-design.md
and docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md 8.18.
"""
import os
os.environ.setdefault("APNS_KEY_ID", "test")
os.environ.setdefault("APNS_TEAM_ID", "test")
os.environ.setdefault("APNS_BUNDLE_ID", "com.test")
os.environ.setdefault("APNS_PRIVATE_KEY_B64", "ZHVtbXk=")
os.environ.setdefault("DB_PATH", "/tmp/test_proxy_allowlist.db")
os.environ.setdefault("SERVERS_JSON_PATH", "/tmp/test_servers.json")

import json
import socket
import pytest
from fastapi import HTTPException

import main as main_mod

TOKEN = "secret-key-123"

# One public host, one on-prem server on a private address, one non-default port.
SERVERS = [
    {"id": "prod", "name": "Prod", "url": "https://bhnm.example.com", "api_key": TOKEN},
    {"id": "onprem", "name": "On-prem", "url": "https://192.168.10.50", "api_key": "k2"},
    {"id": "oddport", "name": "Odd port", "url": "https://lab.example.com:9443", "api_key": "k3"},
    {"id": "slash", "name": "Trailing slash", "url": "https://slash.example.com/", "api_key": "k4"},
]


@pytest.fixture(autouse=True)
def servers_file(tmp_path):
    f = tmp_path / "servers.json"
    f.write_text(json.dumps(SERVERS))
    original = main_mod.SERVERS_JSON_PATH
    main_mod.SERVERS_JSON_PATH = str(f)
    yield f
    main_mod.SERVERS_JSON_PATH = original


@pytest.fixture
def no_dns(monkeypatch):
    """Fail loudly if anything resolves a name. A refused target must never reach DNS.

    **LOAD-BEARING — not a nicety.** The private-address check, `getaddrinfo`, and the
    `socket`/`ipaddress` imports were DELETED from the validator, because once only
    configured hosts pass the allowlist and configured hosts bypass the address check,
    that branch is unreachable. This fixture is what makes that deletion safe: it is the
    only thing standing between "the validator never resolves" and a future edit that
    quietly reintroduces a lookup. If a change makes this fixture fire, the change is
    wrong, not the fixture. See the design note 2.2 and 7.4.
    """
    calls = []

    def boom(*a, **kw):
        calls.append(a)
        raise AssertionError(f"getaddrinfo was called with {a!r} — a refused target reached DNS")

    monkeypatch.setattr(socket, "getaddrinfo", boom)
    return calls


def refuse(url, ua="TestAgent/1.0"):
    """Call the validator with a fake request carrying a User-Agent."""
    class _Req:
        headers = {"user-agent": ua}
    return main_mod._validate_proxy_target(url, _Req())


# ── The test that would have caught the original defect ───────────────────────

def test_unconfigured_public_host_is_refused_without_touching_dns(no_dns):
    """THE REGRESSION TEST for the original defect.

    A public host absent from servers.json used to fall through the private-IP
    check and be ALLOWED. It must now be refused — and refused before resolving,
    so the client-supplied name never leaks to DNS.
    """
    with pytest.raises(HTTPException) as e:
        refuse("https://vpn.hurrikap.org:8888")
    assert e.value.status_code == 403
    assert no_dns == [], "the refused target reached DNS"


def test_configured_host_on_private_address_is_allowed(no_dns):
    """An on-prem BHNM legitimately sits on a private address. Do not 'fix' this."""
    assert refuse("https://192.168.10.50") is None
    assert no_dns == []


def test_configured_host_wrong_port_is_refused(no_dns):
    """Hostname alone used to be the whole comparison."""
    with pytest.raises(HTTPException) as e:
        refuse("https://bhnm.example.com:9999")
    assert e.value.status_code == 403
    with pytest.raises(HTTPException):
        refuse("https://lab.example.com")          # entry is :9443, default 443 must not match


def test_http_where_entry_is_https_is_refused(no_dns):
    """A downgrade would put X-Proxy-Token and pwd= on the wire in cleartext."""
    with pytest.raises(HTTPException) as e:
        refuse("http://bhnm.example.com")
    assert e.value.status_code == 403


def test_unreadable_servers_json_is_503_not_403(servers_file, no_dns):
    """'I cannot read my config' and 'your target is wrong' are different incidents."""
    servers_file.write_text("{ this is not json")
    with pytest.raises(HTTPException) as e:
        refuse("https://bhnm.example.com")
    assert e.value.status_code == 503, "unreadable config must never look like a bad target"

    main_mod.SERVERS_JSON_PATH = "/nonexistent/servers.json"
    with pytest.raises(HTTPException) as e:
        refuse("https://bhnm.example.com")
    assert e.value.status_code == 503


def test_refusal_logs_target_and_user_agent(capsys, no_dns):
    with pytest.raises(HTTPException):
        refuse("https://evil.example.com", ua="BeNeM/36 CFNetwork/3860.700.1 Darwin/25.6.0")
    out = capsys.readouterr().out
    assert "REFUSED" in out
    assert "evil.example.com" in out, "the log must carry the full target"
    assert "BeNeM/36 CFNetwork/3860.700.1 Darwin/25.6.0" in out, "the log must name the client"


def test_refusal_response_does_not_echo_the_target(no_dns):
    """A constant detail: echoing buys nothing and would confirm configured hosts by probe."""
    with pytest.raises(HTTPException) as e:
        refuse("https://probe-me.example.com:1234")
    assert e.value.detail == "Proxy target is not a configured server."
    assert "probe-me" not in str(e.value.detail)


def test_normalisation_accepts_equivalent_spellings(no_dns):
    for url in ("https://bhnm.example.com",
                "https://bhnm.example.com/",
                "https://BHNM.EXAMPLE.COM",
                "https://bhnm.example.com:443",
                "https://slash.example.com",          # entry has a trailing slash
                "https://lab.example.com:9443"):
        assert refuse(url) is None, f"{url} should be allowed"


def test_junk_targets_are_refused(no_dns):
    for url in ("", "not-a-url", "ftp://bhnm.example.com", "https://", "https://bhnm.example.com:notaport"):
        with pytest.raises(HTTPException) as e:
            refuse(url)
        assert e.value.status_code == 403, url


# ── The api_key-resolved path: 45 of 292 requests in the 8.19 capture carried no
#    X-BHNM-Target at all and were resolved from servers.json instead. That path is
#    inherently safe because the target comes from config — but "inherently safe" is
#    an assumption until it is a test. 45 of 292 is not an edge case.

def test_api_key_resolved_target_passes_the_allowlist(no_dns):
    """A target derived from servers.json by api_key must round-trip through the allowlist."""
    derived = main_mod._target_for_api_key(TOKEN)
    assert derived, "fixture precondition: the api_key resolves to a URL"
    assert main_mod._validate_proxy_target(derived, None) is None


def test_every_configured_url_passes_its_own_allowlist(no_dns):
    """Every entry in servers.json must validate — normalisation must round-trip.

    Guards the trailing-slash and default-port spellings in both directions at once: a
    config spelling that did not normalise to its own key would refuse the very server
    it configures.
    """
    for entry in SERVERS:
        assert main_mod._validate_proxy_target(entry["url"], None) is None, entry["url"]


def test_single_server_fallback_target_passes_the_allowlist(tmp_path, no_dns):
    """The 'exactly one configured server' fallback also feeds the validator."""
    only = tmp_path / "one.json"
    only.write_text(json.dumps([{"id": "solo", "name": "Solo",
                                 "url": "https://solo.example.com/", "api_key": "k"}]))
    main_mod.SERVERS_JSON_PATH = str(only)
    derived = main_mod._single_server_url()
    assert derived == "https://solo.example.com"
    assert main_mod._validate_proxy_target(derived, None) is None


def test_server_with_unusable_url_is_excluded_and_therefore_refused(tmp_path, no_dns):
    """Fail closed, consistently: an entry we cannot normalise is in neither the
    allowlist nor the accepted set, so it is refused rather than silently allowed."""
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps([{"id": "bad", "name": "Bad", "url": "not-a-url", "api_key": "k"}]))
    main_mod.SERVERS_JSON_PATH = str(bad)
    assert main_mod._proxy_allowlist() == set()
    with pytest.raises(HTTPException) as e:
        refuse("not-a-url")
    assert e.value.status_code == 403


def test_every_validate_call_site_passes_the_request():
    """All six call sites must pass `request`, or the refusal cannot name the client.

    A new call site added with one argument would still refuse correctly but would log
    `user-agent='(none)'`, quietly degrading the enumeration that replaces the packet
    capture. Structural, so it is caught at the source rather than in production.
    """
    import ast, pathlib
    src = pathlib.Path(main_mod.__file__).read_text()
    calls = [n for n in ast.walk(ast.parse(src))
             if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "_validate_proxy_target"]
    assert len(calls) == 6, f"expected 6 call sites, found {len(calls)}"
    for c in calls:
        assert len(c.args) == 2, f"call at line {c.lineno} does not pass request"


def test_proxy_route_returns_403_end_to_end(no_dns):
    """Through the real route, not just the validator: an authenticated client naming
    an unconfigured host gets an immediate 403, not a 60-second hang."""
    from fastapi.testclient import TestClient
    with TestClient(main_mod.app) as client:
        resp = client.get("/fw/index.php?r=restful/devices/list",
                          headers={"X-Proxy-Token": TOKEN,
                                   "X-BHNM-Target": "https://vpn.hurrikap.org:8888",
                                   "User-Agent": "BeNeM/36 CFNetwork/3860.700.1 Darwin/25.6.0"})
    assert resp.status_code == 403
    assert resp.json()["detail"] == "Proxy target is not a configured server."
    assert "vpn.hurrikap.org" not in resp.text, "the response must not echo the target"
