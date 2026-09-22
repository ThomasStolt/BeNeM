# Incident list filter — session handoff

**Date:** 2026-09-22, written 06:45Z. **Steps 1–3 of the filter build order are done. Middleware
2.20.0 and PWA 0.19.1 are live; iOS 2.14.0 (54) is on one phone and NOT submitted.**

**Earlier state lives in `docs/superpowers/2026-09-20-webhook-first-wave-1-handoff.md`** and is
not repeated here. Read its (d) NOT VERIFIED and (f) WITHDRAWN tables before resurrecting
anything.

**Every state claim below was observed between 06:40Z and 06:45Z on 2026-09-22, not recalled.**
Where a fact comes from Thomas it says so.

---

## (a) What is deployed, observed 2026-09-22T06:40Z

```
### /health (public, unauthenticated)
{"status":"running","version":"2.20.0"}

### PWA
bundle: /assets/index-CWaE_IlO.js      "0.19.1"

### containers
benem-pwa        Up 12 hours
benem-middleware Up 13 hours
benem-admin      Up 13 hours
benem-proxy      Up 7 days

### retain_closed — read PER SERVER, by key, never counted
SaaS Demo Server  <absent>
ThomasLabServer   <absent>
Steve             <absent>
Luiz              <absent>

### device_tokens — 5 rows
0c56a19b production | 86587674 production | a53f7cc1 production
018ab51d production | 10882c55 sandbox   <- 13 Pro Max, now row id 667 (was 663)
web_push_subscriptions: 1

### last 24h
tracebacks 0 | APNs 400s 0 | "Retained … as CLOSED" lines 0
```

**`retain_closed` is absent on all four servers, so CLSD retention is OFF everywhere** and the
`Retained` count of 0 is the expected value rather than a silence to interpret.

**The sandbox token's row id moved 663 → 667.** That is the 13 Pro Max re-registering on the
Debug install of 54; same token suffix, same environment. Nothing was stranded.

**Rollback images, each tagged from the OBSERVED running version and verified by reading the
version back OUT of the tagged image:**

| tag | holds |
|---|---|
| `bhnm-apns-bhnm-apns:pre-2.20.0` | middleware 2.19.1 |
| `bhnm-apns-benem-pwa:pre-0.19.0` | PWA 0.18.1 |
| `bhnm-apns-benem-pwa:pre-0.19.1` | PWA 0.19.0 |

`local == remote` at **`98c8eb6`**. Tree clean apart from the two sampler JSONLs, which stay
uncommitted on purpose.

---

## (b) What shipped, in order

| build | hash | state |
|---|---|---|
| **middleware 2.20.0** | `f6d9ab5` | **LIVE.** M1 additive fields, M2/C7 refresh endpoint, M3 CLSD retention behind `retain_closed` (OFF) |
| **PWA 0.19.0** | `bf568ac` | superseded |
| **PWA 0.19.1** | **`b6b40cc`** | **LIVE.** Disjoint pills, TOTL default in gold, tile is TOTL |
| **iOS 2.14.0 (54)** | **`98c8eb6`** | **Built and installed Debug on the 13 Pro Max. NOT submitted, NOT on any other phone.** |

**Test counts at the end of the session:** middleware **324**, PWA **462** (49 files), iOS **60**.
`tsc --noEmit` and `vite build` clean.

### The rulings that changed the design note mid-build

The note's §1 was amended twice on 2026-09-21 and once more on the 22nd. **The amendment block
in `specs/2026-09-21-incident-list-filter-design.md` is the ruling — not the original table.**

1. **The five pills are DISJOINT.** `OPEN` is state OPEN **and not** acknowledged; ACKD is a
   peer, not a subset.
2. **`TOTL = OPEN + ACKD + CLRD`, EXCLUDING CLSD.** Closed is the one tab you opt into.
3. **TOTL is the DEFAULT and is gold `#c9a227`**, dark text on it. The hex is shared by both
   platforms and is deliberately distinct from the alarm chips' yellow and orange.
4. **The Home tile is "Active Incidents", counts TOTL, lands on TOTL.** This supersedes the
   note's Q5 ("the tile is the OPEN count").
5. **Only the incident list loses its 120 s timer.** Home, Devices and Groups keep theirs.

**(1) and (3) are load-bearing together, and the reason is worth keeping.** Disjoint pills mean
an ack **moves** a row from OPEN to ACKD — the 2026-09-19 field symptom, by design this time.
What keeps it from being the 2026-09-19 *defect* is that **TOTL is the default tab**: the row the
user just acked is still on the screen they were looking at. **Both platforms assert that
pairing in a test**, so moving the default away from TOTL fails the suite rather than the field.

**(4) exists for the same reason.** Under (1) an OPEN-counting tile would drop the moment
somebody acted — the 0.18.1 defect by another route, on the very number that defect was about.
TOTL is BHNM's own Active List View, so the label is right and the number survives an ack. Both
platforms assert the tile count equals the TOTL pill count **and** that it survives an ack.

---

## (c) Lab state, observed 06:42Z

Objects **searched by name/id, never counted from a UI counter**:

```
BHNM-B getincidents  result='completed'  3 rows, all OPEN
   24951 Threshold ADSL Upload Speed
   25482 Service BMC Discovery Outpost Service Check
   29546 Service Check SSL Certificate on Synology920
host_down: []          30017 present: False
```

**Incident 30017 (`Host raspi-050`) is CLOSED and gone.** It was raised at 17:55:14Z on the 21st
when Thomas pulled the plug, paged all 6 targets, and later took a `RECOVERY`:

```
[Webhook] PROBLEM  — raspi-050 — Incident 30017
[Webhook] RECOVERY — raspi-050 — Incident 30017
```

That was the step-3 verification incident and it is finished. Nothing to chase.

---

## (d) VERIFIED vs NOT VERIFIED

### VERIFIED — measured, not argued

| thing | how |
|---|---|
| **2.20.0's M1 fields in production** | all 6 served rows carried `state`, `acknowledged`, `ack_user`, `closed_at`, with `incident_state` unchanged; `rows missing any new field: []` |
| **The refresh endpoint, single-flight** | two calls 0.22 s apart → `coalesced=false` then `true`, identical payloads, **one** `[Refresh:…] List refreshed` log line for two calls |
| **The refresh does not enrich** | after a tap, `state_confirmed_at` moved +151.8 s while `counts_confirmed_at` did not move at all |
| **The `result: completed` guard** | both guard tests were run against the pre-fix code and FAIL there, with the defect in its own log line: `Retained 2 incident(s) as CLOSED` on an `{"result":"error"}` body |
| **PWA 0.19.0 and 0.19.1 are what is serving** | bundle hash **and** version changed both times; the superseded version greps to 0 in the shipped bundle each time |
| **The pill counts match BHNM** | 18:10Z, ThomasLabServer: TOTL/OPEN/ACKD/CLRD/CLSD = 5/5/0/0/0 against BHNM's own 5 OPEN, same five ids enumerated on both sides |
| **iOS 54 is a genuine Debug build on the 13 Pro Max** | installed bundle reads `2.14.0`/`54`, `aps-environment: development`, `get-task-allow: true`; launch printed `aps-environment from embedded.mobileprovision: development` → `Registering with middleware (environment: sandbox)` → `Middleware responded: 200` |

### NOT VERIFIED

| thing | why, and what would close it |
|---|---|
| **CLSD has never been seen with a row in it** | `retain_closed` is off everywhere, so every CLSD count measured so far is a structural zero. **The pill is untested against real data on both platforms.** Closing it is the next lab step — see (e)3 |
| **CLRD was 0 on both sides during the count comparison** | agreement there is two zeros, not a matched non-zero. Weaker evidence than the other four pills |
| **The rendered PWA at 0.19.1** | verified by bundle grep only. `benem.hurrikap.org` does not resolve through this Mac's default resolver (it resolves via 1.1.1.1, and from the VPS), so Chrome loads an error page. **Thomas verified 0.19.0 on the rendered page; 0.19.1 has not been looked at by a human yet** |
| **iOS 54 on any phone but the 13 Pro Max** | one Debug install. Not submitted, not on Thomas's App Store build, not on Steve's or Luiz's |
| **Everything in the 09-20 handoff's NOT VERIFIED table** | carried forward unchanged |

---

## (e) Next, in order

1. **Rename TOTL → TOTAL, with the two-line pill layout from the mockup, and change TOTAL's
   colour.** Both platforms. The label is in exactly one place per platform
   (`IncidentPill.rawValue`, `Pill`), but **the raw value is also the on-screen text and the
   `?pill=` URL value on the PWA**, so the rename touches the URL contract — decide whether
   `?pill=TOTL` keeps working as an alias. The colour constant is `#c9a227`, shared by both
   platforms and asserted in both suites; changing it means changing both and both tests.

2. **Flip `retain_closed` for ThomasLabServer via the admin portal.** The key round-trips a
   portal save (`benem-admin/servers.py`, tested), but **nothing in the portal UI edits it** —
   it has to be set by hand in `servers.json`, in place, **never with an atomic rename** (the
   file is bind-mounted by inode; see `middleware/CLAUDE.md`). Then `/internal/cache/reload`.

3. **Thomas tests CLSD.** This is the first time the pill has data. Watch for the
   `Retained N incident(s) as CLOSED` log line, which is currently 0 for a structural reason and
   should become non-zero.

4. **Thomas submits 54.** Per root `CLAUDE.md`: **EXPORT, then VERIFY the IPA, then UPLOAD**, as
   three steps. The archive is not evidence for the IPA.

5. **`M1-drop`** — remove the `ACKNOWLEDGED`/`CLOSED` writes into `incident_state`, once no
   `BeNeM/53` remains in the field. **Read (f)22 first: the gate as written cannot currently be
   measured.**

---

## (f) Withdrawn claims

**Items 1–21 are in the earlier handoffs and still stand.**

### 22. **"The proxy log carries `BeNeM/<build>` in the User-Agent."** — WRONG LOG, AND THE GATE IT SUPPORTS DOES NOT WORK

Written in the 09-21 handoff and repeated into the filter design note as the M1-drop gate:
*"`BeNeM/53` disappearing and only `BeNeM/54`+ remaining is a measurement; a date is not."*
Measured this morning, three things are wrong with it:

1. **It is not the proxy log.** `benem-proxy`'s container log holds Caddy's TLS/ACME chatter and
   **no access log at all** — the Caddyfile configures none. Over the container's whole life
   (since 2026-09-14) the only match is `BeNeM/36`, from a different logger.
2. **The real home is the persisted middleware log**, `/logs/middleware.log`. It holds
   `BeNeM/37 38 39 40 41 46` — **9 lines in total, and every single one is a
   `[Proxy] REFUSED target not in servers.json` line.** That is the only path in the middleware
   that logs a user-agent.
3. **So the absence proves nothing.** A fleet of perfectly working clients produces **zero**
   lines, because working requests are never refused. The last match of any kind is
   **2026-09-19, build 46** — and builds 47–54 never appear at all, including build 54 which
   registered successfully from the 13 Pro Max last night.

**This is the repository's own doctrine failure, on the gate for a breaking change**: an empty
result that was never capable of being non-empty for the question being asked. "No `BeNeM/53` in
the log" means *no build 53 made a refused request*, not *no build 53 is in the field*.

**The app sends no explicit User-Agent** — `BeNeM/<build> CFNetwork/… Darwin/…` is URLSession's
default, derived from the bundle name and `CFBundleVersion`. The value is real; only the place
it is recorded is useless.

**M1-drop must not be gated on this until a signal exists.** The cheap fix is to log the
user-agent on a path every client actually takes — `/register` or `/api/v1/incidents` — and let
it run long enough to be meaningful. **Until then the honest gate is Thomas's word about who is
on what**, which is the same rule that already applies to App Store state.

---

## (g) Parking list — ADDED THIS SESSION

1. **The iOS app prints the FULL device token to the console** —
   `[APNs] Device token: <64 hex chars>`, seen on the Debug launch of 54. `middleware/CLAUDE.md`
   states *"Never log full device tokens — always truncate: `token[-8:]`"*; the client side does
   not follow it. DEBUG-only and on a physical device, so low severity — but it is the rule this
   project wrote down, being broken in the one place nobody audited.

2. **Per-notification-type switches, per phone** — Open always on; Recovery and Acknowledgement
   optional. Recorded in the design note §6 as explicitly **not** that wave. **The distinction
   that matters: it belongs in the middleware's DELIVERY step, not the cache.** Suppressing a
   notification must never suppress a state change, or the list goes stale to save a buzz.

3. **`build_and_deploy.sh` builds Release, not Debug** (`ios/build_and_deploy.sh:36`,
   `-configuration Release`). Asked for a Debug install last night, it produced a Release build
   and installed it; the Debug build had to be made and installed by hand afterwards. Either
   take a configuration argument or rename the script to say what it does. **The hazard is not
   hypothetical**: a Release build carrying a development profile is the exact 2026-09-20 shape
   that killed push on this phone once already — survivable now only because `AppDelegate` reads
   the profile instead of its compiler flags.

### Carried forward, unchanged

4. **The detail screen refetches instead of rendering the cached row when offline** (filed
   2026-09-20). C9's timestamps are the vocabulary for the honest version.
5. **Does the app clear its own notifications from Notification Centre on launch?** Unanswered.
6. **The two SE experiments** — experiment 1 (standalone SE shutdown) has still not been run;
   experiment 2's fail-back gap is UNKNOWN and whole-group failure is unmeasured. Both need
   Thomas. Runbooks are written.
7. **C13's lab measurement.** Do not run it unasked — it needs a provoked second alarm.
8. **The 09-19 security tail**, unchanged: credential rotation for the short api_keys, S1 1b
   per-server webhook secrets, Caddy's cleartext header logging, the five unlogged refusal
   paths, restricting `/health`.

---

## (h) What must be true before the next thing starts

1. **Nothing is mid-deploy.** Currently true: middleware 2.20.0 and PWA 0.19.1 live and verified,
   tree clean, `local == remote` at `98c8eb6`.
2. **`retain_closed` is still off everywhere** until (e)2 deliberately flips one server.
3. **The reader has read (f)22.** The M1-drop gate does not work and must not be used as though
   it does.
4. **Counts are not evidence in the BHNM UI.** Search for the object by name.
5. **Do not touch App Store Connect.** Processing, review and approval state come from Thomas.
