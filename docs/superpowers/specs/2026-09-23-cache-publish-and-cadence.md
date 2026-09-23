# Design: cache publish and cadence — C16 to C20

**Status: RULED 2026-09-23 (Thomas). Addendum to
`docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md`, continuing its
C-series at C16.** Nothing here is open.
**Date:** 2026-09-23.
**Subject:** `middleware/incident_cache.py`, `middleware/main.py`, `middleware/benem-admin/`,
`ios/`, `pwa/`.
**Extends, does not supersede:** the webhook-first note. C1–C15 stand. C15's 24-hour retention is
unchanged; C16 and C17 change only *when* a row may be declared closed, never *how long* a closed
row is held.

---

## Provenance

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed against the live deployment on 2026-09-23, with the log line or payload quoted |
| **[THOMAS]** | Thomas's ruling. Not to be re-decided |
| **[INFERENCE]** | Reasoning from the above, marked so it can be attacked separately from the facts |

All times UTC. The lab runs CEST, so BHNM's own timestamps are quoted as local and converted by
−2 h, with both shown the first time. **Everything in the evidence section was read out of
`/logs/middleware.log` and BHNM's `getincidentdetail` `incident_log` on 2026-09-23, not recalled.**

---

## 0. What this note is for

Two incidents on 2026-09-23 exposed three separate defects in how the cache decides what to
publish and when. All three are in the same place — the cycle in `_run_one_cycle` that takes a
list, enriches every row, and writes the whole cache at the end — and none of them is a colour
bug, which is what the previous two releases were about.

- **30045 was served as CLOSED while BHNM had it OPEN.** A cycle published a list taken 48 s
  before the incident existed, over newer knowledge from a refresh.
- **30046's green took 3 min 11 s to reach the phone**, of which 101 s was the cache refusing to
  publish a state it already knew.
- **The Android PWA never saw 30045 at all**, because the window in which it was served OPEN was
  17.5 s wide and the PWA samples every 60 s.

C16 and C17 fix the first. C18 and C19 fix the second. The client change fixes the third. C20 is
instrumentation, including a defect in the instrumentation added yesterday.

---

## 1. The rulings

### C16 — Newest confirmation wins **[THOMAS]**

> **Every row carries `state_confirmed_at`, the time of the list call that confirmed it. A publish
> from a list taken at time `T` may not overwrite a row whose `state_confirmed_at` is newer than
> `T`, and may not treat such a row as disappeared.**

**[INFERENCE] The cache has two writers and no ordering rule between them.** `_run_one_cycle`
takes a list and publishes it up to `cache_refresh_seconds` later; `_run_list_only` (the Refresh
endpoint, C7/M2) takes a list and publishes it immediately. Nothing compares their vintages, so
the slower writer wins simply by finishing last. `state_confirmed_at` already records exactly the
fact needed to order them and is already served on every row — C16 is a comparison this data
supports today and nobody performs.

**The rule is per row, not per publish.** A cycle's list is not wholesale stale; it is stale only
for the rows a refresh has since confirmed. A cycle that took its list at `T` still publishes
every row whose `state_confirmed_at` is older than `T`, and skips the handful that are newer.

**[THOMAS] Absence is governed by the same clock.** A row confirmed *after* the list was taken
cannot be said to be missing from that list — it was not eligible to be in it. Retaining it as
CLOSED is the false-CLOSED defect below, and C16 forbids it independently of C17.

### C17 — Disappearance is confirmed, not inferred **[THOMAS]**

> **A row absent from a list that IS newer than its confirmation is checked with one
> `getincidentdetail` before it is retained. BHNM answering `CLOSED` retains it. BHNM answering
> `OPEN` or `ALARMS CLEARED` keeps it active with that state. BHNM not finding it retains it.**

C16 removes the *stale-list* cause of a false CLOSED. C17 removes the rest. **[MEASURED
2026-09-21, recorded in the filter note]** incident 30014 produced zero webhook lines and simply
vanished from `getincidents`; the disappearance rule exists because some closes have no other
signal, and it must stay. What it must stop doing is guessing.

- **One call, not a cycle's worth.** Disappearance is rare — six retained rows across a whole
  morning — so the cost is bounded by how often incidents actually leave the list, not by the
  incident count.
- **"Not found" retains.** BHNM has forgotten the incident, which is a close by another name, and
  the alternative is a row that never ages out.
- **[INFERENCE] This is the doctrine applied to a state rather than a colour.** A retained CLOSED
  is a claim the middleware makes on its own initiative, with BHNM never asked. C17 makes it a
  claim the middleware has checked, and `closed_at` keeps meaning *when the middleware learned*
  (open question 2, unchanged).

### C18 — Publish the list immediately **[THOMAS]**

> **The list call's `state` and `acknowledged` for every row are published the moment the list
> lands, before any enrichment. Enrichment then updates `alarm_counts` and `counts_confirmed_at`
> row by row as each detail call lands — not in one write at the end of the cycle.**

**[MEASURED] Today's cost of the end-of-cycle publish on 30046 was 101 s**: the list that carried
`ALARMS CLEARED` landed at `07:07:36.490Z` and the cache was not written until `07:09:17.555Z`.
For those 101 s the middleware held the right answer and served the old one.

**[INFERENCE] This is why C9's two stamps exist**, and the current loop wastes them.
`state_confirmed_at` and `counts_confirmed_at` are separate precisely so state and counts can move
independently; publishing them together at the end of the cycle re-couples what C9 separated.

**The row-by-row enrichment write is what makes C16 cheap**, incidentally: a cache written
continuously has no long window in which a refresh and a cycle can disagree.

### C19 — Two cadences **[THOMAS]**

> **`list_poll_seconds` is ADDED beside `cache_refresh_seconds`, default 30, minimum 15 — one
> `getincidents` per server per interval. `cache_refresh_seconds` KEEPS its present meaning as the
> ENRICHMENT cadence and is NOT renamed in 2.21.0. The Refresh endpoint remains the on-demand
> trigger of the list call, with C7's 30 s single-flight window unchanged.**

**RULED 2026-09-23 (Thomas), settling the naming question this note opened.** Two keys, two
cadences, one of them new:

| key | means | default | bounds |
|---|---|---|---|
| **`list_poll_seconds`** | interval between `getincidents` calls | **30** | **min 15**, max 900 |
| `cache_refresh_seconds` | interval of the enrichment sweep — **unchanged** | 120 | min 60, max 900 |

**The BHNM cost, stated: one list call per 30 s per server — 120 calls per hour per server,
whatever the incident count.** `getincidents` is one HTTP request returning the whole list
(`incident_cache.py:_fetch_incidents`); it does not scale with incidents. Enrichment is the N-call
side and its cadence is untouched by this note.

**No rename in 2.21.0.** `cache_refresh_seconds` is the key in every `servers.json` in the field
and in `benem-admin`'s form; renaming it to C6's `incident_polling_seconds` is **deferred to a
later migration that reads the old key** and writes the new one, so a configured value cannot be
lost in the change. **[INFERENCE]** A rename that silently drops a configured value is the
`benem-admin` defect of 2026-09-22 in another costume, and there is no reason to take that risk in
the release that also restructures the cache loop.

### C20 — Instrumentation **[THOMAS]**

> **The `[State:]` line is written AFTER overrides are applied and reports the SERVED value, with
> the raw list value alongside when the two differ. The Refresh endpoint logs a `[Client]` line.**

**[MEASURED] The line added in 2.20.3 reports the wrong value during an override's TTL.** At
`07:11:59.949Z` it read:

```
[State:ThomasLabServer] incident 30046: CLOSED/ack=False -> ALARMS CLEARED/ack=False (source: list)
```

while the served row was `CLOSED` — the `RECOVERY` override set at `07:11:29.963Z` was live, and
its expiry is logged at `07:17:32.548Z`. The transition is logged inside the row loop, which runs
*before* `_apply_state_overrides`, so the line describes the list rather than the cache. **A log
line that disagrees with the payload is worse than no line**, because it will be believed.

**[MEASURED] The Refresh endpoint logs no `[Client]` line**, so the refresh at `07:00:37.783Z`
cannot be attributed to a client. That is exactly the question §4 needed to answer and could not:
which app triggered the call that let iOS see 30045. `/register` and `GET /api/v1/incidents`
gained the line in 2.20.1; `POST /api/v1/incidents/refresh` was missed.

### Clients — the silent poll goes to 30 s **[THOMAS]**

> **The incident list's silent foreground poll moves from 60 s to 30 s on both platforms.**

iOS `IncidentListViewModel.startListPoll`, PWA `usePollWhileVisible`. Everything else about them —
no countdown, no UI, stops when not visible or backgrounded, sleeps before its first read — is
unchanged from 2.14.0 / 0.19.5. **[INFERENCE]** With C18 and C19 the server-side answer moves
within ~30 s; a 60 s client poll would become the dominant term in the lag, which is the shape
this note exists to remove.

---

## 2. Evidence — 30045, the false CLOSED

`Service Check Interface Status on GigabitEthernet7 on C800`. **[MEASURED] Not an incident on
raspi-050**, though it is caused by one: it is the switch port the host hangs off.

BHNM's own `incident_log`, local CEST then UTC:

```
OPEN            2026-09-23T09:00:12  ->  07:00:12Z
ALARMS CLEARED  2026-09-23T09:05:27  ->  07:05:27Z
CLOSED          2026-09-23T09:10:29  ->  07:10:29Z
primary alarm OK 2026-09-23T09:04:32 ->  07:04:32Z
```

The middleware:

```
06:59:24.631  [Cache] Enriching 3 incidents (pacing: 30.0s)   <- this cycle's list is taken HERE
07:00:12      BHNM opens 30045                                <- 48 s after that list
07:00:37.782  [State:] 30045: None/ack=None -> OPEN/ack=False (source: list)
07:00:37.783  [Refresh:] List refreshed: 4 active, 6 closed, no detail calls
07:00:55.298  [State:] 30045: OPEN/ack=False -> CLOSED/ack=False (source: disappearance)
07:00:55.298  [Cache] Retained 7 incident(s) as CLOSED — gone from the list, no RECOVERY seen
07:00:55.298  [Cache] Cache updated: 3 active, 7 closed, oldest enrichment 49546s, 1 unconfirmed
07:01:37.587  [Client] BeNeM/54 on /api/v1/incidents           <- the phone sees CLOSED
07:02:08.396  [State:] 30045: CLOSED/ack=False -> OPEN/ack=False (source: list)
07:02:15.978  [Client] BeNeM/54 on /api/v1/incidents           <- the phone sees OPEN again
```

**The cycle that published the false CLOSED took its list 48 seconds before the incident
existed.** `4 active` from the refresh at `07:00:37.783` was overwritten by `3 active` from a list
taken at `06:59:24`, and `_retain_closed` read the absence as a close. **BHNM had it OPEN
throughout**; it was not closed until `07:10:29Z`, nearly ten minutes later.

**C16 alone prevents this**: 30045's `state_confirmed_at` was `07:00:37.783`, newer than the
cycle's list, so the cycle may neither overwrite it nor call it disappeared. **C17 is the second
line of defence** for the case where the list genuinely is newer.

Note also `1 unconfirmed` on that line — the retained row had no `counts_confirmed_at`, which is
C9 correctly refusing to date counts it never had. The freshness accounting was honest about a row
that should not have existed.

---

## 3. Evidence — 30046, the 101-second publish

`Host raspi-050`. BHNM's `incident_log`:

```
OPEN            2026-09-23T09:02:13  ->  07:02:13Z
ALARMS CLEARED  2026-09-23T09:06:27  ->  07:06:27Z
CLOSED          2026-09-23T09:11:29  ->  07:11:29Z
primary alarm UP 2026-09-23T09:06:03 ->  07:06:03Z
```

The middleware, from BHNM's state change to the phone:

```
07:06:27      BHNM: ALARMS CLEARED
07:07:36.490  [Cache] Enriching 5 incidents (pacing: 20.0s)    <- the list that carries it lands
07:08:57.555  [State:] 30046: OPEN -> ALARMS CLEARED (source: list)
07:09:17.555  [Cache] Cache updated: 5 active, 6 closed        <- ONLY NOW is it served
07:09:38.435  [Client] BeNeM/54 on /api/v1/incidents           <- the phone fetches it
```

**The breakdown:**

| segment | cost | cause | fixed by |
|---|---|---|---|
| `07:06:27` → `07:07:36.5` | **69 s** | waiting for the next list call at a 120 s cycle | **C19** (30 s) |
| `07:07:36.5` → `07:08:57.6` | **81 s** | 30046's slot in the paced enrichment loop | **C18** (state published at once) |
| `07:08:57.6` → `07:09:17.6` | **20 s** | the rest of the loop before the cache is written | **C18** |
| `07:09:17.6` → `07:09:38.4` | **21 s** | the client's 60 s silent poll | **client 30 s** |
| **total** | **3 min 11 s** | | |

**The middle two segments are 101 s in which the middleware held the answer and served the old
one.** That is C18's measured cost, and it is the single largest term.

**[MEASURED] This was not a 2.20.3 case, and the note says so rather than claiming a win.** The
`[State:]` line at `07:08:57.555` has no `[Refresh:]` line beside it, so it came from
`_run_one_cycle`, where 30046's own detail call had just landed — the green came from enrichment,
the path that worked before 2.20.3. The same is true of 30045 at `07:06:56.070` and of 30039 at
`17:11:54.416Z` on 2026-09-22 (`counts_confirmed_at 17:11:54.416` = the detail call itself).
**2.20.3's list-path recolour has still not been exercised in the field**; the mismatch it fixes
needs a Refresh to land between BHNM clearing and the next cycle, which is what happened to 30035
on 2026-09-22 and has not happened since.

---

## 4. Evidence — why the PWA missed 30045

30045 was served as OPEN for **17.5 seconds**, from the refresh at `07:00:37.783` to the false
CLOSED at `07:00:55.298`. The PWA's polls:

```
06:59:58.594  [Client] not-BeNeM on /api/v1/incidents   <- before the refresh; 30045 not in the list
              ... the 17.5 s window ...
07:00:58.599  [Client] not-BeNeM on /api/v1/incidents   <- after the false CLOSED
```

**The PWA had no sample inside the window.** iOS did, because the Refresh endpoint returns the
fresh list directly to its caller rather than only into the cache.

**[INFERENCE, and the limit is stated] Which client triggered `07:00:37.783` cannot be read from
the log** — that is C20's second half. It does not change the answer: the window fell entirely
between the PWA's two polls either way.

**C16 removes the window entirely** — there is no false CLOSED to miss. The client's 30 s poll
halves what remains.

---

## 5. The changed data flow

Today, `_run_one_cycle`:

```
1. getincidents                                    <- list_at stamped
2. for each incident:  getincidentdetail, sleep(pacing)
3. _retain_closed  (absence from the step-1 list = CLOSED)
4. _apply_state_overrides
5. _cache[server_id] = everything                  <- ONE write, up to cache_refresh_seconds later
6. [State:] lines were emitted inside step 2, before step 4
```

After C16–C18 and C20:

```
1. getincidents                                    <- list_at stamped
2. PUBLISH state + acknowledged for every row whose state_confirmed_at is OLDER than list_at
     - rows confirmed NEWER than list_at are left alone                       (C16)
     - alarm_counts recoloured from the severity snapshot by the existing
       recolour(), so the colour follows the state it was just given          (2.20.3)
     - absence is NOT a close yet
3. _apply_state_overrides, then emit the [State:] lines from the SERVED value (C20)
4. for each row absent from a list newer than its own confirmation:
     one getincidentdetail -> CLOSED retains / OPEN or ALARMS CLEARED keeps
     active / not found retains                                               (C17)
5. for each incident: getincidentdetail, then PUBLISH that row's alarm_counts
   and counts_confirmed_at immediately, sleep(pacing)                         (C18)
```

**The list loop and the enrichment loop become two cadences over one cache** (C19), and the cache
is written continuously rather than swapped. **[INFERENCE] Step 2 is the whole of C18** — the
other steps are unchanged work in a different order.

---

## 6. The tests that prove C16 to C18

Each ruling gets assertions that fail against 2.20.3. Middleware, `middleware/tests/`.

### C16 — newest confirmation wins

| test | proves |
|---|---|
| `test_a_cycle_may_not_overwrite_a_row_a_refresh_confirmed_later` | Seed a row, refresh it at `T+10`, then publish a cycle whose `list_at` is `T`. The refresh's value survives |
| `test_a_row_confirmed_after_the_list_was_taken_is_NOT_a_disappearance` | **The 30045 case exactly.** A row absent from a list taken before it existed is not retained as CLOSED, and `Retained` does not fire |
| `test_a_cycle_DOES_overwrite_a_row_older_than_its_list` | The guard shown capable of the other answer — without this, a function that never publishes would pass the two above |
| `test_the_comparison_is_per_row_not_per_publish` | One stale row in a cycle does not block the other four |

### C17 — disappearance is confirmed

| test | proves |
|---|---|
| `test_an_absent_row_is_CHECKED_with_one_getincidentdetail_before_retention` | Exactly one detail call, and `Retained` only after it answers |
| `test_BHNM_saying_CLOSED_retains_the_row` | The 30014 path still works |
| `test_BHNM_saying_OPEN_keeps_the_row_ACTIVE_with_that_state` | The false-CLOSED path is closed off at its second cause |
| `test_BHNM_saying_ALARMS_CLEARED_keeps_the_row_active_and_GREEN` | C17 composes with 2.20.3's `recolour` |
| `test_BHNM_not_finding_it_retains_the_row` | The forgotten-incident case |
| `test_the_check_is_one_call_per_ABSENT_row_not_per_row` | The cost claim. Five rows, one absent, one extra call |

### C18 — publish the list immediately

| test | proves |
|---|---|
| `test_state_is_SERVED_before_any_detail_call_is_made` | Drive a cycle with a blocking detail stub; `GET /api/v1/incidents` already shows the new state |
| `test_counts_are_published_row_by_row_as_each_detail_lands` | After the first detail call, that row's `counts_confirmed_at` has moved and the others' have not |
| `test_the_30046_shape_costs_under_a_second_not_101_seconds` | The measurement as a regression test: list lands, state served, assert the gap |
| `test_a_failed_detail_call_does_not_unpublish_the_state` | C11 — a failed enrichment must not roll back a state that was already confirmed |

**[THOMAS] Run the first of each against the current code and show it failing**, per the rule that
has caught two wrong-reason passes this week.

---

## 7. Build order

| step | build | what lands |
|---|---|---|
| **1** | **middleware 2.21.0** | C16, C17, C18, C19 (`list_poll_seconds` added, nothing renamed), C20. One release — C16 without C18 leaves the stale-publish window open, and C18 without C16 widens it |
| **2** | — | **Verify in the lab**: pull raspi-050 again and measure the same two incidents. The pass is a state on the phone within one `list_poll_seconds` plus one client poll of BHNM's own timestamp, and **no `Retained` line for an incident BHNM has OPEN** |
| **3** | **one client wave — iOS 2.14.x + PWA 0.19.x** | the silent poll to 30 s on both platforms. Nothing else |
| **4** | — | **Thomas submits.** Per root `CLAUDE.md`: EXPORT, VERIFY the IPA, UPLOAD, as three steps |

**Why the clients are a separate wave and go second.** They are the smallest term in the
breakdown (21 s of 191) and they cannot be rolled back in minutes. The middleware carries the 170
s and deploys in one command. **[INFERENCE]** If step 2 fails, step 3 has not shipped yet.

**Versions at the time of writing: middleware 2.20.3, PWA 0.19.7, iOS 2.14.0 (54), benem-admin
1.6.4.** Every deploy bumps the version of what it deploys, and the rollback tag is named after
the version observed running (root `CLAUDE.md`).

---

## 8. What this note deliberately does not change

- **C15's 24-hour retention window.** C16 and C17 change when a row may be *declared* closed, never
  how long a closed row is held.
- **`closed_at` semantics** (open question 2): still the middleware's own clock at the moment it
  learned. C17 makes that moment better-informed, not different in kind.
- **C7's 30 s single-flight window** on the Refresh endpoint. C19 adds a background cadence beside
  it; the on-demand trigger and its rate limit are untouched.
- **The colour rules.** `recolour`, `derive_counts` and the severity snapshot land unchanged from
  2.20.3. Cleared still beats acknowledged.
- **Anything in `ios/` or `pwa/` other than the poll interval.**

---

## 9. Open, and not for this note

1. ~~**The `incident_polling_seconds` / `cache_refresh_seconds` naming**~~ — **RULED 2026-09-23,
   see C19.** `cache_refresh_seconds` stays as the enrichment cadence, `list_poll_seconds` is added
   beside it, and the C6 rename is deferred to a migration that reads the old key. Not open.
2. **2.20.3's list-path recolour is still unexercised in the field.** After C18 it will fire on
   every list publish rather than only on a Refresh, so this note makes the verification easy
   rather than answering it.
3. **`_run_one_cycle` enriches every incident every cycle**, which is why state and counts have so
   far always moved together outside the Refresh path. Whether enrichment should skip rows whose
   counts are already fresh is a cost question, not a correctness one, and is not ruled here.
