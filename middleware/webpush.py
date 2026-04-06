import json
from pywebpush import webpush as webpush_send, WebPushException
from config import VAPID_PRIVATE_KEY, VAPID_PUBLIC_KEY, VAPID_CONTACT_EMAIL


def build_payload(title: str, body: str, incident_id: str, severity: str) -> dict:
    return {
        "title": title,
        "body": body,
        "incident_id": incident_id,
        "severity": severity,
    }


async def send_web_push_to_all(
    subscriptions: list[dict],
    title: str,
    body: str,
    incident_id: str = "",
    severity: str = "",
) -> list[str]:
    """Send Web Push to all subscriptions. Returns list of endpoints to remove (410 Gone)."""
    if not VAPID_PRIVATE_KEY:
        return []

    payload = json.dumps(build_payload(title, body, incident_id, severity))
    vapid_claims = {"sub": VAPID_CONTACT_EMAIL}
    gone_endpoints: list[str] = []

    for sub in subscriptions:
        subscription_info = {
            "endpoint": sub["endpoint"],
            "keys": {"p256dh": sub["p256dh"], "auth": sub["auth"]},
        }
        try:
            webpush_send(
                subscription_info=subscription_info,
                data=payload,
                vapid_private_key=VAPID_PRIVATE_KEY,
                vapid_claims=vapid_claims,
            )
            print(f"[WebPush] Sent to {sub['endpoint'][:50]}...")
        except WebPushException as e:
            # pywebpush stores status on .response.status_code (requests)
            # or sometimes only in the exception message string
            status = getattr(e.response, "status_code", 0) if e.response else 0
            if status == 0 and "410" in str(e):
                status = 410
            if status == 410:
                gone_endpoints.append(sub["endpoint"])
                print(f"[WebPush] Subscription expired (410): {sub['endpoint'][:50]}...")
            else:
                print(f"[WebPush] Failed ({status}): {e}")
        except Exception as e:
            print(f"[WebPush] Error: {e}")

    return gone_endpoints
