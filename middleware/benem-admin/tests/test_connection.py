import pytest
import httpx
from unittest.mock import patch, MagicMock

from connection_test import run_test, TestResult


def _mock_dns_ok(hostname):
    return "1.2.3.4"


def _mock_dns_fail(hostname):
    import socket
    raise socket.gaierror("Name or service not known")


def test_run_test_full_success():
    mock_response = MagicMock()
    mock_response.status_code = 200

    with patch("connection_test.socket.gethostbyname", side_effect=_mock_dns_ok), \
         patch("connection_test.httpx.Client") as mock_client:
        instance = mock_client.return_value.__enter__.return_value
        instance.get.return_value = mock_response
        instance.post.return_value = mock_response
        results = run_test("https://bhnm.corp.com", "mykey")

    assert len(results) == 3
    assert all(r.ok for r in results)
    assert results[0].step == "DNS Resolution"
    assert results[1].step == "HTTPS Reachability"
    assert results[2].step == "API Authentication"


def test_run_test_dns_failure():
    with patch("connection_test.socket.gethostbyname", side_effect=_mock_dns_fail):
        results = run_test("https://bhnm.unreachable.com", "mykey")

    assert len(results) == 1
    assert results[0].ok is False
    assert results[0].step == "DNS Resolution"


def test_run_test_https_failure():
    with patch("connection_test.socket.gethostbyname", side_effect=_mock_dns_ok), \
         patch("connection_test.httpx.Client") as mock_client:
        mock_client.return_value.__enter__.return_value.get.side_effect = httpx.ConnectError("refused")
        results = run_test("https://bhnm.corp.com", "mykey")

    assert results[0].ok is True   # DNS ok
    assert results[1].ok is False  # HTTPS failed
    assert len(results) == 2       # stops after HTTPS failure


def test_run_test_api_auth_failure():
    get_response = MagicMock()
    get_response.status_code = 200
    auth_response = MagicMock()
    auth_response.status_code = 401

    with patch("connection_test.socket.gethostbyname", side_effect=_mock_dns_ok), \
         patch("connection_test.httpx.Client") as mock_client:
        instance = mock_client.return_value.__enter__.return_value
        instance.get.return_value = get_response
        instance.post.return_value = auth_response
        results = run_test("https://bhnm.corp.com", "badkey")

    assert results[2].ok is False
    assert "401" in results[2].detail
