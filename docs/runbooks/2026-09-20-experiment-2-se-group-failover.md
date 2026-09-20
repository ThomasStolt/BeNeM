# Runbook — Experiment 2: Service Engine Group failover

**Written 2026-09-20. NOT RUN. Blocked on Thomas building the group — there is no SE group in the
lab today.** Nothing starts until he says go.
**Read-only on BeNeM's side. The lab changes are Thomas creating the group and stopping one SE.**

**Method is the one already written into
`specs/2026-09-16-engine-down-stale-data-design.md` ("PLANNED MEASUREMENT — grouped SE failover").
It stands unchanged; this file is that method made runnable, with the 2026-09-20 measurements
folded in.**

---

## The one number this exists to find

> **THE HANDOVER GAP: how long `lastUpdateTime` pauses on the handed-over devices before the
> surviving SE advances it.**

Everything else in this runbook is instrumentation around that number.

**Why it decides the feature.** The staleness threshold must be **above** the handover gap, or the
marker fires on every normal failover — a system working exactly as designed, crying stale. It must
be **below** the point at which an operator would have acted on wrong data. Those two bounds are
the design, and only one of them can be guessed.

**Run Experiment 1 first.** It supplies the other bound — how fast a freeze is detectable at all —
and this run is meaningless without it.

---

## Part 0 — What is already measured

Everything in **Part 0 of the Experiment 1 runbook applies here unchanged** and is not repeated:
the ~60 s advance rate, `currentStateDuration` being computed at query time and useless as
freshness, BHNM's LOCAL (CEST) timestamps against the middleware's UTC, the absence of any
`/api/v1/devices` route, and the fact that the middleware fetches `lastUpdateTime` every 60 seconds
and discards it before any client sees it.

**Read it before this one.**

### One finding from 2026-09-20 that matters more here than there

At `09:24Z`, eight of the nine `BHNM`-category host rows read `lastUpdateTime 11:22:02`
**to the second**, while `BHNM-B-SE01` read `11:24:03`.

**Devices refreshed by the same poller share a timestamp.** That is not an incidental detail here —
it is the read-out mechanism. **A handover should be visible as a set of devices leaving one
timestamp cohort and joining another**, and that is a sharper signal than watching each device
individually. Record the cohorts, not just the per-device values.

### The prediction this run tests, stated so it can fail

From the design note, marked **[PREDICTION — not measured]**: under working failover
`lastUpdateTime` **keeps advancing**, because a different engine polls the same devices, and the
staleness check therefore stays correctly quiet during a single-SE failure inside a healthy group.

**That is a prediction and it has never been observed.** The 2026-09-16 outage measured a
*standalone* engine and says nothing about failover. **If it is wrong — if handover means minutes
of frozen rows — the threshold has to be generous enough to cover it, and a generous threshold is a
slower alarm.** That trade is the result.

---

## Part 1 — What is needed from Thomas before the run

This experiment **does not exist** until items 1 and 2 are done.

1. **The SE group, built.** At least **two** Service Engines in one group, configured for failover.
   There is no such group in the lab today.
2. **The device set managed by the SE that will be stopped** — by name, exactly as BHNM spells
   them. **Group membership is not known to be readable from the API**, so this cannot be derived
   and cannot be guessed. **This is the prerequisite the design note names, and it is still
   Thomas's to supply.**
3. **Which SE is being stopped**, and confirmation that **the other SE in the group is healthy at
   the start** — a failover into a sick partner measures something else entirely.
4. **The anomaly knob position, stated and then left alone**, same as Experiment 1. Recommended
   ON, so *"does the failed SE page"* has an answer rather than a silence.
5. **A phone with BeNeM installed**, for Part 4.
6. **The stop time to the second**, reported by Thomas, and **nobody else touching either SE**.
7. **Expected duration: ~2 hours.** The design note asks for **at least 60 minutes** of sampling
   after the stop, plus 20 minutes of baseline and a recovery window. A short run that sees the gap
   close is not evidence that it always closes.

---

## Part 2 — Arm the instrument, 20 minutes before the stop

**Same sampler, same discipline, same file** — `docs/runbooks/se-outage-sampler.py`.

```bash
scp docs/runbooks/se-outage-sampler.py root@bhnm-apns.hurrikap.org:/root/se_sampler.py
ssh root@bhnm-apns.hurrikap.org 'docker cp /root/se_sampler.py benem-middleware:/tmp/se_sampler.py'
```

```bash
# --devices = BOTH SEs in the group + every device the stopped one manages.
# Keep a device managed by the OTHER SE as a control, and keep
# bhnm-apns.hurrikap.org as the OPEN FORK control.
ssh root@bhnm-apns.hurrikap.org \
  'docker exec benem-middleware python /tmp/se_sampler.py --interval 30 --devices \
     <SE-being-stopped> <surviving-SE> <managed-device-1> <managed-device-2> ... \
     <control-device-on-other-SE> bhnm-apns.hurrikap.org \
   > /root/exp2-$(date -u +%Y%m%dT%H%M%SZ).jsonl 2>&1'
```

**30 seconds, not 60.** The handover gap is the measurement, and a 60 s sampler against a 60 s BHNM
tick cannot resolve a gap shorter than two minutes. **If the gap comes out at one or two ticks, say
so as "under 60 s, below this instrument's resolution" — not as a number.**

**Second terminal, the log:**

```bash
ssh root@bhnm-apns.hurrikap.org \
  'docker logs -f --since 1m benem-middleware 2>&1 \
   | grep -E "\[Webhook\]|\[Deliver\]|\[APNs\]|Cache updated|ERROR|Traceback"'
```

**Before the stop, confirm and record:**

- **20 minutes of clean baseline.** Every watched device returning `rows_found: 1`, every
  `lastUpdateTime` advancing, and **the timestamp cohorts written down** — which devices share a
  value with which. This is the before-picture of the handover and there is no second chance at it.
- `bhnm_incidents.count > 0`, so the incident read is shown capable of a non-empty answer.
- `/health` version, the four container `StartedAt` values, the sampler's `log.lines` before-mark.
- The anomaly knob position as Thomas stated it.
- The app screens, per Part 4, while healthy.

---

## Part 3 — The stop

**Thomas stops one SE in the group and reports the exact time. Convert to UTC and write both.**

**Sample for at least 60 minutes.** Then Thomas restores it and reports that time the same way;
keep sampling for 30 minutes past the restore.

No deploy, no config change, no container restart on BeNeM's side at any point.

---

## Part 4 — The app screens

**Baseline, +2 min, +10 min, +30 min, +60 min, and after recovery.** Same table as Experiment 1:
Home, device list, a device detail, incident list, Diagnostics, the connection badge — each with a
UTC time against it.

**The prediction here is the opposite of Experiment 1's and just as falsifiable:** if failover
works, **everything stays green and everything stays true**, and there is nothing to see. **That
null result is the point** — it is the evidence that a staleness marker set above the handover gap
will not fire on a healthy failover.

**What would be a finding:** an incident or a page reaching the phone during a failover that cost
nobody anything. A paging product that pages for a non-event trains its users to ignore it.

---

## Part 5 — What to extract, and what each answer means

### 5.1 — THE HANDOVER GAP, per handed-over device

For each managed device: the last tick before its `lastUpdateTime` stops advancing, and the first
tick after it resumes. **The gap is between those two `lastUpdateTime` values — BHNM's own clock,
not the sampler's.** Report per device, then report the **maximum**, because the threshold has to
clear the worst case and not the median.

| outcome | what it means for the design |
|---|---|
| **no pause at all** — advance continues through the stop | failover is seamless at this resolution. **The threshold is then governed entirely by Experiment 1's detection floor**, and the staleness marker is cheap and safe. The best available outcome |
| **a gap under ~2 minutes** | threshold = that, plus the freeze-detection time, plus margin. Quote the number and the margin separately so a later reader can re-derive it |
| **a gap of many minutes** | the threshold must be generous, which makes the marker slow. **Then "stale" cannot be a single global number** — it needs either a per-device poll-interval multiple or an explicit "failover in progress" state, and decision 4 changes shape |
| **the gap never closes** | failover did not work, and the experiment measured a broken group rather than a working one. **That is a lab finding, not a product finding** — say so, and re-run after Thomas fixes it |
| **devices freeze at staggered times** | record the spread. A threshold that clears the median and not the spread fires on a third of the estate |

### 5.2 — Do the handed-over devices join the surviving SE's timestamp cohort?

Per Part 0: same-poller devices share a `lastUpdateTime` to the second.

| outcome | what it means |
|---|---|
| they move into the surviving SE's cohort | **handover is directly observable from the API**, with no group membership needed. That is a stronger answer than the gap alone and it partially rescues decision 2 — BeNeM could infer poller grouping from timestamp cohorts without any config |
| they keep their own cohort | the cohort signal is coincidence, not structure. Drop it; the per-device gap is the only measurement |

### 5.3 — Does `status` change at any point?

The 2026-09-16 standalone result was that devices **retain their last state** and do not go
unknown. Confirm or overturn that under failover.

**Any managed device reading `DOWN` during a successful failover is a false alarm generated by
BHNM itself**, and BeNeM would render it faithfully. That would be worth a BHNM ticket, not a
BeNeM feature.

### 5.4 — Does the failed SE raise its own incident, and does it page?

Cross the new incident ids against the webhook log **by incident id**, never by a count.

This is the 2026-09-16 question (incidents 29585 and 29628: an incident opened, **no webhook**)
asked again on a **grouped** engine.

| outcome | what it means |
|---|---|
| incident + **no webhook** | the standalone result repeats, and the cause is coverage — the SE's alarm class is not attached to the action group. **The withdrawn explanation "a crashed engine cannot notify anyone of its own crash" must not be resurrected**: the appliance sends the webhooks and it is healthy throughout. (09-18 handoff §(f), carried forward) |
| incident **and** a webhook | record the payload's `alert_type`, and note that the engine-down case can page after all |
| **no incident** | a grouped SE's failure is invisible to the incident system. Combined with a seamless handover that is arguably correct behaviour — nothing was lost — but it means **a group degrading to its last engine is silent**, which is the case that matters |

### 5.5 — What the middleware and the clients served

From `mw_maintenance_map`, `mw_incidents`, `mw_diagnostics`: `host_down`, the four feed ages,
`list_age_seconds`, `unconfirmed_counts`.

**Expected: entirely normal throughout, because a working failover means nothing was ever wrong.**
Record it anyway — a normal reading during a real failover is the baseline that makes the abnormal
reading in Experiment 1 legible.

---

## Part 6 — Restore, and prove the restore

1. Thomas restarts the stopped SE and reports the exact time.
2. **Record the fail-BACK the same way as the failover** — this is the half the design note does
   not ask for and it is free while the instrument is running. Do the devices return to the
   restored SE? Is there a second gap? **A fail-back gap counts against the same threshold as the
   failover gap**, and if it is larger it is the one that sets the number.
3. **Confirm the lab is back by searching for each object by name, never by a count** — root
   `CLAUDE.md`, the Actions counter has been wrong twice.
4. If the group was built only for this experiment, **teardown is Thomas's** and is confirmed the
   same way: by failing to find the object by name, not by watching a counter move.
5. Stop the sampler. Copy the JSONL off the VPS.
6. **Write the evidence file** — `docs/evidence/2026-09-20-experiment-2-se-group-failover.md` —
   with the raw ticks around each transition inline, every timestamp labelled Z or CEST, the
   handover gap stated per device **and** as a maximum, and a plain statement of anything **not**
   measured. **"No pause observed" is only a result if the instrument is stated alongside it**:
   write "no pause above the 30 s sampling resolution", not "no pause".

**Nothing is designed, decided or built from this run in the same sitting.** The results go to
`2026-09-16-engine-down-stale-data-design.md` decisions 2 and 4, together with Experiment 1's, and
Thomas rules.
