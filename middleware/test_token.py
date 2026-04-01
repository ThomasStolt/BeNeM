import asyncio, httpx, time, jwt, sqlite3
from config import APNS_PRIVATE_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID

DEV_TOKEN = "6cc0e431b015312349dac86deb7f26a4193ee0d14f330e54eca8313f83e9cc6a"

rows = sqlite3.connect("/data/bhnm_apns.db").execute("SELECT token FROM device_tokens").fetchall()
tokens = [r[0] for r in rows if r[0] != DEV_TOKEN]

if not tokens:
    print("Kein TestFlight Token in DB — BeNeM auf TestFlight-iPhone öffnen und nochmal versuchen.")
    exit(1)

token = tokens[0]
print(f"Teste Token: ...{token[-8:]} (vollständig: {token})\n")

j = jwt.encode(
    {"iss": APNS_TEAM_ID, "iat": int(time.time())},
    APNS_PRIVATE_KEY,
    algorithm="ES256",
    headers={"kid": APNS_KEY_ID}
)
payload = {"aps": {"alert": {"title": "BeNeM Test", "body": "APNs Endpoint Test"}, "sound": "default"}}
headers = {
    "authorization": f"bearer {j}",
    "apns-topic": APNS_BUNDLE_ID,
    "apns-push-type": "alert",
    "apns-priority": "10",
}

async def test():
    for host in ["api.sandbox.push.apple.com", "api.push.apple.com"]:
        async with httpx.AsyncClient(http2=True) as c:
            r = await c.post(f"https://{host}/3/device/{token}", json=payload, headers=headers, timeout=10)
        result = r.text or "OK (200)"
        print(f"{host}: {r.status_code} {result}")

asyncio.run(test())
