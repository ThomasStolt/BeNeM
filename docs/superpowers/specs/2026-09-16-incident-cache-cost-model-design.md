# Design: incident cache cost model — enrich on change, not on cycle

**Status:** **SUPERSEDED 2026-09-19 by
`docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md`.**
Nothing is built from this document. Read the successor instead.
**Date:** 2026-09-16. **Superseded 2026-09-19.**
**Subject:** `middleware/incident_cache.py`. Related: queue item 13 (staleness), §8.8 (coverage
visibility) — this design does not depend on either and neither depends on it.

---

## SUPERSEDED 2026-09-19 (Thomas) — the premise was wrong

**This note treated the poll as the source of truth and webhooks as an overlay on it. Thomas rules
the opposite: webhooks are authoritative for incident state, and the poll is a repair mechanism.**
Every mechanism below was designed to make *polling* affordable at scale. The successor makes
polling the exception — off by default — so most of the machinery here is solving a problem that
the new model does not have.

**What survives, and only this:** **change-driven enrichment** (§5.2 — re-fetch detail only for
incidents the list shows as changed). It survives as a **requirement of polling mode**, which is
where it belongs, and it is what makes a 120 s poll interval achievable against SaaS latency.

**What is struck** — named individually so none of it is resurrected by someone reading the body
below and finding it persuasive:

| struck | where | why |
|---|---|---|
| the rolling sweep | §5.3 | it exists to converge a poll-driven cache; webhooks converge on the event |
| the load budget dial `B` | §5.3, §6 | a dial for a sweep that no longer exists |
| adaptive cadence | §5.3, §6 | same |
| decision 8 *(concurrency)* | §8, §10 | no sweep, no backfill pressure, nothing to parallelise |
| decision 12 | §10 numbering | struck with the model it belonged to |
| decision 13 | §10 numbering | struck with the model it belonged to |
| all concurrency discussion | §8 entire | moot; the one ruling that stands is still *no concurrency* |

**What is carried forward unchanged into the successor:** §5.4 (per-incident freshness, report the
**oldest**) becomes **C9**, required and not separable. §5.5 (a failed enrichment is never cached;
`UNKNOWN`, never `"host"`) becomes **C11**, unchanged and still a hard requirement. §5.1
(`alert_type` learned once and persisted across restarts) becomes **C10**, now on Thomas's
confirmation rather than on inference.

**The measurements in §2, §3 and §7 remain valid and are still the only numbers this project has**
— detail latency, the `getincidents` field set, the payload sizes, and the finding that
`alarm_counts` is absent from the list. The successor cites them rather than repeating them. The
§3 finding that `alert_type` cannot be derived from the title (incident 25076,
`Application Service Wordpress`, type `service`) is what makes C10's persisted type map necessary
rather than convenient.

---

## Provenance, stated first

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed by me against the live lab or this repository on 2026-09-16, output recorded |
| **[PROJECTED]** | Arithmetic from a measured model. The model is validated against one measured point; the projections are not measurements |
| **[INFERENCE]** | Reasoning. Marked so it can be attacked separately from the numbers |
| **[UNMEASURED]** | Named so it is not mistaken for either of the above |

---

## 1. What the cache does today

**[MEASURED — `middleware/incident_cache.py`, read 2026-09-16]**

Every cycle, for **every** incident — active *and* closed — the cache makes one sequential awaited
`getincidentdetail` POST, paced by `refresh/(n+1)`, and there is **no outer sleep between cycles**.

```python
235:    all_incidents = [(inc, "active") for inc in active_raw] + [(inc, "closed") for inc in closed_raw]
237:    n = len(all_incidents)
238:    delay = refresh / (n + 1) if n > 0 else refresh
244:    for i, (incident, bucket) in enumerate(all_incidents):
249:            detail = await _fetch_incident_detail(client, server, inc_id)
260:        if delay > 0.1:
261:            await asyncio.sleep(delay)
```

```python
277:        while True:
279:                await _run_one_cycle(client, server)
282:                diagnostics.record_success(server_id, "incidents", None)
285:            except Exception as e:
288:                await asyncio.sleep(10)
```

The only `sleep` in `_cache_loop` is on the **failure** path, line 288. On success the loop
re-enters `_run_one_cycle` immediately. **`cache_refresh_seconds` is not a period — it is a
budget that the inner pacing spends.** The actual cycle period is whatever the loop takes.

**[MEASURED]** Cost model, derived and then checked:

```
cycle_wall(n, L) = n · refresh/(n+1)  +  n · L        (for n ≤ 1198; see note)
```

Checked against the live lab, `refresh=120`, `n=9`, measured detail latency `L=0.2555 s`:

```
predicted 110.3 s     measured 110.5 s
  20:29:36.679  [Cache:ThomasLabServer] Enriching 9 incidents (pacing: 12.0s between calls)
  20:31:27.848  [Cache:ThomasLabServer] Cache updated: 9 active, 0 closed
  20:31:28.084  Enriching 9 incidents …            (110.5 s later — no gap between cycles)
  20:33:18.612  Cache updated …                    (110.5 s)
  20:33:18.923  Enriching 9 incidents …            (110.5 s)
```

Note: line 260's `if delay > 0.1` means that above **n = 1198** the pacing sleep disappears
entirely and the loop runs detail calls back-to-back at full rate. The brake is released exactly
where it is most needed.

---

## 2. Measured latency, and what it projects to

**[MEASURED]** 20 sequential `getincidentdetail` calls, from inside `benem-middleware` to the lab,
via the same `httpx` client and TLS settings the cache uses:

| | value |
|---|---|
| min | **0.235 s** |
| median | **0.2555 s** |
| max | **0.372 s** |
| mean | 0.269 s |
| response size | 786 – 1536 B (median 953 B) |
| status | 200 × 20 |

**[PROJECTED]** Full-cycle wall time, current design:

| n | L = 0.2555 s (lab, measured) | L = 2 s (SaaS) | L = 4 s (SaaS) |
|---:|---:|---:|---:|
| 100 | 2.4 min | 5.3 min | 8.6 min |
| 526 | 4.2 min | **19.5 min** | **37.1 min** |
| 1000 | 6.3 min | **35.3 min** | **68.7 min** |

The SaaS columns are the ones that matter. **At n = 1000 and 4 s per call, one pass over the
incident list takes 69 minutes**, and because there is no outer sleep the next pass starts
immediately. A user's incident view is then never less than one hour behind at the far end of the
list, and there is no setting that makes it better: `cache_refresh_seconds` only controls the
118 s of pacing sleep, which is a rounding error against 4000 s of calls.

**[UNMEASURED]** The 2 s and 4 s figures are Thomas's SaaS estimates, not measurements I took.
Everything above scales linearly in L, so substituting a real measured SaaS latency rescales the
table without changing its shape.

---

## 3. What the list already gives us — and what the detail call is actually for

**[MEASURED]** One real `getincidents` response, lab, 2026-09-16. Top level: `active_incidents`,
`result`. Two per-incident key sets appear:

| count | keys |
|---:|---|
| 8 of 9 | `device_category`, `device_note`, `device_site`, `incident_id`, `incident_state`, `name`, `open_time`, `title` |
| 1 of 9 | `incident_id`, `incident_state`, `open_time`, `title` *(an Application incident — no device)* |

**`alert_type` is not in the list, in either key set.** Nor is anything from which it can be
reliably derived: 8 of 9 titles start with the type word, but incident 25076 is titled
`Application Service Wordpress` and its `alert_type` is `service` — **title parsing would get that
one wrong**, so the detail call is genuinely the only source. That is the whole justification for
ever calling it.

**[MEASURED]** `_enrich_incident` adds exactly two keys and nothing else:

```python
128: def _enrich_incident(incident: dict, detail: dict) -> dict:
129:     enriched = dict(incident)
130:     enriched["alarm_counts"] = detail.get("alarm_counts")
131:     enriched["alert_type"] = detail.get("alert_type", "host")
132:     return enriched
```

Confirmed. `alarm_counts` is derived locally from `detail.primary_alarm_log` +
`detail.relatedalarms` (lines 103–125); `alert_type` is copied through.

**[MEASURED]** Everything else in the detail response is fetched and thrown away, every cycle, for
every incident: `ack_comment`, `ack_time`, `ack_user`, `acknowledged`, `detail` (the full alarm and
incident logs), `device_documentation`, `incident_open_time`, `primary_alarm_state`,
`related_strategic_groups`.

### Can `alert_type` change for a given `incident_id`?

**[MEASURED]** Across every incident in the lab, `alert_type` is a function of what opened the
incident:

| incident_id | title | alert_type |
|---|---|---|
| 24951 | Threshold ADSL Upload Speed … on DrayTek | `threshold` |
| 25076 | Application Service Wordpress | `service` |
| 25482 | Service BMC Discovery Outpost Service Check on Windows_2016_Server | `service` |
| 27190 | Threshold / Percent Used Space on raspi-059 | `threshold` |
| 27516 | Service Configuration Save Check on C9200CX | `service` |
| 29546 | Service Check SSL Certificate on Synology920 | `service` |
| 29657, 29658, 29659 | Anomaly Bandwidth on … | `anomaly` |

**[MEASURED]** Over an 11-cycle run (20:44Z–21:05Z, 13 incidents, 130 incident/cycle-pair
observations) `alert_type` did not change for any incident id. **This is a weak observation and is
recorded as one:** nothing at all changed in that window — not a list field, not a count, not a
type — so the run had no opportunity to see a change. Absence of an opportunity is not evidence of
absence.

**[INFERENCE]** `alert_type` is the type of the incident's **primary** alarm — the one that opened
it — and an incident's primary alarm does not change identity; related alarms attach to it. So
`alert_type` is immutable per `incident_id`. **This is an inference, and the design must not
require it to be true** — see §5, where the diff catches a change anyway.

**[MEASURED] — a defect found while reading, reported here because it belongs to §8.8 and not to
this design.** When the detail call fails, both the middleware (`incident_cache.py:97, 252`) and
the iOS app (`NetreoAPIService.swift:940`) substitute `alert_type: "host"`. **Host is the one type
that is known to page** (§8.8: every webhook ever produced was a host event). A failed lookup
therefore renders as the strongest possible coverage claim. This is the section (f) failure class
in a new costume: an unverified value drawn as the verified one. It is not fixed here.

**[MEASURED]** A fourth value exists that the code's own documentation does not list:
`NetreoAPIService.swift:921` says *"alert_type values from BHNM: `Host`, `Service`, `Threshold`"*.
`anomaly` is real and currently three of nine incidents in the lab.

---

## 4. The freshness stamp understates staleness

**[MEASURED]** `last_updated` is stamped **once, at the end of the cycle**, after the whole
enrichment loop has run:

```python
265:    _cache[server_id] = CachedIncidents(
266:        active_incidents=active_enriched,
267:        closed_incidents=closed_enriched,
268:        last_updated=time.time(),
269:    )
```

**[MEASURED]** `/api/v1/diagnostics` reports that single stamp as the age of the entire feed:

```python
main.py:1036:  "incidents": diagnostics.feed_block(
main.py:1038:      age_seconds=_age(ic.last_updated) if ic else None,
```

So for the **first** incident enriched in a cycle, the data was fetched one full `cycle_wall`
before the stamp was written. At the instant the stamp is written, diagnostics reports **age 0**
for data that is already `cycle_wall` seconds old; just before the next stamp it reports
`cycle_wall` for data that is `2 × cycle_wall` old.

**[MEASURED]** In the lab that is 110.5 s of understatement. **[PROJECTED]** at n = 1000, L = 4 s
it is **69 minutes** of understatement: diagnostics reports an age between 0 and 69 minutes while
the first-enriched incident is between 69 and 138 minutes stale.

**The reported age understates the true staleness of most of the set.** It is accurate only for
the last incident enriched, and it is reported as though it described all of them. This is the
same false-healthy class as section (f) of the handoff: a positive signal that is real but is
measuring something other than the thing that matters.

---

## 5. Proposed: enrich on change, plus a rolling sweep

Five changes. None of them is concurrency.

### 5.0 The trade this design accepts, stated before the mechanism

**`alarm_counts` is not present in `getincidents`.** It is derived from the *detail* response
(`primary_alarm_log` + `relatedalarms`, lines 103–125), and the list carries nothing from which it
can be computed or even inferred.

Therefore: **a list-level diff is structurally blind to alarm-count movement.** An incident can
gain a red alarm, or have one clear, while every one of its list-level fields —
`incident_state`, `title`, `name`, `open_time`, `device_category`, `device_site`, `device_note` —
stays byte-identical. A design that enriches only on list-level change would never re-fetch that
incident, and **its alarm counts would be permanently stale, for as long as the incident stays
open.**

This is a **correctness regression that enrich-on-change introduces.** It does not exist today:
today's design is wasteful precisely because it re-derives every count every cycle, and that waste
is what currently keeps the counts right. Removing the waste removes the guarantee with it.

It is not a cosmetic staleness. **[MEASURED]** `alarm_counts` drives the severity dots on the
incident list and dashboard on both platforms — `ios/BeNeM/Views/IncidentListView.swift:249`,
`ios/BeNeM/Views/DashboardView.swift:557`, `pwa/src/features/dashboard/IncidentTicker.tsx:38`. A
count that is stale low shows a quieter incident than the one the engineer actually has. That is
the section (f) direction: an affordance asserting a state the app has not confirmed.

**This trade is not left standing. §5.3 resolves it.** But it is named first, because a design that
only reported the cost saving would be hiding the thing that pays for it.

#### What the lab run could and could not say about it

**[MEASURED]** 11 cycles, 20:44Z–21:05Z, n = 13 throughout, 10 cycle-pairs, **130
incident/cycle-pair observations** where a given incident's list fields were byte-identical across
the pair. In **zero** of those did `alarm_counts` move. Each cycle captured the full list-level
field set *and* the `alarm_counts` derived by the middleware's own `_fetch_incident_detail`, so the
comparison is against exactly the values the cache would have stored.

**[MEASURED]** In the same run: 0 new incidents, 0 gone, 0 list-field changes, 0 count changes,
0 `alert_type` changes. **The set was completely static.**

**That is a null result, and it is not evidence that the blind spot is rare.** The run observed a
quiescent lab; it never created the conditions under which the failure would appear. **The blind
spot is established by the field-set measurement in §3 — `alarm_counts` is absent from the list —
not by churn statistics, and no churn figure can retire it.** A measurement on nine to thirteen
incidents in a quiet lab is **not extrapolable**; it is reported here as an observation and the
design does not rest on it.

### 5.1 Cache `alert_type` permanently, keyed by incident_id

`alert_type` is **[INFERENCE]** immutable per incident — it is the type of the alarm that *opened*
the incident, and related alarms attach to that primary rather than replacing it. Learn it once,
on first sighting, never ask again. Incident ids are not reused.

The store is `{incident_id: alert_type}`, dropped when the incident leaves both lists and a
retention window passes. If it is persisted across restarts, a restart stops being a cold start.

If the inference is wrong, §5.2 catches it: a type change would have to be accompanied by a
primary-alarm change, which §5.3's sweep re-derives anyway.

### 5.2 Mechanism (a) — event-driven enrichment for new and changed incidents

Each cycle already fetches the full list. Compare each incident's list-level fields against the
previous cycle's copy:

- **absent last cycle** → new → enrich now.
- **present, any list field differs** → enrich now.
- **present, byte-identical** → no call from this mechanism. Carry the previous `alarm_counts`,
  `alert_type` **and their timestamp** forward (§5.4).

This covers `alert_type` and `incident_state` **immediately** — within one cycle of the change.
It is the right mechanism for exactly the things the list can see, and it is worthless for the one
thing the list cannot (§5.0).

Note this mechanism and the ack-override path agree by construction: an ack patches
`incident_state`, which is a list-level field, so an acked incident shows as changed and is
re-enriched.

### 5.3 Mechanism (b) — a rolling sweep governed by a load budget

**Credit: this is Thomas's pacing proposal, applied to the residual set rather than to the whole
set — which is where it is right.** Today's design paces *every* incident every cycle, so the
budget is spread thinner the more incidents there are and cycle time grows without bound with `n`.
Applied to the residual, the same idea inverts: the **rate** is held constant and the convergence
*time* grows with `n` instead. That is the trade worth making, because a bounded, count-independent
load is something a customer's BHNM can be promised.

**The mechanism.** Maintain a cursor over the incidents mechanism (a) did not touch. Walk it
continuously, one incident at a time, one request in flight. When the cursor reaches the end it
wraps. Every incident's `alarm_counts` is therefore re-derived at a predictable period, and
`enriched_at` (§5.4) says exactly when each one last was.

#### The rate is a load budget, and it is the only dial

```
B = detail calls per second.  DEFAULT 1.  Set independently of everything else.

effective rate   = min(B, 1/L)          one request in flight, so latency is a hard ceiling
full-sweep period = n / min(B, 1/L)
```

**`B` is not derived from `cache_refresh_seconds` and must not be.** `cache_refresh_seconds` is
already overloaded — it is the pacing budget, clamped 60–900, and today it doubles as a period that
is not actually a period (§1). Coupling the sweep to it ties two unrelated things together. **And
any expression involving `n` defeats the entire point**, which is that the load BeNeM places on a
customer's BHNM must not be a function of how many incidents that customer has.

**Floor and ceiling, both required:**

- **Ceiling — `B` is never exceeded.** Not per burst, not on a cold start, not during a backfill.
  It is the number an operator can quote to whoever owns the BHNM appliance.
- **Floor — the effective rate can never reach zero.** A `B` of 0, or a clamp that rounds to no
  calls, produces a cache that **shows alarm counts it has stopped refreshing** — the doctrine
  failure exactly, an affordance asserting a state nothing is checking. A misconfiguration must
  degrade to *slow*, never to *stopped*.

#### It states its own staleness, and that is a feature, not a footnote

`n / min(B, 1/L)` is not an implementation detail — **it is the number an operator actually needs**,
so surface it, in words, wherever coverage and freshness are shown:

> **Alarm counts fully refresh every 17 minutes.**

That single sentence is the thing today's design cannot say at all. Today the answer is "one full
pass, eventually, at a rate that depends on how many incidents you have and how fast your appliance
is" — which is why §4's stamp understates staleness and nobody noticed. A design whose period is a
constant divided by a count can print its own worst case.

**[PROJECTED]** full-sweep period at **B = 1**:

| n | L = 0.2555 s | L = 2 s | L = 4 s |
|---:|---:|---:|---:|
| 100 | 1.7 min | 3.3 min | 6.7 min |
| 526 | 8.8 min | 17.5 min | 35.1 min |
| 1000 | **16.7 min** | 33.3 min | 66.7 min |

At n = 1000 and B = 1 that is **full convergence every ~17 minutes at a load BHNM sees as steady
state** — one request at a time, forever, whatever the incident count. At SaaS latency the sweep
becomes latency-bound rather than budget-bound and the period stretches to 33 or 67 minutes;
**the load does not rise, only the convergence time**, and the surfaced sentence changes with it so
the operator is told.

**Ordering within the sweep is policy, not mechanism** — oldest `enriched_at` first is the obvious
default and needs no state beyond §5.4.

### 5.4 Stamp freshness per incident, and report the worst

Replace the single `last_updated` with a per-incident `enriched_at`, carried forward with
carried-forward enrichment. Then:

- `/api/v1/diagnostics` reports the feed age as the **oldest** `enriched_at` in the set, not the
  newest. A cache is as fresh as its stalest member.
- The list-level fields get their own, always-current stamp — the time of the last successful
  `getincidents` — because that call is unconditional. Report both: *list refreshed 40 s ago,
  enrichment as old as 17 min*. They are different facts, and merging them is what produced §4.

**[INFERENCE]** §5.4 is worth doing **even if everything else here is rejected**. It is the only
one of the five that is purely a truthfulness fix rather than a cost fix, and under the current
design it gets *worse* as n grows — so it should not wait behind the cost work.

### 5.5 A failed enrichment is never cached

Today a failed detail call is survivable by accident: it writes
`{"alarm_counts": None, "alert_type": "host"}` into the cache (lines 97, 252) and **the next cycle
overwrites it** a couple of minutes later. Enrich-on-change removes that accident. If a failure
were cached, nothing would ever trigger a retry — the incident's list fields are unchanged, so
mechanism (a) skips it forever — and **today's transient false-healthy value would become a
permanent one.**

The design therefore states, as a requirement and not a nicety:

1. **A failed enrichment is never written to cache.** Not as `None`, not as a default, not as a
   partial. The previous good value stays, with its previous (older) `enriched_at`, which now tells
   the truth about it.
2. **The incident stays on a retry list until a call succeeds.** It is not dropped, not deferred to
   the next list change, and not left to the sweep's natural period. Retries back off so a
   permanently-broken incident costs a bounded trickle rather than a spin — the `f` term in §6 is
   this set, and it must be bounded by construction.
3. **Until a call has ever succeeded for that incident, its `alert_type` reads `UNKNOWN`** — never
   `"host"`, never any other guess. Clients must render `UNKNOWN` as its own state, per the root
   `CLAUDE.md` doctrine: unverified is a third state and never gets the appearance of a verified
   one. The current `"host"` default is the exact inverse of this rule and is filed separately
   (§3, and `2026-09-16-coverage-visibility-design.md`).

**[INFERENCE]** This is the most important of the five. The cost changes are reversible; a cached
lie that nothing can dislodge is the failure mode this project has now shipped four times.

---

## 6. Cost as a function, not a number

**Today:**

```
calls per cycle = 1 + n
```

Unconditional. Every incident, active and closed, every cycle, forever.

**Proposed:**

```
calls per cycle = 1 + (c + f + s)

  c = new incidents + incidents whose list-level fields changed      (§5.2)
  f = incidents on the retry list after a failed enrichment          (§5.5, bounded by backoff)
  s = sweep calls completed in that period                           (§5.3)
      s = period x min(B, 1/L)      B = the load budget in calls/s, default 1
```

`n` does not appear in the proposed expression. **That is the whole point:** today's cost is a
function of how many incidents exist, and the proposal's cost is a function of how many *changed*,
how many are *broken*, and a *load budget the operator sets*. Closed incidents contribute to none
of the three terms — a closed incident is terminal, its alarm set frozen, so it is enriched once on
the transition to closed and never again. Today it is re-enriched every cycle forever (line 235
concatenates `closed_raw` into `all_incidents`).

**[PROJECTED]** at **n = 1000**, `B = 1 call/s`, over one 120 s window:

| | L = 0.2555 s | L = 2 s | L = 4 s |
|---|---:|---:|---:|
| today: `1 + n` | **1001** | **1001** | **1001** |
| proposed: sweep term `s` | 120 | 60 | 30 |
| proposed: `1 + c + f + 120/60/30` | **121 + c + f** | **61 + c + f** | **31 + c + f** |
| reduction, `c = f = 0` | **8.3×** | **16.4×** | **32.3×** |
| full-sweep period `n / min(B, 1/L)` | 16.7 min | 33.3 min | 66.7 min |
| **what the operator is told** | *"every 17 min"* | *"every 33 min"* | *"every 67 min"* |

The reduction *improves* as latency worsens, because the sweep is rate-limited by a constant while
today's design is rate-limited only by how fast BHNM will answer.

**[MEASURED — lab observation, NOT EXTRAPOLABLE, n = 9 to 13]** In the 11-cycle run of 2026-09-16
20:44Z–21:05Z, `c = 0` in 10 of 10 cycle-pairs, and in the 4 list-only samples immediately before it
(20:38Z–20:44Z) `c` was 2, 2, 0 — all of it new incidents, none of it changes to existing ones.
**Nine to thirteen incidents in a quiet lab says nothing about a thousand in production, and the
cost function above is written so that it does not have to.** `c` is an input to the model, not a
constant the model assumes.

## 7. Payload: is the single list call a second cost centre?

**[MEASURED]** `getincidents`, lab, n = 9: **1930 bytes**, latency **0.217 / 0.246 / 0.285 / 0.294 s**
across four calls. Per-incident JSON: min 121 B, median 213 B, max 246 B, mean 209 B; envelope
overhead 53 B.

**[PROJECTED]** payload at scale, assuming the per-incident record keeps its measured mean size:

| n | payload |
|---:|---:|
| 100 | 20.4 KB |
| 526 | 107.2 KB |
| 1000 | **203.7 KB** |

**[INFERENCE]** 204 KB per cycle is not a cost centre. At one list call per cycle it is trivial
next to 1000 detail calls whose responses total **[PROJECTED]** ~930 KB at the measured median
detail size — and the detail traffic is the part the proposal removes.

**[UNMEASURED] — and this is the honest gap in this section.** The lab has 9 incidents. I could not
vary n, so **the latency of `getincidents` at n = 1000 is not measured** and is not projected here
either: response size grows linearly, but BHNM's own query cost behind it is unknown and need not
be linear. If the list call turns out to be slow at n = 1000, this design's cost claim is unaffected
(it removes detail calls, not the list call) but the **cycle period** claim is, because the list
call then sets a floor. **The measurement that would close this:** one `getincidents` against a
deployment with a large incident count, timed. There is no such deployment in the lab.

---

## 8. Concurrency — argued separately, as instructed

**The rolling sweep (§5.3) is not concurrency.** It is one request in flight under a load budget —
the same serial shape the cache has today, with the rate decoupled from `n`. Nothing below applies
to it.

Parallel detail fetching is **not** proposed, and §6 is why: it buys a linear factor, and it buys
it with BHNM load. **Not fetching is the order-of-magnitude win and it costs BHNM nothing** — it is
strictly less load, not differently-shaped load.

**[INFERENCE]** After §5 there is almost nothing left for concurrency to speed up. The residual
work per cycle is one list call plus `c + f + s`, and `s` is bounded by a budget the operator set.
Concurrency would not raise that budget; it would break it.

The one place a case could still be made is the **cold-start backfill**: the first pass after a
restart must enrich everything, and at n = 1000, B = 1, L = 4 s the sweep needs 67 minutes to cover
it. Note what the budget does here — it makes the backfill *slow on purpose*, and §5.4/§5.5 make it
**say so** rather than serve half-built counts as finished ones.

**What concurrency would cost BHNM, stated plainly:** k concurrent detail requests means k
simultaneous `incident_api.php` executions and k simultaneous database queries behind them, on an
appliance that is also running its own polling engine. One-at-a-time pacing is the only thing that
currently guarantees BeNeM is never more than one request of load on a customer's BHNM. Raising it
to k raises BeNeM's worst-case footprint on someone else's production monitoring system by k,
permanently, to make a once-per-restart backfill faster.

**[INFERENCE] Recommendation: no concurrency.** If the cold-start backfill is judged too slow, the
cheaper answers in order are: (a) persist the `alert_type` map across restarts so a restart is not
a cold start; (b) serve the list immediately with enrichment marked absent — §5.4 and §5.5 already
give the vocabulary to say "not yet enriched" and `UNKNOWN` honestly — and let the sweep fill in
behind it. Both are free of BHNM load. Concurrency is the third choice, not the first.

**For the record:** there is **no "2 parallel pollers" decision in this repository**. The only
concurrency ruling BeNeM has made is **one serial APNs worker (2.14.0)**, for an Apple-specific
reason that does not apply to BHNM. Nothing in this document cites a parallel-poller precedent,
because none exists.

## 9. What this design does not do

- It does not change `getincidents`, its pacing budget, or `cache_refresh_seconds` semantics.
- It does not touch the ack-override machinery (`_state_overrides`, `_pending_overrides`,
  2.15.2's pending-on-first-sighting fix). Those patch `incident_state`, which is a **list-level**
  field, so an ack shows up as a list diff and re-enriches the incident — the override path and the
  diff path agree by construction.
- It does not fix the `alert_type: "host"` fallback on detail failure in today's code (§3). That is
  filed separately as a §8.8 defect. §5.5 states what the *proposed* design must do instead
  (`UNKNOWN`, never a guess), which is a requirement on new code, not a fix to the old.
- It does not propose concurrency (§8). The sweep is serial.

## 10. Open decisions for Thomas

1. ~~Is `max(refresh/m, 1 s)` the right shape?~~ **RULED 2026-09-16 (Thomas): no. Express it as a
   load budget `B` calls/s, default 1, independent of `cache_refresh_seconds` and of `n`; everything
   derives from it, and `n / B` gets surfaced to the operator in words.** §5.3 rewritten. The
   remaining sub-question is only whether **1 call/s is the right default**, and what the floor and
   ceiling clamps should be.
2. **Is §5.4 (per-incident freshness, report the oldest) separable and first?** It is a
   truthfulness fix, it is small, and §4 says the current stamp is a false-healthy signal.
3. **Is §5.5 (never cache a failure, `UNKNOWN` not `"host"`) accepted as a hard requirement**, not
   a refinement? It is the one item here whose absence makes the design worse than today.
4. **Is the §3 immutability inference acceptable as a *cache* policy**, given §5.2 and the sweep
   both re-derive if it is wrong?
5. **Does the cold-start backfill need an answer at all**, or is §8's option (a) enough?
6. **Is the §7 gap worth closing** — is there any deployment with a large incident count that can
   be timed once?

**SUPERSEDED 2026-09-19.** Decisions 1–6 are not ruled and will not be — the model they belong to
is replaced. Decisions 2, 3 and 4 are carried into the successor as **C9**, **C11** and **C10**
respectively, where they are ruled. Decisions 1, 5 and 6 are struck with the sweep.
Read `docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md`.
