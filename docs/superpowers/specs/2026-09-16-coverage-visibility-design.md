# Design: what BeNeM can know about its own coverage, and what to say when it cannot

**Status:** **SETTLED 2026-09-19 — all three decisions ruled by Thomas. STOP AT DESIGN still
applies: nothing is built from this note until a build is ordered.**
**Date:** 2026-09-16. **Ruled 2026-09-19.**
**Evidence:** `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` §8.8
**Queue:** item 11, highest priority in the project.

---

## RULED 2026-09-19 (Thomas) — read this before the body

The body below was written while decision 1 was open. **It is no longer open, and the branch it
decides is settled.** Where the body hedges between "if the API exposes coverage" and "if it does
not", **the second branch is the live one.** Nothing in the body is deleted, so the reasoning that
produced these rulings stays readable — but the "if option 2 succeeds" passages are now
counterfactual and must not be built from.

**Decision 1 — STRUCK. The BHNM API does NOT expose action-group assignment. [THOMAS]**
Confirmed by Thomas from the product. **The probe is cancelled — do not run it, do not re-propose
it, do not re-derive it from the API reference.** This had been the single next action in three
consecutive handoffs (2026-09-17, 2026-09-18, 2026-09-19); it is now closed by the product owner's
knowledge of the product rather than by measurement, and that is a legitimate close. The design
takes the **"cannot know"** branch, permanently.

**Decision 2 — APPROVED as product copy.** The onboarding sentence ships as written:

> *"BeNeM pages you for devices your BHNM administrator has wired to the BeNeM action. It cannot
> tell you which — ask them."*

**Decision 3 — RULED: incident-list per-row marker FIRST, Diagnostics second.** Surface 2 before
surface 3, not instead of it. The marker states **observed history only** — *"no incident of this
type has ever paged this app"* — and **never a prediction**. The prohibitions in *"What not to
do"* below stand unchanged: no coverage percentage, and never a claim that a type *will not* page.

**`INSTALL.md` §7 — APPROVED and independent.** It does not wait for the client work and does not
depend on it. Written **in the imperative**: *attach the action group to everything you expect to
be paged about; an unattached check will never page anyone, and nothing in the app will say so.*

**The S1b "host" fallback defect is fixed as part of this work, not filed separately.** A failed
`alert_type` lookup yields **`UNKNOWN`, with its own rendering** — never `"host"`, never any other
type. This is the same requirement as C11 of
`2026-09-19-incident-freshness-webhook-first-design.md`; the two must not drift apart.

### New consequence, from the webhook-first ruling

`2026-09-19-incident-freshness-webhook-first-design.md` makes webhooks authoritative and reduces
scheduled reconciliation to **once every 24 hours** in the default mode. So **an incident whose
alarm class is not attached to the action group produces no webhook, and can therefore be stale
for up to 24 hours** — its state in the app is whatever the last reconciliation saw.

**That row is exactly the row the never-paged marker marks.** The marker therefore does double
duty: it is a coverage statement *and* a staleness warning, and the two are the same fact seen from
two ends. A type that has never paged this app is a type whose incidents this app learns about only
on the daily sweep. **Say this in the copy's supporting text** — the row-level glyph stays short,
but the incident-detail line and the Diagnostics text must make the staleness consequence explicit,
because "we might not page you for this" and "what you are reading here may be a day old" are
different alarms to an engineer and both are true.

---

## The finding, in one paragraph

**The action group covers host-down only, while the incident list displays service checks,
thresholds and anomalies too — with nothing marking which entries would ever reach a phone.**
Measured 2026-09-15/16 from the deployment's own logs: every incident that has ever produced a
webhook is a host event (`29499`, `29517`, `29570`, `29586`), while the list the app was showing
at that moment held **18 active incidents, of which 16 were of types that have never caused a
phone to ring** — 4 service, 2 threshold, 10 anomaly. Those sixteen rows render identically to
the one that would. A service check failing since May sits in the same list, in the same style,
as the host outage that woke three people ninety seconds earlier.

**And the sharpest case is a host-down incident that did not page** — incident 29585
(`BHNM-B-SE01`), repeated under control on 2026-09-16 as incident 29628. It was briefly withdrawn
from this finding on the explanation that "a crashed Service Engine cannot notify anyone of its
own crash". **That explanation was wrong** — the main BHNM appliance sends the webhooks, not the
Service Engine, so the sender was healthy and could have paged. It is the **second** collapsed
explanation for this same incident, and it came from a reviewer ruling accepted without
measurement. See §8.8 and §8.13, and treat the next tidy explanation for it sceptically.

**The two-hop diagnostics do not cover it.** They verify the middleware reaching BHNM's *front
end*, which answers perfectly while the engine behind it is dead. The engine case is queue item 13
(`2026-09-16-engine-down-stale-data-design.md`) — a different gap: item 11 is incidents that will
never page, item 13 is device state that has silently stopped being true. **The missing page for
the engine belongs to item 11**, and it is this document's strongest case.

## Why this is not the doctrine case, and must not be filed as one

The repository already carries "never render unverified state as healthy", with three instances:
a device icon drawn green for a host BHNM reported DOWN, a "Registered and active" label read
from a local flag, and a push toggle reading ON while nothing was delivered.

**All three share a shape this one does not have: an affordance making a false claim.** Each was
a thing on a screen asserting health, and each fix is the same in kind — make the claim honest,
date it, give the unverified case its own appearance.

This one's failure is a phone that does not ring. *Absence of a page* and *absence of an incident*
are the same observation, and both are what a healthy night looks like. There is nothing displayed
to be suspicious of, nothing stale to mark, nothing to timestamp. A user cannot doubt a
notification they never received.

The incident list is the closest thing to an affordance here, and **its defect runs the opposite
way**: it shows *more* than it will ever tell you about, so it reassures rather than alarms. No
badge, timestamp or freshness state reaches that — a perfectly fresh, perfectly verified list of
eighteen incidents is exactly what a user sees today, and it is still misleading.

So the doctrine's practical form — "prefer *Registered · confirmed 2 minutes ago* to
*Registered*" — has no purchase here. There is no label to improve. **The product has to
manufacture the affordance that does not exist**, which is a design problem rather than a
correction.

For a paging product this is the most expensive failure available: its entire value is the
difference between *nothing is wrong* and *I was never going to hear about it*, and BeNeM
currently cannot express that difference anywhere.

## What BeNeM can actually know

Ordered by cost, and honest about each one's ceiling. **None of these is implemented.**

### 1. Which *incident types* have ever paged (free, already in hand, and now the strongest lead)

The measurement above came entirely from the middleware's own log, and the middleware already
receives everything it needs: each webhook carries the incident and the host. It could keep, per
server, **which incident types and which hosts have ever produced a page**.

- **Answers the sharp question directly:** the incident list can mark rows whose *type* has never
  paged. With host-only coverage that is 16 of 18 rows — a large, immediately useful signal that
  needs no BHNM API at all.
- **Ceiling:** "never paged yet" is not "will never page". A type that has not yet occurred is
  indistinguishable from one that is not wired up, so this is sound as a *warning* and unsound as
  a guarantee. Phrase it as observed history — *"no incident of this type has ever paged this
  app"* — never as *"this will not page you"*.
- Per-host coverage has the same ceiling and a weaker signal, since most hosts never alarm.

### 1b. DEFECT that must be fixed before option 1 ships — the `"host"` fallback

**[MEASURED 2026-09-16, evidence §8.16]** When the `getincidentdetail` call fails, three paths
substitute the literal `host` as the alert type: `middleware/incident_cache.py:97`, `:252`, and
`ios/BeNeM/Services/NetreoAPIService.swift:940`.

`host` is **the one type measured to page**. Option 1 above marks rows by whether their type has
ever paged — so under option 1 a failed lookup does not degrade to "unknown", it degrades to
**"this type pages you"**, the strongest coverage claim the product can make, asserted from a
request that did not return.

Today the damage is bounded by accident: the cache re-enriches every incident every cycle, so a
wrong value survives a minute or two. That accident disappears in any design that stops
re-enriching unconditionally (see `2026-09-16-incident-cache-cost-model-design.md` §5.5).

**Requirement: a failed lookup yields `UNKNOWN`, never a type, and `UNKNOWN` gets its own
rendering.** This is the root `CLAUDE.md` doctrine applied to coverage rather than to health.

**Also:** `NetreoAPIService.swift:921` documents the value set as "`Host`, `Service`, `Threshold`".
**`anomaly` is a fourth, real value** — 3 of 13 incidents in the lab on 2026-09-16.

### 1c. CORRECTION 2026-09-16 — coverage is configuration, and that changes what option 1 is worth

**[MEASURED, evidence §8.15]** Incidents 29657, 29658, 29659 (`Anomaly Bandwidth`, `U6-Pro-EG` and
`UAP-AC-LR`) opened at 20:10Z and produced **no webhook** — searched in a log proven to be writing
across the window. The only webhooks that hour were `raspi-050` incident 29656, a host event.

**[THOMAS, confirmed in the product 2026-09-16]** **BHNM thresholds, anomalies included, CAN call
webhooks.** Those three fired nothing because **the BeNeM Action Group was not attached to that
alarm**. **Anomaly is therefore NOT on the never-paged list and must not be counted there** — an
earlier draft of this section did exactly that and was wrong.

**The measured tally is now a statement about this lab's configuration, not about BHNM:**

| | |
|---|---|
| types observed to page **in this lab, as configured** | host |
| types not observed to page **in this lab, as configured** | service, threshold, application, anomaly |
| types BHNM is **capable** of paging on | **unknown to BeNeM — and that is the point** |

### What this does to the options above

**Option 1 (mark rows whose type has never paged) is weakened.** Its ceiling was already "never
paged yet ≠ will never page". The correction makes that ceiling the *normal* case rather than an
edge: a type that has never paged usually means *nobody attached the action group*, which can be
fixed in thirty seconds by an operator — so presenting it as a property of the incident type
misleads in a new way. It is still usable as history, but it describes the deployment's wiring, not
the product's behaviour, and the copy must say so.

**Option 2 (read action-group assignment from the BHNM API) is now the feature, not a nice-to-have.**
If coverage is per-object configuration then:

1. **It varies per customer and per object.** No static table BeNeM ships can be right for two
   deployments.
2. **An operator can silently be wrong about what pages them.** Three anomaly incidents on two
   devices, no phone moved, and nothing in either product said so.
3. **It is readable data.** Configuration lives in BHNM and is in principle queryable — a
   capability limit would have to be memorised, a configuration can be *read*, per object, and
   reported as fact with a date on it. That is the difference between BeNeM guessing from history
   and BeNeM stating coverage.

**Consequence for decision 1 below: its value goes up, not down.** The read-only probe is no longer
deciding whether to gild a history-based heuristic; it is deciding whether the honest version of
this feature exists at all.

### 2. What BHNM will admit about the Action (unmeasured, and the pivotal unknown)

BHNM knows exactly which devices or groups the action group is attached to and under what
criteria. The open question is whether the **API** exposes it — the UI certainly does, and
`shared/BHNM_API_REFERENCE.md` does not currently document an endpoint for action-group
membership.

- **If it does:** the whole problem collapses into a solved one. BeNeM fetches the covered set,
  compares it with the device list, and can state plainly: *"37 of 41 devices will page you.
  4 will not: …"* That is the answer, and everything else in this document is a fallback.
- **If it does not:** the product cannot know its coverage, and the design must be about saying
  so — see "What to say when it cannot know".
- **This is the one measurement that decides the shape of the fix.** It should be done before
  anything is built, and it is read-only: find whether any documented endpoint returns action
  assignment. §8.10 records that the Action *configuration* could not be read through the browser
  extension; that is a UI limitation, not an API answer.

### 3. What a synthetic test proves (expensive, narrow, but conclusive per device)

Trigger a real notification path for one device and observe whether a webhook arrives — the
end-to-end equivalent of the "test push" already proposed for registration state.

- **Answers, conclusively, for exactly one device at one moment.**
- **Ceiling:** it needs a way to provoke a BHNM notification without creating a real incident,
  which may not exist; it does not scale to an estate; and it goes stale the moment an
  administrator edits the Action.

### 4. Nothing else

Worth stating so it is not re-proposed: device count, incident history volume, and cache health
say nothing about coverage. A server can be perfectly healthy, fully cached, every device green,
and page nobody.

## What to say when it cannot know

This is the part that matters, because option 2 may come back negative and option 1's ceiling is
already known.

**The rule: an unknown coverage set must be visible as unknown, once, where it changes
behaviour — not as a permanent banner nobody reads.**

Candidate surfaces, in preference order:

1. **At onboarding, in the QR/connection flow.** The moment a user adds a server is the moment
   they form the belief "this app will page me". One sentence there is worth ten later:
   *"BeNeM pages you for devices your BHNM administrator has wired to the BeNeM action. It
   cannot tell you which — ask them."* If option 2 succeeds, this becomes the real list instead.
2. **On the incident list, per row, by type — the highest-value surface.** This is where the
   misleading reassurance is manufactured, so it is where the correction belongs. A row whose
   incident type has never produced a page is marked as such; the host row is not. With today's
   host-only coverage that marks 16 of 18 rows, and the screen stops implying that eighteen
   things are being watched on the user's behalf. Copy must state observed history, never a
   prediction: *"no incident of this type has ever paged this app"*.
3. **In Diagnostics, as a dated fact.** *"Only host incidents have ever paged this app. 16 of the
   18 incidents currently listed are of types that never have."* Dated, and phrased as history
   rather than as a coverage guarantee.

**What not to do**, each for a reason:

- Do not show a coverage percentage derived from option 1. It would be read as *"89% covered"*
  when it means *"89% of types have happened to page at some point"*. A wrong number is worse
  than an admitted unknown, and this project has already shipped that mistake three times.
- Do not state that a type *will not* page. Everything option 1 knows is history; a type that has
  not paged yet and a type that never will are indistinguishable from the middleware's side.
- Do not put a permanent warning banner in the alert path. It trains people to dismiss the one
  place that must stay trustworthy.
- Do not block onboarding on it.

## Where it goes, per surface

The finding is produced on the incident list, so the incident list is the primary fix. But all
three surfaces make coverage claims by omission, and each needs its own treatment.

### iOS (`ios/`) — the lead platform

- **Incident list row.** A row whose incident type has never produced a page carries a small,
  non-alarming marker. Not red, not a warning triangle: this is not an error, it is a fact about
  reachability. A muted "bell with a slash" glyph in the row's trailing metadata, with the
  accessibility label carrying the full sentence.
- **Incident detail.** One line, below the state: *"No incident of this type has ever paged this
  app."* Detail is where a woken engineer decides whether to trust the screen, so the sentence
  goes in full rather than as a glyph.
- **Deliberately not** on the tactical or device screens. Those aggregate, and a marker there
  would be read as a device health claim.

### PWA (`pwa/`) — parity, and it is cheap here

Same two placements — `IncidentRow.tsx` and `IncidentDetailScreen.tsx`. The PWA is the surface
where this lands first in practice, because `IncidentDetailScreen` is already being reworked for
the incident-freshness four states; the marker is one more piece of row metadata rather than a new
screen. **Feature-parity rule applies** (`shared/feature-spec.md` must be updated before or
alongside), and this is *not* platform-specific.

### Admin portal (`middleware/benem-admin/`) — the only place it can be fixed rather than described

The clients can only describe the gap; the administrator is the one who can close it. The Push
Config page should state, per server, **which incident types have ever produced a webhook** —
built from the same data as option 1, and phrased as history:

> `Thomas' Lab Server` — pages received for: **host**. Never received: service, threshold,
> anomaly. *(Since 2026-09-14. This reflects what has arrived, not what your BHNM action group is
> configured to send.)*

That single line is what turns "my engineers are not being paged for service checks" from a
discovery made during an outage into something an administrator can notice on a Tuesday. It pairs
naturally with queue item 7, the device overview, and should ship with it.

## INSTALL.md §7 — the consequence, which is sharper than expected

§7.1 already describes the action group as *"in turn attached to your host **and service
checks**"*. **The lab's actual configuration does not match its own install guide**: only host
events have ever produced a webhook. So the documentation is not merely silent — it describes a
configuration the reference deployment does not have, which is the worst case, because a reader
checking the doc concludes they are covered.

Required changes:

1. **§7.1, in the imperative and with the failure named:** attach the action group to everything
   you expect to be paged about — host checks, service checks and thresholds. *A check that is not
   attached will never page anyone, and nothing in the app will tell you.*
2. **§7.4 ("Verify it actually delivers")** currently verifies that *a* notification arrives. It
   should say that verifying one host-down notification proves the transport, not the coverage,
   and that each *type* has to be verified separately.
3. **§7.3's table is now partly aspirational** — see below.

## The middleware's CRITICAL/WARNING handling is dead code, and correct

`main.py:621` routes `PROBLEM`, `CRITICAL` and `WARNING` through one branch, and INSTALL §7.3
documents all three as handled. **Under this deployment's configuration, `CRITICAL` and `WARNING`
have never arrived** — every webhook in the persisted log is `PROBLEM`, `RECOVERY` or
`ACKNOWLEDGEMENT`.

Stated plainly so nobody "cleans it up": **the code is dead here and correct everywhere.** BHNM
documents all seven `{NOTIFICATIONTYPE}` values, another estate with service checks attached will
send `CRITICAL` and `WARNING`, and the branch handles them the way it should. It is dead because
of a *configuration*, not because the values are obsolete — and the configuration is exactly what
this design is about changing. Deleting the branch would turn a coverage gap into a missing
feature the day somebody fixes their action group.

It is worth one line in the changelog notes rather than a code change: *handled, never yet
observed on the reference deployment.*

## The stop-gap, which is not the fix

`INSTALL.md` §7 does not tell an administrator to attach the action group to everything they
expect to be paged about. It should, in the imperative, with the failure named: *a device not
attached to the BeNeM action will never page anyone, and nothing in the app will say so.*

That is documentation for the person configuring BHNM. It does nothing for the engineer holding
the phone, which is why it is a stop-gap and why this item is not closed by writing it.

## Sequencing

1. **Measure option 2 first** — does the BHNM API expose action-group assignment? Read-only,
   and it decides everything below it.
2. **Fix `INSTALL.md` §7** regardless of the answer. Cheap, immediate, independent.
3. **If option 2 succeeds:** build the real coverage list; surfaces 2 and 3 show facts rather
   than admissions, and surface 1 becomes redundant.
4. **If option 2 fails:** build option 1's "has ever paged" set, and the *unknown* framing.
   **Ship surface 2 first** — the incident list is where the false reassurance is actually
   produced, and it is the one surface that needs no BHNM API and no new data source beyond what
   the middleware already logs.

## Decisions needed — ALL RULED 2026-09-19

1. ~~Approve the option-2 measurement (read-only, BHNM API only, no lab change)?~~
   **STRUCK 2026-09-19 (Thomas). The BHNM API does not expose action-group assignment [THOMAS].**
   No probe. The "cannot know" branch is the design.
2. ~~Is the onboarding sentence acceptable product copy?~~ **APPROVED 2026-09-19 (Thomas)**, as
   written in surface 1.
3. ~~Surface 2 or surface 3 first?~~ **RULED 2026-09-19 (Thomas): surface 2 — the incident-list
   per-row marker — FIRST, Diagnostics second.** Observed history only, never a prediction.

**Also ruled:** `INSTALL.md` §7 is approved and independent (imperative, failure named), and the
S1b `"host"` fallback becomes `UNKNOWN` with its own rendering as part of this work.

**Sequencing above is superseded by these rulings:** step 1 (the probe) is struck; step 2
(`INSTALL.md` §7) stands and is independent; step 3 (the "if option 2 succeeds" branch) is
counterfactual and must not be built; step 4 is the live plan, with **surface 2 first** as decision
3 rules.

**STOP AT DESIGN.** The decisions are closed; the build is not ordered.
