# S1 1a, Coverage Visibility and Engine Staleness — session handoff

**Date:** 2026-09-16, written at 20:08Z.
**Supersedes:** `docs/superpowers/2026-09-15-push-delivery-and-s1-WIP-handoff.md` for *state*.
That file remains the authority for **the queue** (items 1–15) and the older decision records.

Written for a reader with no memory of this work. Every state claim below was **observed at
20:08Z**, not recalled — the raw output is inline.

---

## (a) What landed this session

Twenty-eight commits, `746b922..1e61fd0`, all pushed. Three middleware releases.

### middleware 2.15.0 — S1 change 1a, mechanism only (`4ce20b0`)

Per-server **accepted webhook secrets**. `servers.json` entries gain `webhook_secrets` — a *list*,
because rotation needs an overlap window. `/webhook` resolves which server a secret belongs to and
fans out over that server's whole list; `/register` and `/register-webpush` record a `server_id`.

**Behaviourally inert by design.** Every server's list was seeded with the secret already in use,
so the device set a webhook reaches is unchanged. No QR reissued, no device re-onboarded.
`tests/test_server_secret_split.py` asserts that invariant directly.

Also fixed two latent faults in the admin portal found while wiring it: `save_servers()` would
have **erased every accepted list on the next portal save**, and `Server(**s)` raised on any
unknown `servers.json` key.

### middleware 2.15.1 — two logging defects (`332aee3`, `22aa436`)

1. **The redaction filter was eating its own diagnostic.** 2.13.2 rewrites anything matching
   `(secret|token|password|key|pwd)=…`; 1a logged its fingerprint as `secret=<fp>`, which matched,
   so `logs/middleware.log` — the only log that survives a container recreate — recorded
   `secret=<redacted>`. Run against it, 1b's gating question *"is anybody still on the old
   secret?"* would have answered **"nobody"** when it meant **"we can no longer tell"**. Renamed to
   `secret_fp=`. The filter is unchanged; it was right.
2. **The resolved server name was arbitrary when a secret is shared.** `_server_for_webhook_secret`
   (one server) became `_servers_for_webhook_secret` (the **list**), so no caller can be handed an
   arbitrary winner. The log names a server only when exactly one matches, else
   `server=<ambiguous: N servers share this secret>`. `server_id` is stored only when unambiguous.

### middleware 2.15.2 — the ACK cache patch (`7806c57`)

`note_state_override_any_server()` patched only servers whose cache already held the incident and
returned a count; `main.py` logged `if n:`. An incident acknowledged **before its first cache
cycle** therefore had its override dropped — no patch, no log, no error — and flipped back to
**OPEN** on the next poll. The override is now held **pending, keyed by incident id**, and applied
on first sighting within the existing 300 s TTL, then promoted so later cycles do not revert it.
The zero case is logged.

**Field-verified** — see (d).

### Designs written, all STOP AT DESIGN

| file | subject |
|---|---|
| `specs/2026-09-16-coverage-visibility-design.md` | §8.8 — what BeNeM can know about its own paging coverage (**highest priority**) |
| `specs/2026-09-16-engine-down-stale-data-design.md` | queue item 13 — what to show when the engine behind the data is down |
| `specs/2026-09-16-push-relay-design.md` | queue item 6 — encrypted relay for self-hosters |
| `specs/2026-09-15-webhook-secret-header-auth-design.md` | S1 change 1 split into **1a / 1b**; all ten decisions recorded as decided |
| `specs/2026-09-15-incident-freshness-design.md` | four states became **five** — the fifth is *paused* |

### Evidence

- `docs/evidence/2026-09-14-…-measurement.md` — Parts **7 through 8.14** appended.
- `docs/evidence/2026-09-16-2.15.2-ack-cache-patch-field-test.md` — the raspi-050 test, **PASS**.

---

## (b) Deployed state — observed 2026-09-16T20:08:07Z

```
### /health
{
    "status": "running",
    "version": "2.15.2",
    "registered_devices": 3,
    "apns_environment": "per-device",
```

```
### /api/v1/diagnostics (feeds)
middleware.version: 2.15.2
bhnm.reachable: True | consecutive_failures: 0 | last_success_age_s: 4
  incidents        cached=True age=43 count=7  fails=0 err=None
  maintenance_map  cached=True age=29 count=41 fails=0 err=None
  tactical         cached=True age=72 count=15 fails=0 err=None
  thresholds       cached=True age=83 count=37 fails=0 err=None
```

```
### /api/v1/maintenance-map (keys)
keys: ['cache_age_seconds', 'host_down', 'in_maintenance', 'scheduled']
key count: 4
host_down: []
```

**Rollback images present on the VPS** (relevant tags only):

```
bhnm-apns-bhnm-apns:latest        47 minutes ago     <- 2.15.2
bhnm-apns-bhnm-apns:pre-2.15.2    23 hours ago       <- rollback target for 2.15.2
bhnm-apns-bhnm-apns:pre-guard     23 hours ago       <- rollback target for 2.15.1
bhnm-apns-bhnm-apns:pre-2.15.0    28 hours ago       <- rollback target for 2.15.0
bhnm-apns-bhnm-apns:rollback-2.13.4  34 hours ago
bhnm-apns-benem-admin:pre-2.15.2  23 hours ago
bhnm-apns-benem-admin:pre-2.15.0  34 hours ago
```

Git, observed:

```
$ git status --porcelain      (empty — clean)
$ git rev-parse HEAD          1e61fd01b35218db167ea073cd379ba18bcb83b0
$ git rev-parse origin/main   1e61fd01b35218db167ea073cd379ba18bcb83b0
local==remote: YES
```

---

## (c) Lab state — observed 2026-09-16T20:08Z

**BHNM version 26.3** (read from the UI page title earlier today; the repo minimum is 26.1.02).

Devices **searched by name, never counted** — per the `CLAUDE.md` rule:

```
### raspi-050 — searched by name
raspi-050 rows found: 1
    raspi-050 | UP | lastUpdateTime 2026-09-16 22:07:03 | dur 12m 48s

### BHNM-B-SE01 — searched by name
BHNM-B-SE01 rows found: 1
    BHNM-B-SE01 | UP | lastUpdateTime 2026-09-16 22:07:03 | dur 6h 41m 54s
```

`host_down` is `[]` — nothing down. raspi-050 was reconnected at 19:53:17Z after the field test;
its 12-minute state duration is consistent with that.

`servers.json` holds **four servers**, all seeded with `webhook_secrets` fingerprint `95e54469`;
only `ThomasLabServer` has `cache_enabled: true`, refresh 120 s.

**Which Action Group is attached to what: NOT VERIFIED.** Four attempts to open
Administration → Actions through the browser extension failed (the menu does not respond to
synthetic events) and no URL for that page is recorded anywhere in the repository. This is
evidence-file §8.10 and it **needs a human with the UI**. What is known is empirical, not
configuration:

- **host-down on raspi-050 fires the action** — four measured instances: 29499, 29570, 29586,
  29656.
- **Nothing else has ever fired it.** Every incident that has ever produced a webhook is a host
  event. Service checks, thresholds and anomalies: zero, ever. That is finding §8.8.

---

## (d) Verified vs deployed-but-unverified

### VERIFIED — measured in the field

| thing | how |
|---|---|
| **middleware 2.15.2** — ACK inside the first cache cycle | **PASS**, `docs/evidence/2026-09-16-2.15.2-ack-cache-patch-field-test.md`. ACK 69 s after the incident; both new log lines fired in order; ACKNOWLEDGED held across three polls and on Thomas's phone for 8 minutes with no flip to OPEN; the close worked and the pending entry did not leak |
| **S1 1a** — per-server resolution | a real BHNM-originated webhook logged `server=…` with zero FALLBACK, §8.5/§8.7 |
| **The ambiguity guard** | fired correctly on its first real webhook: `server=<ambiguous: 4 servers share this secret>` |
| **`secret_fp=` survives the redaction filter** | visible unredacted in the persisted log, with the old `secret=<redacted>` line in the same file for contrast |
| **Devices retain last state during an SE outage** | §8.13, controlled 26-minute outage |
| **`lastUpdateTime` stalls when the engine stops** | §8.13 — the hinge for item 13, favourable |

### DEPLOYED BUT NOT VERIFIED IN THE FIELD

| thing | why not |
|---|---|
| **S1 1a per-server *isolation*** | every server shares one seeded secret, so resolution is ambiguous by construction. Isolation is 1b's job and 1b has not started |
| **2.15.2 with a live pending override at recovery** | the TTL expired 12 minutes before the RECOVERY arrived. A recovery arriving *while* an override is pending was **not** exercised — needs an ACK and a recovery inside the same 5-minute window |
| **2.15.1's ambiguity label for the unambiguous case** | only the `<ambiguous: 4>` branch has run in the field; the single-match branch that names a server has not |

---

## (e) Open decisions, ranked

**1 — Coverage visibility (§8.8). HIGHEST PRIORITY. STOP AT DESIGN.**
*Question:* what can BeNeM know about its own paging coverage, what should it show on an incident
it would never page for, and what should it say when it cannot tell?
*Measured basis:* only host events have ever paged; at the time of measurement 16 of 18 displayed
incidents were of types that never have, rendered identically to the one that would.
*Options, in the design:* read action-group assignment from the BHNM API **if it is exposed** (one
read-only measurement decides this, and it is decision 1 in that file); otherwise mark rows whose
*type* has never paged, phrased as history, never as prediction.
*Ruling already made:* **do not block on BMC.** BeNeM supports BHNM 26.1.02+, so an upstream change
never reaches deployments in the field.

**2 — Engine-down staleness (queue item 13). STOP AT DESIGN.**
*Question:* what to show when the engine behind the data is down. Both premises are now
**measured**, and the cheap check is viable because `lastUpdateTime` stalls.
*Open fork, do not close it:* `bhnm-apns.hurrikap.org` reads `UP` with a `lastUpdateTime` a week
old. Either the cheap check already found a real gap, or the field is not comparable for
tunnel-managed devices and the check has a false-positive class. Three read-only discriminators
are written up. *Thomas's account: low priority, investigate at some point.*
*Planned, not scheduled:* the grouped-SE failover measurement, method written.

**3 — Incident freshness.** Copy for the **five** state strings needs approval (the fifth is
*paused*). Everything else in that spec is ruled.

**4 — S1 change 1b.** Ruled: 1b is not complete when the global secret leaves the accepted lists —
it is complete when the **unresolved-secret fallback is deleted** and an unresolvable secret is
refused. Until then the fallback logs loudly on every firing, and that log is the gate.

**5 — Push relay (queue item 6). STOP AT DESIGN.** First question is whether it is a product at
all, or whether "publish your own build" is the honest answer for iOS self-hosters. Android
self-hosters need nothing — Web Push has no vendor binding.

**6 — iOS defects found during the field test**, queue items 14 and 15, neither fixed: wrong
incident duration from a `?? Date()` fallback (iOS showed 3m where Android showed 13m on identical
data), and a stale BHNM URL making the app list incidents it cannot open.

**7 — Notification presentation.** The pushes arrive; on the iPhone 15 they sit in
Mitteilungszentrale with no banner and no sound. BeNeM reads none of iOS's presentation settings
(`alertSetting`, `soundSetting`, `lockScreenSetting`, `alertStyle`). Belongs with queue item 5.

**CLOSED this session, do not reopen:** `PROXY_TOKEN` rotation — Thomas is satisfied.

---

## (f) Withdrawn claims and known-wrong beliefs

**Do not resurrect these. Each was believed, recorded, and then refuted.**

1. **The Service Engine does NOT send webhooks — the main BHNM appliance does.** The recorded
   explanation *"a crashed SE cannot notify anyone of its own crash"* is **wrong**. It came from a
   reviewer ruling, was accepted without measurement, and removed the strongest case from §8.8 for
   a day.
2. **An SE outage does not fire the action group — status EXTERNAL, open with BMC.** Measured
   twice, including a controlled outage in which the appliance was demonstrably healthy: zero
   webhooks in either direction, for the outage *and* the recovery. Thomas has taken it to the BMC
   dev team. **Not ours to explain — two explanations have already collapsed, do not attempt a
   third.** The §8.8 design must not wait on it.
3. **SE Group failover is UNTESTED.** SEs can be grouped and a survivor takes over the failed
   one's devices. The 2026-09-16 outage measured a **standalone** engine, so it says nothing about
   failover. That failover keeps `lastUpdateTime` advancing is a **prediction, not a measurement**.
4. **"raspi-050 is the Service Engine"** — wrong; it got its own host incident 30 minutes later.
5. **"The two-hop diagnostics surface an SE outage"** — wrong. They verify the middleware reaching
   BHNM's *front end*, which answers perfectly while the engine is dead.
6. **"~30 minutes to detect a host down"** — withdrawn as contaminated; that window overlapped an
   SE outage. The only clean figure is **12 min 09 s** for *SE-outage* detection.
7. **Two premature readings of `lastUpdateTime`** — first "it is a real check time", then "it is
   rewritten on every fetch". Both were artefacts of polling timing. The controlled outage settled
   it: **it stalls.**
8. **The error branch in `IncidentListScreen.tsx:44` is NOT unreachable.** Tested in vitest: online,
   both a rejected fetch and a 401 reach `status: error`. It must not be "fixed". What is missing is
   a rendering for `fetchStatus: "paused"`.
9. **`[APNs] Sent to …` does not mean a phone showed anything.** It means APNs returned 200. This
   session reported "Sent" for three pushes while both iPhones stayed silent.

---

## (g) Rules and doctrine added this session

Pointers, not restatements.

- **Root `CLAUDE.md`** — the "never render unverified state as healthy" doctrine gains a **fourth
  case**, the operational form: a migration that had not taken looked exactly like one that had,
  and one log line was the entire difference.
- **`middleware/CLAUDE.md`** — three new sections: *the deploy pulls from origin, so
  verify-before-push is impossible* (order is push → deploy → verify → revert on failure); *never
  write a bind-mounted file with an atomic rename* (it binds the inode, and this cost a silent
  failed seed); and *a return value of zero that nobody checks is how a no-op stays invisible*.
- **`docs/DEVELOPING.md`** — the admin-portal suite needs its own venv on macOS; do not reach for
  `--break-system-packages`.
- **`docs/runbooks/2026-09-15-one-sitting-device-measurements.md`** — the sixth observation it
  always claimed to have, and the warm/cold four-cell requirement.

---

## (h) The single next action

**Write nothing new. Start with decision 1 of the coverage-visibility design: the read-only
measurement of whether the BHNM API exposes action-group assignment.**

It is one read-only probe, it needs no lab change and no deploy, and **it decides the shape of the
highest-priority item in the project** — whether BeNeM can state its coverage as fact, or must
admit it cannot know.

**What must be true before it starts:**

1. Thomas has approved the measurement (it is decision 1 in that file, still unanswered).
2. Nothing is mid-deploy — currently true: 2.15.2 is live, verified, and the tree is clean.
3. The reader has read `specs/2026-09-16-coverage-visibility-design.md` and section (f) above,
   so no withdrawn belief is resurrected.

**Do not** start the §8.8 *build* from that measurement. The design is STOP AT DESIGN and stays so
until Thomas rules on decisions 2 and 3 in that file.
