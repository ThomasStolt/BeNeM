# BeNeM Admin Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a secure, web-based admin console hosted on the Linode server (inside the bhnm-apns repo) that generates `benem://` deep-link provisioning URLs and QR codes without requiring access to the development machine.

**Architecture:** A new `benem-admin` Docker service added to the `bhnm-apns` repo. Caddy routes `/admin*` to it behind HTTP Basic Auth. The app adds a second factor (TOTP via `pyotp`) and issues a 24-hour session cookie. Five pages: Generate Link, Connection Test, Push Config, Log, Settings. State (audit log) lives on a Docker volume; device tokens are read directly from the existing `db-data` SQLite volume (read-only).

**Tech Stack:** Python 3.12, FastAPI, Jinja2, pyotp, itsdangerous, qrcode[pil], cryptography, httpx, sqlite3, Tailwind CSS (CDN), HTMX (CDN), Docker

---

## File Structure

All new code lives in `bhnm-apns/benem-admin/` (sub-directory of the existing repo).

| File | Responsibility |
|---|---|
| `benem-admin/Dockerfile` | Container build |
| `benem-admin/requirements.txt` | Runtime Python dependencies |
| `benem-admin/main.py` | FastAPI app — all routes |
| `benem-admin/auth.py` | TOTP verify, session cookie issue/verify |
| `benem-admin/crypto.py` | `encrypt_payload` (ported from generate_benem_link.py) |
| `benem-admin/servers.py` | Load and query `servers.json` |
| `benem-admin/log.py` | Append/read JSON Lines audit log |
| `benem-admin/push_db.py` | Read bhnm-apns SQLite read-only |
| `benem-admin/connection_test.py` | DNS → HTTPS → API auth test steps |
| `benem-admin/sf_symbols.py` | Curated list of 100 SF Symbol names |
| `benem-admin/templates/base.html` | Sidebar shell |
| `benem-admin/templates/login.html` | TOTP login form |
| `benem-admin/templates/generate.html` | Page 1: Generate Link |
| `benem-admin/templates/test.html` | Page 2: Connection Test |
| `benem-admin/templates/push.html` | Page 3: Push Config |
| `benem-admin/templates/log.html` | Page 4: Log |
| `benem-admin/templates/settings.html` | Page 5: Settings |
| `benem-admin/tests/test_crypto.py` | Unit tests: encrypt round-trip |
| `benem-admin/tests/test_auth.py` | Unit tests: TOTP verify, session roundtrip |
| `benem-admin/tests/test_servers.py` | Unit tests: load_servers |
| `benem-admin/tests/test_log.py` | Unit tests: append + read |
| `benem-admin/tests/test_connection.py` | Unit tests: run_test (mocked httpx) |
| `benem-admin/tests/test_routes.py` | Integration tests: login flow |
| `docker-compose.yml` | MODIFIED: add benem-admin service + volumes |
| `Caddyfile` | MODIFIED: add /admin\* route with Basic Auth |
| `servers.json.example` | Example multi-server config |

---

## Task 1: Scaffold

**Files:**
- Create: `bhnm-apns/benem-admin/Dockerfile`
- Create: `bhnm-apns/benem-admin/requirements.txt`
- Create: `bhnm-apns/benem-admin/main.py`
- Create: `bhnm-apns/benem-admin/tests/__init__.py`

- [ ] **Step 1: Create `benem-admin/` directory structure**

```bash
cd /path/to/bhnm-apns
mkdir -p benem-admin/templates benem-admin/tests
touch benem-admin/tests/__init__.py
```

- [ ] **Step 2: Write `benem-admin/requirements.txt`**

```
fastapi[standard]
uvicorn
jinja2
python-multipart
pyotp
itsdangerous
qrcode[pil]
cryptography
httpx
python-dotenv
pytest
pytest-mock
```

- [ ] **Step 3: Write `benem-admin/Dockerfile`**

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# /app/log is a Docker volume for the audit log
# /data is the bhnm-apns db volume, mounted read-only
VOLUME ["/app/log"]

EXPOSE 8001

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
```

- [ ] **Step 4: Write minimal `benem-admin/main.py` with health endpoint**

```python
VERSION = "1.0.0"

import os
from fastapi import FastAPI
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(docs_url=None, redoc_url=None)
templates = Jinja2Templates(directory="templates")


@app.get("/admin/health")
def health():
    return {"status": "running", "version": VERSION}
```

- [ ] **Step 5: Verify the app starts**

```bash
cd bhnm-apns/benem-admin
pip install -r requirements.txt
uvicorn main:app --port 8001
# Expected: Uvicorn running on http://0.0.0.0:8001
# curl http://localhost:8001/admin/health → {"status":"running","version":"1.0.0"}
```

- [ ] **Step 6: Commit**

```bash
git add benem-admin/
git commit -m "feat: scaffold benem-admin container"
```

---

## Task 2: Crypto Module

**Files:**
- Create: `bhnm-apns/benem-admin/crypto.py`
- Create: `bhnm-apns/benem-admin/tests/test_crypto.py`

- [ ] **Step 1: Write the failing tests**

```python
# benem-admin/tests/test_crypto.py
import base64, json, os, zlib
import pytest
from unittest.mock import patch

from crypto import encrypt_payload, load_key

VALID_KEY_HEX = "a" * 64  # 32 bytes as hex


def test_load_key_success():
    with patch.dict(os.environ, {"BENEM_SECRET_KEY": VALID_KEY_HEX}):
        key = load_key()
    assert key == bytes.fromhex(VALID_KEY_HEX)


def test_load_key_missing_raises():
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(ValueError, match="BENEM_SECRET_KEY"):
            load_key()


def test_load_key_wrong_length_raises():
    with patch.dict(os.environ, {"BENEM_SECRET_KEY": "abc"}):
        with pytest.raises(ValueError, match="64 hex"):
            load_key()


def test_encrypt_payload_returns_url_safe_base64():
    key = bytes.fromhex(VALID_KEY_HEX)
    blob = encrypt_payload({"hello": "world"}, key)
    # Must be URL-safe base64 (no +, /, =)
    assert "+" not in blob
    assert "/" not in blob
    assert "=" not in blob


def test_encrypt_payload_roundtrip():
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    key = bytes.fromhex(VALID_KEY_HEX)
    payload = {"bhnm_url": "https://bhnm.corp.com", "api_key": "secret123"}
    blob = encrypt_payload(payload, key)

    raw_bytes = base64.urlsafe_b64decode(blob + "==")
    nonce = raw_bytes[:12]
    ct = raw_bytes[12:]
    compressed = AESGCM(key).decrypt(nonce, ct, None)
    recovered = json.loads(zlib.decompress(compressed))
    assert recovered == payload


def test_encrypt_produces_different_ciphertext_each_call():
    key = bytes.fromhex(VALID_KEY_HEX)
    payload = {"x": 1}
    blob1 = encrypt_payload(payload, key)
    blob2 = encrypt_payload(payload, key)
    assert blob1 != blob2  # random nonce
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd bhnm-apns/benem-admin
python -m pytest tests/test_crypto.py -v
# Expected: ImportError or ModuleNotFoundError — crypto.py does not exist yet
```

- [ ] **Step 3: Write `benem-admin/crypto.py`**

```python
import base64
import json
import os
import zlib

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def load_key() -> bytes:
    hex_key = os.environ.get("BENEM_SECRET_KEY", "")
    if not hex_key:
        raise ValueError("BENEM_SECRET_KEY is not set")
    if len(hex_key) != 64:
        raise ValueError(f"BENEM_SECRET_KEY must be 64 hex characters (32 bytes), got {len(hex_key)}")
    return bytes.fromhex(hex_key)


def encrypt_payload(payload: dict, key: bytes) -> str:
    """Pack payload → JSON → zlib compress → AES-256-GCM encrypt → base64url (no padding)."""
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    compressed = zlib.compress(raw, level=9)
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, compressed, None)  # ct includes 16-byte GCM tag
    return base64.urlsafe_b64encode(nonce + ct).rstrip(b"=").decode("ascii")
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
python -m pytest tests/test_crypto.py -v
# Expected: 6 passed
```

- [ ] **Step 5: Commit**

```bash
git add benem-admin/crypto.py benem-admin/tests/test_crypto.py
git commit -m "feat: add crypto module for benem:// payload encryption"
```

---

## Task 3: Auth Module

**Files:**
- Create: `bhnm-apns/benem-admin/auth.py`
- Create: `bhnm-apns/benem-admin/tests/test_auth.py`

- [ ] **Step 1: Write the failing tests**

```python
# benem-admin/tests/test_auth.py
import os
import pytest
import pyotp
from unittest.mock import patch, MagicMock

from auth import verify_totp, create_session_token, verify_session_token

SECRET = pyotp.random_base32()


def test_verify_totp_valid():
    code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_totp(code) is True


def test_verify_totp_invalid_code():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_totp("000000") is False


def test_verify_totp_missing_secret():
    with patch.dict(os.environ, {}, clear=True):
        assert verify_totp("123456") is False


def test_session_token_roundtrip():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        token = create_session_token()
        assert verify_session_token(token) is True


def test_session_token_tampered():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        token = create_session_token()
        tampered = token[:-4] + "xxxx"
        assert verify_session_token(tampered) is False


def test_session_token_empty():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        assert verify_session_token("") is False
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
python -m pytest tests/test_auth.py -v
# Expected: ImportError — auth.py does not exist yet
```

- [ ] **Step 3: Write `benem-admin/auth.py`**

```python
import os
import pyotp
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from fastapi import Request
from fastapi.responses import RedirectResponse

SESSION_COOKIE = "benem_admin_session"
SESSION_MAX_AGE = 86400  # 24 hours


def _serializer() -> URLSafeTimedSerializer:
    secret = os.environ.get("TOTP_SECRET", "fallback-not-for-production")
    return URLSafeTimedSerializer(secret, salt="benem-admin-session")


def verify_totp(code: str) -> bool:
    secret = os.environ.get("TOTP_SECRET", "")
    if not secret:
        return False
    return pyotp.TOTP(secret).verify(code, valid_window=1)


def create_session_token() -> str:
    return _serializer().dumps({"ok": True})


def verify_session_token(token: str) -> bool:
    if not token:
        return False
    try:
        _serializer().loads(token, max_age=SESSION_MAX_AGE)
        return True
    except (BadSignature, SignatureExpired):
        return False


def is_authenticated(request: Request) -> bool:
    token = request.cookies.get(SESSION_COOKIE, "")
    return verify_session_token(token)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse("/admin/login", status_code=302)
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
python -m pytest tests/test_auth.py -v
# Expected: 6 passed
```

- [ ] **Step 5: Commit**

```bash
git add benem-admin/auth.py benem-admin/tests/test_auth.py
git commit -m "feat: add TOTP auth and session management"
```

---

## Task 4: Data Modules (servers, log, push_db)

**Files:**
- Create: `bhnm-apns/benem-admin/servers.py`
- Create: `bhnm-apns/benem-admin/log.py`
- Create: `bhnm-apns/benem-admin/push_db.py`
- Create: `bhnm-apns/benem-admin/tests/test_servers.py`
- Create: `bhnm-apns/benem-admin/tests/test_log.py`

- [ ] **Step 1: Write failing tests for servers.py**

```python
# benem-admin/tests/test_servers.py
import json
import os
import tempfile
import pytest
from unittest.mock import patch

from servers import load_servers, get_server, Server

SAMPLE = [
    {"id": "prod", "name": "Production", "url": "https://bhnm.corp.com", "api_key": "abc", "pin": ""},
    {"id": "demo", "name": "Demo", "url": "https://bhnm.demo.com", "api_key": "xyz", "pin": "1234"},
]


def test_load_servers_returns_list(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        servers = load_servers()
    assert len(servers) == 2
    assert servers[0].id == "prod"
    assert servers[1].pin == "1234"


def test_get_server_found(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        s = get_server("demo")
    assert s is not None
    assert s.name == "Demo"


def test_get_server_not_found(tmp_path):
    p = tmp_path / "servers.json"
    p.write_text(json.dumps(SAMPLE))
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": str(p)}):
        s = get_server("nonexistent")
    assert s is None


def test_load_servers_file_missing():
    with patch.dict(os.environ, {"SERVERS_JSON_PATH": "/nonexistent/servers.json"}):
        with pytest.raises(FileNotFoundError):
            load_servers()
```

- [ ] **Step 2: Write failing tests for log.py**

```python
# benem-admin/tests/test_log.py
import json
import os
import pytest

from log import append_entry, read_entries


def test_append_and_read(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    with __import__("unittest.mock", fromlist=["patch"]).patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("Thomas", "prod", "Production", "benem://configure?p=abc123long")
        entries = read_entries()
    assert len(entries) == 1
    e = entries[0]
    assert e["user"] == "Thomas"
    assert e["server_id"] == "prod"
    assert e["link_prefix"].startswith("benem://configure?p=")
    assert len(e["link_prefix"]) <= 40


def test_read_entries_empty_when_no_file(tmp_path):
    log_path = str(tmp_path / "missing.jsonl")
    with __import__("unittest.mock", fromlist=["patch"]).patch.dict(os.environ, {"LOG_PATH": log_path}):
        entries = read_entries()
    assert entries == []


def test_read_entries_filtered_by_server(tmp_path):
    log_path = str(tmp_path / "admin.jsonl")
    from unittest.mock import patch
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
    from unittest.mock import patch
    with patch.dict(os.environ, {"LOG_PATH": log_path}):
        append_entry("first", "prod", "Production", "benem://a")
        append_entry("second", "prod", "Production", "benem://b")
        entries = read_entries()
    assert entries[0]["user"] == "second"
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
python -m pytest tests/test_servers.py tests/test_log.py -v
# Expected: ImportError — modules do not exist yet
```

- [ ] **Step 4: Write `benem-admin/servers.py`**

```python
import json
import os
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Server:
    id: str
    name: str
    url: str
    api_key: str
    pin: str = ""


def load_servers() -> list[Server]:
    path = os.environ.get("SERVERS_JSON_PATH", "/app/servers.json")
    with open(path) as f:
        data = json.load(f)
    return [Server(**s) for s in data]


def get_server(server_id: str) -> Optional[Server]:
    for s in load_servers():
        if s.id == server_id:
            return s
    return None
```

- [ ] **Step 5: Write `benem-admin/log.py`**

```python
import json
import os
from datetime import datetime, timezone
from typing import Optional

LOG_PATH = os.environ.get("LOG_PATH", "/app/log/admin.jsonl")


def append_entry(user: str, server_id: str, server_name: str, link: str) -> None:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "user": user,
        "server_id": server_id,
        "server_name": server_name,
        "link_prefix": link[:40],
    }
    with open(path, "a") as f:
        f.write(json.dumps(entry) + "\n")


def read_entries(server_id: Optional[str] = None, page: int = 1, per_page: int = 50) -> list[dict]:
    path = os.environ.get("LOG_PATH", LOG_PATH)
    if not os.path.exists(path):
        return []
    entries = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
                if server_id is None or e.get("server_id") == server_id:
                    entries.append(e)
            except json.JSONDecodeError:
                pass
    entries.reverse()  # newest first
    start = (page - 1) * per_page
    return entries[start : start + per_page]


def count_entries(server_id: Optional[str] = None) -> int:
    return len(read_entries(server_id=server_id, page=1, per_page=999999))
```

- [ ] **Step 6: Write `benem-admin/push_db.py`**

```python
import os
import sqlite3
from dataclasses import dataclass

DB_PATH = os.environ.get("APNS_DB_PATH", "/data/bhnm_apns.db")


@dataclass
class DeviceToken:
    token: str
    device_name: str
    registered_at: str


def get_registered_devices() -> list[DeviceToken]:
    path = os.environ.get("APNS_DB_PATH", DB_PATH)
    if not os.path.exists(path):
        return []
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        rows = conn.execute(
            "SELECT token, device_name, registered_at FROM device_tokens ORDER BY registered_at DESC"
        ).fetchall()
        conn.close()
        return [DeviceToken(token=r[0], device_name=r[1], registered_at=r[2] or "") for r in rows]
    except Exception:
        return []
```

- [ ] **Step 7: Run tests to confirm they pass**

```bash
python -m pytest tests/test_servers.py tests/test_log.py -v
# Expected: 7 passed
```

- [ ] **Step 8: Commit**

```bash
git add benem-admin/servers.py benem-admin/log.py benem-admin/push_db.py \
        benem-admin/tests/test_servers.py benem-admin/tests/test_log.py
git commit -m "feat: add servers, log, and push_db data modules"
```

---

## Task 5: Connection Test Module

**Files:**
- Create: `bhnm-apns/benem-admin/connection_test.py`
- Create: `bhnm-apns/benem-admin/tests/test_connection.py`

- [ ] **Step 1: Write the failing tests**

```python
# benem-admin/tests/test_connection.py
import pytest
import httpx
from unittest.mock import patch, MagicMock
from dataclasses import dataclass

from connection_test import run_test, TestResult


def _mock_dns_ok(hostname):
    return "1.2.3.4"


def _mock_dns_fail(hostname):
    import socket
    raise socket.gaierror("Name or service not known")


def test_run_test_full_success():
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.text = '[{"id": "1"}]'  # valid BHNM response

    with patch("connection_test.socket.gethostbyname", side_effect=_mock_dns_ok), \
         patch("connection_test.httpx.Client") as mock_client:
        mock_client.return_value.__enter__.return_value.get.return_value = mock_response
        mock_client.return_value.__enter__.return_value.post.return_value = mock_response
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
        mock_client.return_value.__enter__.return_value.get.return_value = get_response
        mock_client.return_value.__enter__.return_value.post.return_value = auth_response
        results = run_test("https://bhnm.corp.com", "badkey")

    assert results[2].ok is False
    assert "401" in results[2].detail
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
python -m pytest tests/test_connection.py -v
# Expected: ImportError — connection_test.py does not exist yet
```

- [ ] **Step 3: Write `benem-admin/connection_test.py`**

```python
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

    # Step 1: DNS resolution
    parsed = urlparse(url)
    hostname = parsed.hostname or ""
    try:
        ip = socket.gethostbyname(hostname)
        results.append(TestResult("DNS Resolution", True, f"{hostname} → {ip}"))
    except socket.gaierror as e:
        results.append(TestResult("DNS Resolution", False, str(e)))
        return results

    # Step 2: HTTPS reachability
    base = url.rstrip("/")
    try:
        with httpx.Client(timeout=10.0, verify=True) as client:
            resp = client.get(f"{base}/")
        results.append(TestResult("HTTPS Reachability", True, f"HTTP {resp.status_code}"))
    except httpx.ConnectError as e:
        results.append(TestResult("HTTPS Reachability", False, f"Connection refused: {e}"))
        return results
    except httpx.HTTPError as e:
        results.append(TestResult("HTTPS Reachability", True, f"HTTP error (server is up): {e}"))

    # Step 3: API authentication
    try:
        form: dict = {"password": api_key, "method": "getincidents", "max": "1"}
        if pin:
            form["pin"] = pin
        with httpx.Client(timeout=10.0, verify=True) as client:
            resp = client.post(f"{base}/api/incident_api.php", data=form)
        if resp.status_code == 200:
            results.append(TestResult("API Authentication", True, "Authentication successful"))
        else:
            results.append(TestResult("API Authentication", False, f"HTTP {resp.status_code}"))
    except httpx.HTTPError as e:
        results.append(TestResult("API Authentication", False, str(e)))

    return results
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
python -m pytest tests/test_connection.py -v
# Expected: 4 passed
```

- [ ] **Step 5: Commit**

```bash
git add benem-admin/connection_test.py benem-admin/tests/test_connection.py
git commit -m "feat: add connection test module"
```

---

## Task 6: SF Symbols List

**Files:**
- Create: `bhnm-apns/benem-admin/sf_symbols.py`

(No separate test — it's a pure data constant; verified by inspection in the UI.)

- [ ] **Step 1: Write `benem-admin/sf_symbols.py`**

```python
# Curated list of SF Symbol names for the Generate Link autocomplete picker.
# Full name list: https://developer.apple.com/sf-symbols/
SF_SYMBOLS: list[str] = [
    "server.rack",
    "network",
    "wifi",
    "wifi.exclamationmark",
    "antenna.radiowaves.left.and.right",
    "antenna.radiowaves.left.and.right.slash",
    "router",
    "router.fill",
    "switch.2",
    "pc",
    "desktopcomputer",
    "display",
    "laptopcomputer",
    "printer",
    "externaldrive",
    "internaldrive",
    "externaldrive.connected.to.line.below",
    "sdcard",
    "cpu",
    "cpu.fill",
    "memorychip",
    "fibre.channel",
    "cloud",
    "cloud.fill",
    "icloud",
    "icloud.fill",
    "lock.shield",
    "lock.shield.fill",
    "shield",
    "shield.fill",
    "checkmark.shield",
    "xmark.shield",
    "exclamationmark.shield",
    "bell",
    "bell.fill",
    "bell.slash",
    "bell.badge",
    "exclamationmark.triangle",
    "exclamationmark.triangle.fill",
    "xmark.octagon",
    "xmark.octagon.fill",
    "checkmark.circle",
    "checkmark.circle.fill",
    "xmark.circle",
    "xmark.circle.fill",
    "questionmark.circle",
    "info.circle",
    "info.circle.fill",
    "arrow.triangle.2.circlepath",
    "arrow.clockwise",
    "arrow.counterclockwise",
    "bolt",
    "bolt.fill",
    "bolt.slash",
    "thermometer.medium",
    "gauge",
    "gauge.open.with.lines.needle.33percent",
    "speedometer",
    "waveform.path.ecg",
    "chart.bar",
    "chart.bar.fill",
    "chart.line.uptrend.xyaxis",
    "chart.xyaxis.line",
    "map",
    "map.fill",
    "location",
    "location.fill",
    "building.2",
    "building.2.fill",
    "building.columns",
    "square.stack.3d.up",
    "square.stack.3d.up.fill",
    "tray.full",
    "tray.full.fill",
    "folder",
    "folder.fill",
    "doc.text",
    "doc.text.fill",
    "list.bullet",
    "list.clipboard",
    "magnifyingglass",
    "wrench.and.screwdriver",
    "wrench.and.screwdriver.fill",
    "hammer",
    "hammer.fill",
    "gear",
    "gearshape",
    "gearshape.fill",
    "person",
    "person.fill",
    "person.2",
    "person.2.fill",
    "person.badge.key",
    "key",
    "key.fill",
    "lock",
    "lock.fill",
    "eye",
    "eye.fill",
    "eye.slash",
    "tag",
    "tag.fill",
    "bookmark",
    "bookmark.fill",
    "star",
    "star.fill",
    "flag",
    "flag.fill",
]
```

- [ ] **Step 2: Commit**

```bash
git add benem-admin/sf_symbols.py
git commit -m "feat: add SF Symbol name list for autocomplete picker"
```

---

## Task 7: Base Templates and Login Page

**Files:**
- Create: `bhnm-apns/benem-admin/templates/base.html`
- Create: `bhnm-apns/benem-admin/templates/login.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add login routes)
- Create: `bhnm-apns/benem-admin/tests/test_routes.py`

- [ ] **Step 1: Write failing login route tests**

```python
# benem-admin/tests/test_routes.py
import os
import pyotp
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

SECRET = pyotp.random_base32()

# Import the app with env set
with patch.dict(os.environ, {
    "TOTP_SECRET": SECRET,
    "BENEM_SECRET_KEY": "a" * 64,
    "SERVERS_JSON_PATH": "/nonexistent",  # not needed for auth tests
}):
    from main import app

client = TestClient(app, follow_redirects=False)


def test_get_login_returns_200():
    resp = client.get("/admin/login")
    assert resp.status_code == 200
    assert "TOTP" in resp.text or "code" in resp.text.lower()


def test_post_login_invalid_code_returns_200_with_error():
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        resp = client.post("/admin/login", data={"code": "000000"})
    assert resp.status_code == 200
    assert "invalid" in resp.text.lower() or "incorrect" in resp.text.lower()


def test_post_login_valid_code_redirects():
    valid_code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        resp = client.post("/admin/login", data={"code": valid_code})
    assert resp.status_code == 302
    assert resp.headers["location"] == "/admin/"


def test_protected_route_redirects_to_login_unauthenticated():
    resp = client.get("/admin/")
    assert resp.status_code == 302
    assert "/admin/login" in resp.headers["location"]


def test_logout_clears_session():
    valid_code = pyotp.TOTP(SECRET).now()
    with patch.dict(os.environ, {"TOTP_SECRET": SECRET}):
        login_resp = client.post("/admin/login", data={"code": valid_code})
    session_cookie = login_resp.cookies.get("benem_admin_session")
    assert session_cookie is not None

    logout_resp = client.post("/admin/logout")
    assert logout_resp.status_code == 302
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
python -m pytest tests/test_routes.py -v
# Expected: various failures — routes not yet defined
```

- [ ] **Step 3: Write `benem-admin/templates/base.html`**

```html
<!DOCTYPE html>
<html lang="en" class="h-full">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>BeNeM Admin</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://unpkg.com/htmx.org@1.9.12"></script>
</head>
<body class="h-full flex bg-gray-100">

  <!-- Sidebar -->
  <aside class="w-52 bg-gray-900 text-white flex flex-col min-h-screen">
    <div class="px-5 py-6 border-b border-gray-700">
      <div class="text-blue-400 font-bold text-lg">BeNeM Admin</div>
    </div>
    <nav class="flex-1 px-3 py-4 space-y-1">
      <a href="/admin/"
         class="flex items-center px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-700 {{ 'bg-gray-700 text-white' if active == 'generate' else 'text-gray-300' }}">
        Generate Link
      </a>
      <a href="/admin/test"
         class="flex items-center px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-700 {{ 'bg-gray-700 text-white' if active == 'test' else 'text-gray-300' }}">
        Connection Test
      </a>
      <a href="/admin/push"
         class="flex items-center px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-700 {{ 'bg-gray-700 text-white' if active == 'push' else 'text-gray-300' }}">
        Push Config
      </a>
      <a href="/admin/log"
         class="flex items-center px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-700 {{ 'bg-gray-700 text-white' if active == 'log' else 'text-gray-300' }}">
        Log
      </a>
      <a href="/admin/settings"
         class="flex items-center px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-700 {{ 'bg-gray-700 text-white' if active == 'settings' else 'text-gray-300' }}">
        Settings
      </a>
    </nav>
    <div class="px-5 py-4 border-t border-gray-700">
      <form method="post" action="/admin/logout">
        <button type="submit"
                class="w-full text-left text-xs text-gray-400 hover:text-white">
          Sign out
        </button>
      </form>
    </div>
  </aside>

  <!-- Main content -->
  <main class="flex-1 overflow-auto p-8">
    {% block content %}{% endblock %}
  </main>

</body>
</html>
```

- [ ] **Step 4: Write `benem-admin/templates/login.html`**

```html
<!DOCTYPE html>
<html lang="en" class="h-full bg-gray-100">
<head>
  <meta charset="UTF-8">
  <title>BeNeM Admin — Sign In</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="h-full flex items-center justify-center">
  <div class="bg-white rounded-xl shadow-lg p-10 w-full max-w-sm">
    <h1 class="text-2xl font-bold text-gray-800 mb-1">BeNeM Admin</h1>
    <p class="text-sm text-gray-500 mb-8">Enter your authenticator code to continue.</p>

    {% if error %}
    <div class="mb-4 px-4 py-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-sm">
      {{ error }}
    </div>
    {% endif %}

    <form method="post" action="/admin/login">
      <label class="block text-sm font-medium text-gray-700 mb-1">6-digit code</label>
      <input type="text" name="code" inputmode="numeric" pattern="[0-9]{6}"
             maxlength="6" autocomplete="one-time-code" autofocus
             class="w-full px-4 py-2 border border-gray-300 rounded-lg text-center text-2xl tracking-widest font-mono focus:outline-none focus:ring-2 focus:ring-blue-500 mb-6">
      <button type="submit"
              class="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 rounded-lg transition">
        Sign In
      </button>
    </form>
  </div>
</body>
</html>
```

- [ ] **Step 5: Add login + logout routes to `benem-admin/main.py`**

Replace the contents of `main.py` with:

```python
VERSION = "1.0.0"

import os
import base64
import io
from typing import Optional

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from dotenv import load_dotenv

import auth
from auth import SESSION_COOKIE

load_dotenv()

app = FastAPI(docs_url=None, redoc_url=None)
templates = Jinja2Templates(directory="templates")


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/admin/health")
def health():
    return {"status": "running", "version": VERSION}


# ── Auth ──────────────────────────────────────────────────────────────────────

@app.get("/admin/login", response_class=HTMLResponse)
def login_page(request: Request):
    return templates.TemplateResponse("login.html", {"request": request, "error": None})


@app.post("/admin/login")
def login_submit(request: Request, code: str = Form(...)):
    if not auth.verify_totp(code):
        return templates.TemplateResponse(
            "login.html",
            {"request": request, "error": "Incorrect code — try again."},
            status_code=200,
        )
    token = auth.create_session_token()
    resp = RedirectResponse("/admin/", status_code=302)
    resp.set_cookie(
        SESSION_COOKIE, token,
        max_age=auth.SESSION_MAX_AGE,
        httponly=True, secure=True, samesite="strict",
    )
    return resp


@app.post("/admin/logout")
def logout():
    resp = RedirectResponse("/admin/login", status_code=302)
    resp.delete_cookie(SESSION_COOKIE)
    return resp
```

- [ ] **Step 6: Run login route tests**

```bash
python -m pytest tests/test_routes.py -v
# Expected: 5 passed
```

- [ ] **Step 7: Commit**

```bash
git add benem-admin/main.py benem-admin/templates/base.html benem-admin/templates/login.html \
        benem-admin/tests/test_routes.py
git commit -m "feat: add login/logout routes and base HTML layout"
```

---

## Task 8: Page 1 — Generate Link

**Files:**
- Create: `bhnm-apns/benem-admin/templates/generate.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add generate routes)

- [ ] **Step 1: Write `benem-admin/templates/generate.html`**

```html
{% extends "base.html" %}
{% block content %}
<h1 class="text-2xl font-bold text-gray-800 mb-6">Generate Link</h1>

<div class="max-w-xl bg-white rounded-xl shadow p-6 space-y-5">
  <form method="post" action="/admin/generate" id="gen-form">

    <!-- Server selector -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Server</label>
      <select name="server_id" id="server-select"
              class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
              hx-get="/admin/server-url"
              hx-trigger="change"
              hx-target="#bhnm-url-field"
              hx-include="[name='server_id']">
        {% for s in servers %}
        <option value="{{ s.id }}" {{ 'selected' if selected_server and selected_server.id == s.id }}>
          {{ s.name }}
        </option>
        {% endfor %}
      </select>
    </div>

    <!-- BHNM URL (read-only, updated by HTMX) -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">BHNM URL</label>
      <div id="bhnm-url-field" class="flex gap-2">
        <input type="text" id="bhnm-url" value="{{ selected_server.url if selected_server else '' }}"
               readonly
               class="flex-1 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono text-gray-600">
        <a href="#" id="test-bhnm" onclick="testServer(this)" data-url="{{ selected_server.url if selected_server else '' }}"
           class="px-3 py-2 text-sm bg-gray-100 hover:bg-gray-200 rounded-lg border border-gray-200 text-gray-600">
          Test
        </a>
      </div>
      <div id="bhnm-test-result" class="mt-1 text-xs"></div>
    </div>

    <!-- Push Middleware URL (read-only) -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Push Middleware URL</label>
      <div class="flex gap-2">
        <input type="text" value="{{ middleware_url }}" readonly
               class="flex-1 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono text-gray-600">
        <a href="#" onclick="testMiddleware(this)" data-url="{{ middleware_url }}"
           class="px-3 py-2 text-sm bg-gray-100 hover:bg-gray-200 rounded-lg border border-gray-200 text-gray-600">
          Test
        </a>
      </div>
      <div id="mw-test-result" class="mt-1 text-xs"></div>
    </div>

    <!-- Username -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Username</label>
      <input type="text" name="user" value="{{ form_data.user if form_data else '' }}"
             placeholder="e.g. Thomas"
             class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500">
    </div>

    <!-- SF Symbol -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">SF Symbol</label>
      <input type="text" name="symbol" list="symbol-list"
             value="{{ form_data.symbol if form_data else 'server.rack' }}"
             class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono">
      <datalist id="symbol-list">
        {% for sym in sf_symbols %}
        <option value="{{ sym }}">
        {% endfor %}
      </datalist>
    </div>

    <!-- Accent Colour -->
    <div>
      <label class="block text-sm font-medium text-gray-700 mb-1">Accent Colour</label>
      <div class="flex gap-3 items-center flex-wrap">
        {% set swatches = ["#0A84FF","#30D158","#FF9F0A","#FF453A","#BF5AF2","#64D2FF","#FFD60A","#FF6961"] %}
        {% for c in swatches %}
        <button type="button" onclick="setColor('{{ c }}')"
                class="w-8 h-8 rounded-full border-2 border-white shadow-md focus:outline-none"
                style="background-color: {{ c }};"
                title="{{ c }}"></button>
        {% endfor %}
        <input type="color" id="color-picker" value="{{ form_data.color if form_data else '#0A84FF' }}"
               onchange="document.getElementById('color-hex').value=this.value"
               class="w-8 h-8 rounded cursor-pointer border border-gray-300">
        <input type="text" id="color-hex" name="color"
               value="{{ form_data.color if form_data else '#0A84FF' }}"
               pattern="#[0-9A-Fa-f]{6}" maxlength="7"
               oninput="document.getElementById('color-picker').value=this.value"
               class="w-28 border border-gray-300 rounded-lg px-2 py-1 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500">
      </div>
    </div>

    <button type="submit"
            class="w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 rounded-lg transition">
      Generate Link
    </button>
  </form>

  <!-- Result -->
  {% if result %}
  <div class="border-t border-gray-100 pt-5 space-y-4">
    <div>
      <label class="block text-xs font-medium text-gray-500 uppercase mb-1">benem:// URL</label>
      <div class="flex gap-2">
        <code class="flex-1 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-xs font-mono break-all text-gray-800">{{ result.url }}</code>
        <button onclick="navigator.clipboard.writeText('{{ result.url }}')"
                class="px-3 py-2 text-xs bg-gray-100 hover:bg-gray-200 rounded-lg border border-gray-200 whitespace-nowrap">
          Copy
        </button>
      </div>
    </div>
    <div class="flex justify-center">
      <img src="data:image/png;base64,{{ result.qr_b64 }}" alt="QR Code" class="w-56 h-56 border border-gray-200 rounded-lg">
    </div>
  </div>
  {% endif %}
</div>

<script>
function setColor(hex) {
  document.getElementById('color-hex').value = hex;
  document.getElementById('color-picker').value = hex;
}
async function testReachability(url, resultId) {
  const el = document.getElementById(resultId);
  el.textContent = 'Testing…';
  el.className = 'mt-1 text-xs text-gray-500';
  try {
    const resp = await fetch('/admin/reachability-check?url=' + encodeURIComponent(url));
    const data = await resp.json();
    el.textContent = data.ok ? '✓ Reachable' : '✗ ' + data.detail;
    el.className = 'mt-1 text-xs ' + (data.ok ? 'text-green-600' : 'text-red-600');
  } catch (e) {
    el.textContent = '✗ Error';
    el.className = 'mt-1 text-xs text-red-600';
  }
}
function testServer(el) { testReachability(el.dataset.url, 'bhnm-test-result'); return false; }
function testMiddleware(el) { testReachability(el.dataset.url, 'mw-test-result'); return false; }
</script>
{% endblock %}
```

- [ ] **Step 2: Add generate routes to `benem-admin/main.py`**

Append to `main.py` (after the auth routes):

```python
import qrcode
from servers import load_servers, get_server
from crypto import load_key, encrypt_payload
from log import append_entry
from sf_symbols import SF_SYMBOLS

MIDDLEWARE_URL = os.environ.get("MIDDLEWARE_URL", "")
PUSH_SECRET = os.environ.get("WEBHOOK_SECRET", "")


def _make_qr_b64(url: str) -> str:
    img = qrcode.make(url)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


@app.get("/admin/", response_class=HTMLResponse)
def generate_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    servers = load_servers()
    selected = servers[0] if servers else None
    return templates.TemplateResponse("generate.html", {
        "request": request,
        "active": "generate",
        "servers": servers,
        "selected_server": selected,
        "middleware_url": MIDDLEWARE_URL,
        "sf_symbols": SF_SYMBOLS,
        "form_data": None,
        "result": None,
    })


@app.get("/admin/server-url", response_class=HTMLResponse)
def server_url_fragment(request: Request, server_id: str = ""):
    """HTMX endpoint — returns updated URL field HTML for the selected server."""
    server = get_server(server_id)
    if not server:
        return HTMLResponse('<input type="text" value="" readonly class="flex-1 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono text-gray-600">')
    return HTMLResponse(f'''
        <input type="text" id="bhnm-url" value="{server.url}" readonly
               class="flex-1 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono text-gray-600">
        <a href="#" onclick="testServer(this)" data-url="{server.url}"
           class="px-3 py-2 text-sm bg-gray-100 hover:bg-gray-200 rounded-lg border border-gray-200 text-gray-600">
          Test
        </a>
    ''')


@app.get("/admin/reachability-check")
async def reachability_check(request: Request, url: str = ""):
    if not auth.is_authenticated(request):
        return JSONResponse({"ok": False, "detail": "Not authenticated"}, status_code=401)
    try:
        async with __import__("httpx").AsyncClient(timeout=5.0) as client:
            resp = await client.get(url)
        return {"ok": True, "detail": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"ok": False, "detail": str(e)}


@app.post("/admin/generate", response_class=HTMLResponse)
def generate_link(
    request: Request,
    server_id: str = Form(...),
    user: str = Form(""),
    symbol: str = Form("server.rack"),
    color: str = Form("#0A84FF"),
):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()

    servers = load_servers()
    server = get_server(server_id)
    if not server:
        return RedirectResponse("/admin/", status_code=302)

    key = load_key()
    payload = {
        "bhnm_url":       server.url,
        "middleware_url": MIDDLEWARE_URL,
        "notifications":  bool(MIDDLEWARE_URL),
        "api_key":        server.api_key,
        "pin":            server.pin,
        "user":           user,
        "name":           server.name,
        "push_secret":    PUSH_SECRET,
        "symbol":         symbol,
        "color":          color,
    }
    blob = encrypt_payload(payload, key)
    url = f"benem://configure?p={blob}"
    qr_b64 = _make_qr_b64(url)
    append_entry(user, server.id, server.name, url)

    from dataclasses import dataclass

    @dataclass
    class GenResult:
        url: str
        qr_b64: str

    @dataclass
    class FormData:
        user: str
        symbol: str
        color: str

    return templates.TemplateResponse("generate.html", {
        "request": request,
        "active": "generate",
        "servers": servers,
        "selected_server": server,
        "middleware_url": MIDDLEWARE_URL,
        "sf_symbols": SF_SYMBOLS,
        "form_data": FormData(user=user, symbol=symbol, color=color),
        "result": GenResult(url=url, qr_b64=qr_b64),
    })
```

- [ ] **Step 3: Smoke test the generate page**

```bash
BENEM_SECRET_KEY="$(python3 -c "import os; print(os.urandom(32).hex())")" \
TOTP_SECRET="$(python3 -c "import pyotp; print(pyotp.random_base32())")" \
SERVERS_JSON_PATH=./servers.json.example \
uvicorn main:app --port 8001
# Open http://localhost:8001/admin/login — log in, go to Generate Link
# Select a server, fill form, click Generate — URL and QR should appear
```

- [ ] **Step 4: Commit**

```bash
git add benem-admin/templates/generate.html benem-admin/main.py benem-admin/sf_symbols.py
git commit -m "feat: add Generate Link page (Page 1)"
```

---

## Task 9: Page 2 — Connection Test

**Files:**
- Create: `bhnm-apns/benem-admin/templates/test.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add /admin/test route)

- [ ] **Step 1: Write `benem-admin/templates/test.html`**

```html
{% extends "base.html" %}
{% block content %}
<h1 class="text-2xl font-bold text-gray-800 mb-6">Connection Test</h1>

<div class="max-w-xl bg-white rounded-xl shadow p-6 space-y-5">
  <form method="post" action="/admin/test">
    <label class="block text-sm font-medium text-gray-700 mb-1">Server</label>
    <div class="flex gap-3">
      <select name="server_id"
              class="flex-1 border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500">
        {% for s in servers %}
        <option value="{{ s.id }}" {{ 'selected' if selected_id == s.id }}>{{ s.name }}</option>
        {% endfor %}
      </select>
      <button type="submit"
              class="px-5 py-2 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition">
        Run Test
      </button>
    </div>
  </form>

  {% if results %}
  <div class="border-t border-gray-100 pt-4 space-y-3">
    {% for r in results %}
    <div class="flex items-start gap-3">
      <span class="mt-0.5 text-lg {{ 'text-green-500' if r.ok else 'text-red-500' }}">
        {{ '✓' if r.ok else '✗' }}
      </span>
      <div>
        <div class="text-sm font-medium text-gray-800">{{ r.step }}</div>
        <div class="text-xs text-gray-500">{{ r.detail }}</div>
      </div>
    </div>
    {% endfor %}
  </div>
  {% endif %}
</div>
{% endblock %}
```

- [ ] **Step 2: Add connection test route to `main.py`**

Append to `main.py`:

```python
from connection_test import run_test


@app.get("/admin/test", response_class=HTMLResponse)
def test_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    return templates.TemplateResponse("test.html", {
        "request": request,
        "active": "test",
        "servers": load_servers(),
        "selected_id": None,
        "results": None,
    })


@app.post("/admin/test", response_class=HTMLResponse)
def test_submit(request: Request, server_id: str = Form(...)):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    servers = load_servers()
    server = get_server(server_id)
    results = run_test(server.url, server.api_key, server.pin) if server else []
    return templates.TemplateResponse("test.html", {
        "request": request,
        "active": "test",
        "servers": servers,
        "selected_id": server_id,
        "results": results,
    })
```

- [ ] **Step 3: Commit**

```bash
git add benem-admin/templates/test.html benem-admin/main.py
git commit -m "feat: add Connection Test page (Page 2)"
```

---

## Task 10: Page 3 — Push Config

**Files:**
- Create: `bhnm-apns/benem-admin/templates/push.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add /admin/push route)

- [ ] **Step 1: Write `benem-admin/templates/push.html`**

```html
{% extends "base.html" %}
{% block content %}
<h1 class="text-2xl font-bold text-gray-800 mb-6">Push Config</h1>

<div class="max-w-2xl space-y-6">

  <!-- URLs -->
  <div class="bg-white rounded-xl shadow p-6 space-y-4">
    <h2 class="text-sm font-semibold text-gray-500 uppercase">Middleware Endpoints</h2>
    <div>
      <label class="block text-xs text-gray-500 mb-1">Middleware URL</label>
      <code class="block bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono">{{ middleware_url }}</code>
    </div>
    <div>
      <label class="block text-xs text-gray-500 mb-1">Webhook URL (for BHNM)</label>
      <code class="block bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 text-sm font-mono">{{ webhook_url }}</code>
    </div>
  </div>

  <!-- Registered Devices -->
  <div class="bg-white rounded-xl shadow p-6">
    <h2 class="text-sm font-semibold text-gray-500 uppercase mb-4">
      Registered Devices
      <span class="ml-2 text-blue-600">({{ devices | length }})</span>
    </h2>
    {% if not devices %}
    <p class="text-sm text-gray-500">No devices registered yet.</p>
    {% else %}
    <table class="w-full text-sm">
      <thead>
        <tr class="text-left text-xs text-gray-500 border-b border-gray-100">
          <th class="pb-2 pr-4">Device</th>
          <th class="pb-2 pr-4">Token (truncated)</th>
          <th class="pb-2">Registered</th>
        </tr>
      </thead>
      <tbody>
        {% for d in devices %}
        <tr class="border-b border-gray-50 hover:bg-gray-50">
          <td class="py-2 pr-4 font-medium text-gray-800">{{ d.device_name }}</td>
          <td class="py-2 pr-4 font-mono text-xs text-gray-500">…{{ d.token[-12:] }}</td>
          <td class="py-2 text-gray-500 text-xs">{{ d.registered_at }}</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
    {% endif %}
  </div>

</div>
{% endblock %}
```

- [ ] **Step 2: Add push route to `main.py`**

Append to `main.py`:

```python
from push_db import get_registered_devices


@app.get("/admin/push", response_class=HTMLResponse)
def push_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    webhook_url = f"{MIDDLEWARE_URL}/webhook?secret=<your-secret>" if MIDDLEWARE_URL else ""
    return templates.TemplateResponse("push.html", {
        "request": request,
        "active": "push",
        "middleware_url": MIDDLEWARE_URL,
        "webhook_url": webhook_url,
        "devices": get_registered_devices(),
    })
```

- [ ] **Step 3: Commit**

```bash
git add benem-admin/templates/push.html benem-admin/main.py
git commit -m "feat: add Push Config page (Page 3)"
```

---

## Task 11: Page 4 — Log

**Files:**
- Create: `bhnm-apns/benem-admin/templates/log.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add /admin/log route)

- [ ] **Step 1: Write `benem-admin/templates/log.html`**

```html
{% extends "base.html" %}
{% block content %}
<h1 class="text-2xl font-bold text-gray-800 mb-6">Log</h1>

<div class="max-w-3xl space-y-4">

  <!-- Filters -->
  <form method="get" action="/admin/log" class="flex gap-3 items-end">
    <div>
      <label class="block text-xs text-gray-500 mb-1">Filter by server</label>
      <select name="server_id"
              class="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
        <option value="">All servers</option>
        {% for s in servers %}
        <option value="{{ s.id }}" {{ 'selected' if server_id == s.id }}>{{ s.name }}</option>
        {% endfor %}
      </select>
    </div>
    <button type="submit"
            class="px-4 py-2 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg text-sm border border-gray-200">
      Filter
    </button>
    {% if server_id %}
    <a href="/admin/log" class="px-4 py-2 text-sm text-gray-500 hover:text-gray-700">Clear</a>
    {% endif %}
  </form>

  <!-- Log table -->
  <div class="bg-white rounded-xl shadow overflow-hidden">
    {% if not entries %}
    <p class="p-6 text-sm text-gray-500">No log entries yet.</p>
    {% else %}
    <table class="w-full text-sm">
      <thead>
        <tr class="text-left text-xs text-gray-500 bg-gray-50 border-b border-gray-100">
          <th class="px-4 py-3">Timestamp</th>
          <th class="px-4 py-3">User</th>
          <th class="px-4 py-3">Server</th>
          <th class="px-4 py-3">Link (prefix)</th>
        </tr>
      </thead>
      <tbody>
        {% for e in entries %}
        <tr class="border-b border-gray-50 hover:bg-gray-50">
          <td class="px-4 py-2 text-gray-500 text-xs font-mono whitespace-nowrap">{{ e.ts }}</td>
          <td class="px-4 py-2 font-medium text-gray-800">{{ e.user }}</td>
          <td class="px-4 py-2 text-gray-600">{{ e.server_name }}</td>
          <td class="px-4 py-2 font-mono text-xs text-gray-500 truncate max-w-xs">{{ e.link_prefix }}…</td>
        </tr>
        {% endfor %}
      </tbody>
    </table>
    {% endif %}
  </div>

  <!-- Pagination -->
  {% if total_pages > 1 %}
  <div class="flex gap-2 justify-center">
    {% for p in range(1, total_pages + 1) %}
    <a href="?page={{ p }}{% if server_id %}&server_id={{ server_id }}{% endif %}"
       class="px-3 py-1 rounded text-sm {{ 'bg-blue-600 text-white' if p == page else 'bg-gray-100 text-gray-700 hover:bg-gray-200' }}">
      {{ p }}
    </a>
    {% endfor %}
  </div>
  {% endif %}

</div>
{% endblock %}
```

- [ ] **Step 2: Add log route to `main.py`**

Append to `main.py`:

```python
from log import read_entries, count_entries

LOG_PER_PAGE = 50


@app.get("/admin/log", response_class=HTMLResponse)
def log_page(request: Request, server_id: str = "", page: int = 1):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    filter_id = server_id or None
    entries = read_entries(server_id=filter_id, page=page, per_page=LOG_PER_PAGE)
    total = count_entries(server_id=filter_id)
    total_pages = max(1, (total + LOG_PER_PAGE - 1) // LOG_PER_PAGE)
    return templates.TemplateResponse("log.html", {
        "request": request,
        "active": "log",
        "servers": load_servers(),
        "server_id": server_id,
        "entries": entries,
        "page": page,
        "total_pages": total_pages,
    })
```

- [ ] **Step 3: Commit**

```bash
git add benem-admin/templates/log.html benem-admin/main.py
git commit -m "feat: add Log page (Page 4)"
```

---

## Task 12: Page 5 — Settings

**Files:**
- Create: `bhnm-apns/benem-admin/templates/settings.html`
- Modify: `bhnm-apns/benem-admin/main.py` (add /admin/settings route)

- [ ] **Step 1: Write `benem-admin/templates/settings.html`**

```html
{% extends "base.html" %}
{% block content %}
<h1 class="text-2xl font-bold text-gray-800 mb-6">Settings</h1>

<div class="max-w-xl space-y-6">

  <!-- TOTP Setup -->
  <div class="bg-white rounded-xl shadow p-6 space-y-4">
    <h2 class="text-sm font-semibold text-gray-500 uppercase">Authenticator Setup</h2>
    <p class="text-sm text-gray-600">
      Scan this QR code in Google Authenticator, 1Password, or Authy.
      The TOTP secret is read from <code class="bg-gray-100 px-1 rounded">TOTP_SECRET</code> in your <code class="bg-gray-100 px-1 rounded">.env</code> file.
    </p>
    <div class="flex justify-center">
      <img src="data:image/png;base64,{{ totp_qr_b64 }}" alt="TOTP QR Code"
           class="w-48 h-48 border border-gray-200 rounded-lg">
    </div>
    <p class="text-xs text-gray-400 text-center">
      To rotate the TOTP secret: edit <code>.env</code> on the server, set a new <code>TOTP_SECRET</code>,
      restart the container, then re-scan.
    </p>
  </div>

  <!-- Version -->
  <div class="bg-white rounded-xl shadow p-6">
    <h2 class="text-sm font-semibold text-gray-500 uppercase mb-3">App Info</h2>
    <dl class="text-sm space-y-1">
      <div class="flex gap-4">
        <dt class="text-gray-500 w-32">Version</dt>
        <dd class="font-mono text-gray-800">{{ version }}</dd>
      </div>
    </dl>
  </div>

  <!-- Restart -->
  <div class="bg-white rounded-xl shadow p-6">
    <h2 class="text-sm font-semibold text-gray-500 uppercase mb-3">Container</h2>
    {% if can_restart %}
    <p class="text-sm text-gray-600 mb-3">
      Restart the <code>benem-admin</code> container (requires Docker socket mount — see deployment notes).
    </p>
    <form method="post" action="/admin/restart"
          onsubmit="return confirm('Restart container? You will be disconnected briefly.')">
      <button type="submit"
              class="px-4 py-2 bg-red-50 hover:bg-red-100 text-red-700 rounded-lg text-sm border border-red-200">
        Restart Container
      </button>
    </form>
    {% else %}
    <p class="text-sm text-gray-500">
      Container restart not available — Docker socket not mounted.
      Restart manually via SSH: <code class="bg-gray-100 px-1 rounded">docker restart benem-admin</code>
    </p>
    {% endif %}
  </div>

</div>
{% endblock %}
```

- [ ] **Step 2: Add settings routes to `main.py`**

Append to `main.py`:

```python
import pyotp
import subprocess


def _totp_qr_b64() -> str:
    secret = os.environ.get("TOTP_SECRET", "")
    if not secret:
        return ""
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name="admin", issuer_name="BeNeM Admin")
    img = qrcode.make(uri)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def _can_restart() -> bool:
    return os.path.exists("/var/run/docker.sock")


@app.get("/admin/settings", response_class=HTMLResponse)
def settings_page(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    return templates.TemplateResponse("settings.html", {
        "request": request,
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": _can_restart(),
    })


@app.post("/admin/restart")
def restart_container(request: Request):
    if not auth.is_authenticated(request):
        return auth.redirect_to_login()
    if not _can_restart():
        return RedirectResponse("/admin/settings", status_code=302)
    # Runs in background — this process will be killed
    subprocess.Popen(["docker", "restart", "benem-admin"])
    return templates.TemplateResponse("settings.html", {
        "request": request,
        "active": "settings",
        "totp_qr_b64": _totp_qr_b64(),
        "version": VERSION,
        "can_restart": True,
        "restart_initiated": True,
    })
```

- [ ] **Step 3: Commit**

```bash
git add benem-admin/templates/settings.html benem-admin/main.py
git commit -m "feat: add Settings page with TOTP QR and restart button (Page 5)"
```

---

## Task 13: Infrastructure

**Files:**
- Create: `bhnm-apns/servers.json.example`
- Modify: `bhnm-apns/docker-compose.yml`
- Modify: `bhnm-apns/Caddyfile`

- [ ] **Step 1: Create `bhnm-apns/servers.json.example`**

```json
[
  {
    "id": "prod",
    "name": "Production",
    "url": "https://bhnm.corp.com",
    "api_key": "your-api-key-here",
    "pin": ""
  },
  {
    "id": "demo",
    "name": "Demo",
    "url": "https://bhnm.demo.netreo.com",
    "api_key": "your-api-key-here",
    "pin": "1234"
  }
]
```

- [ ] **Step 2: Update `bhnm-apns/docker-compose.yml`**

Replace with:

```yaml
services:
  bhnm-apns:
    build: .
    env_file: .env
    volumes:
      - db-data:/data
    restart: unless-stopped

  benem-admin:
    build: ./benem-admin
    env_file: .env
    environment:
      - SERVERS_JSON_PATH=/app/servers.json
      - LOG_PATH=/app/log/admin.jsonl
      - APNS_DB_PATH=/data/bhnm_apns.db
    volumes:
      - ./servers.json:/app/servers.json:ro
      - benem-admin-log:/app/log
      - db-data:/data:ro
      # Optional: uncomment to enable the "Restart Container" button in Settings
      # - /var/run/docker.sock:/var/run/docker.sock:ro
    expose:
      - "8001"
    restart: unless-stopped

  caddy:
    image: caddy:2-alpine
    env_file: .env
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    restart: unless-stopped

volumes:
  db-data:
  benem-admin-log:
  caddy-data:
  caddy-config:
```

- [ ] **Step 3: Update `bhnm-apns/Caddyfile`**

Replace with:

```
{$DOMAIN} {
    # Admin console — protected by Basic Auth (first factor)
    # TOTP is the second factor enforced by the app itself.
    # Generate bcrypt hash: docker run --rm caddy:2-alpine caddy hash-password --plaintext 'yourpassword'
    handle /admin* {
        basicauth {
            {$BASIC_AUTH_USER} {$BASIC_AUTH_HASH}
        }
        reverse_proxy benem-admin:8001
    }

    # bhnm-apns middleware (unchanged)
    handle {
        reverse_proxy bhnm-apns:8889
    }
}
```

- [ ] **Step 4: Add required `.env` keys to `.env.example` (if one exists) or document in README**

Add to your `.env` file on the server:

```bash
# BeNeM Admin Console
BASIC_AUTH_USER=admin
BASIC_AUTH_HASH=$2a$14$...   # bcrypt hash — generate with: docker run --rm caddy:2-alpine caddy hash-password --plaintext 'yourpassword'
TOTP_SECRET=                  # base32 — generate with: python3 -c "import pyotp; print(pyotp.random_base32())"
BENEM_SECRET_KEY=             # 64 hex chars — same key used by generate_benem_link.py
MIDDLEWARE_URL=https://bhnm-apns.hurrikap.org
```

- [ ] **Step 5: Create `bhnm-apns/servers.json` on the server (not committed)**

```bash
# On the Linode server, in the bhnm-apns directory:
cp servers.json.example servers.json
# Edit servers.json with real credentials — this file is never committed
```

- [ ] **Step 6: Deploy and smoke test**

```bash
# On Linode server
git pull
docker compose build benem-admin
docker compose up -d
# Verify: curl https://<your-domain>/admin/health → 401 (Basic Auth required)
# Open https://<your-domain>/admin/ in browser
# Enter Basic Auth credentials → TOTP login page appears
# Enter TOTP code → Generate Link page loads
# Generate a link → QR code appears, entry appears in Log page
```

- [ ] **Step 7: Commit**

```bash
git add servers.json.example docker-compose.yml Caddyfile
git commit -m "feat: add benem-admin to docker-compose and Caddy config"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Docker container `benem-admin` | Task 1, 13 |
| Caddy Basic Auth (outer gate) | Task 13 |
| TOTP second factor + session cookie | Task 3, 7 |
| `servers.json` multi-server config | Task 4, 13 |
| Page 1: Generate Link with server selector, SF Symbol, colour, QR | Task 8 |
| Page 1: HTMX server URL update | Task 8 |
| Page 1: audit log entry on generate | Task 8 |
| Page 2: Connection Test (DNS, HTTPS, API) | Task 5, 9 |
| Page 3: Push Config (middleware URLs + device list) | Task 10 |
| Page 4: Log with pagination + server filter | Task 11 |
| Page 5: Settings — TOTP QR, version, restart button | Task 12 |
| Log format (truncated link, no full URL stored) | Task 4 |
| `BENEM_SECRET_KEY` / secrets strictly in env | Task 2, 13 |
| Restart button security trade-off | Task 12, 13 |
| bhnm-apns container untouched | ✓ (no changes to bhnm-apns code) |
| Named log volume | Task 13 |

**No spec gaps found.**

**Type consistency check:** `Server` dataclass defined in Task 4, used in Tasks 8–11. `TestResult` dataclass defined in Task 5, used in Task 9. `DeviceToken` defined in Task 4, used in Task 10. All consistent.

**Placeholder scan:** No TBD or TODO markers present in task code.
