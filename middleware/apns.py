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
) -> tuple[str, bool, int]:
    """Send to one device. Returns (token, success, status_code)."""
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
    tag = device_token[-8:]
    print(f"[Trace] _send_one enter {tag} env={environment}", flush=True)
    try:
        print(f"[Trace] before POST {tag}", flush=True)
        r = await client.post(url, json=payload, headers=headers, timeout=APNS_TIMEOUT)
        print(f"[Trace] after POST {tag} status={r.status_code}", flush=True)
        body_len = len(r.content)
        print(f"[Trace] after read body {tag} bytes={body_len}", flush=True)
        success = r.status_code == 200
        if not success:
            print(f"[APNs] Failed ({r.status_code}) via {environment}: {r.text}")
        print(f"[Trace] _send_one leave {tag}", flush=True)
        return device_token, success, r.status_code
    except Exception as e:
        print(f"[Trace] _send_one EXCEPTION {tag}: {type(e).__name__}: {e}", flush=True)
        print(f"[APNs] Error: {e}")
        return device_token, False, 0


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
    """Send to all (token, environment) pairs. Returns list of tokens to remove (410 Gone)."""
    if not tokens:
        return []

    stale_tokens = []
    print(f"[Trace] send_to_all enter, {len(tokens)} token(s)", flush=True)
    client = _get_client()
    print(f"[Trace] client ready closed={client.is_closed}", flush=True)
    print("[Trace] before gather", flush=True)
    results = await asyncio.gather(*[
        _send_one(client, token, title, body, incident_id, env)
        for token, env in tokens
    ], return_exceptions=False)
    print(f"[Trace] after gather, {len(results)} result(s)", flush=True)
    for token, success, status in results:
        if status == 410:
            stale_tokens.append(token)
        elif success:
            print(f"[APNs] Sent to ...{token[-8:]}")
    print(f"[Trace] send_to_all leave, {len(stale_tokens)} stale", flush=True)
    return stale_tokens
