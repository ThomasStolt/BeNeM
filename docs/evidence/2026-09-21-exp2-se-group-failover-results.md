# Experiment 2 — BHNM-A Service Engine Group failover: RESULTS

**Run 2026-09-20T15:51:36Z → 2026-09-21T06:13:31Z. 3449 ticks at 15 s, no sampling gap over 60 s.**
Raw record: `docs/evidence/2026-09-20-exp2-failover.jsonl`.
Instrument: `docs/runbooks/se-failover-sampler.py`, run on the laptop against **BHNM-A**
(`bhnm-a-m.local`) — the server is named because a measurement without its source is how the
2026-09-20 `device_type` error happened.

**T0 = `2026-09-20T16:01:04.500Z`** — `qm stop 212` on node `pve`. Issued 16:01:01.654Z, reported
`stopped` by 16:01:04.500Z, so T0 is accurate to under 3 s. Taken by CC, not reported by hand.

**All BHNM timestamps below are LOCAL (Europe/Berlin, UTC+2). `T+` values are wall clock.**

---

## THE NUMBER

> **HANDOVER GAP = 21 minutes 58 seconds.**
>
> Frozen at `2026-09-20 18:01:05` — the second of the stop.
> Resumed at `2026-09-20 18:23:03`.
> **Identical for all 13 devices, to the second.** No stagger.

Wall clock: frozen from **T+1 s**, resumed at **T+22 m 01 s**.

---

## Timeline

| T+ | event |
|---|---|
| **0** | `qm stop 212`. SE01 hard-stopped |
| **+1 s** | all 13 SE01 devices freeze at `lastUpdateTime 18:01:05`. **Zero false positives** — SE02's 12 kept advancing throughout |
| **+13 m 01 s** | `BHNM-A-SE01`'s own row flips `UP` → **`DOWN`**, message `"No updates received in the last 10 minutes."` |
| **+13 m 16 s** | incident **141184** opens, `BHNM-A-SE01` (`18:14:13`). **Still OPEN 14 h later** |
| **+19 m 12 s** | BHNM UI shows all 25 devices reassigned to SE02 — **while their host rows are still frozen** |
| **+22 m 01 s** | **all 13 resume**, `lastUpdateTime 18:23:03` |
| **+24 m 16 s** | `BHNM-A-SE-GROUP` message changes to `"(Host check triggered from Service Service Engine 'BH…"`. Status stays `UP` |
| **+24 m 31 s** | incident **141187** opens, `BHNM-A-SE-GROUP` (`18:25:23`). **Still OPEN** |
| +14 h | SE01 still stopped. Everything below measured against that |

---

## Polling rates, per phase

| phase | SE01's 13 devices | SE02's 12 devices |
|---|---|---|
| **baseline**, pre-stop | n=52, median **128 s**, max **225 s** | n=108, median 60 s, max 75 s |
| **outage**, T+0…22 m | **NO ADVANCE AT ALL** | n=228, median 60 s, max 135 s |
| **post-handover**, T+30 m…now | n=7709, median **60 s**, max **420 s** | n=7116, median 60 s, max 420 s |

**SE02 polls SE01's former devices BETTER than SE01 did** — median 128 s → 60 s. Their pre-stop
irregularity was real, and consistent with SE01's standing `"No updates received."` message.

**The normal maximum is now 420 s on both sets**, not the 225 s measured pre-stop. Any threshold
has to clear the *current* worst case, not the baseline's.

---

## What was visible, and what was not

**[MEASURED] `status` never moved. Not once.** All 13 devices read `UP` at **every one of 3449
ticks** — before, during and after 22 minutes in which nothing on the network was checking them.

**[MEASURED] `currentStateDuration` actively misleads.** It is computed at query time, so during
the freeze `C9200CX` read `10d 16h 56m 55s` and climbing. A row with a rising duration looks more
alive than a static one, not less.

**[MEASURED] `lastUpdateTime` was the only signal, and it was perfect.** Froze on the exact second,
on exactly the right 13 devices, resumed on the exact second, no false positive on the other 12
across 14 hours.

**[MEASURED] Watching the ENGINE is too slow.** `BHNM-A-SE01`'s row asserted `UP` for the first
**13 minutes** after its VM was hard-stopped, and BHNM's own detection is a 10-minute "no updates"
check. By the time the engine reads `DOWN`, the devices have been stale for 13 minutes.

**[MEASURED] The GROUP object does page — and it is also too slow, and it lies about itself.**
`BHNM-A-SE-GROUP` raised incident **141187** at T+24 m 31 s, which is **after** the handover had
already completed. Its own row still reads `status: UP` with an open incident against it, and its
`lastUpdateTime` has been frozen at `18:25:10` for over 15 hours. Useful as a **paging** signal,
useless as a **freshness** signal.

**[MEASURED] SE01's former devices are genuinely monitored now.** Overnight they raised incidents
normally — `UAP-AC-Pro-DB` 42, `UAP-AC-LR-Keller` 26, `US-8-60W-DB2` 6, `C9200CX` 1, `US-24-G1` 1.
This is the check that keeps the result honest: an absence of incidents would not have distinguished
"monitored and quiet" from "not monitored".

---

## The design consequence, and it INVERTS the 2026-09-16 prediction

The engine-down note recorded, marked **[PREDICTION — not measured]**:

> Under *working* failover, `lastUpdateTime` should **keep advancing** … The staleness check should
> therefore stay **correctly quiet** during a single-SE failure inside a healthy group.

**That is wrong, and it is wrong in the direction that matters.** Failover on this deployment
leaves **22 minutes during which 13 devices are checked by nothing and rendered green.** A
staleness marker that stays quiet through that is not being correct — it is reproducing the exact
defect this project keeps shipping.

**So the threshold is NOT bounded above by the handover gap.** It is bounded below by the normal
polling maximum, and the marker firing during a failover is **correct behaviour, not a false
positive.**

| threshold | fires during failover at | verdict |
|---|---|---|
| > 22 min | never | **hides a real 22-minute blind spot.** Rejected |
| **~10 min** | **T+10 m**, 12 min before recovery | clears the observed 420 s maximum with margin, and tells the truth |
| < 7 min | would fire on normal polling | false positives. Rejected |

**Recommendation: 10 minutes, per device, on `lastUpdateTime`.** It is derived from the measured
420 s worst case, not guessed, and it beats BHNM's own engine detection by three minutes.

---

## Still open

- **Fail-BACK is unmeasured.** SE01 has been stopped for 14 h. Restarting it, with the sampler
  still running, measures the return gap for free. A fail-back gap larger than 21 m 58 s would be
  the number that sets the threshold instead.
- **Whole-group failure is unmeasured.** Stopping SE02 as well is the second scenario Thomas named.
- **No app-side observation exists**, by design: BHNM-A is not in `servers.json` and has no
  connectivity to the middleware. Everything here is BHNM-side.
- **Incident 141184 (`BHNM-A-SE01`) and 141187 (`BHNM-A-SE-GROUP`) are both still OPEN** and will
  need clearing when SE01 comes back — worth watching, since the recovery path is untested.
