# Design: what BeNeM shows when the engine behind the data is down

**Status:** **DEFERRED TO MEASUREMENT — RULED 2026-09-19 (Thomas). Decisions 2 and 4 wait for two
lab experiments. Both SCHEDULED 2026-09-20 — runbooks written, awaiting Thomas's go.**
STOP AT DESIGN — nothing built.
**Date:** 2026-09-16. **Ruled 2026-09-19.**
**Queue:** item 13. **Ranked against item 11 below — it does not displace it.**

---

## RULED 2026-09-19 (Thomas): deferred to measurement, not deferred by priority

**Thomas will run two lab experiments with Claude Code before this is designed further:**

1. **A standalone Service Engine shutdown, with full timing.** What the estate looks like from the
   API while the engine is down, and how long each symptom takes to appear.
2. **An SE Group failover.** **Thomas sets the group up first** — there is no SE group in the lab
   today, so this experiment does not exist until he builds it.

**Decisions 2 and 4 are held open until those results are in.** Decision 2 (can the Service Engine
be identified programmatically) and decision 4 (per-row staleness plus one banner, or a
modal-level interruption) are both answers that a guess would make worse — the first is a question
about what the API actually returns during an outage, and the second depends on what the outage
looks like on screen, which nobody has seen.

### SCHEDULED 2026-09-20 (Thomas): both experiments run NOW, before any further build

**Everything else waits behind them.** Runbooks written 2026-09-20 and ready to paste:

- `docs/runbooks/2026-09-20-experiment-1-standalone-se-shutdown.md`
- `docs/runbooks/2026-09-20-experiment-2-se-group-failover.md`
- `docs/runbooks/se-outage-sampler.py` — one instrument, used unchanged by both

**Experiment 2 is still blocked on Thomas building the group**; experiment 1 needs only his go, the
SE name and the managed device set. **Run 1 before 2** — 1 supplies the freeze-detection floor and
2 supplies the handover gap, and the threshold is bounded by both.

**Read-only observations taken 2026-09-20 while writing the runbooks are folded into them and
change what the runs must look at:** `currentStateDuration` advances on every read and is useless
as freshness (only `lastUpdateTime` is); BHNM's timestamps are **local CEST** against the
middleware's UTC; and **decision 2 is ANSWERED — `device_type`, see below** (and a Service Engine
GROUP turns out to be a first-class object too). The OPEN FORK device
has also **moved** its frozen timestamp since 2026-09-16, which makes branch B more likely, not
less — detail in experiment 1's Part 0.

**No probe is to be run unasked beyond those runbooks, and nothing in them starts without Thomas's
go on the day.** **Do not design against an imagined result, and do not fold this note into the
webhook-first work** — the two are independent, and
`2026-09-19-incident-freshness-webhook-first-design.md` deliberately does not depend on any answer
from here.

**Decision 3** (approve the `lastUpdateTime` read-only measurement) is **absorbed into experiment
1** — it is the same observation, and running it separately would waste the one controlled outage.

---

## Provenance, stated first

This document mixes three kinds of statement and they must not be read as equivalent.

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed by me, in this repository or against the live deployment, with the observation recorded |
| **[THOMAS]** | Thomas's account of how BHNM behaves. Not verified by me. The design's central premise is one of these |
| **[INFERENCE]** | My reasoning from the above. Wrong inferences have already cost this project one correction today |

## The premise

**[THOMAS]** The Service Engine manages **all** devices. If it is down, BHNM cannot reach
anything — so an SE outage is the *cause* of device-level symptoms, never the effect of one host
going away.

**[MEASURED — was [THOMAS], confirmed by controlled outage 2026-09-16, evidence §8.13]** When the
Service Engine is down, **devices retain their last state in BHNM**. They do not go unknown, they
do not go down. All four watched devices read `UP` with `lastUpdateTime` frozen at `10:47:03` for
the whole 26-minute outage, and `host_down` contained only the engine itself.

**[MEASURED]** Wave B made BeNeM's device list mirror BHNM's host status
(`restful/devices/get-host-and-service-status`, fetched by `middleware/maintenance_cache.py:144`).

**[INFERENCE]** Therefore: engine down → every device row frozen at its last value → BeNeM
faithfully renders a screen full of green. **BeNeM is not wrong about BHNM; BHNM is not wrong
about what it last saw. The green is a faithful rendering of data that stopped being true.**

This is the doctrine — unverified state presented as healthy — **originating a layer below
anything BeNeM currently checks.** The two-hop diagnostics verify the middleware reaching BHNM's
front end. The front end answers perfectly while the engine behind it is dead.

## Establish first: is this knowable at all?

The reviewer asked for this to be established before designing. What follows was measured today.

### Is Service Engine health readable?

**[MEASURED] Yes — the SE appears as a monitored host in BHNM.** Incident **29585** carried
`name: "BHNM-B-SE01"`, `alert_type: "host"`, and appeared in `host_down` while it was down. So its
state is readable through exactly the API BeNeM already uses; no new integration is required to
*see* it.

**[MEASURED] But it did not page**, and the explanation previously recorded for that is wrong.
29585 produced no webhook, and neither did its controlled repeat 29628 on 2026-09-16. The
explanation "a crashed Service Engine cannot notify anyone of its own crash" **has collapsed**:
per Thomas, **the main BHNM appliance sends the webhooks, not the Service Engine**, so during
both outages the sender was healthy and able to page.

So: **the one device whose outage invalidates every other device's status is the one whose outage
reaches nobody, while the machine that would do the paging is up.** That belongs to queue item 11
(coverage), not here — see the dedicated section below.

**~~[INFERENCE, needs confirming]~~ ANSWERED 2026-09-20 — see decision 2.** The open part was
recognising *which* host row is the Service Engine. It is **`device_type: "Helix Network Service
Engine"`**, carried by `restful/devices/list` and measured unique across the 41-device estate.
The three candidates guessed at here are all **measured dead**: no such endpoint exists,
`category` is a per-instance id (19 on BHNM-A, 36 on BHNM-B) holding unrelated boxes, and
`template` is `0` for every device on both instances. **The fourth candidate, asking the user, is
retired for identifying an ENGINE — but it still stands for group MEMBERSHIP and for the managed
device set, neither of which the API exposes.**

### Does a stale device row carry a freshness marker?

**[MEASURED] Yes, and BeNeM throws it away.** `get-host-and-service-status` rows carry
`lastUpdateTime` and `currentStateDuration` alongside `status` and `stateType`
(`shared/BHNM_API_REFERENCE.md`). Grepping `middleware/`, `pwa/src/` and `ios/` for
`lastUpdateTime`, `currentStateDuration` and `stateType` returns **nothing**. The middleware
fetches these rows and reads only the status.

**[INFERENCE]** This is the good news of the whole document: **staleness may be detectable without
identifying the Service Engine at all.** If `lastUpdateTime` stops advancing while the middleware
keeps successfully fetching, the data is stale whatever the cause — engine down, poller wedged,
one device stuck. A freshness test is more general than an engine test, and it needs no new
endpoint and no naming convention.

**[MEASURED 2026-09-16, evidence §8.13] `lastUpdateTime` STALLS. The hinge lands favourably.**
Across a controlled 26-minute engine outage, sampled every 60 s, the four managed rows held
`10:47:03` throughout while `BHNM-B-SE01`'s own row advanced with every fetch — a field rewritten
on query could not do both at once. **The cheap staleness check is viable**, and item 13 does not
depend on identifying the Service Engine.

*Two premature readings of this field were recorded and withdrawn before the outage settled it.
Neither survived contact with a controlled test.*

### OPEN FORK — `bhnm-apns.hurrikap.org`, and it decides the feature's shape

One row has read `UP` with `lastUpdateTime` **2026-09-09 18:26:13** — a week stale — in every
sample taken, before, during and after the outage, while its `currentStateDuration` advances
normally.

**[THOMAS]** It is a VPS he configured with a direct tunnel into the BHNM appliance, managed by
the main appliance rather than by a Service Engine. **[THOMAS] He states explicitly that this does
not explain the stale timestamp.** Low priority to investigate — but **not closed**, because the
two branches lead to different features:

| branch | if true | consequence for this design |
|---|---|---|
| **A — BHNM genuinely has not verified that host in a week** | the appliance is reporting `UP` for a device it has not checked since 2026-09-09 | the cheap staleness check **works and has already found a real gap in Thomas's own estate**, before a line of code is written |
| **B — the field behaves differently for tunnel-managed devices** | `lastUpdateTime` is not comparable across management paths | the check has a **false-positive class**: every tunnel-managed device would render permanently "stale". The design must then detect or exempt them |

**Do not pick one.** What would distinguish them, all read-only:

1. **Compare against the same host's *service* rows** (`serviceFilter=service_desc`). If services
   on that host carry fresh timestamps while the host row does not, the host row is anomalous
   (branch B or a bug); if the service rows are equally stale, the device genuinely is not being
   checked (branch A).
2. **Look for a second tunnel-managed device.** If one exists and shows the same frozen pattern,
   that is branch B; if it updates normally, branch A.
3. **BHNM's own Device Polling Status check** for that device, read in the UI — it states whether
   polling is succeeding, independently of this field.

Until it is settled, **the design must assume branch B is possible** and not ship a staleness
marker that would light up permanently on a healthy device. That is the same error class as every
other entry in this repository's doctrine, pointed the other way: crying stale on something fine
trains users to ignore the marker that matters.

## Service Engine GROUPS — new domain knowledge, and it reshapes the check

**[THOMAS]** Service Engines can be arranged in **groups**. If one SE in a group fails, **another
SE takes over management of the devices the failed one handled.** This was not known when the
controlled outage of 2026-09-16 was designed, and it changes what the staleness check is for.

### What follows, marked honestly

**[PREDICTION — not measured]** Under *working* failover, `lastUpdateTime` should **keep
advancing**, because a different Service Engine is polling the same devices. The staleness check
should therefore stay **correctly quiet** during a single-SE failure inside a healthy group. This
is the desired behaviour and it is a prediction, not an observation — the 2026-09-16 outage
measured **a standalone engine**, not a grouped one, so it says nothing about failover.

**[INFERENCE]** The cases the staleness check must still catch, because failover cannot rescue
them:

1. **A standalone Service Engine with no group.** Nothing takes over. Devices freeze. This is
   exactly what was measured on 2026-09-16.
2. **A whole group failing.** Nothing left to take over. Devices freeze.

**Both leave the operator's screen green**, which is the whole point of item 13 and is unchanged
by the existence of failover.

**[INFERENCE]** Failover also strengthens the case for a *freshness* check over an *engine* check.
A check that watches "is SE01 up?" would fire loudly during a successful failover in which nobody
lost anything — a false alarm on a system working as designed. A check that watches
`lastUpdateTime` stays quiet exactly when failover works and fires exactly when it does not. **The
cheap check is not merely cheaper; with groups in the picture it is the more correct one.**

### PLANNED MEASUREMENT — grouped SE failover — **SCHEDULED 2026-09-20**

**The method below is unchanged and stands.** It is now made runnable as
`docs/runbooks/2026-09-20-experiment-2-se-group-failover.md`; read that to run it, and this for the
reasoning behind it. **Still blocked on Thomas building the group** — step 1 below is the
prerequisite and it has not moved.

**Question:** during a single-SE failure inside a healthy group, does `lastUpdateTime` keep
advancing on the devices that were handed over, and how long does the handover take?

**Method**, identical in shape to the 2026-09-16 run, which worked:

1. Identify a group with at least two SEs and the device set handled by the one to be stopped.
   **This is the prerequisite and it needs Thomas** — group membership is not known to be readable
   from the API.
2. Capture a baseline: `get-host-and-service-status` for those devices, recording `status`,
   `lastUpdateTime`, `currentStateDuration` verbatim, plus the incident list, `host_down`, and the
   middleware log position.
3. Start a 60-second sampler *before* the stop, so the normal advance rate is on record.
4. **Thomas stops one SE in the group and reports the exact time. Nobody else touches it.**
5. Sample for at least 60 minutes. Record, per device: does `lastUpdateTime` keep advancing; if it
   pauses, **for how long** — that gap is the handover time and it is the number the design needs;
   does `status` change at any point.
6. Record whether the failed SE raises its own incident, and whether it pages. That is Q1 again,
   on a grouped engine, and BMC may answer it first.
7. Thomas restores it; record what arrives.

**What the answer changes:** if `lastUpdateTime` keeps advancing, the staleness threshold only has
to clear the *handover gap* — measure it and set the threshold above it. If it pauses for minutes,
the threshold must be generous enough not to cry stale during every normal failover, and that
number cannot be guessed.

## What BeNeM should show

Only the shape, since the mechanism above is unsettled.

**The rule, from the existing doctrine:** three states, and the third gets its own appearance.
For a device row: *verified up recently*, *verified down*, and **stale — last confirmed at
HH:MM**. Not green. Not red. Its own appearance.

- **Per-row staleness beats a global banner.** A row whose `lastUpdateTime` is older than some
  multiple of its `poll_intvl` reads as stale, dated. This works whether one device is stuck or
  the whole estate is frozen, and degrades gracefully when the cause is unknown.
- **When *everything* is stale, say so once, prominently**, because that is the engine case and a
  screen of individually-stale rows under-sells it: *"No device has been checked since 21:51. The
  data below is that old."*
- **The connection badge must participate.** Today it goes green on "data arrived at some point"
  (incident-freshness Part 3). Data arriving from a front end whose engine is dead is exactly the
  case it should refuse to call healthy.
- **Paging is the separate question.** If the SE can be identified, its outage is the single most
  page-worthy event on the system — it means *nothing else will page you either*. That belongs
  with item 11, not here.

## How this ranks against item 11 (coverage visibility)

**It does not displace item 11.** Both are "the user cannot tell that they are not being told",
and they differ in reach and in remedy:

| | item 11 — coverage | item 13 — engine down |
|---|---|---|
| when it bites | **always**, silently, from the day of install | only during an engine outage |
| what the user sees | a list that implies more coverage than exists | a screen of green that was true an hour ago |
| detectable today? | **no** — needs BHNM config BeNeM cannot read | **probably yes** — `lastUpdateTime` is already fetched and discarded |
| fix cost | design-heavy, may end in an admission | plausibly small, if the freshness field behaves |

**Item 11 stays first** because it is permanent and undetectable; item 13 is intermittent and,
on today's evidence, cheaply detectable. **But item 13 may well ship first**, precisely because a
freshness marker already in hand is a smaller change than a coverage story that may have no
answer. Ranked below 11 in *importance*, likely above it in *order*, and that is not a
contradiction.

## Decisions for Thomas

1. ~~Confirm the premise~~ — **DONE, confirmed by measurement 2026-09-16 (§8.13).** Devices retain
   their last state; the premise is no longer an assumption.
2. **ANSWERED 2026-09-20 — `device_type`. Closed; no question outstanding.**

   **[THOMAS] A Service Engine is always of type `"Helix Network Service Engine"`.**

   **[MEASURED 2026-09-20, against BHNM-A (`bhnm-a-m.local`) and BHNM-B
   (`bhnm-b.tstolt.com`) separately]** `restful/devices/list` carries `device_type` on every row,
   and **a BHNM instance types its OWN Service Engines with that value**:

   | instance | its own engines | `device_type` |
   |---|---|---|
   | BHNM-A | `BHNM-A-SE01`, `BHNM-A-SE02` | `Helix Network Service Engine` |
   | BHNM-B | `BHNM-B-SE01` | `Helix Network Service Engine` |

   **So BeNeM does not have to ask the user**, and the unglamorous branch of this decision is
   retired.

   **[MEASURED] A Service Engine GROUP is also a first-class object with its own type.** On
   BHNM-A: `BHNM-A-SE-GROUP`, `device_type: "Helix Network Service Engine Group"`, with a
   synthetic `ip` of `seg:1` encoding the group id. **Its MEMBERSHIP is still not readable** —
   `groupFilterBy=strategicGroup|category|site` against the group name all return 400, and
   `groups/list`, `strategic-groups/list` and `serviceengines/list` are all 404. So *which*
   engines are in a group, and *which* devices they manage, still come from the operator.

   **[MEASURED] Mechanics the implementation needs.** Only `devices/list` carries `device_type`
   — `devices/find` and `get-host-and-service-status` host rows both omit it, so identification is
   a **join on `name`** between the list and the status feed (the clients already fetch the list,
   so it costs nothing new). There is **no server-side type filter**: `device_type`, `deviceType`,
   `type` and `filter` are all ignored and the full estate comes back regardless — filter
   client-side. And the match is an exact string owned by BHNM, with nothing here establishing
   stability across versions or locales, so **zero matches means "cannot identify", never "no
   engines"** — the doctrine's third state applied to this lookup.

   **[MEASURED] `category` must NOT be used, and not only because it is imprecise: its ID is
   per-instance.** The same category is `19` on BHNM-A and `36` on BHNM-B. `template` is `0` and
   `poll_intvl` is `5` for every device on both instances, so neither discriminates anything.

   #### WITHDRAWN 2026-09-20 — "name and description lie in both directions, so `device_type` may
   miss two of three engines"

   **Wrong, and wrong for a reason worth recording: it compared two different servers' rows and
   did not say so.** The morning's reading — `BHNM-A-SE01`/`SE02` typed `Linux/Net-SNMP` while
   named SE, and `Helix-Network-Core`/`BHNM-A-M` described "Service Engine" while typed
   `Helix Network Core` — was taken **entirely from BHNM-B**. Those are **B's rows about hosts it
   monitors over SNMP but does not manage**, which is correct and expected behaviour, not a stale
   or misleading registration. Nothing was stale, and the afternoon claim that rebuilding the VMs
   "settled it" is withdrawn along with the premise: the rebuild changed the VMs, not the fact.

   **The real rule is narrower and stronger than the one that error obscured**: `device_type`
   identifies an engine *to the instance that manages it*. A BHNM instance will not type a foreign
   appliance as an engine, and should not.

   **Rule taken from this:** a measurement records **which server produced it**, and no
   cross-server comparison enters a document without both sides named. Same family as
   `middleware/CLAUDE.md`'s *an assertion must first be shown to have been checked*.

3. ~~Approve the `lastUpdateTime` measurement (read-only) as the first step?~~ **APPROVED and
   ABSORBED into experiment 1** — the standalone SE shutdown is the only controlled outage
   available, and this observation is taken during it rather than separately.
4. **HELD 2026-09-19 — waits for experiments 1 and 2.** Is per-row staleness plus a single
   "nothing has been checked since HH:MM" banner the right shape, or should a frozen estate be a
   modal-level interruption?

**The two experiments, as ruled:** (1) a standalone SE shutdown with full timing; (2) an SE Group
failover, **after Thomas sets the group up**. **Both SCHEDULED 2026-09-20 and runbooked** — see the
SCHEDULED block at the top of this file. **Run 1 before 2.** Neither starts without Thomas's go on
the day.
