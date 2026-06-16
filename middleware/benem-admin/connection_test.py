import os
import socket
import httpx
from dataclasses import dataclass
from urllib.parse import urlparse


@dataclass
class TestResult:
    step: str
    ok: bool
    detail: str


def run_test(url: str, api_key: str, pin: str = "") -> list[TestResult]:
    results: list[TestResult] = []

    # Honour the same TLS-verification flag the runtime middleware uses, so the
    # test does not produce false negatives for BHNM servers with self-signed
    # or expired certificates (common for on-prem appliances).
    tls_verify = os.environ.get("BHNM_TLS_VERIFY", "true").lower() != "false"

    # Step 1: DNS resolution
    parsed = urlparse(url)
    hostname = parsed.hostname or ""
    scheme_label = "HTTPS" if parsed.scheme == "https" else "HTTP"
    try:
        ip = socket.gethostbyname(hostname)
        results.append(TestResult("DNS Resolution", True, f"{hostname} → {ip}"))
    except socket.gaierror as e:
        results.append(TestResult("DNS Resolution", False, str(e)))
        return results

    # Step 2: reachability (labelled by the URL's actual scheme)
    base = url.rstrip("/")
    try:
        with httpx.Client(timeout=10.0, verify=tls_verify) as client:
            resp = client.get(f"{base}/")
        results.append(TestResult(f"{scheme_label} Reachability", True, f"HTTP {resp.status_code}"))
    except httpx.ConnectError as e:
        results.append(TestResult(f"{scheme_label} Reachability", False, f"Connection refused: {e}"))
        return results
    except httpx.HTTPError as e:
        results.append(TestResult(f"{scheme_label} Reachability", False, f"HTTP error: {e}"))
        return results

    # Step 3: API authentication
    try:
        form: dict = {"pwd": api_key, "method": "getincidents", "max": "1"}
        if pin:
            form["pin"] = pin
        with httpx.Client(timeout=10.0, verify=tls_verify) as client:
            resp = client.post(f"{base}/api/incident_api.php", data=form)
        if resp.status_code == 200:
            results.append(TestResult("API Authentication", True, "Authentication successful"))
        else:
            results.append(TestResult("API Authentication", False, f"HTTP {resp.status_code}"))
    except httpx.HTTPError as e:
        results.append(TestResult("API Authentication", False, str(e)))

    return results
