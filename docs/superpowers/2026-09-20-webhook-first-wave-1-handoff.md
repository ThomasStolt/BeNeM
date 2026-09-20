# Webhook-first Wave 1 — session handoff

**Date:** 2026-09-20, written 09:05Z. **Wave 1 is closed. iOS 2.13.6 (53) is with Apple.**

**Earlier state lives in the two 09-19 handoffs and is not repeated here:**
`docs/superpowers/2026-09-19-phase-1-batch-handoff.md` (Phase 1, the ack-user break and repair, the
APNs environment defect, the ACK alarm-colour finding) and
`docs/superpowers/2026-09-18-security-hardening-and-diagnostics-handoff.md` (security hardening,
the connection probe, withdrawn claims 1–18). **Read the 09-19 one first** if you have no memory of
this work.

**Every state claim below was observed at 09:03Z, not recalled.**

---

## (a) What landed since the 09-19 handoff

**The Phase 2 decision sitting, then Wave 1.** Thomas ruled ~15 open decisions across four design
notes; the coverage note is settled on the "cannot know" branch, the push relay is **parked
permanently**, the engine-down note is **deferred to two lab experiments**, and the 09-16 incident
cache cost model is **superseded**.

**The new design:** `docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md`
— C1–C14, **approved**, 13-step build order, cut line after step 5. Its premise is the inversion:
**webhooks are authoritative for incident state and the poll is a repair mechanism**, where every
previous design had it the other way round (`main.py:732-733` still says so in its own comment).

| build | what changes in behaviour |
|---|---|
| **middleware 2.19.0** | **C9** — every incident carries `state_confirmed_at` and `counts_confirmed_at`; diagnostics reports the **oldest** enrichment, never the newest, plus `list_age_seconds` and `unconfirmed_counts`. **C10** — `alert_type` learned once from a confirmed call and persisted in a new `incident_types` table. **`GET /api/v1/incidents/{id}`** with **404 and 502 kept distinct**, the route designed 2026-09-15 and never built |
| **middleware 2.19.1** | **An acknowledged incident's alarms render BLUE**, matching BHNM, driven by the incident-level flag. The dead per-alarm `ACKNOWLEDGED` branch is **deleted** — it mapped a value alarms never carry, so blue had never once been displayed |
| **PWA 0.18.0** | The incident detail screen gets **three states** — *Fetching incident data…* / *no longer exists* / *could not load* — and **"Incident not found" is gone from the shipped bundle** (banned 2026-09-15, still rendering until now). An unverified alert type renders as **Unverified** |
| **PWA 0.18.1** | **"Active" means NOT CLOSED** — the Home tile stopped dropping an incident from its count the moment somebody acknowledged it |
| **iOS 2.13.3–2.13.6** | API Configuration card removed with its three keys; one save, one success signal; ack user restored to the QR Username; **`UNKNOWN` alert type rendered as Unverified** and the dead `?? "host"` deleted; **the notification deep link** (see below); the unreachable card gained the OS reason as a second line; **"Active" means NOT CLOSED** on the tile *and* the list filter |
| **iOS 2.13.6 (53)** | Archived, IPA verified, **uploaded 08:54:44Z and submitted for review by Thomas** |

**Three defects found on a phone and fixed:**

- **Acking from the app made the incident disappear.** `IncidentStatus` has `.active` and
  `.acknowledged` as separate cases, so the Home tile's `filterByStatus(.active)` excluded every
  incident the user acted on. The ack itself was innocent — it patches the row in place. Fixed with
  **one predicate used by both the tile count and the list filter**, so they agree by construction
  rather than by two authors happening to write the same condition.
- **An acknowledged incident's alarm stayed red.** Separate from C2, and C2 would not have fixed
  it — see 2.19.1 above.
- **The deep link did nothing.** `IncidentListView` printed to the console and left the user on the
  list when a tapped notification named an incident not in it. Now: exact match → **unambiguous**
  suffix match → fetch, with the three states. The 09-15 rule that *more than one suffix candidate
  means no match* is implemented at last.

---

## (b) Deployed state — observed 2026-09-20T09:03Z

```
### /health (unauthenticated)
{"status":"running","version":"2.19.1"}

### PWA
bundle: /assets/index-BrqNwJ7v.js
"0.18.1"

### containers
benem-middleware StartedAt=2026-09-19T21:33:30.445Z Restarts=0
benem-pwa        StartedAt=2026-09-19T22:02:47.298Z Restarts=0
benem-admin      StartedAt=2026-09-18T10:40:39.233Z Restarts=0
benem-proxy      StartedAt=2026-09-14T15:36:58.253Z Restarts=0

### device_tokens — 5 rows
0c56a19b production | 86587674 production | 018ab51d production
a53f7cc1 production | 10882c55 sandbox    <- the 13 Pro Max, Debug build 52

### incident_types (new in 2.19.0)
58 rows

### today
tracebacks: 0 | webhook deliveries: 64 | APNs 400s: 0
```

**Rollback images:** `bhnm-apns-bhnm-apns:pre-2.19.0`, `pre-2.19.1`,
`bhnm-apns-benem-pwa:pre-0.18.0`, `pre-0.18.1` — each tagged from the **observed** running version
and then verified by reading the version back **out of the tagged image**.

`servers.json`: 4 servers, 4 distinct keys. Unchanged.

---

## (c) Lab state — observed 2026-09-20T09:03Z

Devices **searched by name, never counted**:

```
raspi-050    1 row | DOWN | 10h 28m 5s | "Ping CRITICAL: Packet Loss 100%" | incident 29883
BHNM-B-SE01  1 row | UP   | 3d 19h 37m 15s | "Updates received."
0 in maintenance, 41 host rows, 1 down
8 active incidents, 0 closed
last webhook 08:45:50Z, incident 29914, 6 targets
```

**`raspi-050` has been DOWN for over ten hours** and **it paged correctly** —
`22:35:25Z [Webhook] PROBLEM — raspi-050 — Incident 29883`. Flagged because it is a live host-down,
not because anything is wrong with BeNeM. **Thomas will know whether that pi is deliberately off.**

**The anomaly knob is ON** — 64 deliveries today. It is hand-operated in both directions, so the
rate is not a health signal and a quiet period is a question, not a finding.

**Incident 29882** (`Service Check Interface Status … on C800`, opened 00:31Z) produced **no
webhook at all**, while the host incident four minutes later did. That is §8.8's coverage gap
happening live: only host checks are attached to the action group.

---

## (d) Verified vs unverified

### VERIFIED — measured, not argued

| thing | how |
|---|---|
| **2.18.1's `BadDeviceToken` cleanup — VERIFIED IN THE FIELD** | first fire 2026-09-19T20:38:15Z. `Failed (400) … BadDeviceToken` → `Token bad … removing` → `Cleanup] Removed stale APNs token`. `device_tokens` **5 → 4**, and the four survivors were untouched, so the deliberate narrowing to *only* that reason did its job rather than emptying the fleet |
| **The notification deep link, BOTH paths, on build 52** | Thomas, on the 13 Pro Max: a notification tap opens that incident; an **offline** tap shows **"Could not load this incident."** with the OS reason and a working **Try again** |
| **Acking keeps the incident in the list** | the regression test was run against the OLD code and **fails** there, so it is a guard rather than a decoration; and it drives a real view model, not a reimplementation of the filter |
| **Blue counts, end to end through the deployed 2.19.1** | 27516: baseline `OPEN`/`red:1` → ack → `blue:1` → un-ack → `red:1`, lab restored to `OPEN`, `acknowledged 0`, `ack_user ''` |
| **2.19.0's C9 and C10 in production** | `Cache updated: … oldest enrichment 108s, 0 unconfirmed`; three rows carrying ages of 136/120/105 s where one stamp used to speak for all; 58 persisted type rows |
| **PWA 0.18.0/0.18.1 are what is serving** | bundle hash **and** version changed both times, and the banned string greps to **0** in the shipped bundle |
| **Build 53's IPA is signed for production push** | unpacked and read: `aps-environment: production`, `get-task-allow false`, `Apple Distribution: Thomas Stolt (8L27BJGYXP)`, `2.13.6 (53)`, no `.xctest`. **The `.xcarchive` reads `development`** — same archive, one re-sign apart |

### NOT VERIFIED

| thing | why, and what would close it |
|---|---|
| **Build 53 has never run on any device** | submitted with no TestFlight install. The changed code has no build-configuration branches apart from the untouched `AppDelegate` fork, so the residual gap is **optimisation level only** — Release `-O` against build 52's `-Onone`. That is a conclusion from a grep, not from a running app |
| **Processing and review state of 53** | **not knowable here by ruling** — see (g). It comes from Thomas |
| **C2's fetch-at-webhook-time question** | unbuilt, so unmeasured: is a `PROBLEM` incident already fetchable from BHNM at webhook time? Everything seen so far says yes and none of it is on that path |
| **C13** | does an alarm joining an *existing* open incident fire a webhook — method written, **not run** |
| **The `UNKNOWN` alert type end to end** | the clients render it; the middleware does not emit it yet (C11 middleware half, step 6, gated on 53 reaching the field) |
| **Everything in the 09-19 handoff's NOT VERIFIED table** | carried forward — Steve's and Luiz's clients, the inconclusive verdict branch, `/internal/cache/reload` after the rotation, a RECOVERY while an override is PENDING, S1 1b per-server isolation |

---

## (e) Parked items, RANKED

1. **The `AppDelegate` APNs environment fix — first item of the next client wave.** Read
   `aps-environment` from the embedded provisioning profile at runtime; **no profile means App
   Store, means `production`**. The app states what it holds, not what its compiler flags imply.
   Removes the app's **only** behavioural Debug/Release fork, after which a build's configuration
   stops being a push hazard. Evidence in the 09-19 handoff.
2. **Build order steps 6–13** of the webhook-first note. **C11's middleware half (step 6) is
   unblocked the moment 53 is in the field** — that is the gate, and it is the only thing waiting
   on Apple.
3. **Incident list filter — Total / Open / Ackd / Cleared, plus search.** Mockup **approved**, rows
   unchanged. **TWO rulings needed from Thomas before any build:**
   - **does "Open" mean un-acked only, or open-including-acked?** This is the same question
     "Active" just answered for the tile, and the two must not end up meaning different things on
     one screen;
   - **what window does "Cleared" cover?**

   and a third thing to settle with them: **how the Home tile maps onto the tabs** — the tile's set
   is "not closed", which is not any single one of these four.
4. **The detail screen refetches instead of rendering the cached row when offline.** Filed
   2026-09-20. It has a perfectly good cached row and asks anyway, so an offline tap looks like a
   failure where it could look like data with an age on it. C9's timestamps are the vocabulary for
   the honest version.
5. **Does the app clear its own notifications from Notification Centre on launch?** Unanswered —
   nobody has looked.
6. **The two SE experiments** — a standalone Service Engine shutdown with full timing, and an SE
   Group failover after Thomas sets the group up. **Runbooks to be written when he schedules
   them**, not before. They gate decisions 2 and 4 of the engine-down note.
7. **C13's lab measurement.** Method is written into the webhook-first note. **Do not run it
   unasked** — it needs a provoked second alarm, so it is not a read-only lab operation.
8. **The 09-19 security tail**, unchanged and still ranked as it was: credential rotation for the
   short api_keys (`ThomasLabServer` 15 chars, `Luiz` 9), **S1 1b** per-server webhook secrets,
   Caddy's cleartext header logging, the five unlogged refusal paths, restricting `/health`.

---

## (f) Withdrawn claims

**Items 1–19 are in the two 09-19 handoffs and still stand.** In particular: **"the Service Engine
sends webhooks"** (it does not), **"anomaly incidents cannot page"** (they can), **"the rotation's
blast radius is one diagnostic button"**, and **(f)19, "the ack user reads as the device name"** —
an assertion offered in review as though it were a measurement, accepted without a check, ruled on,
and shipped as a regression. The producer's own record settled it and was one `docker exec` away.

### Today's

20. **"No token will be stranded by a Debug → Release swap; `device_tokens` will not drop to 4; the
    2.18.1 cleanup branch is still never fired."** **All three false**, falsified 78 minutes after
    they were written. The prediction they replaced was wrong about the *mechanism* — no new token
    string, no extra row — and **right about the outcome**, and the outcome was discarded along
    with the mechanism. The real mechanism: the token string **is** the same across Debug and
    Release; what is environment-specific is **which host will accept it**, and that is set by the
    entitlement, not the build configuration.

    **Twice in one session on one token, both times from reasoning about a mechanism instead of
    waiting for the row.**

21. **"`10:54:44Z`" for the upload.** It was **08:54:44Z** — xcodebuild prints local time and the
    laptop is CEST. The identical UTC/local confusion had been recorded in the 09-19 handoff hours
    earlier, after a grep filtered a UTC log with a local timestamp, and it was repeated anyway.
    **Convert before writing a `Z`.**

---

## (g) Rules added — pointers, not restatements

- **Root `CLAUDE.md` — *App Store Connect is Thomas's alone.*** Do not read it or touch it by any
  route, **including his browser session**. Processing, review and approval state come from Thomas
  or from Apple's email that he forwards. Written down because it was crossed: the Chrome session
  was pointed at App Store Connect to answer "tell me when it has processed". Nothing was read and
  no credentials were entered — **the attempt was the error, not the outcome.** "Read-only" and "he
  asked me to report it" both felt like permission and neither was.
- **Root `CLAUDE.md` — *every iOS release is EXPORT, then VERIFY, then UPLOAD.*** The entitlement
  check happens on the exported IPA, never on the archive and never on an artefact a combined
  export-and-upload has already sent. Today's contrast is the evidence: the same archive yields an
  app reading `development` and an IPA reading `production`. And the sharp part, measured today:
  **after `destination: upload`, `-exportPath` contains no `.ipa` at all** — so skipping the local
  export does not defer the check, it makes it impossible.
- **Root `CLAUDE.md` (2026-09-19) — *a new VALUE in an existing field* is a change the shipped
  client must tolerate**, checked in two cases: the unknown value **and** the field absent.

---

## (h) The single next action

**The `AppDelegate` APNs environment fix**, then **build order step 6**.

The environment fix is first because it is small, it is ruled, and it closes the defect that cost
the most time this week: an app that declares its push environment from its compiler flags rather
than from the entitlement it is actually holding. It needs no ruling and no lab.

**Step 6 — C11's middleware half** (a failed enrichment is never cached; `UNKNOWN`, never `"host"`;
bounded retry) **is gated on 2.13.6 (53) being in the field**, because a new *value* in an existing
field is a change the shipped client must tolerate first. Both clients were measured to tolerate it,
so the gate is cheap — but it is the first case decided under that rule and the rule is worth more
than the shortcut.

**What must be true before either starts:**

1. **Nothing is mid-deploy.** Currently true: middleware 2.19.1 and PWA 0.18.1 live and verified,
   tree clean, `local == remote`.
2. **For step 6 only: 53 is in the field**, and that is Thomas's word, not an inference from time.
3. **The reader has read (d) NOT VERIFIED and (f)** — nothing in either is to be resurrected.
4. **Counts are not evidence in the BHNM UI.** Search for the object by name.

**Do not** run C13 or the SE experiments unasked. **Do not** start item 3's build — it has two
unruled questions in it. **Do not** touch App Store Connect.
