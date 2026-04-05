import time
import jwt
import httpx
from config import APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID

APNS_HOSTS = {
    "sandbox": "api.sandbox.push.apple.com",
    "production": "api.push.apple.com",
}

_jwt_token = None
_jwt_issued_at = 0

def _get_jwt() -> str:
    global _jwt_token, _jwt_issued_at
    now = int(time.time())
    if _jwt_token is None or (now - _jwt_issued_at) > 3300:  # refresh after 55 min
        _jwt_token = jwt.encode(
            {"iss": APNS_TEAM_ID, "iat": now},
            APNS_PRIVATE_KEY,
            algorithm="ES256",
            headers={"kid": APNS_KEY_ID}
        )
        _jwt_issued_at = now
    return _jwt_token

async def send_notification(device_token: str, title: str, body: str, incident_id: str = "", environment: str = "production") -> tuple[bool, int]:
    """Returns (success, http_status_code)."""
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
        async with httpx.AsyncClient(http2=True) as client:
            r = await client.post(url, json=payload, headers=headers, timeout=10)
        success = r.status_code == 200
        if not success:
            print(f"[APNs] Failed ({r.status_code}) via {environment}: {r.text}")
        return success, r.status_code
    except Exception as e:
        print(f"[APNs] Error: {e}")
        return False, 0

async def send_to_all(tokens: list[tuple[str, str]], title: str, body: str, incident_id: str = "") -> list[str]:
    """Send to all (token, environment) pairs. Returns list of tokens to remove (410 Gone = unregistered)."""
    stale_tokens = []
    for token, environment in tokens:
        success, status = await send_notification(token, title, body, incident_id, environment)
        if status in (410,):
            stale_tokens.append(token)
        elif success:
            print(f"[APNs] Sent to ...{token[-8:]} via {environment}")
    return stale_tokens
