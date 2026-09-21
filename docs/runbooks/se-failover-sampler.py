#!/usr/bin/env python3
"""Sampler for the BHNM-A Service Engine Group failover experiment (2026-09-20).

Runs on the laptop, against BHNM-A directly. Reads ./.env. One JSON object per
tick to stdout — JSONL, so the record is diffable afterwards and nothing has to
be re-derived from a scrollback.

    python3 docs/runbooks/se-failover-sampler.py --interval 15 \
        > docs/evidence/2026-09-20-exp2-failover.jsonl

WHAT IT COLLECTS, per tick:
  * every host row on BHNM-A, in FIVE calls (one per category) rather than 29 —
    measured at 0.7 s for the set, so a 15 s tick is comfortable
  * the incident list (legacy getincidents)
  * a derived per-device view: did lastUpdateTime advance since the previous tick

RESOLUTION, stated because it bounds every number this produces:
  BHNM's own `lastUpdateTime` steps about once a MINUTE. So a handover gap read
  from that field is quantised to ~60 s and cannot be reported finer, however
  fast this samples. What IS measurable at tick resolution is wall-clock time
  from the stop until a device's lastUpdateTime resumes advancing. Report both,
  and never quote the quantised one as if it were precise.

TIME: every BHNM string is recorded VERBATIM and is LOCAL (Europe/Berlin);
`ts_utc` is UTC. Both are kept, neither is converted here.
"""
import argparse
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ponytail: verify=False — the lab serves a self-signed cert. Named here rather
# than buried so nobody reads it as a considered TLS policy.
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

# Category NAMES on BHNM-A. Ids are per-instance (19 here, 36 on BHNM-B) and
# `groupFilterValue` wants the name, so the names are what is hardcoded.
CATEGORIES = ["New Routers", "New Servers", "Database Servers",
              "New Devices", "Helix Network Devices"]

FIELDS = ("status", "message", "lastUpdateTime", "currentStateDuration",
          "incidentID", "inMaintenance", "deviceIndex")


def load_env(path=".env"):
    env = {}
    for line in open(path):
        m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", line.rstrip("\n"))
        if m:
            env[m.group(1)] = m.group(2).strip()
    return env


def post(base, path, form, timeout=30):
    req = urllib.request.Request(
        base.rstrip("/") + path,
        data=urllib.parse.urlencode(form).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "User-Agent": "BeNeM-se-failover-sampler/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, {"_error": e.read()[:200].decode("utf-8", "replace")}
    except Exception as e:                                   # noqa: BLE001
        return None, {"_error": f"{type(e).__name__}: {e}"[:200]}


def host_rows(base, key):
    """All host rows, five calls. Returns {deviceName: row} plus any call errors."""
    rows, errors = {}, []
    for cat in CATEGORIES:
        st, body = post(base, "/fw/index.php?r=restful/devices/get-host-and-service-status",
                        {"password": key, "groupFilterBy": "category",
                         "groupFilterValue": cat, "serviceFilter": "host_only",
                         "recordCount": "200", "recordStart": "0"})
        if st != 200 or not isinstance(body, dict) or "statuses" not in body:
            errors.append({"category": cat, "http": st,
                           "detail": (body or {}).get("_error")})
            continue
        for r in body["statuses"] or []:
            n = r.get("deviceName")
            if isinstance(n, str) and n:
                rows[n] = {k: r.get(k) for k in FIELDS}
    return rows, errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--interval", type=int, default=15)
    ap.add_argument("--minutes", type=int, default=0, help="0 = until Ctrl-C")
    ap.add_argument("--note", default="", help="free-text marker written into every tick")
    a = ap.parse_args()

    env = load_env()
    base, key = env["BHNM_A_URL"], env["BHNM_A_API_KEY"]
    se_stop = env.get("BHNM_A_SE_STOP_TARGET", "")
    se01 = [d for d in env.get("BHNM_A_SE_MANAGED_DEVICES", "").split(",") if d]
    se02 = [d for d in env.get("BHNM_A_SE02_MANAGED_DEVICES", "").split(",") if d]
    group = env.get("BHNM_A_SE_GROUP_NAME", "")
    role = {}
    for n in se01:
        role[n] = "SE01"
    for n in se02:
        role[n] = "SE02"
    for n in (se_stop, "BHNM-A-SE02", group):
        if n:
            role[n] = "INFRA"

    prev, deadline = {}, (time.time() + a.minutes * 60 if a.minutes else None)
    while True:
        t0 = time.time()
        rows, errors = host_rows(base, key)
        st, inc = post(base, "/api/incident_api.php",
                       {"pwd": key, "method": "getincidents"})
        active = (inc or {}).get("active_incidents") if isinstance(inc, dict) else None

        # advanced[] is the whole point: which rows moved since the previous tick.
        # Absence of movement is the signal, so it is recorded explicitly rather
        # than left to be inferred from two lines of a diff.
        advanced, frozen = [], []
        for n, r in rows.items():
            p = prev.get(n)
            if p is None:
                continue
            (advanced if r["lastUpdateTime"] != p else frozen).append(n)
        prev = {n: r["lastUpdateTime"] for n, r in rows.items()}

        rec = {
            "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "epoch": round(time.time(), 3),
            "note": a.note,
            "rows_found": len(rows),
            "call_errors": errors,
            "incidents": {"http": st,
                          "count": len(active) if isinstance(active, list) else None,
                          "rows": [{k: i.get(k) for k in
                                    ("incident_id", "incident_state", "name", "open_time")}
                                   for i in (active or [])] if isinstance(active, list) else None},
            "advanced": sorted(advanced),
            "frozen": sorted(frozen),
            "by_role": {r: sorted(n for n in frozen if role.get(n) == r)
                        for r in ("SE01", "SE02", "INFRA")},
            "devices": rows,
        }
        sys.stdout.write(json.dumps(rec) + "\n")
        sys.stdout.flush()
        if deadline and time.time() >= deadline:
            return
        time.sleep(max(0.0, a.interval - (time.time() - t0)))


if __name__ == "__main__":
    main()
