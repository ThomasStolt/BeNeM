"""The QR's middleware URL is derived from DOMAIN, with MIDDLEWARE_URL as an override."""
import main


def test_derived_from_DOMAIN(monkeypatch):
    monkeypatch.delenv("MIDDLEWARE_URL", raising=False)
    monkeypatch.setenv("DOMAIN", "bhnm-apns.tstolt.com")
    assert main._middleware_url() == ("https://bhnm-apns.tstolt.com", "DOMAIN in .env")


def test_an_explicit_override_wins(monkeypatch):
    monkeypatch.setenv("DOMAIN", "bhnm-apns.tstolt.com")
    monkeypatch.setenv("MIDDLEWARE_URL", "https://elsewhere.example/")
    assert main._middleware_url() == ("https://elsewhere.example", "MIDDLEWARE_URL override in .env")


def test_nothing_set_says_so(monkeypatch):
    monkeypatch.delenv("MIDDLEWARE_URL", raising=False)
    monkeypatch.delenv("DOMAIN", raising=False)
    assert main._middleware_url() == ("", "not configured")
