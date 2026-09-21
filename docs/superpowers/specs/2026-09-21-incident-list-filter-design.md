# Design: the incident list filter — TOTL / OPEN / ACKD / CLRD / CLSD

**Status: APPROVED 2026-09-21 (Thomas). All five open questions RULED the same day —
nothing in this note is open. Complete enough to build from in ONE wave.**
**Date:** 2026-09-21.
**Supersedes** the four-tab sketch recorded in `shared/feature-spec.md` on 2026-09-20 and the two
open questions in the 09-20 handoff (e)3. Those are answered here.

## Provenance

| mark | meaning |
|---|---|
| **[THOMAS]** | ruled by Thomas. Not to be re-decided |
| **[MEASURED]** | observed against the live lab or read out of this repository today, with the source named |
| **[INFERENCE]** | reasoning from the above |

**Every measurement below names the server or file it came from.** That rule exists because on
2026-09-20 a `device_type` finding was taken from BHNM-B, presented as if it described the whole
estate, and had to be withdrawn.

---

## 1. The five pills **[THOMAS]**

The incident list gets **five filter pills and a free-text search**. Rows are unchanged — only the
filter row and the counts are new.

| pill | contents | colour |
|---|---|---|
| **TOTL** | OPEN + CLRD + CLSD | neutral outline |
| **OPEN** | state `OPEN`, acknowledged or not | red |
| **ACKD** | the acknowledged ones **inside** OPEN | blue |
| **CLRD** | state `ALARMS CLEARED` | green |
| **CLSD** | closed within the last 24 hours | grey |

- **Default pill: OPEN.**
- **The Home tile lands on OPEN, and its count is the OPEN count.** That is the mapping question
  from the 09-20 handoff, answered: the tile's set is exactly one pill.
- **Search matches `title`, device name, incident id and ack user, within the selected pill.**
- **Both iOS and the PWA.**

### Definitions **[THOMAS]**

> **BHNM has three incident states: `OPEN`, `ALARMS CLEARED`, `CLOSED`.**
> **Acknowledged is a FLAG on an OPEN incident, not a state.**

```
OPEN  = state OPEN, acknowledged or not
ACKD  = { i in OPEN : i.acknowledged }        a SUBSET, not a fourth bucket
CLRD  = state ALARMS CLEARED
CLSD  = state CLOSED, closed_at within 24h
TOTL  = OPEN + CLRD + CLSD                    (ACKD is inside OPEN and is NOT added again)
```

**[INFERENCE] ACKD being a subset is the whole reason this note exists.** Today both clients
compute acknowledgement by reading `incident_state == "ACKNOWLEDGED"` — a value BHNM never uses
for a state — so "acknowledged" and "alarms cleared" occupy the same field and cannot both be
true. An acknowledged incident whose alarms then clear can only be shown as one or the other.

---

## 2. Middleware — three changes **[THOMAS]**

### M1 — stop mixing the flag into the state

**[MEASURED — `middleware/main.py:762`]** A webhook writes the flag into the state field today:

```python
cache_state = {"ACKNOWLEDGEMENT": "ACKNOWLEDGED", "RECOVERY": "CLOSED"}.get(
    notification_type, "OPEN" if unack else None)
```

**[MEASURED — `middleware/incident_cache.py:299-306`]** `note_state_override` then writes that
string straight into `inc["incident_state"]`, and `_apply_state_overrides` (`:331-356`) re-applies
it over whatever the poll read, for `STATE_OVERRIDE_TTL = 300` seconds.

**Ruled: carry them separately.**

| field | values | source |
|---|---|---|
| `state` | `OPEN` \| `ALARMS CLEARED` \| `CLOSED` | BHNM's `incident_state` from `getincidents`, or the webhook for `RECOVERY` |
| `acknowledged` | `true` \| `false` | BHNM's `incident.acknowledged`, or the `ACKNOWLEDGEMENT` / unack webhook |

**[MEASURED]** `is_acknowledged()` already exists at `incident_cache.py:189-206` and already reads
BHNM's own `acknowledged` field — it is used to colour alarms blue (2.19.1). **The flag is already
being computed correctly and then discarded.** M1 is largely a matter of serving what is already
derived.

#### The payload rule, and the thing it bites on here

Root `CLAUDE.md`: **a client-decoded payload may only ever GAIN fields**, and a **new VALUE in an
existing field** is the same class of change.

**[MEASURED — shipped code, not HEAD]** Both released clients derive their entire notion of
acknowledgement from `incident_state`:

```
ios/BeNeM/Services/NetreoAPIService.swift:1300-1308   (build 53, in the field)
    let stateString = incidentData["incident_state"] as? String ?? "OPEN"
    if let forced = defaultStatus { status = forced }
    else if stateString == "ACKNOWLEDGED" { status = .acknowledged }
    else { status = .active }

pwa/src/lib/api/incidents.ts:101-104                  (0.18.1, live)
    if (forcedStatus) status = forcedStatus;
    else if (stateString === 'ACKNOWLEDGED') status = 'acknowledged';
    else status = 'active';
```

**[INFERENCE] So removing `ACKNOWLEDGED` from `incident_state` is a breaking change with no field
removed at all.** Build 53 would silently stop showing ACKD for every acknowledged incident. This
is the GAIN rule's sharpest case yet: the field stays, the key stays, the type stays, and a
released client still loses a feature.

**Ruled:**

1. **Add `state`, `acknowledged` and `closed_at` alongside.** Purely additive.
2. **Keep `incident_state` populated exactly as it is now**, `ACKNOWLEDGED` and all.
3. **The old behaviour may be dropped only when no client that reads `incident_state` for
   acknowledgement is in the field** — i.e. when iOS 2.14.0 has replaced 2.13.6 (53) on every
   phone and PWA 0.19.0 has replaced 0.18.1 in every browser. **That is Thomas's word, never an
   inference from elapsed time** (root `CLAUDE.md`, *App Store Connect is Thomas's alone*).
4. **The field evidence for (3) is `BeNeM/<build>` in the proxy log** — the User-Agent carries the
   build number. `BeNeM/53` disappearing and only `BeNeM/54`+ remaining is a measurement; a date
   is not.

**Filed as a follow-up, not this wave: `M1-drop`.** One commit, middleware only, removing the
`ACKNOWLEDGED`/`CLOSED` writes into `incident_state` and leaving `state` + `acknowledged` as the
only carriers.

### M2 — CLRD comes from a list-only fetch

**[MEASURED 2026-09-21, BHNM-B]** BHNM sends **no webhook for the `ALARMS CLEARED` transition**.
Incidents 30008, 30009, 30010 and 30011 produced `WARNING` at `15:40:12–18Z` and `RECOVERY` at
`16:16:11Z` and nothing in between, while BHNM's Active List View showed them `ALARMS CLEARED`.
Incident 30014 produced **zero webhook lines in the entire log** and nonetheless reached the app as
CLRD — because with no webhook there was no override, so the poll's value survived.

**[MEASURED]** `getincidents` on BHNM-B returns `incident_state: "ALARMS CLEARED"` when it is in
that state — observed on incident 29883 at `09:20Z`.

**[INFERENCE] So CLRD is reachable only through a list call, and the list call must not be gated
on the polling switch** — under webhook mode (C6, `incident_polling` default `false`) there is no
poll to carry it.

**Ruled:**

> **A Refresh tap, or the app coming to the foreground, triggers ONE `getincidents` call on the
> middleware. Single-flight, at most once per 30 seconds per server, independent of the polling
> switch. It updates `state` for every incident, and `acknowledged` for every incident whose row
> says anything about it, and makes NO `getincidentdetail` call.**

**CORRECTED 2026-09-21, during the 2.20.0 build. The original wording said "updates `state` and
`acknowledged` for every incident", and the list call cannot do the second half.** [MEASURED — the
served-row key list in §3 below, minus the four keys enrichment adds] a `getincidents` row carries
`incident_id`, `incident_state`, `name`, `title`, `open_time`, `device_category`, `device_site` and
`device_note` — **and no ack field at all.**

**A row that carries no ack field means "does not say", never `false`.** [THOMAS 2026-09-21] Reading
its absence as `false` would **un-acknowledge every incident on every refresh** — the doctrine's own
failure, an unverified value rendered as the healthy one, on the field that says whether anybody is
already on it. So `ack_flag()` returns `None` for such a row and the refresh keeps whatever the
cache already knew.

**The consequence, stated rather than hidden: a refresh cannot learn about an acknowledgement made
in the BHNM UI.** That fact arrives by `ACKNOWLEDGEMENT` webhook or by the next enrichment — which
is the webhook-first premise doing its job, not a gap in the refresh. **No design change follows:**
the ruling's substance — one list call, single-flight, no detail call, independent of the polling
switch — is unchanged, and only the claim about what the call can observe is corrected.

- **Fold this with C7.** `2026-09-19-incident-freshness-webhook-first-design.md` C7 already
  specifies a refresh endpoint, *"rate-limited server-side to one per server per 30 s"*, with *"a
  tap inside the window returns the running one's result"* and *"one user's refresh serves everyone
  on that server"*. **Same trigger, same window, same single-flight — one endpoint, not two.**
  C7's scope widens from "full reconciliation" to include this list-only mode.
- **List-only is the point.** `_fetch_incidents` is one HTTP call
  (`incident_cache.py:82-91`); enrichment is N calls paced over ~110 s
  (**[MEASURED]** `Enriching 10 incidents (pacing: 10.9s between calls)`, 2026-09-21). A refresh
  that waits for enrichment is not a refresh.
- **`state_confirmed_at` is stamped from this call** (C9), so the row can say how old its state is.
  `counts_confirmed_at` is untouched — the counts are exactly what this call does not refresh.

**[INFERENCE]** The foreground trigger already exists client-side as of `b3cc27a`
(`onChange(of: scenePhase)` in `IncidentListView`); it currently calls `loadIncidents()`. It
re-points at the refresh endpoint.

### M3 — CLSD is retained by the middleware

**[MEASURED 2026-09-21, BHNM-B, `getincidents` called exactly as `_fetch_incidents` does]** The
response's top-level keys are **`['active_incidents', 'result']`**. **There is no
`closed_incidents` key at all** — `_fetch_incidents` gets `[]` from
`data.get("closed_incidents", [])`, which is why every cache cycle today logged `0 closed`.

**[MEASURED]** `shared/BHNM_API_REFERENCE.md` documents no parameter that returns closed
incidents. The only documented form is `pwd=…&method=getincidents`, with `getincidentdetail` +
`incident_id` as the sole other method. Whether an undocumented parameter exists is **unmeasured**.

**Ruled:**

> **When an incident receives a `RECOVERY` webhook, or disappears from the list call, keep its last
> known row with `state: "CLOSED"` and a `closed_at`. Serve it for 24 hours from `closed_at`, then
> drop it. Nothing older than 24 hours is held, for any state.**

- **This is C15 with its purpose.** C15 recorded the 24-hour retention as a constraint; this says
  what it is for. The two must not drift — a change to one is a change to both.
- **`incident_types` is exempt**, as C15 already states: it is an id→type map, not incident data.
- **[INFERENCE] Disappearance is a close, and it is the only signal for some incidents.** 30014 was
  never webhooked and is now absent from `getincidents`; without the disappearance rule it would
  simply vanish with no CLSD row. The rule must therefore not require a `RECOVERY`.
- **[INFERENCE] A disappearance-driven close has no BHNM close time**, so `closed_at` is the
  middleware's own clock at the cycle that noticed. Open question 2.

---

## 3. The data contract

**Endpoint: `GET /api/v1/incidents`.** Served shape unchanged at the top level:

```json
{ "cache_age_seconds": 86, "active_incidents": [ … ], "closed_incidents": [ … ] }
```

**[MEASURED 2026-09-21] Keys on a served row today:**

```
alarm_counts, alert_type, counts_confirmed_at, device_category, device_note,
device_site, incident_id, incident_state, name, open_time, state_confirmed_at, title
```

**Added by this design — all additive:**

| field | type | meaning |
|---|---|---|
| `state` | `"OPEN"` \| `"ALARMS CLEARED"` \| `"CLOSED"` | BHNM's own state. Never carries the ack flag |
| `acknowledged` | `bool` | the flag. Meaningful on any state; the pills only read it inside OPEN |
| `ack_user` | `string` \| `null` | who acknowledged. Feeds search. From `getincidentdetail`/webhook |
| `closed_at` | `float` (epoch, UTC) \| `null` | when the middleware recorded the close. Present only on `CLOSED` |

**Retained, deliberately, until `M1-drop`:** `incident_state`, populated exactly as today —
`OPEN` / `ALARMS CLEARED` / `ACKNOWLEDGED` / `CLOSED`. **[MEASURED]** iOS decodes it at
`NetreoIncident.swift:99` (`case incidentState = "incident_state"`) via `decodeIfPresent ?? "OPEN"`
at `:144`; the PWA at `types.ts:20` as a required `string`.

### One example row per visible state

**OPEN, not acknowledged → pill OPEN**

```json
{ "incident_id": "30005", "name": "UAP-AC-Pro-DB",
  "title": "Anomaly Bandwidth on UAP-AC-Pro-DB wifi1 In",
  "state": "OPEN", "acknowledged": false, "ack_user": null, "closed_at": null,
  "incident_state": "OPEN",
  "open_time": "2026-09-21T17:40:10", "alert_type": "anomaly",
  "alarm_counts": {"red":0,"orange":0,"yellow":1,"green":0,"blue":0},
  "state_confirmed_at": 1789934464.5, "counts_confirmed_at": 1789934471.2 }
```

**OPEN, acknowledged → pills OPEN and ACKD**

```json
{ "incident_id": "27516", "name": "C9200CX",
  "title": "Service Configuration Save Check on C9200CX",
  "state": "OPEN", "acknowledged": true, "ack_user": "Thomas iPhone 13 ProMax",
  "closed_at": null,
  "incident_state": "ACKNOWLEDGED",
  "open_time": "2026-09-01T11:16:12", "alert_type": "service",
  "alarm_counts": {"red":0,"orange":0,"yellow":0,"green":0,"blue":1},
  "state_confirmed_at": 1789934464.5, "counts_confirmed_at": 1789934480.1 }
```

**ALARMS CLEARED → pill CLRD**

```json
{ "incident_id": "30014", "name": "UAP_AC_M",
  "title": "Anomaly Bandwidth on UAP_AC_M wifi1ap5 In",
  "state": "ALARMS CLEARED", "acknowledged": false, "ack_user": null, "closed_at": null,
  "incident_state": "ALARMS CLEARED",
  "open_time": "2026-09-21T17:55:09", "alert_type": "anomaly",
  "alarm_counts": {"red":0,"orange":0,"yellow":0,"green":1,"blue":0},
  "state_confirmed_at": 1789936112.0, "counts_confirmed_at": 1789936120.4 }
```

**CLOSED, inside 24h → pill CLSD.** Served in `closed_incidents`.

```json
{ "incident_id": "30007", "name": "raspi-050", "title": "Host raspi-050",
  "state": "CLOSED", "acknowledged": false, "ack_user": null,
  "closed_at": 1789928537.339,
  "incident_state": "CLOSED",
  "open_time": "2026-09-21T16:14:13", "alert_type": "host",
  "alarm_counts": {"red":0,"orange":0,"yellow":0,"green":1,"blue":0},
  "state_confirmed_at": 1789928537.339, "counts_confirmed_at": 1789928400.0 }
```

**[MEASURED]** 30007's numbers are real: `RECOVERY` at `14:22:17.339Z`, BHNM's own `CLOSED` at
`14:22:13Z` (`incident_log[0]`, `16:22:13` local).

### Client-side derivation

**[THOMAS] Pill counts are computed client-side from the served list.** No count endpoint.

```
open  = rows where state == "OPEN"
ackd  = rows where state == "OPEN" && acknowledged
clrd  = rows where state == "ALARMS CLEARED"
clsd  = rows where state == "CLOSED"
totl  = open + clrd + clsd
```

**During the transition**, a client reads `state` when present and otherwise falls back to
`incident_state`, mapping `ACKNOWLEDGED` → `state OPEN, acknowledged true`. That fallback is
deleted at `M1-drop`.

**[THOMAS] A CLOSED row must render, including on the detail screen** — a tapped Recovery
notification lands on one. **[MEASURED]** Both shipped clients already parse `closed_incidents`
(`NetreoAPIService.swift:1099,1226`; `incidents.ts:180-181`) and merge them into one list, so the
rows arrive; what is missing is the pill, and a detail screen that does not treat closed as an
error.

---

## 4. Build order — ONE client wave plus ONE middleware release

| step | build | what lands |
|---|---|---|
| **1** | **middleware 2.20.0** | M1 additive fields (`state`, `acknowledged`, `ack_user`, `closed_at`), `incident_state` unchanged; M2 refresh endpoint folded with C7; M3 CLSD retention **behind a per-server flag, default OFF** |
| **2** | **PWA 0.19.0** | five pills, search, client-side counts, CLOSED rows render, detail screen renders a closed incident |
| **3** | **iOS 2.14.0 (54)** | the same, submitted for review |
| **4** | — | **Thomas confirms 2.14.0 is in the field** (`BeNeM/54` in the proxy log) |
| **5** | **middleware 2.20.1** | flip the CLSD retention flag ON |
| **later** | **`M1-drop`** | remove `ACKNOWLEDGED`/`CLOSED` from `incident_state`, once no `BeNeM/53` remains |

**Why step 1 deploys before the clients and why CLSD hides behind a flag.**
**[MEASURED]** Both shipped clients already merge `closed_incidents` into the list, and build 53's
unfiltered list applies **no status filter at all** (`IncidentListViewModel.filteredIncidents:69-102`
— with no badge and no `selectedStatus`, nothing is filtered). **So turning on CLSD retention
before the clients ship would put closed rows into build 53's list with no pill to hide them.**
That is a visible behaviour change on a released client produced by a purely additive payload —
the GAIN rule's blind spot, found by reading the shipped filter rather than assuming it.

Everything else in 2.20.0 is invisible to build 53 and can deploy immediately.

**Versions today, for the diff: middleware 2.19.1, PWA 0.18.1, iOS 2.13.6 (53).**
**Every deploy bumps the version of what it deploys** (root `CLAUDE.md`), and the rollback tag is
named after the version observed running, not the one expected to ship.

---

## 5. The tests that prove each definition

**Each definition gets a test that fails if the definition changes.** Not one suite over the five —
five separate assertions, because that is what makes a later edit visible.

### Middleware — `middleware/tests/test_incident_state_and_flag.py`

| test | proves |
|---|---|
| `test_an_acknowledgement_webhook_sets_the_FLAG_and_leaves_state_OPEN` | M1. `state == "OPEN"`, `acknowledged is True` |
| `test_an_acknowledgement_webhook_still_writes_ACKNOWLEDGED_into_incident_state` | the transition guarantee build 53 depends on. **Deleted at `M1-drop`, not before** |
| `test_a_recovery_webhook_sets_state_CLOSED_and_stamps_closed_at` | M3 |
| `test_alarms_cleared_arrives_only_from_the_list_call` | M2. Feed a `getincidents` fixture carrying `ALARMS CLEARED`; assert the served row flips with **no `getincidentdetail` call made** |
| `test_the_refresh_endpoint_makes_exactly_one_getincidents_and_no_detail_call` | M2, list-only |
| `test_two_refreshes_inside_30s_produce_ONE_upstream_call_and_the_same_answer` | M2 single-flight, and C7's *"a tap inside the window returns the running one's result"* |
| `test_refresh_works_with_incident_polling_OFF` | M2 independence from the polling switch |
| `test_an_incident_that_disappears_from_the_list_is_retained_as_CLOSED` | M3's disappearance path — the 30014 case |
| `test_a_closed_row_is_served_for_24h_from_closed_at_and_dropped_after` | CLSD window and C15 |
| `test_nothing_older_than_24h_is_held_in_any_state` | C15's other half |
| `test_incident_types_is_NOT_dropped_by_the_24h_rule` | the C15 exemption |
| `test_an_error_body_RAISES_and_the_cache_is_untouched` | **added 2026-09-21 during the build.** `_fetch_incidents` returned the BHNM body unchecked, so an error answer — wrong api_key, HTTPS refusal, BHNM fault — read as ZERO incidents. Harmless before M3; **with retention it marks the whole estate CLOSED and serves it as CLSD for 24 hours.** The body must say `result: completed` before anything is derived from what it does not contain |
| `test_a_completed_body_with_no_active_incidents_key_closes_everything` | the legitimate zero still works. [MEASURED 2026-09-19] BHNM's own "none" is `{"result":"completed","detail":"No active incident."}` — it completed, and every cached incident really has gone |

### iOS — `ios/BeNeMTests/IncidentPillsTests.swift`, driving the real `IncidentListViewModel`

| test | proves |
|---|---|
| `testOPENContainsAcknowledgedIncidentsToo` | OPEN definition |
| `testACKDIsASubsetOfOPENAndIsNotAddedToTOTLTwice` | ACKD is a subset. Assert `totl == open + clrd + clsd` with an acked row present |
| `testCLRDIsExactlyStateAlarmsCleared` | CLRD definition |
| `testCLSDIsExactlyStateClosed` | CLSD definition |
| `testTheHomeTileCountEqualsTheOPENPillCount` | the tile mapping — the same class of defect as 2026-09-19 |
| `testTheDefaultPillIsOPEN` | default |
| `testSearchMatchesTitleDeviceIncidentIdAndAckUserWithinTheSelectedPill` | search scope, all four keys, and that it does not escape the pill |
| `testARowWithNoStateFieldFallsBackToIncidentState` | the transition fallback, including `ACKNOWLEDGED` → OPEN+flag |
| `testAClosedRowRenders` | the Recovery-notification landing |

### PWA — `pwa/src/features/incidents/__tests__/pills.test.ts`

The same nine, against the real selector and `parseIncidentsResponse`. **[MEASURED]** The two
platforms already derive status with identical logic
(`NetreoAPIService.swift:1300-1308` ≡ `incidents.ts:101-104`); the tests must stay symmetrical or
the platforms will drift where they currently agree.

**Run before every commit:** `cd middleware && python3 -m pytest tests -q`, and the iOS suite via
`xcodebuild test … -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

---

## 6. Parking list — record only, NOT this wave **[THOMAS]**

**Per-notification-type switches, per phone:** Open always on; Recovery and Acknowledgement
optional. **Belongs in the middleware's delivery step — the cache still takes every state update.**
The distinction matters: suppressing a notification must never suppress a state change, or the list
goes stale to save a buzz.

---

## 7. Open questions — ALL FIVE RULED 2026-09-21 (Thomas). Nothing here is open.

1. ~~**Does the CLSD 24-hour window start at `closed_at` or at `open_time`?**~~
   **RULED: `closed_at`.** An incident open for three days and closed ten minutes ago is CLSD.

2. ~~**What is `closed_at` for a disappearance-driven close?**~~
   **RULED: the middleware's own clock at the moment it noticed, and no approximate marker in the
   UI.** Under webhook mode that moment can be a refresh (M2) or the 24-hour reconcile (C5) rather
   than a poll cycle, **and that is fine** — the field states when the middleware learned, which is
   the only thing it can honestly claim. **[INFERENCE]** This is the one place the note knowingly
   serves a time that is not BHNM's, and it is ruled rather than hidden: the lag is bounded by
   whichever of refresh or reconcile comes first, not by a poll interval.

3. ~~**Does `acknowledged` survive an `ALARMS CLEARED` transition?**~~
   **RULED: ACKD stays a subset of OPEN exactly as defined, and a CLRD row keeps whatever blue
   alarm chips 2.19.1 already gives it.** So an acked incident whose alarms clear appears in CLRD,
   not in ACKD, and its chips stay blue.
   **Still to be MEASURED during the build, with no design change either way:** ack an incident in
   the lab, let its alarms clear, and record what `incident.acknowledged` and
   `incident_state` read afterwards. **Record the result whichever way it comes out** — the
   ruling does not depend on it, but the note must not carry an unmeasured claim about BHNM.
   Evidence file at build time.

4. ~~**Does the foreground refresh fire on every resume, or only when the list is older than N?**~~
   **RULED: every resume. The 30-second server-side window is the bound**, and it is the only
   bound — no client-side staleness check. **[INFERENCE]** One place enforces the rate, which is
   what makes C7's *"one user's refresh serves everyone on that server"* true rather than
   approximately true.

5. ~~**Should CLSD count toward the Home tile?**~~
   **RULED: no. The tile is the OPEN count.** A closed incident is not somebody's problem.

## 8. Two corrections this note carries

**[MEASURED] `filteredIncidents` DOES sort.** `IncidentListViewModel.swift:102` ends
`return filtered.sorted { (Int($0.incidentID) ?? 0) > (Int($1.incidentID) ?? 0) }` — descending by
id. The comment added to `upsertIncident` in `b3cc27a` said *"filteredIncidents does not sort, it
filters"* and was **wrong**. The append is still correct, for a different reason: the sort makes
insertion position irrelevant. **Corrected in the same commit as this note.**

**[WITHDRAWN 2026-09-21] "The poll kept reading OPEN for 30008–30011."** That was inferred from a
later measurement of different incidents and was never measured for those rows. What those three
poll cycles read is unrecorded — the log does not carry per-incident state. **Hop B stands and is
quoted in M1 above; Hop A does not.**
