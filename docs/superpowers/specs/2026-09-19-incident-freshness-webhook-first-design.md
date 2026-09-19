# Design: incident freshness, webhook-first — the webhook is the truth, the poll is the repair

**Status:** **APPROVED 2026-09-19 (Thomas).** Build order accepted at 13 steps, cut line after
step 5. **WAVE 1 = steps 1–4, then STOP** — step 5 is the App Store release and it is Thomas's go,
not the builder's. Steps 6–13 are approved but not started.
**Date:** 2026-09-19
**Ruled by:** Thomas, Phase 2 decision sitting, 2026-09-19.
**Supersedes:** `docs/superpowers/specs/2026-09-16-incident-cache-cost-model-design.md` (marked
superseded, kept for its measurements).
**Absorbs and extends:** `docs/superpowers/specs/2026-09-15-incident-freshness-design.md` Parts 1
and 2 — **decided 2026-09-15, still unbuilt.** See §0.3.
**Subject:** `middleware/incident_cache.py`, `middleware/main.py`, `middleware/benem-admin/`,
`ios/`, `pwa/`, `shared/push-payload-spec.md`.

---

## Provenance, stated first

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed by me, in this repository or against the live deployment, with the observation recorded here or in the note it cites |
| **[THOMAS]** | Thomas's ruling, or Thomas's account of how BHNM behaves. Not verified by me |
| **[INFERENCE]** | My reasoning from the above. Marked so it can be attacked separately from the facts |

Two rules from `middleware/CLAUDE.md` govern every claim in this document: *an empty result must
first be shown capable of returning a non-empty one*, and *an assertion must first be shown to have
been checked.* Both were added on 2026-09-19 after an assertion offered in review as a measurement
cost a released build its ack attribution.

---

## 0. The inversion, which is the whole design

### 0.1 What the code believes today

**[MEASURED — `middleware/main.py:732-733`, read 2026-09-19.]** The webhook handler patches the
cached incident state, and says in its own comment what it thinks it is doing:

```python
732:    # Patch the cached incident so the list reflects the new state before the next
733:    # poll. The poll remains the source of truth and overwrites this.
734:    cache_state = {"ACKNOWLEDGEMENT": "ACKNOWLEDGED", "RECOVERY": "CLOSED"}.get(
735:        notification_type, "OPEN" if unack else None)
```

**The poll is the source of truth. The webhook is a hint with a 300-second shelf life**
(`incident_cache.py:141`, `STATE_OVERRIDE_TTL = 300`). That is the premise of every design this
project has written about the incident cache, and it is the premise the 09-16 cost model spent
548 lines trying to make affordable.

### 0.2 What Thomas rules

**[THOMAS] The webhook is authoritative. The poll is a repair mechanism.**

That single reversal collapses most of the 09-16 note. A design whose job is to make a full poll
cheap at n = 1000 is solving a problem that a webhook-first system does not have: it does not need
to re-derive the whole estate on a cadence, because BHNM tells it what changed, when it changed.
What it needs instead is to be **correct about the things webhooks cannot tell it**, and **honest
about how long it has been since it last checked.**

**[INFERENCE] The two failure modes swap places.** Under polling, the risk is staleness you can
compute — you know the cycle period, so you know the worst case. Under webhook-first, the risk is
**a webhook that never arrived**, which from the middleware's side is indistinguishable from
nothing having happened. That is the same shape as the anomaly-knob silence recorded in the 09-18
handoff §(c): *"no webhooks arrived" and "the setting is off" are indistinguishable.* **C5 exists
entirely to make that distinguishable**, and it is the load-bearing part of this design.

### 0.3 What the 09-15 note already decided, and what is left of it

**[MEASURED — grep over `middleware/`, 2026-09-19]** `docs/superpowers/specs/2026-09-15-incident-freshness-design.md`
Parts 1 and 2 were **decided on 2026-09-15 and are not built.** There is no webhook-triggered
refresh (`_fetch_incidents` has exactly one caller, `incident_cache.py:228`, inside the paced
cycle) and there is no `GET /api/v1/incidents/{incident_id}` route (`main.py` declares
`/api/v1/incidents` only, lines 826–827). The only part of that note that shipped is the
state-override patch, in 2.15.x.

| 09-15 part | status under this design |
|---|---|
| **Part 1** — webhook triggers a whole-**list** refresh, debounced 15 s leading-edge | **SUPERSEDED by C2.** A per-incident list+detail fetch is strictly better: it is cheaper (one incident, not the estate), it carries the detail the list cannot (`alarm_counts`, `alert_type`), and it has no debounce problem because ten correlated alerts are ten different incidents that each need fetching anyway. **Keep the leading-edge principle**, which was the right ruling: act on the first event, never delay a lone one |
| **Part 2** — `GET /api/v1/incidents/{incident_id}`, 404 vs 502 distinguishable | **STANDS, unchanged, and is now a prerequisite.** C2's fetch and C7's refresh both need it, and C2's "the tap beats the fetch" case is exactly what it was written for |
| **Part 3** — the four (five) states, *"Incident not found"* banned | **STANDS.** Still unbuilt: **[MEASURED]** `pwa/src/features/incidents/IncidentDetailScreen.tsx:105` renders the literal string `Incident not found.` today |

**[INFERENCE]** Part 1's supersession is a *narrowing*, not a reversal, and the 09-15 decision
record should be read as still correct about *why* server-side beats client-side: it runs whether
or not the phone is awake, and it serves every client at once. C2 keeps both properties.

---

## 1. The rulings

Each is stated as Thomas ruled it, then what it obliges, then what is not yet known about it.

### C1 — Webhooks are authoritative for incident state **[THOMAS]**

When BHNM sends a webhook, that is the truth, **immediately**.

**Obliges:** the `main.py:732-733` comment is not merely out of date, it is the opposite of the
design — it must be rewritten, not deleted, so the next reader learns the ordering rather than
guessing it. **The 300-second `STATE_OVERRIDE_TTL` is replaced: RULED 2026-09-19 — an override is
cleared by C2's SUCCESSFUL fetch, never by a clock; a failed fetch leaves it in place and retries;
a 10-minute cap exists only so nothing leaks forever, and if it ever fires in normal operation that
is a defect to log loudly.** See open decision 2.

**[INFERENCE]** "Authoritative" has a limit worth stating so nobody over-reads it: a webhook is
authoritative about **the state change it reports**, at the moment it reports it. It is not
authoritative about anything it does not carry — alarm counts inside an already-open incident (C13),
or an incident it never mentioned. Authority over a field is not authority over the record.

### C2 — Every webhook triggers a fetch of that incident **[THOMAS]**

**All types, not only `PROBLEM`.** The middleware fetches **the list entry and the detail for that
incident** into the cache at once, without waiting for any cycle.

| type | what the fetch must produce |
|---|---|
| `PROBLEM` / `CRITICAL` / `WARNING` | add the incident |
| `RECOVERY` | state `CLOSED`, alarm counts refreshed, **and the incident MOVED from the active bucket to the closed bucket** — BHNM does, so BeNeM must |
| `ACKNOWLEDGEMENT` / `DEACKNOWLEDGEMENT` | state, **ack user**, **ack comment** |

**Push and fetch run in parallel.** Delivery is never delayed by the fetch — a paging product does
not hold a page behind a cache write.

**If the user's tap beats the fetch, the app shows `Fetching incident data…` and waits.**
**`Incident not found` stays banned** (09-15 Part 3).

**RULED 2026-09-19 (Thomas): the fix for the still-rendered banned string belongs to THIS build,
not to a separate ticket.** **[MEASURED]** `pwa/src/features/incidents/IncidentDetailScreen.tsx:105`
renders the literal `Incident not found.` today, banned since 2026-09-15. It becomes
**`Fetching incident data…` → a bounded wait → an honest `could not load this incident`** — three
states, and the middle one is the *unverified* state the doctrine requires rather than a terminal
claim the app has not earned. It is **step 4** of the build order, batched into the same client
release as C11's `UNKNOWN` rendering.

**[MEASURED]** The ack fields this makes available are already in the detail response and are
currently fetched and discarded every cycle: `ack_comment`, `ack_time`, `ack_user`, `acknowledged`
(09-16 note §3). **[INFERENCE]** So C2 does not need a new upstream call shape — it needs the
existing `_fetch_incident_detail` called on an event instead of on a cursor, and its response
*kept* rather than reduced to two keys by `_enrich_incident` (`incident_cache.py:128-132`).

**[INFERENCE] The `RECOVERY` bucket move is the sharpest item here and the easiest to get wrong.**
Today the buckets are rebuilt wholesale from a fresh `getincidents` every cycle
(`incident_cache.py:235`), so nothing ever "moves" — the list simply comes back different. Under
C2 the cache is mutated in place by events, and a `RECOVERY` that updates state to `CLOSED`
**without moving the row** leaves a closed incident sitting in the active list wearing the right
label. That is a doctrine failure in the active-count tile: a number that counts a thing that is
not active. It must be one operation, not two.

#### The measurement C2 requires, on the first live webhook after it ships **[THOMAS]**

> **Is the incident already fetchable from BHNM at webhook time, on the `PROBLEM` path?**

**Everything seen so far says yes** — **[MEASURED]** the 2.15.2 pending-override work established
that BHNM reflects acks in `getincidents` instantly (`incident_cache.py:141` comment), and
incident 29869 appeared in `getincidents` in the lab at 17:18Z having opened at 17:10Z. **But it
has not been measured on the `PROBLEM` path**, which is the one where a race is plausible: the
notification is generated by the alerting pipeline, and whether the incident record is committed
and queryable at that instant is a question about BHNM's internals.

**[INFERENCE] This is the C13-shaped trap in miniature.** The evidence for "yes" is drawn from
`ACKNOWLEDGEMENT` and from an incident observed eight minutes after it opened. Neither observes
the `PROBLEM` path at t=0. **Log the result, do not assert it.**

**Method:** on the first `PROBLEM` webhook after this ships, log — at minimum — the webhook arrival
time, the fetch dispatch time, the fetch result (`found` / `not found` / `error`), the fetch
latency, and the incident id. If `not found`, log the retry outcome and how long it took to become
fetchable. **A single `[Freshness] fetch-at-webhook incident=<id> result=<r> latency=<ms>` line is
the whole requirement**, and it is the line that makes the answer a measurement instead of a
belief — the same role the fallback's announcement played in the 2026-09-15 migration that had
silently not applied (root `CLAUDE.md`).

**If the answer is no:** the fetch needs a bounded retry, and C2's contract becomes "fetch, and if
BHNM does not have it yet, retry until it does or the retry budget runs out" — with the app's
`Fetching incident data…` state covering the gap, which it already must for the tap race.

### C3 — The push payload carries the state change to the app **[THOMAS]**

iOS and the PWA **apply a state change from the notification payload directly to their list** — a
row goes acknowledged or cleared **without a fetch**. This is app-side work and it is **in scope
for this design**.

**[MEASURED — `shared/push-payload-spec.md`]** The payload today carries exactly one field beyond
the alert text: `incident_id`. Both platforms:

```json
{ "aps": { "alert": {...}, "sound": "default" }, "incident_id": "<id>" }
{ "title": "...", "body": "...", "incident_id": "<id>" }
```

**Obliges:** new fields — at minimum the notification type and the resulting state, and for an
acknowledgement the ack user. **This is purely additive, so it is safe under C14** and needs no
client release to precede it. The contract file is the source of truth for both platforms and must
be updated **before or alongside** either client (`shared/feature-spec.md` rule, root `CLAUDE.md`).

**[INFERENCE] C3 and C2 must not be allowed to disagree, and they can.** The payload arrives at the
phone; the fetch lands in the middleware cache. If the phone applies the payload's state and then
pulls a list whose fetch has not completed, the row flips and flips back. The rule that resolves it
is **C9**: a row carries its own last-confirmed time, and a payload-applied state is confirmed at
the push's timestamp. A list row that is older than the payload does not overwrite it. Without C9
this race has no principled resolution — which is why C9 is not separable (and why the 09-16 note
was wrong to float it as optional).

**[INFERENCE]** C3 is also the only part of this design that works when the middleware is
unreachable. A phone that has the push has the state change, whatever the server is doing.

### C4 — Reconcile on startup, always **[THOMAS]**

Every middleware start does a **full load before serving**. **No exceptions.**

**RULED 2026-09-19 (Thomas), refining what "before serving" means: serve immediately, with
enrichment honestly marked absent. Blocking is an outage.** The **list** load happens before
serving and carries every incident's **state**, which is the thing a deploy can lose — it is one
request whatever the estate size, so it costs seconds. **Type and counts trail behind it and say
so**, through C9's per-incident timestamps: a row with no `counts_confirmed_at` has not been
enriched yet and the client must not draw a count for it. See open decision 1.

**Why, stated as Thomas ruled it:** a deploy loses the webhooks that arrived during it. **[THOMAS]**
BHNM retries three times at roughly 30-second intervals and then stops. **[INFERENCE]** A container
recreate is comfortably inside that window for a single webhook and comfortably outside it for one
that arrived at the start of a slow image pull — so "the retries will cover it" is not a guarantee
anyone can hold, and the startup load is what makes the guarantee unnecessary.

**[INFERENCE]** The doctrine position is satisfied by C9 rather than by waiting: a half-built list
is honest as long as every row says which of its facts are confirmed and when. Waiting would have
traded one unverified state for a self-inflicted outage — and an outage after a deploy is the
failure this project is least able to tell apart from a broken deploy.

### C5 — Webhook mode: reconcile every 24 hours, and **count the corrections** **[THOMAS]**

Default mode. Full reconciliation **once every 24 hours**, plus on Refresh (C7).

**The reconciliation COUNTS CORRECTIONS** — every incident whose state in BHNM differs from the
cache — and the admin portal shows it **per server**:

> *Last reconciliation found N changes that webhooks did not deliver — check the BHNM action group
> and firewall.*

**Zero means webhooks are working. This number is how an admin knows whether to switch to polling
mode.**

**[INFERENCE] This is the most important thing in the document, and it is not the caching.** Every
other ruling here makes the system faster or cheaper. C5 is the only one that makes a *silent*
failure *loud*. Without it, webhook-first has exactly the property the root `CLAUDE.md` doctrine
forbids: a quiet system and a healthy system look identical, and the app renders the second while
being the first. The 09-18 handoff already recorded the lived version of this — an 11-hour silence
that was a knob position, not a network — and the conclusion there was *ask before drawing any
conclusion from a quiet period.* **C5 is that question, asked automatically, once a day.**

**[INFERENCE]** Which means the corrections count is a **number with a doctrine obligation
attached**: it must be dated, it must say when the last reconciliation ran, and *"no reconciliation
has run yet"* must not render as zero. Zero-because-checked and zero-because-never-checked are the
device icon all over again.

**Obliges:** per-server persisted state (last reconciliation time, corrections count, and ideally
which incidents were corrected), surfaced in `benem-admin`. **[MEASURED]**
`benem-admin/servers.py:29-32` discards `servers.json` keys the `Server` dataclass does not
declare — so a new key can be written by the middleware before the portal knows about it without
taking the portal down. That ordering is available and should be used.

### C6 — Polling mode: a per-server switch, OFF by default **[THOMAS]**

Redefines the existing `cache_refresh_seconds` **rather than adding beside it**. Interval **120 s
to 3600 s, default 300 s.**

**Portal copy, verbatim as ruled — do not paraphrase:**

> **Scheduled polling**
> **Off (recommended):** BeNeM learns about incident changes from BHNM webhooks the moment they
> happen. The full incident list is reconciled once every 24 hours, and whenever a user taps
> Refresh in the app.
> **On:** BeNeM additionally polls BHNM for the full incident list on a timer. Use this only when
> BHNM cannot deliver webhooks to this middleware — for example when a firewall blocks the
> connection and cannot be changed. Every poll costs BHNM API calls, and users will see incident
> changes with a delay of up to the interval.
> **Interval:** 2 minutes to 60 minutes. Default 5 minutes.

**Polling mode REQUIRES change-driven enrichment** — the list call is one request whatever the
count; detail is re-fetched **only for incidents the list shows as changed.** *That is the
surviving piece of the old note (§5.2) and it is what makes 120 s achievable on SaaS.* **[THOMAS]**

#### RULED 2026-09-19 (Thomas), after the collision below was found: **do NOT redefine `cache_refresh_seconds`**

**The ruling as written in C6 — "redefines the existing `cache_refresh_seconds` rather than adding
beside it" — is withdrawn by Thomas on the evidence below.** Redefining it would have left the Home
tiles and threshold badges stale for a day, because polling mode is off by default and no webhook
covers those two caches.

**What is built instead — two NEW per-server settings:**

| setting | type | default | range |
|---|---|---|---|
| `incident_polling` | bool | **`false`** | — |
| `incident_polling_seconds` | int | **300** | 120–3600 |

**The portal copy above applies to these two, verbatim and unchanged.**

**`cache_refresh_seconds` stays exactly as it is** — same key, same 60–900 clamp, same default of
120 — and serves **the tactical and threshold caches only.** The incident cache stops reading it.
**Rename nothing.** A rename would touch `servers.json`, both apps' config mirrors and the portal
form for no behavioural gain, and the name is only wrong from the incident cache's point of view,
which no longer reads it.

**Follow-up, noted and deliberately not now [THOMAS]:** whether the tactical and threshold caches
should slow down when no client is active. They currently refresh on a timer whether or not anyone
is looking, which is the same waste this design removes from incidents — but it is a separate
question with a separate mechanism (knowing whether a client is active at all), and it does not
block anything here.

---

**[MEASURED] — the collision that produced the ruling above.**
`cache_refresh_seconds` is **not** the incident cache's private setting. Three caches read the same
key with the same clamp:

| file | line | clamp |
|---|---|---|
| `middleware/incident_cache.py` | 225 | `max(60, min(900, …))`, default 120 |
| `middleware/tactical_cache.py` | 121 | `max(60, min(900, …))`, default 120 |
| `middleware/threshold_cache.py` | 127 | `max(60, min(900, …))`, default 120 |
| `middleware/maintenance_cache.py` | 197 | **fixed 60 s, deliberately does not inherit** |

and the admin form constrains it in the UI too: **[MEASURED]**
`benem-admin/templates/_server_form.html:43` is `min="60" max="900" step="10"` under the label
`seconds (60–900)`.

**[INFERENCE]** So "redefine rather than add beside" had a consequence the original ruling could
not have been expected to anticipate: **widening the range to 120–3600 widens it for the tactical
and threshold caches too**, which have nothing to do with webhooks and are not covered by any
webhook at all — BHNM sends no webhook when a threshold *definition* changes or a strategic group
is re-grouped. Turning scheduled polling **off** would have meant those two caches stop refreshing,
freezing the Home tiles and the threshold badges for a day. **Ruled 2026-09-19: two new settings,
`cache_refresh_seconds` untouched.** See the ruling above.

**[INFERENCE]** A second, smaller collision: the admin form's existing toggle is labelled
**Incident Cache** (`_server_form.html:32`) and maps to `cache_enabled`. Under C4 the cache is not
optional — a webhook needs somewhere to write, and a startup reconciliation writes it
unconditionally. `cache_enabled: false` and webhook-first are not compatible. **Open decision 4.**

### C7 — Manual Refresh replaces the countdown, on both platforms **[THOMAS]**

The app shows **`Updated HH:MM`** plus a **refresh control**. Tapping it calls a **new
authenticated middleware endpoint** that performs a **full reconciliation of that server**,
**rate-limited server-side to one per server per 30 s**; a tap inside the window **returns the
running one's result**. **One user's refresh serves everyone on that server.**

**[MEASURED]** What this replaces: `ios/BeNeM/Views/AutoRefreshButton.swift`, and on the PWA
`src/components/RefreshRing.tsx` and `src/components/RefreshCountdown.tsx`, used from
`src/components/AppHeader.tsx` and `src/features/tactical/TacticalGroupListScreen.tsx`. The ring
counts down client-side against an `intervalMs` prop (`RefreshRing.tsx:22-27`).

**[INFERENCE] Removing the countdown is a truthfulness fix, not a cosmetic one.** A countdown is a
promise that something will happen at zero. Under webhook mode nothing happens at zero — the next
scheduled event is 24 hours away — so the ring would be counting down to nothing, which is a green
affordance asserting an unchecked claim. `Updated HH:MM` states a fact the app can date. This is
the doctrine's *"prefer 'Registered · confirmed 2 minutes ago' to 'Registered'"* applied to the
list.

**[INFERENCE]** *"a tap inside the window returns the running one's result"* is a single-flight,
not a rejection: the second caller **waits for and receives** the first caller's answer. A 429 would
push the coalescing into two clients that would each implement it differently. Server-side
single-flight is one place, and it is also what makes *"one user's refresh serves everyone"* true
rather than approximately true.

### C8 — The app shows the mode **[THOMAS]**

Per server, in **Diagnostics** and on the **server row**: **`Webhook`** or
**`Polling every N min`**. *A user on a polling server must be able to see they are on one.*

**[INFERENCE]** This is C5's finding made visible to the person holding the phone rather than only
to the administrator. An engineer who knows they are on a 5-minute poll reads a quiet screen
differently from one who believes they are on webhooks — and under webhook-first, "quiet" is the
state that needs interpreting.

### C9 — Every incident states its age **[THOMAS]**

Per-incident last-confirmed time, **for state and for counts**, as two facts rather than one.
**Diagnostics reports the OLDEST, never the youngest.** *This is the 09-16 note's §5.4 and it is
**required, not separable**.*

**[MEASURED]** Today there is a single `last_updated` stamped once at the end of the whole cycle
(`incident_cache.py:265-269`) and reported as the age of the entire feed
(`main.py:1134-1136`) — so it is accurate for the last incident enriched and wrong for every other
one, understating the true staleness by up to a full cycle. The 09-16 note §4 measured 110.5 s of
understatement in the lab.

**[INFERENCE]** Under webhook-first the understatement gets *worse*, not better, and this is the
thing to see clearly: with a 24-hour reconciliation, a feed-level stamp refreshed by any single
webhook would report the whole list as seconds old on the strength of one incident having moved.
**One webhook would launder the freshness of every row it did not touch.** C9 is what stops that,
and it is why "required, not separable" is the right ruling rather than a strict one.

### C10 — Type is fetched once and kept **[THOMAS]**

**[THOMAS]** *A host incident is always a host incident; service and threshold are different things
that do not convert.* **Persist the type map across restarts.**

**[MEASURED]** This retires the 09-16 note's §5.1 inference — it argued immutability from the
structure of primary alarms and explicitly said the design must not require it to be true. Thomas
confirms it from the product, so it is now a premise rather than a hedge.

**[MEASURED]** The type cannot be derived from the title and must be fetched: incident 25076 is
titled `Application Service Wordpress` with `alert_type` `service`, so title parsing gets it wrong
(09-16 §3). **[MEASURED]** A fourth value, `anomaly`, exists and is not in the code's own
documentation at `ios/BeNeM/Services/NetreoAPIService.swift:932`.

**[INFERENCE]** Persisting the map makes a restart cheap in the one dimension C4 makes expensive:
the startup reconciliation still needs the *list*, but it needs *detail* only for incidents whose
type it has never seen. That is the 09-16 note's §8 option (a), and it survives because it is
independent of the sweep that did not.

### C11 — A failed enrichment is never cached **[THOMAS]**

**`UNKNOWN`, never `"host"`. Hard requirement.** *This is the 09-16 note's §5.5, unchanged.*

**[MEASURED]** Today a failed detail call writes `alert_type: "host"` in three places —
`incident_cache.py:97`, `incident_cache.py:252`, and the synthesised default in
`_enrich_incident` at `incident_cache.py:131` — and the iOS client does the same at
`NetreoAPIService.swift:951` (`incident["alert_type"] as? String ?? "host"`). **Host is the one type that is known to page.** A failed lookup
therefore renders as the strongest possible coverage claim.

**[INFERENCE]** Today this is survivable by accident, because the next cycle overwrites it within
minutes. **Under webhook-first that accident is gone**: nothing re-runs for 24 hours, so a cached
`"host"` written by a failed fetch would persist for a day, on a screen, next to a coverage marker
that reads it as a type that pages. The requirement is the same as it was in September; the cost of
ignoring it has gone up by three orders of magnitude in time.

#### RULED 2026-09-19 (Thomas): **CLIENT FIRST**, and the rule in `CLAUDE.md` is extended

**A new VALUE in an existing field is a change the shipped client must tolerate, exactly as a new
field is.** Added to the root `CLAUDE.md` beside the GAIN rule, because the GAIN rule is about
*keys* and said nothing about this.

**Ordering, ruled:**

1. iOS and the PWA render `UNKNOWN` **with its own appearance**;
2. **store release**;
3. **only then** does the middleware emit it.

**Until then the middleware keeps today's behaviour, and the defect stays documented as open.**

#### The check, run 2026-09-19 — and it came out better than the argument for it

**[MEASURED — `git show 36a0583:ios/BeNeM/Services/NetreoAPIService.swift`, plus the models and
views at that commit. Store build 2.13.1 (36).]** Both cases were checked, as the extended rule now
requires — the unknown value **and** the field absent:

| path in build 36 | field absent | value `UNKNOWN` |
|---|---|---|
| **`fetchCachedIncidents()`** (`:968`) — the middleware's `/api/v1/incidents`, which is where `UNKNOWN` would actually arrive | **never reads `alert_type` at all** — it takes only `alarm_counts` from the enriched rows | **never reads it** |
| **`fetchIncidentAlarmData()`** (`:940`, the `?? "host"` line) | returns `"host"` — **but the only caller is `fetchIncidentAlarmCounts()` (`:958-959`), which returns `.counts` and discards the type** | lowercased, discarded |
| **`IncidentDetail`** (`IncidentDetail.swift:24,116`) — `alertType: String?`, parsed with `as? String` | `nil` → `IncidentDetailView.swift:132` renders `"—"` | renders the string verbatim: the Alert Type row would read `UNKNOWN` |

**[MEASURED]** The PWA is the same shape: `alertType: string \| null` (`pwa/src/lib/api/types.ts:60`),
`coerceString(incident.alert_type)` (`lib/api/incidents.ts:237`), rendered only when truthy as a
plain row (`IncidentDetailScreen.tsx:140`).

**[MEASURED] So build 36 tolerates both, and so does the PWA.** Nothing crashes, nothing renders a
false `host`. The worst case is an Alert Type row reading the literal `UNKNOWN` — ugly, and honest.

**[INFERENCE] This corrects something I asserted before checking, and the correction matters.** I
wrote that a shipped client "would render `UNKNOWN` as `host`, reintroducing the exact defect", and
that HEAD "does exactly that". **The `?? "host"` fallback exists in both build 36 and HEAD, but its
value is discarded by its only caller — it is dead code, not a live false-healthy path.** The real
`"host"` defect lives in the *middleware* cache (`incident_cache.py:97,131,252`), whose value
reaches the clients through `/api/v1/incidents`, which build 36 does not read for this field. The
danger was real in shape and absent in fact, and the difference was one `git show` away — the same
lesson as the ack user.

**The ruling is unaffected: client first, as ordered.** What the measurement changes is the *cost*,
not the sequence. This is a cheap ordering rather than an expensive one, and the `?? "host"` line
remains a **latent trap** for whoever next wires that return value up — worth removing while the
file is open, with a comment saying why.

**The three sub-requirements stand verbatim from §5.5:** a failure is never written to cache in any
form; the incident stays on a bounded, backed-off retry list until a call succeeds; until a call
has ever succeeded the type reads `UNKNOWN` and **clients render `UNKNOWN` as its own state.**
**This is the same requirement as the S1b fix in
`2026-09-16-coverage-visibility-design.md`** — one behaviour, two notes, and they must not drift.

### C12 — Struck from the old note **[THOMAS]**

One line each, so nobody resurrects them:

| struck | why it does not come back |
|---|---|
| **The rolling sweep** (§5.3) | it exists to converge a poll-driven cache on a cursor; webhooks converge on the event, and the 24-hour reconciliation covers what they miss |
| **The load budget dial `B`** (§5.3, §6) | a dial for a sweep that no longer exists |
| **Adaptive cadence** | there is no cadence to adapt; there is a webhook, a daily reconciliation, and a manual refresh |
| **Decision 8** *(concurrency)* | nothing left to parallelise — the per-incident fetch is one call on one event |
| **Decision 12** | struck with the model it belonged to |
| **Decision 13** | struck with the model it belonged to |
| **All concurrency discussion** (§8 entire) | moot; the standing ruling is still **no concurrency**, and it now costs nothing to hold |

**[INFERENCE]** The 09-16 note's §2, §3 and §7 **measurements** are not struck and remain the only
numbers this project has: detail latency (median 0.2555 s, 20 calls), the `getincidents` field set,
the payload sizes, and the finding that `alarm_counts` is absent from the list. This design cites
them rather than repeating them.

### C13 — The lab measurement this design waits on **[THOMAS]**

> **Does BHNM send a webhook when a new alarm joins an EXISTING open incident?**

**[THOMAS]** The alarm counts matter.

| answer | consequence |
|---|---|
| **yes** | counts stay current in webhook mode. Nothing further needed |
| **no** | **counts inside an open incident can drift for up to 24 hours**, and **the row must say so** |

**[MEASURED]** Why this is not answerable from the list: `alarm_counts` is **absent from
`getincidents`** and is derived from the *detail* response (`primary_alarm_log` + `relatedalarms`,
`incident_cache.py:103-125`). An incident can gain a red alarm while every list-level field stays
byte-identical. **[MEASURED — re-checked 2026-09-19, because the 09-16 note's iOS line numbers have since
shifted]** The counts drive the severity dots on both platforms —
`ios/BeNeM/Views/IncidentListView.swift:249`, `ios/BeNeM/Views/DashboardView.swift:578`,
`pwa/src/features/dashboard/IncidentTicker.tsx:38` — so a count stale low shows a quieter incident
than the engineer actually has.

**[MEASURED]** The 09-16 note's 11-cycle run observed 130 incident/cycle-pairs with zero count
movement, and recorded itself as a **null result**: the lab was completely static, so the run never
created the conditions in which the failure would appear. **That is not evidence and must not be
cited as any.**

#### Method — written into the note as instructed, **not to be run unasked** **[THOMAS]**

Read-only on BeNeM's side; it does require provoking a second alarm in the lab, so it is **not** a
read-only lab operation and must be scheduled.

1. **Pick a target with two independently provokable alarms on one device** — a device already
   carrying an open incident is ideal, since the question is specifically about *joining an
   existing* incident. Record the incident id and its current `alarm_counts`, read through
   `getincidentdetail`, with the timestamp.
2. **Record the webhook log position before provoking anything.** `grep -c "Queued delivery"` on
   the day's log is enough; the point is a before-mark that is not a count of something else.
3. **Provoke the second alarm** on that same device such that BHNM attaches it to the existing
   incident rather than opening a new one. **Confirm which happened by incident id**, not by a
   count — root `CLAUDE.md`: *search for the object, never trust the count.* If a **new** incident
   id appears, the experiment has not tested the question and must be redone; that outcome is
   itself worth recording, because "BHNM opens a new incident instead" is a third answer the binary
   above does not contain.
4. **Watch the middleware log for a webhook naming that incident id.** Wait at least one BHNM
   notification interval past the alarm's own detection, and say in the record how long was waited
   — *"no webhook in N minutes"* is a measurement; *"no webhook"* is not.
5. **Re-read `getincidentdetail`** and confirm the counts actually moved upstream. **If they did
   not, the experiment proves nothing about webhooks** — it proves the alarm did not join. This
   step is the one that keeps a negative result honest, and it is the *"an empty result must first
   be shown capable of returning a non-empty one"* rule applied to a lab procedure.
6. **Tear down**, and confirm teardown **by searching for the object by name**, not by the Actions
   counter — which has been wrong twice (root `CLAUDE.md`).

**If the answer is no**, the row must say so, and **[INFERENCE]** C9's second timestamp — the
last-confirmed time *for counts*, separate from the one for state — is already the mechanism for
saying it. That is a further reason C9 is not separable: it is the fallback for C13's bad outcome,
and it has to exist before the answer is known.

### C14 — Payload discipline applies to everything the app decodes **[THOMAS]**

Fields may only be **GAINED** until the client that tolerates their loss is in the field.

**[MEASURED]** The root `CLAUDE.md` rule, with its procedure: add the field, deploy the middleware,
ship the client, and only then remove anything — and **check the shipped code, not HEAD**
(`git show <release-commit>:path`). Swift's synthesised `Decodable` treats a non-optional property
as required and fails the **whole** decode on a missing key.

**[INFERENCE] This design is unusually exposed to it**, because it changes three decoded surfaces
at once: the push payload (C3), the `/api/v1/incidents` row shape (C9's per-incident timestamps,
C10's type, C11's `UNKNOWN`), and the new refresh endpoint's response (C7). **All of the additions
are additive and therefore safe.** The hazards are two specific non-additive changes hiding inside
C2 and C11:

- **C2's `RECOVERY` bucket move** changes which array an incident appears in. A shipped client that
  reads the active list and assumes an incident it knows about is still there is not losing a
  *field*, but it is seeing a record vanish. **[INFERENCE]** That is within what the existing
  clients already tolerate — incidents leave the list today when they close — but it is the one
  C2 behaviour worth checking against the shipped decoder rather than assuming.
- **C11's `UNKNOWN`** is a *new value in an existing field*, which the GAIN rule did not cover.
  **RULED 2026-09-19: the rule is extended to cover it** — a new value is a change the shipped
  client must be shown to tolerate, checked in **two** cases, the unknown value and the field
  absent. **Checked: build 36 and the PWA tolerate both** (see C11). **Ordering ruled regardless:
  clients first, store release, then the middleware emits it.**

---

## 2. What this design does NOT do

- **It does not touch the ack-override machinery's purpose**, only its standing: `_state_overrides`,
  `_pending_overrides` and the 2.15.2 pending-on-first-sighting fix stay. Under C1 they stop being
  a patch awaiting a poll and become the authoritative write. Whether the 300 s TTL survives is
  **open decision 3**.
- **It does not propose concurrency.** C12 strikes the discussion; the standing ruling is no
  concurrency, and the per-incident fetch gives it nothing to do.
- **It does not change the maintenance cache**, which is a fixed 60 s and deliberately does not
  inherit `cache_refresh_seconds` (`maintenance_cache.py:197`). Nothing here touches it.
- **It does not resolve coverage visibility.** That is
  `2026-09-16-coverage-visibility-design.md`, settled separately on 2026-09-19. The two meet at one
  point and it is recorded in both: **an incident whose alarm class is not attached to the action
  group produces no webhook and can be stale for up to 24 hours**, and the never-paged marker is
  exactly that row — so the marker doubles as the staleness warning.
- **It does not depend on the engine-down note.** That is deferred to measurement
  (`2026-09-16-engine-down-stale-data-design.md`), and this design deliberately takes nothing from
  it. **[INFERENCE]** Worth stating because they look related and are not: a dead Service Engine
  produces *no* webhooks and *no* incidents, which webhook-first cannot distinguish from a quiet
  network — and the thing that would distinguish it is C5's corrections count plus the engine-down
  note's own `lastUpdateTime` work. Neither design needs to wait for the other, but a reader
  should know the seam is there.
- **It does not restate the 09-16 measurements.** They are cited from the superseded note, which is
  kept for exactly that reason.

---

## 3. Open decisions — ALL RULED. **THE DESIGN IS APPROVED 2026-09-19 (Thomas).**

**Approved 2026-09-19.** Build order accepted at 13 steps, with the cut line after step 5.
**WAVE 1 = steps 1–4, then STOP.** Step 5 (the store release) is Thomas's go, not the builder's.

All five original decisions are ruled; nothing in this design is open.

- ~~**1. `cache_refresh_seconds` is shared by three caches.**~~ **RULED — do not redefine it.**
  Two new per-server settings, `incident_polling` (bool, default `false`) and
  `incident_polling_seconds` (120–3600, default 300). `cache_refresh_seconds` stays as-is for the
  tactical and threshold caches. Rename nothing. Follow-up noted, not now: whether those two
  caches should slow down when no client is active. See C6.
- ~~**5. Can C11's middleware half ship before the client half?**~~ **RULED — no, client first**,
  and the root `CLAUDE.md` payload rule is extended to cover a new *value* in an existing field.
  **[THOMAS] Keep it client-first even though the check came back cheap** — build 36 and the PWA
  tolerate both the unknown value and the absent field — **because this is the first case decided
  under the extended rule, and the rule is worth more than the shortcut.** See C11.

### 1. C4's startup reconciliation — RULED: serve immediately

**[THOMAS] Serve immediately, with enrichment honestly marked absent. Blocking is an outage.**

*The list call gives every incident's **state** in seconds; **type and counts trail, and say so**.*

**[INFERENCE]** This is the ruling that makes C4 cheap, and it works because the two halves of an
incident have very different costs: `getincidents` is **one** request whatever the estate size
(09-16 note §7 — 1930 bytes at n = 9, ~204 KB projected at n = 1000), while enrichment is one
request **per incident**. So the state of the whole estate is available almost at once and the
counts are not. C9 is what lets the second half arrive late without lying about it: a row whose
`counts_confirmed_at` is absent has not been enriched yet, and the client says so rather than
drawing an unconfirmed count.

**This changes the wording of C4, not its intent.** "Full list-and-detail load **before serving**"
becomes **"full list load before serving, detail load behind it, and never a count the app has not
confirmed."** The guarantee C4 exists for — a deploy does not silently lose the webhooks that
arrived during it — is delivered by the **list** load, which is the part that carries state.

### 2. `STATE_OVERRIDE_TTL` — RULED: cleared by a successful fetch, not by a clock

**[THOMAS]**

- **A successful C2 fetch clears the override.** That is the normal path and the only one that
  should ever run.
- **A failed fetch leaves the override in place and retries.** The override is the only thing
  holding the truth until the fetch succeeds; dropping it on failure would revert the row to a
  state that may be a day old.
- **A 10-minute safety cap exists only so nothing leaks forever.**
- **If the cap ever fires in normal operation, that is a defect — log it loudly.** It is not a
  path to rely on and not a fallback to design against.

**[INFERENCE]** The cap's log line is the whole point of the cap, and it must name what it is
admitting: *an override survived 10 minutes without a successful fetch*, with the incident id and
the number of fetch attempts. A cap that expires silently would be the 300-second TTL again — a
clock quietly overwriting the truth — which is exactly what this ruling removes. The cap is
instrumentation with a safety function, not a timeout with a log line.

### 3. `cache_enabled` — RULED: keep the key, narrow the meaning, relabel

**[THOMAS] Keep the key. It now means "BeNeM monitors this server at all". Relabel it. Do the
relabel in the same wave as C6.**

**Proposed label and help text, for approval when C6 is built:**

> **Monitor this server**
> *Off: BeNeM still proxies app requests to this server, but fetches nothing in the background —
> incidents, Home tiles, thresholds and maintenance stay empty for it. Push notifications are
> unaffected.*

**[MEASURED]** The help text is accurate to what the flag actually gates: `server_cache_enabled()`
is read by the incident, tactical, threshold and maintenance crawlers. **Push is genuinely
unaffected** — the webhook fan-out selects devices by accepted secret and the `device_tokens`
table, and never consults `cache_enabled`. **[INFERENCE]** Saying so in the help text matters more
than it looks: the current label, **Incident Cache**, reads like a performance option, and an
administrator turning off a performance option to reduce load on their BHNM has no reason to
suspect they might stop being paged. They would not — but the label does not tell them that
either way.

---

## 4. Build order

**Thirteen steps, not the eleven in the first draft.** It grew by two because **C11 split around an
App Store release** (client first, ruled 2026-09-19) and because the detail-screen copy fix joined
it. Not a schedule; an ordering, with the reason each step precedes the next.
**Nothing starts until a build is ordered.**

| # | step | why here |
|---|---|---|
| 1 | **C9 — per-incident timestamps for state and counts; Diagnostics reports the oldest** | everything downstream races or lies without it: C3's payload-vs-list conflict, C13's bad-answer fallback and C5's dated count all resolve through it. Pure truthfulness fix, improves today's code on its own |
| 2 | **C10 — persisted type map** | cheap, middleware-only, and it is what makes step 7's startup load affordable |
| 3 | **09-15 Part 2 — `GET /api/v1/incidents/{incident_id}`, 404 ≠ 502** | decided 2026-09-15, unbuilt. Steps 4, 9 and 12 all need it, and it must exist before the clients can render an honest failure |
| 4 | **CLIENT WAVE, both platforms — `UNKNOWN` rendered with its own appearance (C11 client half), and the incident-detail states: `Fetching incident data…` → bounded wait → `could not load this incident`** | **batched deliberately into one release.** Kills `IncidentDetailScreen.tsx:105`'s banned `Incident not found.`, banned since 2026-09-15 and still rendered. Also removes the dead `?? "host"` at `NetreoAPIService.swift:951` with a comment saying why |
| 5 | **iOS STORE RELEASE carrying step 4** | **a gate, not code.** C11's middleware half may not ship until this is in the field — ruled 2026-09-19, and "in the field" means other people's phones |
| 6 | **C11 middleware half — a failed enrichment is never cached; `UNKNOWN`, never `"host"`; bounded backed-off retry** | the one item whose absence makes webhook-first *worse* than today, because the 24-hour reconciliation removes the accidental overwrite that currently limits the damage. Also delivers the coverage note's S1b fix |
| 7 | **C4 — startup reconciliation before serving** | needs C10 to be cheap and C11 to be honest. Repairs every deploy from the moment it lands. Open decision 1 governs whether it blocks |
| 8 | **C2 — per-incident fetch on every webhook, all types, with the `RECOVERY` bucket move — and the fetch-at-webhook-time log line** | the core. The log line ships **with** it, never after: it is the measurement Thomas ordered and it cannot be retrofitted to a webhook that already happened |
| 9 | **C5 — 24-hour reconciliation, corrections count, per-server admin display** | must not lag C2 by long. Between C2 and C5 a webhook that never arrives is invisible again — the pre-existing condition, but now *relied upon* |
| 10 | **C6 — `incident_polling` + `incident_polling_seconds`, portal copy verbatim, change-driven enrichment** | after C5, because C5's corrections count is what tells an admin to turn it on. `cache_refresh_seconds` is not touched |
| 11 | **C3 — push payload gains state fields; both clients apply them to the list without a fetch** | additive and safe under C14; `shared/push-payload-spec.md` updated first |
| 12 | **C7 — manual Refresh endpoint with 30 s server-side single-flight; countdown removed on both clients** | needs step 3's route and step 9's reconciliation to have something to call |
| 13 | **C8 — mode shown per server in Diagnostics and on the server row** | needs C6 to have a mode to show |
| — | **C13's lab measurement** | **scheduled separately by Thomas, not run unasked.** Its answer changes only whether the row must state count staleness — which C9 already makes possible, so it blocks nothing |

**[INFERENCE] Steps 1–4 are worth doing even if everything after them were abandoned.** Each is a
truthfulness fix to code that ships today, none depends on webhook-first, and all of them get
*harder* to retrofit once the cache is event-driven. If this design is ever cut short, cut it after
step 5 and not before.

**`shared/feature-spec.md` is updated before or alongside each client-visible step** (4, 11, 12,
13), per the root `CLAUDE.md` parity rule. **`middleware/CHANGELOG.md` and the version bump are
part of each deploy, not a follow-up** — every deploy bumps the version of what it deploys, and the
pre-deploy check reads the running version **before** tagging the rollback image.

---

**STOP AT DESIGN.** Nothing in this document is built, deployed, configured or measured until
Thomas orders it. Open decisions 1, 2 and 3 above are the first things to ask for when he does.
