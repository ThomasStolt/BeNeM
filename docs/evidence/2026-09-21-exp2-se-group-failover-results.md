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

**[MEASURED] The GROUP object raises its own incident — and it is too slow, it lies about itself,
and no alert notification was sent for it.**
`BHNM-A-SE-GROUP` raised incident **141187** at T+24 m 31 s, which is **after** the handover had
already completed. Its own row still reads `status: UP` with an open incident against it, and its
`lastUpdateTime` has been frozen at `18:25:10` for over 15 hours. Useful as an **incident** signal,
useless as a **freshness** signal — and see the alert-notification section below, which is the
reason the distinction matters.

**[MEASURED] SE01's former devices are genuinely monitored now.** Overnight they raised incidents
normally — `UAP-AC-Pro-DB` 42, `UAP-AC-LR-Keller` 26, `US-8-60W-DB2` 6, `C9200CX` 1, `US-24-G1` 1.
This is the check that keeps the result honest: an absence of incidents would not have distinguished
"monitored and quiet" from "not monitored".

---

## Did 141184 and 141187 send an ALERT NOTIFICATION?

**Asked because "an incident opened" and "somebody was told" are different facts, and only the
second one matters to a product whose job is telling somebody.**

### 141184 (`BHNM-A-SE01`) and 141187 (`BHNM-A-SE-GROUP`): NO — and the absence proves nothing about BHNM

**[MEASURED]** `grep` over the whole middleware log returns **no line naming either incident id**,
and **zero lines naming the group object at all**, ever.

**That absence is structural and must not be read as a finding about BHNM's behaviour.**
BHNM-A is on `192.168.2.208`, a LAN address with **no route to the middleware**, so no alert
notification from BHNM-A could have arrived however its action group is configured. Whether A has
an action group, a method, or either incident attached to one is **unmeasured** — and the honest
statement is *"not measured"*, not *"did not notify"*. Root `CLAUDE.md`: before writing "cannot",
ask what observation distinguishes it from "did not".

### But BHNM-B detected the same outage independently, and DID send one — ten minutes sooner

**[MEASURED]** BHNM-B monitors the A-stack machines as ordinary SNMP hosts (it carries
`BHNM-A-SE01` typed `Linux/Net-SNMP`; see the 2026-09-20 correction). It raised **its own**
incident and its action group fired:

```
2026-09-20 16:04:15,324Z [Webhook] PROBLEM — BHNM-A-SE01 — Incident 29944
2026-09-20 16:04:15,327Z [Webhook] Queued delivery to 6 target(s) for incident 29944
```

**`16:04:15Z` is T+3 m 11 s.** Against BHNM-A's own detection of the same event at **T+13 m 01 s**.

| detector | what it watches | time to alert notification |
|---|---|---|
| **BHNM-B**, host check on the engine's IP | is the box reachable | **T+3 m 11 s**, delivered to 6 targets |
| **BHNM-A**, engine check on its own SE | `"No updates received in the last 10 minutes."` | T+13 m 01 s, incident only, no route to notify |
| **BHNM-A**, the group object | passive check | T+24 m 31 s, incident only |

**A plain host check on the engine's address beats BHNM's own engine-health check by ten minutes.**
The engine-specific check has a 10-minute window built into its wording, and it spends that window
asserting `UP`.

Note the two ids are not comparable and must not be conflated: **29944 is a BHNM-B incident id**
(B's run in the 29xxx range) and **141184 is BHNM-A's** (141xxx). Two servers, two incidents, one
outage.

### The log independently corroborates yesterday's whole VM timeline

**[MEASURED]** Unprompted confirmation from a second source, which is why it is kept:

```
2026-09-20 11:04:15,018Z  PROBLEM  BHNM-A-SE02  Incident 29933   <- ~4.5 min after both VMs destroyed (10:59:40Z)
2026-09-20 11:04:15,021Z  PROBLEM  BHNM-A-SE01  Incident 29934
2026-09-20 14:04:16,955Z  RECOVERY BHNM-A-SE01  Incident 29934   <- after the rebuild started ~13:55Z
2026-09-20 14:09:20,279Z  RECOVERY BHNM-A-SE02  Incident 29933
2026-09-20 14:18:14,759Z  PROBLEM  BHNM-A-SE01  Incident 29942   <- SE01 up, NIC not connected
2026-09-20 14:28:27,433Z  RECOVERY BHNM-A-SE01  Incident 29942   <- "Automatically connect" ticked
2026-09-20 16:04:15,324Z  PROBLEM  BHNM-A-SE01  Incident 29944   <- THIS EXPERIMENT, T+3m11s
```

**The control this needs:** the log was demonstrably capable of a non-empty answer in the window —
**245 webhook lines** between 2026-09-20 16:00Z and 2026-09-21 06:15Z. So the silence about 141184
and 141187 is a silence about *those* incidents, not a dead log.

### What it means for the design

**BeNeM should not wait for an engine-health check.** The fastest, simplest and already-working
detector of an engine outage is **a host check on the engine's own address from a server that is
not that engine** — which is exactly what BHNM-B does, at 3 minutes, with an alert notification
that reaches the phones today.

The 10-minute staleness threshold recommended below therefore covers a **different** case: not
"the engine died" — that is detectable in 3 minutes by a second BHNM — but **"these rows stopped
being refreshed for any reason"**, which no incident anywhere describes and which stayed
invisible for the full 22 minutes.

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

## Fail-back — SE01 restarted 2026-09-21

**T1 = `2026-09-21T06:34:50.364Z`** — `qm start 212`. Issued 06:34:46.870Z, reported `running` by
06:34:50.364Z. Sampler ran continuously across both events, so fail-back and failover are on one
timeline.

| T1+ | event |
|---|---|
| **+2 m 25 s** | `BHNM-A-SE01` row flips **`DOWN` → `UP`**, message `"No updates received in the last 10 minutes."` → **`"Updates received."`** |
| **by +8 m 40 s** | incident **141184** (`BHNM-A-SE01`) has **CLOSED** |
| **+8 m 40 s** | incident **141187** (`BHNM-A-SE-GROUP`) is **STILL OPEN**, 15 h 46 m old |

### No pause occurred — and that is NOT yet the same as "fail-back is free"

**[MEASURED]** Across the first 8 m 40 s after the restart, SE01's 13 devices advanced **n=78**
times, **median 60 s, longest single pause 240 s** (`vusolo4k`, `08:35:10 → 08:39:05`) — inside the
normal post-handover maximum of 420 s. **Nothing froze.**

**[NOT MEASURED, and the distinction matters] Whether ownership has returned to SE01 at all.**
The API exposes no service-engine assignment field — `devices/list`, `devices/find` and
`get-host-and-service-status` all omit it, and the group object cannot be expanded. So the
observation above is consistent with **two different worlds**:

| | what it would mean |
|---|---|
| devices have moved back to SE01 | **fail-back is seamless** — no gap at all, against 21 m 58 s going out |
| devices are still on SE02 | **fail-back has not happened yet**, and its gap is still ahead |

**Only the BHNM UI's Service Engine tab distinguishes them, and that is Thomas's read.** Until it
is made, the fail-back gap is **unknown**, not zero. Writing "no gap" here without this paragraph
would be the same error as the 2026-09-20 `device_type` claim: a true observation carrying an
untrue implication because its source was not stated.

### The engine's own `message` changed, and it had not before

`BHNM-A-SE01` now reads **`"Updates received."`** — the string `BHNM-B-SE01` has always carried.
Before this experiment it read `"No updates received."` continuously for hours
(`docs/evidence/2026-09-20-se-message-watch.jsonl`). `BHNM-A-SE02` still reads
`"No updates received."`. Recorded as an observation; no cause is claimed.

### `BHNM-A-SE-GROUP` has a stuck incident

Incident **141187** has been open **15 h 46 m** while the group's own row reads `status: UP` with
`lastUpdateTime` frozen at `2026-09-20 18:25:10` — unchanged since 2 minutes after it opened.
**An object asserting `UP` while carrying its own open incident, and not refreshed in 15 hours,
is the doctrine case wearing a third costume.** Whether it clears on its own is worth watching.

---

## Still open

- **Fail-back gap: UNKNOWN**, pending the UI read above. Not zero.
- **No RECOVERY alert notification for BHNM-B's incident 29944 yet**, 9 minutes after SE01 came
  back and 2.5 minutes after its row read `UP`. The PROBLEM went out at T+3 m 11 s; the matching
  RECOVERY is still outstanding and is worth chasing, because "does every clear produce one" is
  already on the 09-18 handoff's NOT VERIFIED list.
- **Whole-group failure is unmeasured.** Stopping SE02 as well is the second scenario Thomas named,
  to run once he confirms the lab is settled.
- **Whether BHNM-A has an action group or method at all is unmeasured**, and cannot be inferred
  from the silence — BHNM-A has no route to the middleware.
- **No app-side observation exists**, by design: BHNM-A is not in `servers.json`.
