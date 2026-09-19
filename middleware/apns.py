import asyncio
import time
import jwt
import httpx
from config import APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID

APNS_HOSTS = {
    "sandbox": "api.sandbox.push.apple.com",
    "production": "api.push.apple.com",
}

APNS_TIMEOUT = 10.0
JWT_REFRESH_SECONDS = 3300  # refresh after 55 min (APNs requires < 60 min)

_jwt_token = None
_jwt_issued_at = 0


def _get_jwt() -> str:
    global _jwt_token, _jwt_issued_at
    now = int(time.time())
    if _jwt_token is None or (now - _jwt_issued_at) > JWT_REFRESH_SECONDS:
        _jwt_token = jwt.encode(
            {"iss": APNS_TEAM_ID, "iat": now},
            APNS_PRIVATE_KEY,
            algorithm="ES256",
            headers={"kid": APNS_KEY_ID}
        )
        _jwt_issued_at = now
    return _jwt_token


async def _send_one(
    client: httpx.AsyncClient,
    device_token: str,
    title: str,
    body: str,
    incident_id: str,
    environment: str,
) -> tuple[str, bool, int, str]:
    """Send to one device. Returns (token, success, status_code, reason).

    `reason` is APNs' own machine-readable cause (`{"reason": "BadDeviceToken"}`),
    empty when the body carries none. It is returned rather than logged and
    discarded because a 400 is only sometimes about the token — see `send_to_all`.
    """
    host = APNS_HOSTS.get(environment, APNS_HOSTS["production"])
    url = f"https://{host}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {_get_jwt()}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default"
        }
    }
    if incident_id:
        payload["incident_id"] = incident_id
    try:
        r = await client.post(url, json=payload, headers=headers, timeout=APNS_TIMEOUT)
        success = r.status_code == 200
        reason = ""
        if not success:
            try:
                reason = (r.json() or {}).get("reason", "") or ""
            except Exception:
                reason = ""   # a non-JSON error body is not a parse failure worth raising
            print(f"[APNs] Failed ({r.status_code}) via {environment}: {r.text}")
        return device_token, success, r.status_code, reason
    except Exception as e:
        print(f"[APNs] Error sending to ...{device_token[-8:]}: {type(e).__name__}: {e}")
        return device_token, False, 0, ""


_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    """One long-lived HTTP/2 client, reused across sends.

    A per-request `async with httpx.AsyncClient(http2=True)` hung forever on exit:
    the sends completed and the phone got the push, but the block never returned,
    so /webhook never responded and BHNM retried it three times. Apple also asks
    that APNs connections be kept open rather than rebuilt per notification.
    """
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(http2=True, timeout=APNS_TIMEOUT)
    return _client


async def send_to_all(tokens: list[tuple[str, str]], title: str, body: str, incident_id: str = "") -> list[str]:
    """Send to all (token, environment) pairs. Returns the tokens to remove.

    Removable means permanently dead for this app: **410 Gone**, and **400 with
    reason `BadDeviceToken`** — which is what a sandbox token looks like when it
    reaches the production host, so a Debug build replaced by a TestFlight or App
    Store build leaves exactly this behind.

    Only that one 400 reason. A 400 is not a statement about the token in general:
    `BadTopic`, `PayloadEmpty`, `MissingTopic` and friends are OUR bug and arrive
    for *every* token, so removing on any 400 would silently empty the whole fleet
    on a bad deploy and the next incident would page nobody.
    """
    if not tokens:
        return []

    stale_tokens = []
    client = _get_client()

    # Sequential, deliberately — not asyncio.gather. Five concurrent POSTs down
    # one multiplexed HTTP/2 connection to APNs wedged after the first response:
    # the remaining coroutines never returned, no request timeout fired, and only
    # the first registered device was ever notified. Traced 2026-09-15; see
    # docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md §3.8.
    # Deliberately simple: ~0.5s per device in a background task — revisit only if a
    # deployment has enough devices for that to matter.
    for token, environment in tokens:
        _token, success, status, reason = await _send_one(
            client, token, title, body, incident_id, environment)
        if status == 410:
            stale_tokens.append(token)
            print(f"[APNs] Token gone (410) ...{token[-8:]}")
        elif status == 400 and reason == "BadDeviceToken":
            stale_tokens.append(token)
            print(f"[APNs] Token bad (400 BadDeviceToken) ...{token[-8:]} "
                  f"env={environment} — removing")
        elif success:
            print(f"[APNs] Sent to ...{token[-8:]}")
    return stale_tokens
