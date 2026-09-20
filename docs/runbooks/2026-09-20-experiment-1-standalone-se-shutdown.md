# Runbook — Experiment 1: standalone Service Engine shutdown, instrumented

**Written 2026-09-20. NOT RUN. Nothing starts until Thomas says go.**
**Read-only on BeNeM's side. The one lab change is Thomas stopping and restarting SE01.**

**Why it exists:** `specs/2026-09-16-engine-down-stale-data-design.md` decisions **2** and **4** are
held for measurement, and decision **3** (the read-only `lastUpdateTime` observation) is **absorbed
into this run** — a controlled outage is scarce and running the observation separately wastes it.

**What it must produce, in one sentence:** the number of seconds between the engine stopping and
each symptom appearing, on both sides of the middleware — because the design has to pick a
staleness threshold and nobody has a number.

---

## Part 0 — What is already measured, so the run does not re-measure it

Everything in this part was observed **2026-09-20 between 09:15Z and 09:25Z** against the live lab,
not recalled. It shapes what the run has to look at.

### The normal advance rate is ~60 seconds, and `currentStateDuration` is not a freshness signal

```
09:23:26Z  BHNM-B-SE01  UP  lastUpdateTime 2026-09-20 11:23:02  dur 3d 19h 57m 22s
09:23:41Z  BHNM-B-SE01  UP  lastUpdateTime 2026-09-20 11:23:02  dur 3d 19h 57m 37s
09:24:11Z  BHNM-B-SE01  UP  lastUpdateTime 2026-09-20 11:24:03  dur 3d 19h 58m  7s
```

`lastUpdateTime` steps once a minute. **`currentStateDuration` advances on every single read**, so
it is computed at query time and can never distinguish fresh data from frozen data. Only
`lastUpdateTime` can. This re-confirms the 2026-09-16 finding on a second occasion.

**Consequence for the sampler: 30 s is the right interval.** It oversamples the ~60 s BHNM tick by
2×, which is what is needed to catch the first *missed* tick rather than the second.

### BHNM's timestamps are LOCAL (CEST, UTC+2). The middleware log is UTC.

**Measured:** BHNM returned `2026-09-20 11:15:22` at `09:15:22Z`. `lastUpdateTime`, `open_time` and
the BHNM UI are all local; `ts_utc` in the sampler, `/logs/middleware.log` and
`state_confirmed_at` are UTC. **This exact confusion is withdrawn claim (f)21 in the 09-20
handoff** — a two-hour error written into a record hours after the same mistake had been written
down. **Every timestamp in the result file says which it is.**

### A client today has NO freshness data at all — this is the defect, stated precisely

There is **no `/api/v1/devices` route** (`main.py` has incidents, incidents/{id}, qr-redeem,
tactical-overview, maintenance-map, threshold-counts, diagnostics, then a catch-all proxy). The
device list both clients render is:

| source | what it carries |
|---|---|
| `restful/devices/list`, proxied through the middleware catch-all | **configuration only** — no status, no `lastUpdateTime`. Confirmed in `shared/BHNM_API_REFERENCE.md` and re-read today |
| `GET /api/v1/maintenance-map` | `{cache_age_seconds, in_maintenance, scheduled, host_down}` — **the DOWN set and nothing else** |

`maintenance_cache.py:144-163` fetches `get-host-and-service-status`, which **does** carry
`lastUpdateTime`, and reads only `status` and `inMaintenance` from it. **The freshness field
arrives at the middleware every 60 seconds and is thrown away before any client sees it.**

So the prediction the run is testing is not "will the app look wrong" — it is *"the app cannot
look anything but green, because nothing it receives can say otherwise."* **If a screen does show
a problem during the outage, that is the surprise and it must be chased.**

### Identifying the Service Engine programmatically — **ANSWERED 2026-09-20, by `device_type`**

**[THOMAS] A Service Engine is always of type `"Helix Network Service Engine"`.**

**[MEASURED 2026-09-20 — against each instance separately, and the server is named because an
earlier version of this section got that wrong]** `restful/devices/list` returns `device_type` on
every row, and **a BHNM instance types its OWN Service Engines with that value**:

| instance queried | its own engines | `device_type` | estate |
|---|---|---|---|
| **BHNM-B** `bhnm-b.tstolt.com` | `BHNM-B-SE01` | `Helix Network Service Engine` | 41 devices |
| **BHNM-A** `bhnm-a-m.local` | `BHNM-A-SE01`, `BHNM-A-SE02` | `Helix Network Service Engine` | 32 devices |

BHNM-A's type distribution, whole estate:

```
 14  Linux/Net-SNMP                          2  Helix Network Service Engine
 12  Other Devices(interface polling only)   1  Helix Network Service Engine Group
  2  Cisco IOS Router                        1  Helix Network Core
```

**A Service Engine GROUP is a first-class object too**, which nothing in this project knew before
today: `BHNM-A-SE-GROUP`, `device_type: "Helix Network Service Engine Group"`, with a synthetic
`ip` of **`seg:1`** encoding the group id, `UID 190`, `dev_index 151`.

**Three mechanical caveats, all measured, all cheap:**

1. **Only `devices/list` carries `device_type`.** `devices/find` omits it, and so do
   `get-host-and-service-status` host rows. **Identification is a join on `name`** between the
   list and the status feed. The clients already fetch `devices/list`, so this costs nothing new.
2. **There is no server-side type filter.** `device_type`, `deviceType`, `type` and `filter` are
   all ignored by `devices/list`, which returns the whole estate in one page. Filter client-side.
3. **Match the exact string.** It is BHNM's own label and nothing here establishes that it is
   stable across versions or locales. **Treat an estate with zero matches as "cannot identify",
   never as "no engines"** — the doctrine's third state, applied to this lookup.

**`category` is unusable and it is worth saying why:** the id is **per-instance** — the Helix
category is `19` on BHNM-A and `36` on BHNM-B. `template` is `0` and `poll_intvl` is `5` for every
device on **both** instances, so neither discriminates anything.

### What is STILL not readable, and still comes from the operator

**Group membership, and the managed device set.** Against BHNM-A:
`groupFilterBy=strategicGroup|category|site` with the group name all return **400**; and
`restful/groups/list`, `restful/strategic-groups/list`, `restful/serviceengines/list` are all
**404**. The group object exists and can be *found*; it cannot be *expanded*.

### WITHDRAWN 2026-09-20 — "neither name nor description identifies a Service Engine"

**That claim came from querying ONE server about ANOTHER server's machines, and did not say so.**
The reading behind it — `BHNM-A-SE01`/`SE02` typed `Linux/Net-SNMP`, `Helix-Network-Core` and
`BHNM-A-M` described "Service Engine" but typed `Helix Network Core` — was taken **entirely from
BHNM-B**. Those are **B's rows about hosts it monitors over SNMP but does not manage.** That is
correct behaviour, not a lying field. The follow-on warning that `device_type` "misses two of
three engines in this very estate" was an artefact of the same error and is withdrawn with it.

**Rule taken from it, and applied throughout this file:** a measurement records **which server
produced it**, and no cross-server comparison appears in a document without both sides named.

---

## Part 1 — What is needed from Thomas before the run

1. **Which Service Engine** is being stopped. This runbook assumes **`BHNM-B-SE01`**, the lab's
   only confirmed standalone SE — confirm or name another.
2. **The device set that SE manages**, by name, exactly as BHNM spells them. **Group membership is
   not known to be readable from the API and this cannot be derived.** If the answer is "all of
   them", say so — then the watch list is the eight named in Part 2 plus SE01.
3. **The anomaly knob position, stated and then left alone for the whole window.** It is
   hand-operated in both directions and the rate is not a health signal
   (root `CLAUDE.md`; 09-19 handoff (c)). A knob moved mid-run makes "did anything page" unreadable.
   **Recommended: leave it ON** — a live anomaly generator is the only way to answer *"does the
   anomaly detector keep firing with the engine down"*, which is one of the questions.
4. **A phone with BeNeM installed and reachable**, for Part 4. The 13 Pro Max is on 2.13.6 (50)
   Debug with a sandbox token; that is fine — the screens are what is being read, not the build.
5. **The stop time, to the second, reported by Thomas**, and **nobody else touching SE01** for the
   window.
6. **Expected duration: ~90 minutes.** 20 min baseline, ~40 min down, ~30 min recovery. The
   2026-09-16 outage ran 26 minutes and that was enough to see the freeze, but not enough to see
   whether anything *eventually* fires.

---

## Part 2 — Arm the instrument, 20 minutes before the stop

The sampler is `docs/runbooks/se-outage-sampler.py`, shared with Experiment 2. It runs **inside
`benem-middleware`**, because `/data/servers.json` and `/logs/middleware.log` are already there and
no credential has to be typed or copied.

```bash
# from the repo root, on the laptop
scp docs/runbooks/se-outage-sampler.py root@bhnm-apns.hurrikap.org:/root/se_sampler.py
ssh root@bhnm-apns.hurrikap.org 'docker cp /root/se_sampler.py benem-middleware:/tmp/se_sampler.py'
```

```bash
# start it BEFORE the stop and leave it running. Output lands on the HOST, not in
# the container, so a container recreate cannot take the record with it.
ssh root@bhnm-apns.hurrikap.org \
  'docker exec benem-middleware python /tmp/se_sampler.py --interval 30 --devices \
     BHNM-B-SE01 Helix-Network-Core BHNM-A-M BHNM-A-A BHNM-A-R BHNM-A-SE01 BHNM-A-SE02 \
     BHNM-OV bhnm-apns.hurrikap.org raspi-050 raspi-059 \
   > /root/exp1-$(date -u +%Y%m%dT%H%M%SZ).jsonl 2>&1'
```

Replace the device list with **the set SE01 actually manages** once Thomas names it. Keep
`bhnm-apns.hurrikap.org` in it regardless — it is the OPEN FORK control and costs one call.

**In a second terminal, the log, visible throughout:**

```bash
ssh root@bhnm-apns.hurrikap.org \
  'docker logs -f --since 1m benem-middleware 2>&1 \
   | grep -E "\[Webhook\]|\[Deliver\]|\[APNs\]|Cache updated|ERROR|Traceback"'
```

**Confirm the sampler is producing non-empty rows before the stop.** One tick must show
`"rows_found": 1` for every watched device and `bhnm_incidents.count > 0`. *An empty result must
first be shown capable of returning a non-empty one* (`middleware/CLAUDE.md`) — and this sampler
has already returned a silent estate once, from a Cloudflare 403 on the default urllib
User-Agent. That is fixed; verify it anyway.

**Record before the stop, in the result file's header:**

- the middleware log line count (the sampler's `log.lines` — the before-mark)
- `/health` version and the four container `StartedAt` values
- the anomaly knob position as Thomas stated it
- what every app screen shows, per Part 4, **while everything is healthy**

---

## Part 3 — The stop

**Thomas stops SE01 and reports the exact time. Convert it to UTC and write both.**

Nothing else changes. No deploy, no `servers.json` edit, no restart of any container. If something
here seems to need one, stop and re-read this file.

Let it run **~40 minutes**, then Thomas restores it and reports that time the same way. Keep the
sampler running through the restore and for **30 minutes after**, because recovery timing is half
the result and the 2026-09-16 run did not capture it.

---

## Part 4 — The app screens, throughout

**On the phone, at four moments: baseline, +5 min, +20 min, +35 min — and again after recovery.**
Note the wall-clock time (UTC) against each.

| screen | what to write down |
|---|---|
| **Home** | the Active Incidents count; the status cards; **does anything on this screen say the data is old** |
| **Device list** | how `BHNM-B-SE01` renders; how a device it manages renders; **any grey, any dating, any warning** |
| **A device detail** for one managed device | status, and whether a timestamp appears anywhere |
| **Incident list** | which incidents, which states |
| **Diagnostics** | `bhnm.reachable`, the four feed ages, `list_age_seconds`, `unconfirmed_counts`, the version row |
| **The connection badge** | its colour and its words, verbatim |

**The prediction, stated so it can be falsified:** every screen stays green and the Diagnostics
feeds stay fresh, because the middleware keeps reaching BHNM's front end perfectly and BHNM keeps
answering with its last known values. **The badge goes green on "data arrived", and data does
arrive.** If any screen disagrees, that is the finding.

**Also note anything that pages, and anything that does not.** A phone that buzzes during the
outage is a data point; a phone that stays silent for 40 minutes while an engine is dead is the
headline.

---

## Part 5 — What to extract afterwards, and what each answer means for the design

Read the JSONL, not the scrollback. Every row below is `T+seconds from the reported stop`.

### 5.1 — Seconds until BHNM's own row for SE01 changes

The first tick where `bhnm_host_rows["BHNM-B-SE01"].rows[0].status != "UP"`, or where
`rows_found` drops to 0.

| outcome | what it means for the design |
|---|---|
| SE01 goes `DOWN` within a few minutes | **the engine is visible as a host.** The most page-worthy event on the system has a row, and the only open question is whether BeNeM can tell *which* row it is — decision 2, and Part 0 says name and description both lie |
| SE01 stays `UP`, frozen | the engine's own row is polled by the engine, so it cannot report its own death. **Staleness is then the only available signal and decision 2 collapses into "you cannot watch the engine, only the data"** |
| the row disappears | `rows_found: 0` is neither UP nor DOWN. **The clients would show nothing at all**, which is its own doctrine failure — an absent row must not render as an absent problem |

### 5.2 — Seconds until `lastUpdateTime` stops advancing, per managed device

The first tick where a device's `lastUpdateTime` equals the previous tick's **and keeps equalling
it**. Report per device, and report the spread across devices.

**This is the number the whole feature rests on.** Baseline advance is ~60 s, so a single repeat is
normal and two consecutive repeats is the first real evidence.

| outcome | what it means for the design |
|---|---|
| all managed devices freeze together, within ~60–120 s | **the cheap staleness check works, and the threshold floor is the freeze detection time.** Threshold = that, plus the handover gap from Experiment 2, plus margin. **Do not set a threshold from this run alone** |
| they freeze at staggered times | the threshold has to clear the spread as well. Record the spread explicitly |
| some keep advancing | those are not managed by SE01 — which is itself the answer to Part 1 question 2, arrived at the hard way. Say so rather than treating it as noise |
| none freeze | **the premise is wrong and the feature has no signal.** Stop; do not design a marker with nothing to drive it |

### 5.3 — Seconds until any incident opens, and whether anything pages

Cross `bhnm_incidents.rows` (new `incident_id`s) against the webhook log, by **incident id**.

| outcome | what it means |
|---|---|
| an incident opens for SE01 and **no webhook fires** | this is the 2026-09-16 result (incidents 29585, 29628) repeating, and the explanation *"a crashed engine cannot notify"* is **already withdrawn** — the appliance sends webhooks and it is healthy. So the cause is coverage: SE01's alarm class is not attached to the action group. **That makes the engine outage the flagship case for the never-paged marker** in `2026-09-16-coverage-visibility-design.md` |
| an incident opens and **it pages** | better news than expected. Record the payload's `alert_type` |
| **no incident opens at all** | the engine's death is invisible to the incident system. Then nothing pages by construction, and the only possible product answer is client-side staleness |
| incidents open for the **managed devices** | unexpected against the 2026-09-16 measurement, which found devices retain their last state. Chase it |

### 5.4 — Does the anomaly detector keep firing with the engine down?

Count `[Webhook]` lines with `Anomaly` titles before, during and after, per 10-minute bucket.
**Only meaningful if the knob did not move** — if it did, this question has no answer and must be
written as "not measured", not as zero.

| outcome | what it means |
|---|---|
| anomalies keep arriving | **the phone keeps buzzing while the estate is unmonitored.** The single most dangerous shape in this whole document: a paging product that is actively paging is the one nobody suspects. It makes the staleness banner mandatory rather than nice |
| anomalies stop | a quiet phone is at least an honest one — but silence is indistinguishable from the knob being off, which is why the knob position is recorded |

### 5.5 — What the middleware and the clients served throughout

From `mw_incidents`, `mw_maintenance_map`, `mw_diagnostics`:

- `host_down` — expected **0 or 1** (SE01 only). **If it stays 0 while an engine is dead, that is
  the screenshot for the design note.**
- Diagnostics feed ages — expected to stay **normal**, because the caches keep succeeding.
- `unconfirmed_counts` and `list_age_seconds` — expected normal. **C9's timestamps measure the
  middleware's own enrichment, not BHNM's freshness, and this run is where that distinction stops
  being theoretical.** If C9's numbers look healthy through a dead engine, then C9 cannot be the
  staleness mechanism and the design needs `lastUpdateTime` plumbed through separately.

### 5.6 — The OPEN FORK, settled in the same window

For `bhnm-apns.hurrikap.org`, **and for one known-good device as a control**, run the service-row
comparison once during the outage and once after:

```bash
ssh root@bhnm-apns.hurrikap.org 'docker exec benem-middleware python - <<'"'"'PY'"'"'
import json,urllib.request,urllib.parse
s=json.load(open("/data/servers.json")); c=[x for x in s if x["id"]=="ThomasLabServer"][0]
for name in ("bhnm-apns.hurrikap.org","raspi-059"):
    for f in ("host_only","service_desc"):
        d=urllib.parse.urlencode({"password":c["api_key"],"groupFilterBy":"device",
            "groupFilterValue":name,"serviceFilter":f,"recordCount":"100"}).encode()
        r=urllib.request.Request(c["url"].rstrip("/")+
            "/fw/index.php?r=restful/devices/get-host-and-service-status",data=d,
            headers={"Content-Type":"application/x-www-form-urlencoded",
                     "User-Agent":"BeNeM-probe/1.0"})
        j=json.load(urllib.request.urlopen(r,timeout=30))
        for row in j.get("statuses",[]):
            print(name,f,row.get("status"),row.get("lastUpdateTime"),row.get("currentStateDuration"))
PY'
```

| outcome | branch |
|---|---|
| its **service** rows carry fresh timestamps while the host row does not | **B** — `lastUpdateTime` is not comparable across management paths, and a naive marker has a permanent false-positive class. The design must detect or exempt them |
| both are equally stale | **A** — BHNM genuinely has not checked that host, and the cheap check has found a real gap in Thomas's own estate before a line of code exists |

**Part 0 already leans B** — on that device `lastUpdateTime` equals the state-change instant, while
on `BHNM-A-M` it is a per-poll refresh. **This probe is what turns that from a reading into a
result.** Do not skip it because the answer looks known.

---

## Part 6 — Restore, and prove the restore

1. Thomas restarts SE01 and reports the exact time.
2. **Record recovery the same way as the outage:** seconds until `lastUpdateTime` advances again
   per device; seconds until SE01's own row reads `UP`; whether the SE incident closes; whether a
   RECOVERY webhook arrives and whether it pages; whether the middleware caches show any
   disturbance at all.
3. **Confirm the lab is back by searching for the objects by name, never by a count** — root
   `CLAUDE.md`: the Actions Administration counter has been wrong twice.
4. Stop the sampler. Copy the JSONL off the VPS.
5. **Write the evidence file** — `docs/evidence/2026-09-20-experiment-1-standalone-se-shutdown.md`
   — with the raw ticks inline for the moments that matter, every timestamp labelled Z or CEST,
   and a plain statement of anything that was **not** measured.

**Nothing is designed, decided or built from this run in the same sitting.** The results go back
to `2026-09-16-engine-down-stale-data-design.md`, decisions 2 and 4, and Thomas rules.
