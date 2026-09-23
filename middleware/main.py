import os

# The VERSION file is the single source of truth (see CLAUDE.md) — never
# hardcode the number here; a literal already drifted once (stuck at 2.6.1).
try:
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "VERSION")) as _f:
        VERSION = _f.read().strip()
except OSError:
    VERSION = "unknown"

from contextlib import asynccontextmanager
import base64
import hashlib
import json
import zlib
from urllib.parse import parse_qs, urlparse
import httpx
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import Response, JSONResponse
from pydantic import BaseModel, field_validator

from config import MIDDLEWARE_PORT, VAPID_PUBLIC_KEY, BHNM_TLS_VERIFY, SERVERS_JSON_PATH, PROXY_TIMEOUT, PROXY_TOKEN, BENEM_SECRET_KEY, server_cache_enabled, server_accepted_secrets
from database import init_db, save_token, get_tokens_for_secret, get_tokens_for_secrets, get_all_tokens, delete_token, \
    save_web_push_subscription, get_web_push_subscriptions_for_secret, \
    get_web_push_subscriptions_for_secrets, delete_web_push_subscription
from apns import send_to_all
from webpush import send_web_push_to_all
import asyncio
import time
import html as _html
import re
import logging.handlers
import sys
import incident_cache
import tactical_cache
import threshold_cache
import maintenance_cache
import diagnostics

HOP_BY_HOP_REQUEST = {
    "host", "x-proxy-token", "x-bhnm-target", "connection", "keep-alive",
    "proxy-authenticate", "proxy-authorization", "te", "trailers", "upgrade",
    # Never forward the client's Accept-Encoding: httpx negotiates its own
    # (gzip/deflate) and transparently decompresses the upstream body. If a
    # client's "br" leaks through, Traefik returns Brotli, httpx (no brotli
    # support) leaves it compressed, and we'd ship binary labeled as JSON.
    "accept-encoding",
}
HOP_BY_HOP_RESPONSE = {
    "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade",
    # httpx decompresses gzip automatically; strip these so Starlette sets
    # Content-Length from the actual (decompressed) body length.
    "content-encoding", "content-length",
}


def _target_for_api_key(api_key: str) -> str:
    """Look up BHNM server URL by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s.get("url", "").rstrip("/")
    except FileNotFoundError:
        print(f"[Config] servers.json not found at {SERVERS_JSON_PATH}")
    except json.JSONDecodeError as e:
        print(f"[Config] servers.json is not valid JSON: {e}")
    except Exception as e:
        print(f"[Config] Error reading servers.json: {e}")
    return ""


def _server_config_for_api_key(api_key: str) -> dict | None:
    """Look up full server config by api_key from servers.json."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == api_key:
                    return s
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return None


def _server_config_for_bhnm_url(bhnm_url: str) -> dict | None:
    """Look up full server config by BHNM URL from servers.json."""
    normalized = bhnm_url.rstrip("/")
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("url", "").rstrip("/") == normalized:
                    return s
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    return None


def _resolve_server_config(request: Request) -> dict | None:
    """Resolve server config from X-Proxy-Token (api_key) or X-BHNM-Target (url)."""
    api_key = request.headers.get("X-Proxy-Token", "").strip()
    cfg = _server_config_for_api_key(api_key)
    if cfg:
        return cfg
    bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
    if bhnm_target:
        return _server_config_for_bhnm_url(bhnm_target)
    return None


def secret_fingerprint(secret: str) -> str:
    """A short, non-reversible label for a webhook secret, for logs.

    NOT a prefix of the secret — a prefix is a piece of the secret, and 2.13.2 is
    the precedent for why that warning is written down rather than assumed. Eight
    hex characters of SHA-256 is enough to tell two secrets apart in a log and
    tells an attacker nothing.
    """
    if not secret:
        return "none"
    return hashlib.sha256(secret.encode()).hexdigest()[:8]


_CLIENT_BUILD_RE = re.compile(r"\bBeNeM/(\d{1,6})\b")


def log_client_build(request: Request | None, path: str) -> None:
    """Log which BeNeM build made this call — **the build number and nothing else.**

    This exists because the gate it serves did not work. The M1-drop gate was
    written as *"`BeNeM/53` disappearing and only `BeNeM/54`+ remaining is a
    measurement"*, and on 2026-09-22 it was measured and withdrawn (handoff (f)22):
    the only place this service logged a user-agent was
    `[Proxy] REFUSED target not in servers.json`, **a refusal path**. A fleet of
    perfectly working clients produces zero lines there, so "no `BeNeM/53` in the
    log" meant *no build 53 made a refused request* — an empty result that was
    never capable of being non-empty for the question being asked. The whole
    persisted log holds nine such lines, the last from build 46 on 2026-09-19,
    while build 54 had registered successfully the night before and appeared
    nowhere.

    So it is logged on the two paths **every** client takes: `/register` at launch
    and `/api/v1/incidents` on every list load. Absence here can mean something,
    which is the entire point.

    **The build number only, never the raw header and never a token.** The
    user-agent URLSession sends is `BeNeM/<build> CFNetwork/… Darwin/…`; the
    CFNetwork and Darwin versions say what OS the phone runs and are nobody's
    business in a log that gets grepped and pasted. A client with no `BeNeM/<n>`
    — a browser, a curl, a probe — logs `not-BeNeM` rather than its header.

    ponytail: one line per request, no dedupe state. ~5 phones loading a list
    every couple of minutes is a few hundred KB a day against a 5 MB x 5 rotation,
    so ~80 days of history, and the gate needs weeks. If it ever crowds the log
    out, dedupe per (build, hour) in a dict rather than dropping the line.
    """
    ua = request.headers.get("user-agent", "") if request is not None else ""
    match = _CLIENT_BUILD_RE.search(ua)
    client = f"BeNeM/{match.group(1)}" if match else "not-BeNeM"
    print(f"[Client] {client} on {path}")


def _servers_for_webhook_secret(secret: str) -> list[dict]:
    """Every server that accepts this webhook secret (S1 change 1a).

    Returns a LIST, deliberately, and never a single winner. While 1a seeds every
    server with the same secret, "which server sent this" has no answer — the
    first match is arbitrary, and a caller handed one `dict` would quietly build
    per-server behaviour on an arbitrary name. A list cannot be misread that way.
    Empty means no server lists it, including every servers.json predating 1a;
    the caller then falls back to the pre-1a single-secret lookup, because an
    unresolved webhook must still page the devices it pages today.
    """
    if not secret:
        return []
    return [s for s in _load_all_servers() if secret in server_accepted_secrets(s)]


def webhook_server_label(matches: list[dict]) -> str:
    """How the resolved server is named in the log.

    Exactly one match: the name, which is then meaningful. More than one: no name
    at all, because any name would be arbitrary. 1b makes secrets unique, at which
    point this always takes the first branch.
    """
    if len(matches) == 1:
        return str(matches[0].get("name") or matches[0].get("id") or "unnamed")
    return f"<ambiguous: {len(matches)} servers share this secret>"


def _load_all_servers() -> list[dict]:
    """All servers.json entries (the BHNM monitor covers every server,
    regardless of cache_enabled — health is independent of caching)."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            return json.load(f)
    except Exception:
        return []


def _single_server_url() -> str:
    """Return the URL of the only configured server, or '' if 0 or >1 servers."""
    try:
        with open(SERVERS_JSON_PATH) as f:
            servers = json.load(f)
        if len(servers) == 1:
            return servers[0].get("url", "").rstrip("/")
    except FileNotFoundError:
        print(f"[Config] servers.json not found at {SERVERS_JSON_PATH}")
    except json.JSONDecodeError as e:
        print(f"[Config] servers.json is not valid JSON: {e}")
    except Exception as e:
        print(f"[Config] Error reading servers.json: {e}")
    return ""


def _verify_proxy_token(request: Request) -> None:
    """Validate X-Proxy-Token against PROXY_TOKEN env var or any api_key in servers.json.

    Raises HTTPException(401) if the token is missing or invalid.
    """
    token = request.headers.get("X-Proxy-Token", "").strip()
    if not token:
        raise HTTPException(status_code=401, detail="X-Proxy-Token header is required")
    # Accept if it matches the global PROXY_TOKEN
    if PROXY_TOKEN and token == PROXY_TOKEN:
        return
    # Accept if it matches any api_key in servers.json
    try:
        with open(SERVERS_JSON_PATH) as f:
            for s in json.load(f):
                if s.get("api_key") == token:
                    return
    except (FileNotFoundError, json.JSONDecodeError, Exception):
        pass
    raise HTTPException(status_code=401, detail="Invalid proxy token")


_DEFAULT_PORTS = {"http": 80, "https": 443}


def _target_key(url: str) -> tuple[str, str, int] | None:
    """Normalised (scheme, host, port) for allowlist comparison, or None if unusable.

    Normalises case, a trailing slash, and the default port, so that
    `https://H/` and `https://h:443` are the same key. The scheme is part of the
    key on purpose: X-Proxy-Token rides on every proxied request and the BHNM
    api_key rides in proxied bodies as pwd=, so an http downgrade to a host
    configured as https would put a credential on the wire in cleartext.
    """
    parsed = urlparse(url.strip().rstrip("/"))
    scheme = (parsed.scheme or "").lower()
    host = (parsed.hostname or "").lower()
    if scheme not in _DEFAULT_PORTS or not host:
        return None
    try:
        port = parsed.port or _DEFAULT_PORTS[scheme]
    except ValueError:          # malformed port in the URL
        return None
    return (scheme, host, port)


class _AmbiguousServers(Exception):
    """Two servers in servers.json share an api_key, so a key cannot name one server."""


def _routing_servers() -> list[dict]:
    """servers.json, refused outright when an api_key cannot name exactly one server.

    Under key-target binding (2.17.0) a duplicate api_key is a **correctness bug, not
    a curiosity**: `_server_id_for_api_key` returns the FIRST match, so two servers
    sharing a key would bind a caller to whichever entry sorts first in the file —
    routing one operator's request to another operator's server and calling it
    correct.

    **Checked at load, not at startup**, because servers.json is a bind mount that
    benem-admin rewrites at runtime: a startup-only check passes at boot and is
    silently wrong for every edit after it. And it refuses rather than crashing,
    because webhook ingestion and APNs delivery do not depend on proxy routing —
    refusing proxy requests while continuing to page is strictly the better failure.
    See docs/evidence/2026-09-17-cross-server-key-reachability-defect.md 7.
    """
    with open(SERVERS_JSON_PATH) as f:
        servers = json.load(f)
    seen: set[str] = set()
    dupes: set[str] = set()
    for s in servers:
        key = s.get("api_key", "")
        if not key:
            continue
        (dupes if key in seen else seen).add(key)
    if dupes:
        # Fingerprints, never values: the same rule as secret_fingerprint's docstring.
        raise _AmbiguousServers(
            f"{len(dupes)} api_key(s) shared by more than one server "
            f"(fingerprints: {', '.join(sorted(secret_fingerprint(k) for k in dupes))})")
    return servers


def _proxy_allowlist() -> set[tuple[str, str, int]]:
    """Every configured server as a normalised key. Raises if servers.json is unusable."""
    return {key for s in _routing_servers() if (key := _target_key(s.get("url", "")))}


def _validate_proxy_target(target_url: str, request: Request | None = None) -> None:
    """Refuse any proxy target that is not a configured server, or not THIS caller's.

    **Two gates, in order: the allowlist, then key-target binding (2.17.0).** A
    request authenticated with a server's api_key may target only that server.

    **This is the single place the binding lives, and it is deliberate.** All six
    call sites route through here, including the cold-cache fall-throughs that read
    `target_base` from X-BHNM-Target while sending `server_cfg["api_key"]` — the
    caller's own credential. Those lines are NOT patched separately: once the target
    can only be the key's own server, A's key can only ever go to A, so the leak is
    closed by construction. A second guard beside `bhnm_api_key = ...` would be a new
    place for the two to disagree. See the defect note 6, ruling 3.

    **servers.json is the ALLOWLIST, not a bypass list.** There is deliberately no
    "resolves to a public address, therefore allowed" fall-through: that was the
    defect (evidence 8.18) and it made any api_key a relay token for the whole
    public internet, since _verify_proxy_token accepts any api_key in servers.json
    and those keys live on phones and in onboarding QR codes.

    **Nothing is resolved here.** A refused target must never reach DNS, so a
    client-supplied hostname is never handed to getaddrinfo.

    **A configured host is allowed whatever it resolves to, including a private
    address.** An on-prem BHNM legitimately sits on one. That is why the old
    private-address check is gone rather than kept for a second pass: with only
    configured hosts reaching past the allowlist, no path could reach it. This is
    NOT an oversight to tidy up — see
    docs/superpowers/specs/2026-09-17-proxy-target-allowlist-design.md 2.3 and 7.4.
    """
    try:
        servers = _routing_servers()
    except _AmbiguousServers as exc:
        # Same 503 as unreadable: both mean "I cannot route safely", and both must stay
        # distinct from the 403, which is about the caller's target and not the config.
        # The LOG is where the two are told apart.
        print(f"[Proxy] CONFIG AMBIGUOUS: {SERVERS_JSON_PATH} ({exc}) — refusing all proxy targets")
        raise HTTPException(status_code=503, detail="Server configuration unavailable")
    except Exception as exc:
        # Distinct from a refusal on purpose: "I cannot read my config" and "your
        # target is wrong" are different incidents, and the status code is where
        # that has to be visible, not only the log.
        print(f"[Proxy] CONFIG UNREADABLE: {SERVERS_JSON_PATH} ({exc}) — refusing all proxy targets")
        raise HTTPException(status_code=503, detail="Server configuration unavailable")

    allowed = {key for s in servers if (key := _target_key(s.get("url", "")))}
    ua = request.headers.get("user-agent", "(none)") if request is not None else "(none)"
    target = _target_key(target_url)

    if target not in allowed:
        # Full target and client in the log; a constant in the response. Echoing
        # the target back buys nothing and would confirm by probe which hosts are
        # configured. This log line is also the enumeration the log could not
        # produce before — it answers "which client is naming an unconfigured
        # host" without a packet capture.
        print(f"[Proxy] REFUSED target not in servers.json: {target_url!r} user-agent={ua!r}")
        raise HTTPException(status_code=403, detail="Proxy target is not a configured server.")

    # ── 2.17.0 — KEY-TARGET BINDING ───────────────────────────────────────────
    token = request.headers.get("X-Proxy-Token", "").strip() if request is not None else ""

    if PROXY_TOKEN and token == PROXY_TOKEN:
        # The operator token keeps multi-server access — that is its job. It is LOGGED
        # so operator cross-server use is visible rather than indistinguishable from a
        # client's. This is the only unbound path, and the log is what says so.
        print(f"[Proxy] OPERATOR TOKEN selected target: {target_url!r} user-agent={ua!r}")
        return

    own = next((_target_key(s.get("url", "")) for s in servers
                if s.get("api_key") and s.get("api_key") == token), None)
    if own != target:
        # Fail closed: an unmatched token (own is None) is refused, not waved through.
        # The detail is the SAME constant as the allowlist refusal, deliberately — a
        # caller must not be able to tell "not configured" from "not yours", or the
        # endpoint becomes a way to enumerate the other servers. The log tells them
        # apart; the response does not.
        print(f"[Proxy] REFUSED target not owned by this key: {target_url!r} user-agent={ua!r}")
        raise HTTPException(status_code=403, detail="Proxy target is not a configured server.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    incident_cache.start_all()
    tactical_cache.start_all()
    threshold_cache.start_all()
    maintenance_cache.start_all()
    for server in _load_all_servers():
        diagnostics.start_monitor(server, BHNM_TLS_VERIFY)
    global _delivery_queue, _delivery_worker
    _delivery_queue = asyncio.Queue(maxsize=DELIVERY_QUEUE_MAX)
    _delivery_worker = asyncio.create_task(_delivery_worker_loop())
    print(f"[Startup] BHNM APNs middleware v{VERSION} ready on port {MIDDLEWARE_PORT} — dynamic multi-server routing enabled")
    yield
    _delivery_worker.cancel()

app = FastAPI(lifespan=lifespan)


# ── Device Token Registration ─────────────────────────────────────────────────

# The only two values APNs has, and the only two /register accepts. The iOS
# client maps the ENTITLEMENT's vocabulary onto this one
# (AppDelegate.apnsEnvironment(forEntitlement:)) — "development" is an
# entitlement word, not an APNs host, and must never arrive here.
APNS_ENVIRONMENTS = ("sandbox", "production")

# A constant, so the refusal reads the same in every log and every test and
# cannot drift into leaking what was sent.
INVALID_APNS_ENVIRONMENT = "environment must be 'sandbox' or 'production'"


class TokenRegistration(BaseModel):
    token: str
    device_name: str = "unknown"
    environment: str = "production"

    @field_validator("token")
    @classmethod
    def token_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("token must not be empty")
        return v.strip()

@app.post("/register")
def register_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    # An environment we do not recognise is a DEFECT at the client, and
    # defaulting it to "production" is the worst possible response: a
    # development-entitlement token gets stored as production, APNs answers
    # 400 BadDeviceToken, 2.18.1's cleanup removes it, and push dies on that
    # phone. That is not hypothetical — it happened on 2026-09-21, when an iOS
    # build read `aps-environment` correctly and sent the entitlement's own
    # word, `development`, which this line silently turned into production.
    # Refuse it instead, so a wrong client fails loudly at registration rather
    # than quietly at the first incident.
    if body.environment not in APNS_ENVIRONMENTS:
        print(f"[Register] REFUSED ...{body.token[-8:]}: unknown environment "
              f"{body.environment!r} — must be one of {sorted(APNS_ENVIRONMENTS)}")
        raise HTTPException(status_code=400, detail=INVALID_APNS_ENVIRONMENT)
    env = body.environment
    matches = _servers_for_webhook_secret(active_secret)
    server_id = str(matches[0].get("id", "")) if len(matches) == 1 else ""
    save_token(body.token, body.device_name, active_secret, env, server_id)
    # Log the token suffix, as [Unregister], [APNs] and [Cleanup] all do. Without it
    # every registration in the log is anonymous and a token's history cannot be
    # reconstructed — tracing ...62f21e50 on 2026-09-15 had to be assembled from
    # 410s and a single lucky [Unregister].
    # Server and secret fingerprint (1a): this is the cheap signal that answers
    # "is anybody still on the old secret?" before 1b retires it — see the S1
    # spec, Part 17. The fingerprint is a hash, never the secret.
    where = webhook_server_label(matches) if matches else "unresolved"
    print(f"[Register] Token saved: ...{body.token[-8:]} for {body.device_name} (APNs: {env}) "
          f"server={where} secret_fp={secret_fingerprint(active_secret)}")
    log_client_build(request, "/register")
    return {"status": "ok"}


@app.delete("/register")
def unregister_token(body: TokenRegistration, request: Request):
    active_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not active_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    delete_token(body.token)
    print(f"[Unregister] Token removed: ...{body.token[-8:]}")
    return {"status": "ok"}


# ── Web Push Subscription Registration ───────────────────────────────────────

class WebPushRegistration(BaseModel):
    endpoint: str
    p256dh: str
    auth: str

    @field_validator("endpoint")
    @classmethod
    def endpoint_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("endpoint must not be empty")
        return v.strip()


@app.post("/register-webpush", status_code=201)
def register_webpush(body: WebPushRegistration, request: Request, response: Response):
    webhook_secret = request.headers.get("X-Webhook-Token", "").strip()
    if not webhook_secret:
        raise HTTPException(status_code=400, detail="X-Webhook-Token header is required")
    existing = get_web_push_subscriptions_for_secret(webhook_secret)
    is_update = any(s["endpoint"] == body.endpoint for s in existing)
    matches = _servers_for_webhook_secret(webhook_secret)
    server_id = str(matches[0].get("id", "")) if len(matches) == 1 else ""
    save_web_push_subscription(body.endpoint, body.p256dh, body.auth, webhook_secret, server_id)
    if is_update:
        response.status_code = 200
    where = webhook_server_label(matches) if matches else "unresolved"
    print(f"[WebPush] Subscription {'updated' if is_update else 'registered'}: {body.endpoint[:50]}... "
          f"server={where} secret_fp={secret_fingerprint(webhook_secret)}")
    return {"status": "ok"}

@app.get("/vapid-key")
def get_vapid_key():
    import config
    if not config.VAPID_PUBLIC_KEY:
        raise HTTPException(status_code=404, detail="Web Push not configured")
    return {"publicKey": config.VAPID_PUBLIC_KEY}


# ── BHNM Webhook ──────────────────────────────────────────────────────────────

# -- Host-side log -------------------------------------------------------------
# Container stdout dies with the container. Two deploys (2026-09-03, 2026-09-14)
# erased the webhook evidence we were in the middle of measuring, so everything
# printed here is also appended to a rotated file on the bind-mounted host path.

HOST_LOG_PATH = os.environ.get("HOST_LOG_PATH", "/logs/middleware.log")
# /data is the SQLite volume and is always writable by appuser; the bind mount is
# only writable if the host directory is owned by the container user.
FALLBACK_LOG_PATH = "/data/middleware.log"

# The webhook secret rides in the query string, so uvicorn's access line contains
# it verbatim. Keep it out of stdout and out of the persisted log.
_SECRET_RE = re.compile(r"((?:secret|token|password|key|pwd)=)[^&\s\"']+", re.I)


def _redact(text: str) -> str:
    return _SECRET_RE.sub(r"\1<redacted>", text)


class _RedactingFilter(logging.Filter):
    def filter(self, record):
        try:
            if isinstance(record.msg, str):
                record.msg = _redact(record.msg)
            if isinstance(record.args, tuple):
                record.args = tuple(_redact(a) if isinstance(a, str) else a for a in record.args)
        except Exception:
            pass
        return True


class _StdoutTee:
    """Write through to the real stdout and to a rotated file."""

    def __init__(self, stream, path: str):
        self._stream = stream
        handler = logging.handlers.RotatingFileHandler(
            path, maxBytes=5_000_000, backupCount=5)
        handler.setFormatter(logging.Formatter("%(asctime)sZ %(message)s"))
        handler.formatter.converter = time.gmtime
        log = logging.getLogger("benem.stdout")
        log.setLevel(logging.INFO)
        log.propagate = False
        log.addHandler(handler)
        self._log = log

    def write(self, data):
        self._stream.write(data)
        text = data.rstrip("\n")
        if text:
            try:
                self._log.info(_redact(text))
            except Exception:
                pass

    def flush(self):
        self._stream.flush()

    def isatty(self):
        return False


def _install_host_log() -> None:
    logging.getLogger("uvicorn.access").addFilter(_RedactingFilter())
    logging.getLogger("uvicorn.error").addFilter(_RedactingFilter())
    for path in (HOST_LOG_PATH, FALLBACK_LOG_PATH):
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            sys.stdout = _StdoutTee(sys.stdout, path)
            print(f"[Log] Mirroring stdout to {path}")
            return
        except Exception as e:
            print(f"[Log] {path} unavailable ({e})")
    print("[Log] No persistent log available; stdout only")


_install_host_log()


# -- BHNM text -----------------------------------------------------------------
# BHNM 26.3.01 emits HTML in the plain-text {OUTPUT} macro
# ("<br />Ping CRITICAL: Packet Loss 100%"), which reaches the lock screen as
# literal markup. The incident API's own data is clean, so this is scoped to
# Action macro text. Thomas is filing the defect with BHNM.
#
# Line breaks are preserved rather than flattened: the likely BHNM fix is to emit
# a real newline instead of "<br />", and collapsing all whitespace would swallow
# that fix so it never reached the screen.

_BREAK_RE = re.compile(r"<\s*(?:br\s*/?|/\s*p)\s*>", re.I)
_TAG_RE = re.compile(r"<[^>]+>")


def clean_bhnm_text(value) -> str:
    """Turn BHNM's HTML-ish output into plain text, keeping real line breaks."""
    text = _BREAK_RE.sub("\n", str(value or ""))
    text = _TAG_RE.sub(" ", text)
    text = _html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)          # spaces/tabs only — never newlines
    text = re.sub(r"[ \t]*\n[ \t]*", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


# Sends are sequential at ~0.5s each, so this covers roughly a hundred devices.
# It exists to make a stall loud, not to bound normal work.
FANOUT_TIMEOUT = 60.0


# ── Delivery queue: ONE worker, one fan-out at a time ─────────────────────────
#
# APNs caps HTTP/2 stream concurrency per connection, and with token-based
# authentication Apple documents that it "allows only one stream until you post a
# request with a valid authentication token". Concurrent POSTs down the shared
# connection therefore wedge: the first completes and the rest never return, with
# httpx's own timeouts not firing (traced in evidence §3.8).
#
# 2.13.4 made sends sequential *inside* one fan-out, which is not enough — two
# webhooks arriving in the same second each start their own fan-out and the two
# race on the same client. Measured 2026-09-15: both stalled ~3 sends in and were
# abandoned by the 60s guard; the two newest devices got nothing (§3.9). A site
# outage raises several host alerts in the same second, so this is the normal
# case, not a corner.
#
# One consumer task drains a bounded queue. Not a lock: a lock would make every
# alert wait behind every other one with no way to tell lock-wait from send-stall,
# and FANOUT_TIMEOUT would then be measuring the wrong thing. With a queue nothing
# waits on anything — the per-job timeout covers only that job's own sending.

# This bound exists for STALLED DELIVERY, not for a legitimate flood. Do not raise
# it to "absorb more alerts" — that fixes the wrong side.
#
# BHNM performs its own alarm reduction (correlation, parenting, incident-criteria
# rules), so a correctly configured server does not emit hundreds of simultaneous
# notifications. If one does, that is a BHNM misconfiguration, and hiding it behind
# a bigger queue here would turn a server-side fault into silent latency. Reaching
# this bound at all should be treated as a signal, not as capacity to be increased.
#
# What it does guard: while APNs is unreachable the worker cannot drain, and without
# a bound the queue would grow until the process died. The warning below is the part
# that actually matters in practice.
# Known ceiling, tracked in CHANGELOG.md under 2.14.0 "Known issue — carried
# forward": this discards by count, not by age. While APNs is stalled each job burns
# the whole FANOUT_TIMEOUT, so every queued job pushes the next one a further minute
# late — ten queued alerts is ten minutes of drain, and the one at the back arrives
# as history. (Not the multi-hour figure a full 256-job queue would imply: getting
# anywhere near the bound would itself be the BHNM misconfiguration described above.)
# Fix is to stamp jobs with an arrival time and discard stale ones on dequeue.
DELIVERY_QUEUE_MAX = 256
DELIVERY_QUEUE_WARN = 32   # depth at which a backlog stops being normal

_delivery_queue: asyncio.Queue | None = None
_delivery_worker: asyncio.Task | None = None


def _enqueue_delivery(tokens, web_push_subs, title: str, body: str, incident_id: str) -> bool:
    """Hand a fan-out to the worker. False means it was dropped — never silently."""
    if _delivery_queue is None:
        print("[Deliver] DROPPED — delivery worker is not running; "
              f"incident {incident_id or '?'} notified nobody")
        return False
    try:
        _delivery_queue.put_nowait((tokens, web_push_subs, title, body, incident_id))
    except asyncio.QueueFull:
        print(f"[Deliver] QUEUE FULL ({DELIVERY_QUEUE_MAX}) — DROPPED incident "
              f"{incident_id or '?'}, {len(tokens)} token(s), "
              f"{len(web_push_subs)} subscription(s). Nobody was paged for it.")
        return False
    depth = _delivery_queue.qsize()
    if depth >= DELIVERY_QUEUE_WARN:
        print(f"[Deliver] BACKLOG — {depth}/{DELIVERY_QUEUE_MAX} jobs queued; "
              f"delivery is falling behind")
    return True


async def _delivery_worker_loop() -> None:
    """Drain the queue forever, one fan-out at a time."""
    print("[Deliver] Worker started")
    while True:
        tokens, web_push_subs, title, body, incident_id = await _delivery_queue.get()
        try:
            await asyncio.wait_for(
                _fan_out(tokens, web_push_subs, title, body, incident_id),
                timeout=FANOUT_TIMEOUT)
        except asyncio.TimeoutError:
            # A stall must be loud. The previous one was silent for months.
            print(f"[Deliver] TIMEOUT after {FANOUT_TIMEOUT}s — fan-out abandoned for "
                  f"incident {incident_id or '?'}, {len(tokens)} token(s), "
                  f"{len(web_push_subs)} subscription(s)")
        except asyncio.CancelledError:
            raise
        except Exception as e:
            # One bad job must never kill the worker — that would silence every
            # alert after it.
            print(f"[Deliver] Fan-out failed: {type(e).__name__}: {e}")
        finally:
            _delivery_queue.task_done()


async def _fan_out(tokens, web_push_subs, title: str, body: str, incident_id: str) -> None:
    if tokens:
        for token in await send_to_all(tokens, title, body, incident_id):
            delete_token(token)
            print(f"[Cleanup] Removed stale APNs token ...{token[-8:]}")
    if web_push_subs:
        for endpoint in await send_web_push_to_all(web_push_subs, title, body, incident_id):
            delete_web_push_subscription(endpoint)
            print(f"[Cleanup] Removed expired Web Push subscription: {endpoint[:50]}...")


@app.post("/webhook")
async def receive_webhook(request: Request):
    secret = request.query_params.get("secret", "").strip()
    if not secret:
        raise HTTPException(status_code=400, detail="?secret= query parameter is required")

    # Parse body — try JSON first, fall back to form-encoded.
    # BHNM may send JSON without the Content-Type: application/json header.
    body = await request.body()
    data = {}
    try:
        data = json.loads(body)
    except (json.JSONDecodeError, ValueError):
        parsed = parse_qs(body.decode("utf-8", errors="replace"))
        data = {k: v[0] if v else "" for k, v in parsed.items()}

    # 2.11.1 — hygiene, not security (?secret= is still the only gate): a body
    # that decodes to something other than an object (JSON scalar/array), or
    # to an object without a hostname (garbage form-decodes to {}), used to be
    # pushed as a PROBLEM for "Unknown device". Reject it instead. Logged
    # scrubbed: content-type and length only, never the body.
    if not isinstance(data, dict) or not str(data.get("hostname", "")).strip():
        print(f"[Webhook] Rejected: no hostname in decoded body "
              f"(content-type={request.headers.get('content-type', '')!r}, {len(body)} bytes)")
        raise HTTPException(status_code=422,
                            detail="payload must be a JSON object or form with a non-empty hostname")

    notification_type    = str(data.get("notification_type", "PROBLEM")).strip().upper()
    hostname             = str(data["hostname"]).strip()
    host_state           = data.get("host_state", "")
    site                 = clean_bhnm_text(data.get("site", ""))
    service_desc         = clean_bhnm_text(data.get("service_desc", ""))
    output               = clean_bhnm_text(data.get("output", ""))
    incident_id          = str(data.get("incident_id", ""))
    primary_alarm_status = str(data.get("primary_alarm_status", "")).strip()

    # BHNM's macro reference documents UNACKNOWLEDGEMENT; the wire carries
    # DEACKNOWLEDGEMENT. Accept both — neither may reach the problem branch.
    unack = notification_type in ("DEACKNOWLEDGEMENT", "UNACKNOWLEDGEMENT")

    # Renotifications carry a 1-based counter; absent or unparseable means first notice.
    try:
        notice = int(str(data.get("notification_number", "")).strip() or 1)
    except ValueError:
        notice = 1

    # Build human-readable notification
    if notification_type == "RECOVERY":
        title = f"Resolved: {hostname}"
        body  = f"{service_desc or 'Host'} recovered. {output}".strip()
    elif notification_type == "ACKNOWLEDGEMENT":
        title = f"Acknowledged: {hostname}"
        body  = output or service_desc or host_state
    elif unack:
        # BHNM leaves host_state at DOWN on this one, so the problem branch would
        # render it identically to a fresh outage. It is not one.
        title = f"Unacknowledged: {hostname}"
        body  = output or primary_alarm_status
    else:
        # PROBLEM, CRITICAL, WARNING
        emoji = "🔴" if host_state in ("DOWN", "UNREACHABLE") else "⚠️"
        state = host_state or notification_type
        title = (f"{emoji} {hostname} — still {state} (notice {notice})" if notice > 1
                 else f"{emoji} {hostname} — {state}")
        body  = f"{service_desc or output or ''} | Site: {site}".strip(" |")

    print(f"[Webhook] {notification_type} — {hostname} — Incident {incident_id}")

    # Patch the cached incident so the list reflects the new state before the next
    # poll. The poll remains the source of truth and overwrites this.
    cache_state = {"ACKNOWLEDGEMENT": "ACKNOWLEDGED", "RECOVERY": "CLOSED"}.get(
        notification_type, "OPEN" if unack else None)
    if cache_state and incident_id:
        n = incident_cache.note_state_override_any_server(incident_id, cache_state)
        if n:
            print(f"[Webhook] Cache patched: incident {incident_id} -> {cache_state} ({n} server(s))")
        else:
            # LOUD on purpose. This branch used to be `if n:` with no else, so an
            # incident acknowledged before its first cache cycle produced no patch,
            # no log and no error — an unchecked return value of zero, which is how
            # it stayed invisible. It is not an error now: the override is pending
            # and applies on first sighting. It is logged because "nothing to patch"
            # and "patched" must never look the same.
            print(f"[Webhook] Cache not patched: incident {incident_id} is in no cache yet — "
                  f"override -> {cache_state} recorded as pending, applies on first sighting "
                  f"within {incident_cache.STATE_OVERRIDE_TTL}s")

    # S1 change 1a: resolve which server this webhook came from, and fan out over
    # every secret that server accepts. While each server's list holds only the
    # seeded global secret this selects exactly the devices the single-secret
    # lookup selected — the mechanism lands with no behavioural change. A secret
    # no server lists (any servers.json predating 1a) falls back to that lookup
    # rather than paging nobody.
    matches = _servers_for_webhook_secret(secret)
    if matches:
        # Union of every matching server's accepted list. While the lists are
        # identical (1a) this is the same set either way.
        accepted = sorted({x for m in matches for x in server_accepted_secrets(m)})
        tokens = get_tokens_for_secrets(accepted)
        web_push_subs = get_web_push_subscriptions_for_secrets(accepted)
        # secret_fp=, not secret=: the 2.13.2 redaction filter rewrites anything
        # matching `secret=…`, which silently blanked this fingerprint in the
        # mirrored host log — the one log that survives a container recreate and
        # therefore the only one that can answer "is anybody still on the old
        # secret?" over a week. The fingerprint is a hash and is safe to keep.
        print(f"[Webhook] server={webhook_server_label(matches)} "
              f"secret_fp={secret_fingerprint(secret)}")
    else:
        tokens = get_tokens_for_secret(secret)
        web_push_subs = get_web_push_subscriptions_for_secret(secret)
        # LOUD on purpose, every single time. This fallback is 1a's safety net and
        # 1b's obstacle: while it exists, a device still holding the global secret
        # keeps being paged through it, so retiring that secret splits nothing.
        # The count of devices still on the old path has to be visible in the log
        # rather than inferred from who remembers re-scanning. 1b deletes this
        # branch and refuses an unresolvable secret — see the S1 spec, Part 17.
        print(f"[Webhook] FALLBACK — no server lists secret_fp={secret_fingerprint(secret)}; "
              f"using the pre-1a single-secret lookup. This path must be empty before "
              f"S1 change 1b retires the global secret.")

    if not tokens and not web_push_subs:
        print(f"[Webhook] No registered devices for this secret — nothing to notify.")
        return {"status": "ok", "notified": 0}

    # Answer BHNM now; deliver afterwards. BHNM times out at ~30s and retries
    # three times, and a retry is a duplicate alert on every engineer's phone.
    queued = _enqueue_delivery(tokens, web_push_subs, title, body, incident_id)

    notified = len(tokens) + len(web_push_subs)
    if not queued:
        return {"status": "dropped", "notified": 0}
    print(f"[Webhook] Queued delivery to {notified} target(s) for incident {incident_id}")
    return {"status": "ok", "notified": notified}


# ── Health Check ──────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Liveness and version. UNAUTHENTICATED, so it carries nothing else.

    It used to also return `registered_devices` (a FLEET-WIDE count across every
    tenant), `apns_environment`, and `cache` / `tactical_cache` keyed by server_id
    with per-server open-incident counts, cache ages and estate topology sizes. To
    an anonymous caller that is the server_id of every cache-enabled customer plus
    their live incident count rising and falling in real time — operational
    intelligence about somebody else's network, one GET away, with no credential.
    Audited field by field in docs/evidence/2026-09-18-health-endpoint-audit.md.

    **The version stays and is load-bearing**: every deploy record this week read
    the deployed version from here, and a deploy that cannot state what it deployed
    is the failure mode the root CLAUDE.md doctrine is about.

    Everything operational lives behind `_verify_proxy_token` on
    `/api/v1/diagnostics`, where 2.17.0's key-target binding already scopes
    per-server state to the caller's own server.
    """
    return {"status": "running", "version": VERSION}


# ── Cached Incidents Endpoint ────────────────────────────────────────────────

@app.get("/api/v1/incidents")
@app.post("/api/v1/incidents")
async def cached_incidents(request: Request):
    """Return enriched incidents from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)
    # AFTER the auth check, so an unauthenticated caller cannot write lines into
    # the log by asking. Before every return, so the cache-hit path — the one
    # every healthy client actually takes — is the one that logs.
    log_client_build(request, "/api/v1/incidents")

    # Resolve server: try api_key first, then BHNM URL from X-BHNM-Target header
    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = incident_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = incident_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = incident_cache.get_cached(server_id)
        if cached:
            return {
                "cache_age_seconds": round(time.time() - cached.last_updated),
                "active_incidents": cached.active_incidents,
                "closed_incidents": cached.closed_incidents,
            }

    # Cache cold or server not found — fetch live from BHNM.
    # The client sends a header-only GET (no form body), so we must build
    # the proper form-encoded POST that the BHNM incident API expects.
    # Note: X-Proxy-Token may be a webhook secret, not the BHNM api_key,
    # so we resolve the server config by API key OR BHNM URL to get the real credentials.
    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base, request)

    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key
    form = {"pwd": bhnm_api_key, "method": "getincidents"}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/api/incident_api.php"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    return Response(content=resp.content, status_code=resp.status_code,
                    headers={k: v for k, v in resp.headers.items()
                             if k.lower() not in HOP_BY_HOP_RESPONSE})


@app.post("/api/v1/incidents/refresh")
async def refresh_incidents(request: Request):
    """C7's Refresh control / M2's list-only refresh — ONE endpoint, not two.

    A Refresh tap or the app coming to the foreground lands here. It performs a
    single `getincidents` for the caller's server, rate-limited server-side to
    one per server per 30 s, and makes **no** `getincidentdetail` call. That is
    what makes it fast enough to be a refresh: the list is one request whatever
    the estate size, enrichment is one request per incident.

    **It is independent of the polling switch on purpose.** [MEASURED
    2026-09-21, BHNM-B] BHNM sends no webhook for the `ALARMS CLEARED`
    transition — incidents 30008–30011 went WARNING at 15:40Z and RECOVERY at
    16:16Z with nothing in between while BHNM's own list showed them cleared —
    so under webhook mode a list call is the ONLY way that state can arrive.

    Returns the same shape as `GET /api/v1/incidents` plus `coalesced`, so one
    tap is one round trip and the client parses one payload shape. `coalesced`
    is true when the answer came from a refresh inside the 30 s window rather
    than from a fresh upstream call — the response says which, rather than
    letting a cached answer pass as a new measurement.
    """
    _verify_proxy_token(request)
    # C20 — the refresh endpoint logs a [Client] line too. Without it the call
    # cannot be attributed: on 2026-09-23 the refresh at 07:00:37.783Z was the
    # reason iOS saw incident 30045 and the PWA did not, and the log could not
    # say which client made it. /register and GET /api/v1/incidents gained the
    # line in 2.20.1; this route was missed.
    log_client_build(request, "/api/v1/incidents/refresh")

    server_cfg = _resolve_server_config(request)
    if not server_cfg or not server_cfg.get("id"):
        # No registry entry means no api_key and no id to rate-limit per server.
        # A refresh that cannot name its server cannot be single-flighted, and
        # an un-flighted refresh is a client-driven hammer on BHNM.
        raise HTTPException(status_code=404, detail="no configured server for this token")

    _validate_proxy_target(server_cfg.get("url", ""), request)

    try:
        return await incident_cache.refresh_server(server_cfg)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except (httpx.RequestError, ValueError, KeyError) as e:
        print(f"[Refresh] {server_cfg['id']} upstream unavailable: {type(e).__name__}: {e}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")


@app.get("/api/v1/incidents/{incident_id}")
async def single_incident(incident_id: str, request: Request):
    """One incident, fetched live from BHNM, with 404 and 502 kept DISTINCT.

    The list route above cannot answer this. A tap can beat the cache cycle, the
    cache can be cold after a restart, caching can be off for the server, or the
    notification can be hours old and name an incident that has since closed and
    gone. Collapsing "it does not exist" into "we could not reach BHNM" is what
    produces the lie the clients then render: `Incident not found.` said to
    someone whose network was simply down.

    404 {"error": "incident_not_found"} — a TERMINAL fact.
    502 {"error": "upstream_unavailable"} — ask again later.

    [MEASURED 2026-09-19 against the lab] BHNM answers a missing incident with
    HTTP 200 and a body carrying `result: completed` and NO `incident` key
    ({"result":"completed","detail":"No active incident."}). So the 404 signal is
    structural, not a status code. Note the wording is "No active incident": BHNM
    is not known to distinguish "never existed" from "closed and purged", and
    this route does not pretend to either — both are 404, because both mean the
    same thing to a client holding a notification, and the client copy says "no
    longer exists" rather than "not found".
    """
    _verify_proxy_token(request)

    numeric_id = incident_cache.normalise_incident_id(incident_id)
    if not numeric_id.isdigit():
        raise HTTPException(status_code=400, detail="incident_id must be numeric")

    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base, request)

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server = {
        "id": (server_cfg or {}).get("id", ""),
        "url": target_base,
        "api_key": server_cfg["api_key"] if server_cfg else api_key,
        "pin": (server_cfg or {}).get("pin") if server_cfg else None,
    }

    form = {"pwd": server["api_key"], "method": "getincidentdetail", "incident_id": numeric_id}
    if server.get("pin"):
        form["pin"] = server["pin"]

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(f"{target_base}/api/incident_api.php", data=form)
            if resp.status_code >= 400:
                raise httpx.RequestError(f"HTTP {resp.status_code}")
            data = resp.json()
            if isinstance(data, list):
                data = data[0] if data else {}
            raw = data.get("incident") if isinstance(data, dict) else None
            if not raw:
                print(f"[Incident] {numeric_id} not found on {server['id'] or target_base}")
                return JSONResponse(status_code=404, content={"error": "incident_not_found"})
            detail = await incident_cache._fetch_incident_detail(client, server, numeric_id)
    except (httpx.RequestError, ValueError, KeyError) as e:
        # Deliberately NOT collapsed into 404. The client renders these two
        # differently and must: one is terminal, the other is "ask again later".
        print(f"[Incident] {numeric_id} upstream unavailable: {type(e).__name__}: {e}")
        return JSONResponse(status_code=502, content={"error": "upstream_unavailable"})

    # List-shaped row from the detail response, which carries every list field
    # plus the ack block. open_time is the one rename: the list calls it
    # open_time, the detail calls it incident_open_time. [MEASURED 2026-09-19]
    row = {k: raw.get(k) for k in ("incident_id", "incident_state", "title", "name",
                                   "device_category", "device_site", "device_note")}
    row["open_time"] = raw.get("incident_open_time") or raw.get("open_time")
    for k in ("acknowledged", "ack_time", "ack_user", "ack_comment"):
        row[k] = raw.get(k)

    if detail.get("confirmed") and detail.get("alert_type"):
        incident_cache.remember_type(server["id"], numeric_id, detail["alert_type"])
    enriched = incident_cache._enrich_incident(
        row, detail, time.time(),
        remembered=incident_cache.known_type(server["id"], numeric_id))

    # Merge, so the tap benefits the list too. A cold cache has nothing to merge
    # into and that is not an error — the caller still gets its answer.
    if server["id"]:
        merged = incident_cache.merge_incident(server["id"], enriched)
        if not merged:
            print(f"[Incident] {numeric_id} fetched but not merged — "
                  f"no cache for {server['id']} yet")

    return enriched


@app.post("/internal/cache/reload")
async def cache_reload(request: Request):
    """Trigger cache reload for a server. Called by admin portal (internal only)."""
    _verify_proxy_token(request)
    try:
        body = await request.json()
    except Exception:
        body = {}
    server_id = body.get("server_id", "")
    if not server_id:
        raise HTTPException(status_code=400, detail="server_id is required")
    incident_cache.reload_server(server_id)
    tactical_cache.reload_server(server_id)
    threshold_cache.reload_server(server_id)
    maintenance_cache.reload_server(server_id)
    diagnostics.reload_monitor(server_id, _load_all_servers(), BHNM_TLS_VERIFY)
    return {"status": "ok", "server_id": server_id}


@app.post("/api/v1/qr-redeem")
async def qr_redeem(request: Request):
    """Decrypt a compact QR config blob server-side so the key never enters the PWA bundle."""
    if not BENEM_SECRET_KEY:
        raise HTTPException(status_code=503, detail="QR decryption is not configured on this server")
    try:
        key = bytes.fromhex(BENEM_SECRET_KEY)
    except ValueError:
        raise HTTPException(status_code=503, detail="QR decryption is not configured on this server")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Request body must be JSON")

    blob_b64url = body.get("blob", "").strip()
    if not blob_b64url:
        raise HTTPException(status_code=400, detail="blob is required")

    try:
        pad = (4 - len(blob_b64url) % 4) % 4
        raw = base64.urlsafe_b64decode(blob_b64url + "=" * pad)
        nonce, ct = raw[:12], raw[12:]
        compressed = AESGCM(key).decrypt(nonce, ct, None)
        return json.loads(zlib.decompress(compressed))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid or undecryptable QR payload")


# ── Cached Tactical Overview Endpoint ──────────────────────────────────────

@app.get("/api/v1/tactical-overview")
async def cached_tactical_overview(request: Request, grouping_type: str = "category"):
    """Return tactical overview from cache; fall through to live BHNM if cache is cold."""
    _verify_proxy_token(request)

    if grouping_type not in ("category", "site", "app"):
        raise HTTPException(status_code=400, detail="grouping_type must be category, site, or app")

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = tactical_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = tactical_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = tactical_cache.get_cached(server_id, grouping_type)
        if cached:
            data, ts = cached
            return {
                "cache_age_seconds": round(time.time() - ts),
                "grouping_type": grouping_type,
                "data": data,
            }

    # Cache cold or server not found — fetch live from BHNM.
    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base, request)

    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key
    form = {"password": bhnm_api_key, "grouping_type": grouping_type}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/fw/index.php?r=restful/tactical-overview/data"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    return Response(content=resp.content, status_code=resp.status_code,
                    headers={k: v for k, v in resp.headers.items()
                             if k.lower() not in HOP_BY_HOP_RESPONSE})


# ── Cached Maintenance Map Endpoint ───────────────────────────────────────

@app.get("/api/v1/maintenance-map")
async def cached_maintenance_map(request: Request):
    """Maintenance map + host state from the background cache.

    Response: {"cache_age_seconds": N | null,
               "in_maintenance": ["name", ...],
               "scheduled": [{"name", "start_time", "end_time"}, ...],
               "host_down": ["name", ...]}     # 2.12.0, additive; UP is never served
    Deliberately NO live fall-through on a cold cache (that would be one
    upstream call per category, in-request): cold or unresolved server →
    empty lists, which render as "no state shown" — safe. Clients must
    treat host_down as unusable when cache_age_seconds is null or > 300.
    """
    _verify_proxy_token(request)

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = maintenance_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = maintenance_cache._server_id_for_bhnm_url(bhnm_target)

    cached = maintenance_cache.get_cached(server_id) if server_id else None
    active = cached.names if cached else set()
    scheduled = maintenance_cache.get_scheduled(server_id, active_names=active) if server_id else []
    return {
        "cache_age_seconds": round(time.time() - cached.last_updated) if cached else None,
        "in_maintenance": sorted(active),
        "scheduled": scheduled,
        "host_down": sorted(cached.down) if cached else [],
    }


# ── Cached Threshold Counts Endpoint ──────────────────────────────────────

@app.get("/api/v1/threshold-counts")
async def cached_threshold_counts(request: Request):
    """Return per-device threshold counts from cache; fall through to live BHNM if cold.

    Response: {"cache_age_seconds": N, "counts": {"deviceName": count, ...}}
    When cache is cold the CSV is fetched live, parsed, and returned as JSON.
    """
    _verify_proxy_token(request)

    api_key = request.headers.get("X-Proxy-Token", "").strip()
    server_id = threshold_cache._server_id_for_api_key(api_key)
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = threshold_cache._server_id_for_bhnm_url(bhnm_target)

    if server_id:
        cached = threshold_cache.get_cached(server_id)
        if cached:
            return {
                "cache_age_seconds": round(time.time() - cached.last_updated),
                "counts": cached.counts,
            }

    # Cache cold or server not found — fetch live from BHNM and parse on the fly.
    server_cfg = _resolve_server_config(request)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    _validate_proxy_target(target_base, request)

    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key
    form: dict[str, str] = {"password": bhnm_api_key}
    pin = (server_cfg or {}).get("pin") if server_cfg else None
    if pin:
        form["pin"] = pin

    target = f"{target_base}/fw/index.php?r=restful/devices/list-thresholds-csv"
    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.post(target, data=form)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError:
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    # Parse CSV server-side and return compact JSON
    counts: dict[str, int] = {}
    for line in resp.text.splitlines()[1:]:
        if not line.strip():
            continue
        parts = line.split(",")
        if len(parts) >= 5:
            device_name = parts[4].strip()
            if device_name:
                counts[device_name] = counts.get(device_name, 0) + 1

    return {"cache_age_seconds": None, "counts": counts}


@app.get("/api/v1/diagnostics")
async def diagnostics_endpoint(request: Request):
    """Connection diagnostics — app→middleware→BHNM. The BHNM hop comes from the
    background monitor's cached probe result; feeds are passive cache telemetry
    (detail only). This route only READS — it never awaits a live probe, so it
    is uniformly fast and safe to poll.

    Fully isolated: its own try/except (never raises into the app), reads cache
    telemetry read-only. The payload carries only counts/booleans/timestamps/
    latency and scrubbed, truncated error strings — no secrets, host only
    (never the full URL)."""
    _verify_proxy_token(request)  # api_key (or PROXY_TOKEN) as X-Proxy-Token
    # No `registered_devices`: it is a fleet-wide count across every tenant, so it
    # is not the caller's business on any client-facing endpoint. The admin portal
    # keeps it, read from its own database (benem-admin push_db.get_registered_devices).
    middleware_block = {
        "version": VERSION,
        "server_time": int(time.time()),
    }
    try:
        server_cfg = _resolve_server_config(request) or {}
        target_base = (server_cfg.get("url", "") or _single_server_url()).rstrip("/")
        server_id = server_cfg.get("id", "")
        # unresolved server ({}) is never "cached"; a resolved one follows the
        # single default in config.server_cache_enabled (ON unless set false)
        cache_enabled = bool(server_cfg) and server_cache_enabled(server_cfg)
        host = urlparse(target_base).hostname or ""

        def _age(ts):
            return round(time.time() - ts) if ts else None

        # per-feed freshness (read-only snapshot)
        ic = incident_cache.get_cached(server_id) if server_id else None
        tc = tactical_cache.get_cached(server_id, "category") if server_id else None
        th = threshold_cache.get_cached(server_id) if server_id else None
        mm = maintenance_cache.get_cached(server_id) if server_id else None
        # C9 — the incidents feed reports the age of its STALEST member, not the
        # age of the last cycle stamp. The old single stamp was accurate only for
        # the last incident enriched and was reported as though it described all
        # of them. list_age_seconds is the separate, always-current fact: the list
        # call is unconditional, so state is young even when enrichment is old.
        ic_oldest, ic_unconfirmed = incident_cache.freshness(ic) if ic else (None, 0)
        feeds = {
            "incidents": {
                **diagnostics.feed_block(
                    server_id, "incidents", cached=cache_enabled and ic is not None,
                    age_seconds=_age(ic_oldest) if ic else None,
                    count=len(ic.active_incidents) if ic else None),
                "list_age_seconds": _age(ic.list_updated) if ic else None,
                "unconfirmed_counts": ic_unconfirmed if ic else None,
            },
            "tactical": diagnostics.feed_block(
                server_id, "tactical", cached=cache_enabled and tc is not None,
                age_seconds=_age(tc[1]) if tc else None,
                count=len(tc[0]) if tc else None),
            "thresholds": diagnostics.feed_block(
                server_id, "thresholds", cached=cache_enabled and th is not None,
                age_seconds=_age(th.last_updated) if th else None,
                count=len(th.counts) if th else None),
            "maintenance_map": diagnostics.feed_block(
                server_id, "maintenance_map", cached=cache_enabled and mm is not None,
                age_seconds=_age(mm.last_updated) if mm else None,
                # host rows the last crawl classified UP/DOWN — the same number the
                # cycle log prints; clients label it "N hosts" (spec rev 5 §11.3)
                count=mm.host_rows if mm else None),
        }

        # BHNM hop = the background monitor's cached probe result. Never a live
        # probe here: Traefik waits ~3 s for a dead backend, so an in-request
        # probe blocks the response and a client cancel loses the result.
        bhnm = diagnostics.bhnm_monitor(server_id)
        # The BHNM build, for the topology header. Cached for hours inside
        # diagnostics, so this route stays fast; None means UNKNOWN — on-prem BHNM
        # exposes no api_key-readable version at all — and the clients must draw
        # unknown differently from known, never blank.
        bhnm["version"] = await diagnostics.bhnm_version(server_cfg, BHNM_TLS_VERIFY) \
            if server_cfg else None

        return {
            "middleware": middleware_block,
            "server": {
                "name": server_cfg.get("name", ""),
                "host": host,
                "cache_enabled": cache_enabled,
                "bhnm": bhnm,
                "feeds": feeds,
            },
        }
    except HTTPException:
        raise
    except Exception as e:  # isolation: degrade, never 500 into the app
        return {
            "middleware": middleware_block,
            "server": {"bhnm": {"reachable": False, "source": "error",
                                "last_error": diagnostics.scrub(str(e))},
                       "feeds": {}},
        }


# ── BHNM Proxy — Dedicated Routes (cache-ready) ─────────────────────────────
# These explicit routes exist so the middleware can later add caching /
# cache-invalidation logic per endpoint.  For now they are thin pass-throughs.

async def _proxy_to_bhnm(request: Request, bhnm_path: str) -> Response:
    """Forward a form-encoded POST to the given BHNM path and return the response."""
    _verify_proxy_token(request)
    body = await request.body()

    # Resolve target BHNM server (same logic as the catch-all proxy)
    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        content_type = request.headers.get("content-type", "")
        if "application/x-www-form-urlencoded" in content_type:
            parsed_body = parse_qs(body.decode("utf-8", errors="replace"))
            api_key = parsed_body.get("password", [""])[0] or parsed_body.get("pwd", [""])[0]
            if api_key:
                target_base = _target_for_api_key(api_key)
    if not target_base:
        target_base = _single_server_url()
    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base, request)

    target = f"{target_base}/{bhnm_path.lstrip('/')}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method="POST",
                url=target,
                headers=forward_headers,
                content=body,
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError as exc:
        raise HTTPException(status_code=502, detail=f"Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }
    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)


async def _note_ack_state(request: Request, response: Response, state: str) -> None:
    """On a successful ACK/UnACK, patch the incident cache so the list shows
    the new state instantly instead of up to two cache cycles later."""
    try:
        if json.loads(response.body).get("result") != "completed":
            return
        body = parse_qs((await request.body()).decode("utf-8", errors="replace"))
        incident_id = body.get("incident_id", [""])[0].strip()
        if not incident_id:
            return
        server_id = _registry_server_id(request)
        if not server_id:
            api_key = body.get("password", [""])[0] or body.get("pwd", [""])[0]
            if api_key:
                server_id = maintenance_cache._server_id_for_api_key(api_key)
        if server_id:
            incident_cache.note_state_override(server_id, incident_id, state)
    except Exception:
        pass


@app.post("/api/proxy/incident/acknowledge")
async def proxy_incident_acknowledge(request: Request):
    print("[Proxy] ACK incident request")
    response = await _proxy_to_bhnm(request, "/fw/index.php?r=restful/incident/acknowledge")
    await _note_ack_state(request, response, "ACKNOWLEDGED")
    return response


@app.post("/api/proxy/incident/unacknowledge")
async def proxy_incident_unacknowledge(request: Request):
    print("[Proxy] UnACK incident request")
    response = await _proxy_to_bhnm(request, "/fw/index.php?r=restful/incident/unacknowledge")
    await _note_ack_state(request, response, "OPEN")
    return response


@app.post("/api/proxy/ha-status")
async def proxy_ha_status(request: Request):
    print("[Proxy] HA status check")
    return await _proxy_to_bhnm(request, "/api/ha_status_api.php")


MAINT_START_BOUNDARY = 300  # snap maintenance starts to 5-min wall-clock boundaries
MAINT_START_MARGIN = 60     # min lead time so the start is still future when BHNM sees it


def snap_start(now: int) -> int:
    """Next 5-minute wall-clock boundary; if <60s away, the following one
    (BHNM rejects non-future start times)."""
    nxt = (now // MAINT_START_BOUNDARY + 1) * MAINT_START_BOUNDARY
    if nxt - now < MAINT_START_MARGIN:
        nxt += MAINT_START_BOUNDARY
    return nxt


@app.post("/api/proxy/maintenance/create")
async def proxy_maintenance_create(request: Request):
    print("[Proxy] Maintenance window create request")
    _verify_proxy_token(request)

    body_bytes = await request.body()
    parsed_body = parse_qs(body_bytes.decode("utf-8", errors="replace"))

    name = parsed_body.get("name", [""])[0].strip()
    duration_raw = parsed_body.get("duration", [""])[0].strip()
    comment = parsed_body.get("comment", [""])[0].strip()

    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    if not duration_raw:
        raise HTTPException(status_code=400, detail="duration is required")
    try:
        duration = int(duration_raw)
    except ValueError:
        raise HTTPException(status_code=400, detail="duration must be an integer")
    if duration < 1:
        raise HTTPException(status_code=400, detail="duration must be >= 1")

    start_time = snap_start(int(time.time()))
    end_time = start_time + (duration * 60)

    response = await _proxy_maint_window(request, {
        "action": "new",
        "name": name,
        "start_time": str(start_time),
        "end_time": str(end_time),
        "comment": comment,
    })
    # Echo the snapped start so clients can show "Starts at HH:MM" without
    # duplicating the boundary math; the body stays a verbatim passthrough.
    response.headers["X-Maintenance-Start"] = str(start_time)
    # Record the scheduled window so ALL clients see it (BHNM has no
    # list-scheduled API; the middleware remembers its own creates).
    try:
        if json.loads(response.body).get("result") == "completed":
            server_id = _registry_server_id(request)
            if server_id:
                maintenance_cache.note_scheduled(server_id, name, start_time, end_time)
    except Exception:
        pass
    return response


@app.post("/api/proxy/maintenance/close")
async def proxy_maintenance_close(request: Request):
    print("[Proxy] Maintenance window close request")
    _verify_proxy_token(request)

    body_bytes = await request.body()
    parsed_body = parse_qs(body_bytes.decode("utf-8", errors="replace"))
    name = parsed_body.get("name", [""])[0].strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")

    # BHNM's action=close ends ALL windows for the device, scheduled ones included.
    response = await _proxy_maint_window(request, {"action": "close", "name": name})
    server_id = _registry_server_id(request)
    if server_id:
        maintenance_cache.clear_scheduled(server_id, name)
    return response


@app.post("/api/proxy/maintenance/status")
async def proxy_maintenance_status(request: Request):
    """Merged read: {inMaintenance, windows, scheduled, status?}. Best-effort — a
    failed upstream call degrades (false / empty), it never 5xxes the whole read.
    `status` (2.12.1, spec rev 5 §11.1) is the host row's literal passed through
    untouched — absent when there is no row or the row carries no string status."""
    _verify_proxy_token(request)

    body_bytes = await request.body()
    parsed_body = parse_qs(body_bytes.decode("utf-8", errors="replace"))
    name = parsed_body.get("name", [""])[0].strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")

    target_base, api_key = _resolve_bhnm_target_and_key(request)

    from urllib.parse import urlencode
    form_headers = {"content-type": "application/x-www-form-urlencoded"}
    in_maintenance = False
    host_status: str | None = None
    windows = []

    async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
        # Call A — the boolean (source of truth for the badge/state).
        # recordCount is required (else statuses[] comes back empty); name, not IP.
        try:
            resp = await client.request(
                method="POST",
                url=f"{target_base}/fw/index.php?r=restful/devices/get-host-and-service-status",
                headers=form_headers,
                content=urlencode({
                    "password": api_key,
                    "groupFilterBy": "device",
                    "groupFilterValue": name,
                    "serviceFilter": "host_only",
                    "recordCount": "100",
                }).encode("utf-8"),
            )
            statuses = resp.json().get("statuses", [])
            # Missing key (BHNM < 26.3.01) or no row → False: never claim
            # maintenance we can't confirm.
            in_maintenance = bool(statuses and statuses[0].get("inMaintenance", False))
            raw_status = statuses[0].get("status") if statuses else None
            if isinstance(raw_status, str) and raw_status:
                host_status = raw_status   # exact literal, never coerced
        except Exception as exc:
            print(f"[Proxy] maintenance/status host-status call failed: {exc}")

        # Call B — the detail (ends-at / comment); active windows only.
        try:
            resp = await client.request(
                method="POST",
                url=f"{target_base}/api/maint_window_api.php",
                headers=form_headers,
                content=urlencode({
                    "password": api_key,
                    "action": "list",
                    "name": name,
                }).encode("utf-8"),
            )
            windows = resp.json().get("windows", []) or []
        except Exception as exc:
            print(f"[Proxy] maintenance/status list call failed: {exc}")

    scheduled = None
    if not in_maintenance:
        server_id = _registry_server_id(request)
        if server_id:
            entry = next(
                (e for e in maintenance_cache.get_scheduled(server_id, active_names=set())
                 if e["name"] == name), None)
            if entry:
                scheduled = {"start_time": entry["start_time"], "end_time": entry["end_time"]}
    out = {"inMaintenance": in_maintenance, "windows": windows, "scheduled": scheduled}
    if host_status is not None:
        out["status"] = host_status
    return out


def _registry_server_id(request: Request) -> str:
    """server_id for the scheduled-window registry — same resolution as the
    maintenance-map route (api_key match, else X-BHNM-Target URL match)."""
    server_id = maintenance_cache._server_id_for_api_key(
        request.headers.get("X-Proxy-Token", "").strip())
    if not server_id:
        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
        if bhnm_target:
            server_id = maintenance_cache._server_id_for_bhnm_url(bhnm_target)
    return server_id


def _resolve_bhnm_target_and_key(request: Request) -> tuple[str, str]:
    """Resolve the target BHNM base URL + api key server-side (never from the client)."""
    cfg = _resolve_server_config(request)
    if cfg:
        target_base = cfg.get("url", "").rstrip("/")
        api_key = cfg.get("api_key", "")
    else:
        target_base = _single_server_url()
        api_key = ""
        if target_base:
            try:
                with open(SERVERS_JSON_PATH) as f:
                    for s in json.load(f):
                        if s.get("url", "").rstrip("/") == target_base:
                            api_key = s.get("api_key", "")
                            break
            except Exception:
                pass

    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base, request)
    return target_base, api_key


async def _proxy_maint_window(request: Request, fields: dict) -> Response:
    """POST form fields (plus the server-side api key) to maint_window_api.php
    and pass the BHNM response through verbatim."""
    target_base, api_key = _resolve_bhnm_target_and_key(request)

    from urllib.parse import urlencode
    bhnm_body = urlencode({"password": api_key, **fields})
    target = f"{target_base}/api/maint_window_api.php"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST and k.lower() != "content-length"
    }
    forward_headers["content-type"] = "application/x-www-form-urlencoded"

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method="POST",
                url=target,
                headers=forward_headers,
                content=bhnm_body.encode("utf-8"),
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }
    return Response(content=resp.content, status_code=resp.status_code, headers=response_headers)


# ── BHNM API Proxy (for BeNeM) ────────────────────────────────────────────────────
# Target BHNM server is supplied per-request via X-BHNM-Target header.

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(path: str, request: Request):
    _verify_proxy_token(request)
    body = await request.body()

    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
    if not target_base:
        content_type = request.headers.get("content-type", "")
        if "application/x-www-form-urlencoded" in content_type:
            parsed_body = parse_qs(body.decode("utf-8", errors="replace"))
            # fw/index.php uses "password", incident_api.php uses "pwd"
            api_key = parsed_body.get("password", [""])[0] or parsed_body.get("pwd", [""])[0]
            if api_key:
                target_base = _target_for_api_key(api_key)
    if not target_base:
        # Also check query params (some BHNM API calls pass password as ?password=...)
        api_key = request.query_params.get("password", "")
        if api_key:
            target_base = _target_for_api_key(api_key)
    if not target_base:
        # Fallback: if exactly one server is configured, use it (covers session-based requests)
        target_base = _single_server_url()
        if target_base:
            print(f"[Proxy] No target header/key found — falling back to single configured server")

    if not target_base:
        raise HTTPException(status_code=502, detail="Bad Gateway: BHNM target server not configured")
    if not (target_base.startswith("http://") or target_base.startswith("https://")):
        raise HTTPException(status_code=400, detail="X-BHNM-Target must be an http/https URL")
    _validate_proxy_target(target_base, request)

    target = f"{target_base}/{path}"
    if request.url.query:
        target += f"?{request.url.query}"

    forward_headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in HOP_BY_HOP_REQUEST
    }

    try:
        async with httpx.AsyncClient(verify=BHNM_TLS_VERIFY, timeout=PROXY_TIMEOUT) as client:
            resp = await client.request(
                method=request.method,
                url=target,
                headers=forward_headers,
                content=body,
            )
    except httpx.TimeoutException:
        print(f"[Proxy] Timeout proxying {request.method} {target}")
        raise HTTPException(status_code=504, detail="Gateway Timeout: BHNM server did not respond in time")
    except httpx.ConnectError as exc:
        print(f"[Proxy] Connection error proxying {request.method} {target}: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: could not connect to BHNM server")
    except httpx.RequestError as exc:
        print(f"[Proxy] Request error proxying {request.method} {target}: {exc}")
        raise HTTPException(status_code=502, detail="Bad Gateway: request to BHNM server failed")

    response_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in HOP_BY_HOP_RESPONSE
    }

    response = Response(content=resp.content, status_code=resp.status_code, headers=response_headers)
    # iOS calls the restful ack/unack endpoints through this catch-all —
    # patch the incident cache so the list reflects the new state instantly.
    r_param = request.query_params.get("r", "")
    if r_param == "restful/incident/acknowledge":
        await _note_ack_state(request, response, "ACKNOWLEDGED")
    elif r_param == "restful/incident/unacknowledge":
        await _note_ack_state(request, response, "OPEN")
    return response
