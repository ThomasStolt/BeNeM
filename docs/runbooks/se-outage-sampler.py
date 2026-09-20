#!/usr/bin/env python3
"""Sampler for the two Service Engine experiments (2026-09-20).

ONE instrument, used unchanged by both runbooks:
  docs/runbooks/2026-09-20-experiment-1-standalone-se-shutdown.md
  docs/runbooks/2026-09-20-experiment-2-se-group-failover.md

Runs INSIDE benem-middleware on the VPS, because that is where
/data/servers.json (the api_key) and /logs/middleware.log already are. No
credential is typed, copied or printed.

Writes ONE JSON object per tick to stdout — JSONL, so the record is diffable
afterwards and nothing has to be re-derived from a scrollback.

    docker exec benem-middleware python /tmp/se_sampler.py \
        --devices BHNM-B-SE01 raspi-050 raspi-059 \
        --interval 30

Every BHNM string is recorded VERBATIM. In particular `lastUpdateTime`,
`currentStateDuration` and `open_time` are BHNM's own LOCAL time (CEST, UTC+2
on this lab) while `ts_utc` below and the middleware log are UTC. Measured
2026-09-20: BHNM said `2026-09-20 11:15:22` at 09:15:22Z. Do not convert here
— convert when reading, and say which you wrote.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SERVERS = "/data/servers.json"
LOG = "/logs/middleware.log"
MW = "http://127.0.0.1:8889"

# MEASURED 2026-09-20: Cloudflare in front of the lab answers 403 to the default
# `Python-urllib/3.x` User-Agent and 200 to literally any other. The middleware
# itself never hits this because httpx sends its own. Without this line every
# BHNM call in this sampler returns rows_found=0 — an empty result that was
# never capable of being non-empty.
UA = "BeNeM-se-sampler/1.0"


def server_cfg(server_id):
    for s in json.load(open(SERVERS)):
        if s.get("id") == server_id:
            return s
    raise SystemExit(f"server id {server_id!r} not in {SERVERS}")


def post_form(url, form, timeout=30):
    body = urllib.parse.urlencode(form).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return {"http": r.status, "body": json.loads(r.read() or b"null")}
    except urllib.error.HTTPError as e:
        return {"http": e.code, "error": e.read()[:200].decode("utf-8", "replace")}
    except Exception as e:                       # noqa: BLE001 — record, never raise
        return {"http": None, "error": f"{type(e).__name__}: {e}"[:200]}


def mw_get(path, headers, timeout=45):
    req = urllib.request.Request(MW + path, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return {"http": r.status, "body": json.loads(r.read() or b"null")}
    except urllib.error.HTTPError as e:
        return {"http": e.code, "error": e.read()[:200].decode("utf-8", "replace")}
    except Exception as e:                       # noqa: BLE001
        return {"http": None, "error": f"{type(e).__name__}: {e}"[:200]}


def host_status(base, pwd, pin, name):
    """One device's HOST row. groupFilterBy=device — recordCount is required
    or statuses[] comes back empty with totalRecords>0."""
    form = {"password": pwd, "groupFilterBy": "device", "groupFilterValue": name,
            "serviceFilter": "host_only", "recordCount": "100", "recordStart": "0"}
    if pin:
        form["pin"] = pin
    r = post_form(f"{base}/fw/index.php?r=restful/devices/get-host-and-service-status", form)
    rows = (r.get("body") or {}).get("statuses") or []
    # rows_found is the honest answer. A device that vanishes from the API is a
    # different fact from one that reads DOWN, and 0 must not read as "fine".
    return {"http": r.get("http"), "error": r.get("error"),
            "rows_found": len(rows), "rows": rows}


def log_position():
    try:
        with open(LOG, "rb") as f:
            data = f.read()
        return {"lines": data.count(b"\n"), "bytes": len(data)}
    except Exception as e:                       # noqa: BLE001
        return {"error": f"{type(e).__name__}: {e}"}


def tick(cfg, devices):
    base = cfg["url"].rstrip("/")
    pwd, pin = cfg["api_key"], cfg.get("pin") or ""
    hdr = {"X-Proxy-Token": pwd, "X-BHNM-Target": cfg["url"]}

    out = {"ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "epoch": round(time.time(), 3)}

    # --- BHNM direct: the fine-grained source. Not cached by anything. -------
    out["bhnm_host_rows"] = {n: host_status(base, pwd, pin, n) for n in devices}

    inc = post_form(f"{base}/api/incident_api.php",
                    dict({"pwd": pwd, "method": "getincidents"},
                         **({"pin": pin} if pin else {})))
    rows = ((inc.get("body") or {}).get("active_incidents")) or []
    out["bhnm_incidents"] = {
        "http": inc.get("http"), "error": inc.get("error"), "count": len(rows),
        # id + state + name + open_time, verbatim. The whole row is not needed
        # and a 12-incident lab makes the file unreadable if it is kept.
        "rows": [{k: i.get(k) for k in
                  ("incident_id", "incident_state", "name", "open_time", "title")}
                 for i in rows]}

    # --- What the middleware serves a CLIENT. There is no /api/v1/devices: the
    # device list is restful/devices/list (config only, no status, no
    # freshness) overlaid with host_down from maintenance-map. -------------
    mm = mw_get("/api/v1/maintenance-map", hdr)
    out["mw_maintenance_map"] = mm.get("body") if mm.get("http") == 200 else mm

    ci = mw_get("/api/v1/incidents", hdr)
    b = ci.get("body") if ci.get("http") == 200 else None
    if b is None:
        out["mw_incidents"] = ci
    else:
        act = b.get("active_incidents") or []
        out["mw_incidents"] = {
            "cache_age_seconds": b.get("cache_age_seconds"),
            "active": len(act), "closed": len(b.get("closed_incidents") or []),
            "rows": [{k: i.get(k) for k in
                      ("incident_id", "incident_state", "name", "alert_type",
                       "alarm_counts", "state_confirmed_at", "counts_confirmed_at")}
                     for i in act]}

    dg = mw_get("/api/v1/diagnostics", hdr)
    out["mw_diagnostics"] = dg.get("body") if dg.get("http") == 200 else dg

    out["log"] = log_position()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--devices", nargs="+", required=True,
                    help="device names to watch, EXACTLY as BHNM spells them")
    ap.add_argument("--interval", type=int, default=30)
    ap.add_argument("--server", default="ThomasLabServer")
    ap.add_argument("--minutes", type=int, default=0,
                    help="stop after N minutes; 0 = until Ctrl-C")
    a = ap.parse_args()

    cfg = server_cfg(a.server)
    deadline = time.time() + a.minutes * 60 if a.minutes else None
    while True:
        t0 = time.time()
        try:
            rec = tick(cfg, a.devices)
        except Exception as e:                   # noqa: BLE001
            # A sampler that dies mid-experiment loses the experiment. Record
            # the failure as a tick and keep going.
            rec = {"ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   "sampler_error": f"{type(e).__name__}: {e}"[:300]}
        sys.stdout.write(json.dumps(rec) + "\n")
        sys.stdout.flush()
        if deadline and time.time() >= deadline:
            return
        time.sleep(max(0.0, a.interval - (time.time() - t0)))


if __name__ == "__main__":
    main()
