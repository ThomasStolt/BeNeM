#!/usr/bin/env python3
"""Watch the `message` and `lastUpdateTime` fields on named devices.

Records only. Draws no conclusion — the point is whether a string changes, and
when. Run from the repo root; reads credentials from ./.env.

    python3 docs/runbooks/se-message-watch.py --server A \
        --devices BHNM-A-SE01 BHNM-A-SE02 BHNM-A-SE-GROUP --interval 300 \
        >> docs/evidence/2026-09-20-se-message-watch.jsonl

Source field: statuses[].message from
  POST {base}/fw/index.php?r=restful/devices/get-host-and-service-status
Every BHNM timestamp is LOCAL (Europe/Berlin); `ts_utc` is UTC. Both are kept.
"""
import argparse, json, re, ssl, sys, time, urllib.error, urllib.parse, urllib.request

# ponytail: verify=False because the lab serves a self-signed cert. Named here
# rather than hidden so nobody mistakes it for a considered TLS policy.
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def load_env(path=".env"):
    env = {}
    for line in open(path):
        m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", line.rstrip("\n"))
        if m:
            env[m.group(1)] = m.group(2).strip()
    return env


def host_row(base, key, name):
    form = {"password": key, "groupFilterBy": "device", "groupFilterValue": name,
            "serviceFilter": "host_only", "recordCount": "100"}
    req = urllib.request.Request(
        base.rstrip("/") + "/fw/index.php?r=restful/devices/get-host-and-service-status",
        data=urllib.parse.urlencode(form).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "User-Agent": "BeNeM-se-message-watch/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=CTX) as r:
            rows = (json.loads(r.read() or b"{}") or {}).get("statuses") or []
    except urllib.error.HTTPError as e:
        return {"http": e.code, "rows_found": 0}
    except Exception as e:                                  # noqa: BLE001
        return {"http": None, "error": f"{type(e).__name__}: {e}"[:200], "rows_found": 0}
    # rows_found is reported separately: a device that vanishes from the API is a
    # different fact from one that reads DOWN, and 0 must never render as "fine".
    return {"http": 200, "rows_found": len(rows),
            "rows": [{k: r.get(k) for k in
                      ("status", "message", "lastUpdateTime", "currentStateDuration",
                       "incidentID", "inMaintenance")} for r in rows]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", choices=("A", "B"), required=True)
    ap.add_argument("--devices", nargs="+", required=True)
    ap.add_argument("--interval", type=int, default=300)
    ap.add_argument("--minutes", type=int, default=0, help="0 = until Ctrl-C")
    a = ap.parse_args()

    env = load_env()
    base, key = env[f"BHNM_{a.server}_URL"], env[f"BHNM_{a.server}_API_KEY"]
    deadline = time.time() + a.minutes * 60 if a.minutes else None
    last = {}
    while True:
        t0 = time.time()
        rec = {"ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "server": a.server, "base": base,
               "devices": {n: host_row(base, key, n) for n in a.devices}}
        # changed[] makes the answer to "did it change" readable without a diff
        changed = []
        for n, d in rec["devices"].items():
            cur = (d.get("rows") or [{}])[0].get("message")
            if n in last and last[n] != cur:
                changed.append({"device": n, "from": last[n], "to": cur})
            last[n] = cur
        rec["message_changed"] = changed
        sys.stdout.write(json.dumps(rec) + "\n")
        sys.stdout.flush()
        if deadline and time.time() >= deadline:
            return
        time.sleep(max(0.0, a.interval - (time.time() - t0)))


if __name__ == "__main__":
    main()
