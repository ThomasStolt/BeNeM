# Cache publish and cadence — session handoff

**Date:** 2026-09-23, written 14:52Z. **Middleware 2.21.0 and benem-admin 1.6.5 are live and
verified on a raspi-050 cycle. PWA 0.19.7 is live. iOS 2.14.0 (54) is Debug on one phone and
NOT submitted.**

---

## UPDATE 2026-09-24 — read this first

- **iOS 2.14.0 (54) is UPLOADED.** The upload ran from the Organizer archive at
  `2026-09-23 19:12:46` local (**17:12:46Z**) and printed `Upload succeeded.` /
  `** EXPORT SUCCEEDED **`.
  - The options were the same as 53's, differing only in `destination: upload`.
  - Processing, review and submission are Thomas's. Nothing here has read App Store Connect.
- **Build 54 still draws white text on the CLOSED chip.** The chip is `#F2F2F7`, so the label is
  unreadable in the incident list, the detail screen and the Home ticker.
- **iOS 2.14.0 (55), `e445e32`, fixes it.**
  - `NetreoIncident.chip` now carries the pill's `onColor`, so CLOSED gets `#111114` and the
    other four keep white.
  - 55 is a Debug build on the 13 Pro Max only. **It is not archived and not uploaded.**
  - **Thomas decides:** submit 54 and ship the fix later, or have 55 archived, exported, verified
    and uploaded.
- **The PWA is unaffected.** Its CLOSED chip is `bg-slate-500` with white text.
- **Nothing else changed since 17:06Z:** middleware 2.21.1, benem-admin 1.6.5, PWA 0.19.10.

**Where to pick up:**
1. Thomas's decision on 54 vs 55.
2. The webhook-insert race (parking item 11).
3. The next middleware release, which carries `e4f500a`.

---

## UPDATE 2026-09-23T17:06Z — supersedes (a), (b) and (e) below

**Observed 17:06Z, not recalled:**

| component | version | evidence |
|---|---|---|
| **middleware** | **2.21.1** | `/health` → `{"status":"running","version":"2.21.1"}`, container up 2 h |
| **benem-admin** | **1.6.5** | `VERSION = "1.6.5"` in the running container |
| **PWA** | **0.19.10** | bundle `index-BLytN5Fe.js` reads `"0.19.10"` |
| **iOS** | **2.14.0 (54) — ARCHIVED AND EXPORTED, AWAITING THOMAS'S UPLOAD** | tag `ios-2.14.0-54` on `95a8aa0` |

**Rollback tags:**
- `bhnm-apns-bhnm-apns:pre-2.21.1` holds 2.21.0.
- `bhnm-apns-benem-pwa:pre-0.19.8`, `pre-0.19.9` and `pre-0.19.10` hold 0.19.7, 0.19.8 and 0.19.9.
- Each one was read back out of the image after tagging.

**On `main` but NOT deployed:** `e4f500a`, one log line per absence check. It rides with the next
middleware release.
- **The VPS checkout has already pulled it**, because the PWA deploys were done with
  `git pull` plus a pwa-only rebuild; `upgrade.sh` would have rebuilt the middleware too.
- So the next `upgrade.sh` will not see `incident_cache.py` as changed. It still rebuilds
  `bhnm-apns` provided that release touches a middleware file, which its `VERSION` bump does.

### iOS 2.14.0 (54), the store build

- **Archive:** `~/Library/Developer/Xcode/Archives/2026-09-23/BeNeM 2.14.0 (54).xcarchive`.
  It shows in Xcode's Organizer.
- **Exported IPA:** `~/dev/BeNeM-export-2.14.0-54/BeNeM.ipa` (2,799,283 bytes).
- **Export options:** `app-store-connect`, `destination: export`, `signingStyle: automatic`,
  teamID `8L27BJGYXP`, `manageAppVersionAndBuildNumber: false`. The same as 53.
- **Not uploaded.** Upload is Thomas's step. Per root `CLAUDE.md` it re-exports with identical
  options, differing only in `destination: upload`.

Read out of the unzipped IPA:

| check | value |
|---|---|
| `CFBundleShortVersionString` / `CFBundleVersion` | 2.14.0 / 54 |
| `CFBundleIdentifier` | `com.tstolt.benem` |
| `aps-environment` | **production** (the archive's own app reads `development`, as with 53) |
| `get-task-allow` | false |
| Authority | Apple Distribution: Thomas Stolt (8L27BJGYXP) |
| `embedded.mobileprovision` | **present** — `iOS Team Store Provisioning Profile: com.tstolt.benem`, no `ProvisionedDevices`, profile `aps-environment: production` |
| `*.xctest` | 0 |

**What is in 54 over 53:**
- the five incident pills and search;
- CLOSED rows;
- the silent poll at **30 s** (C19);
- TOTAL `#5B21B6` / `#A78BFA`, and CLOSED with a white frame and no glow when unselected.

**Only Debug has run on a phone** (the 13 Pro Max). No device has run the Release build.

**iOS suite:** 74 green on six completed runs at `95a8aa0`.
- **One earlier run reported `74 tests, 1 failure` and was not captured.** It never recurred, so
  the failing test is unidentified. Suspect a timing test (the 0.05 s poll tests).
- **Every other run failed to launch** with `Application failed preflight checks` (simulator
  Busy). That is the environment, not a test.

### What (e) became

1. **Row inserted before the push — DONE, 2.21.1, verified on 30056** (cache-publish note §10).
   **New open item:** the insert checks "known" before awaiting the detail and never checks again,
   so a list poll landing inside that await gets overwritten. Harmless on 30056, but it breaks "a
   known incident is unchanged". Fix: re-check before the merge.
2. **TOTAL darker — DONE**, twice: `#6D28D9` (0.19.8), then **`#5B21B6`** (0.19.10); iOS 54 the same.
3. **CLOSED white frame unselected, no glow — DONE**, 0.19.8 / iOS 54.
4. **Client silent poll to 30 s — DONE**, 0.19.9 / iOS 54.

### Parking list, in order

1. **CLSD retention is in memory, so every middleware deploy empties it.** Unchanged, see (f)1.
2. **`M1-drop`.** Now gated on 54 reaching the store and `BeNeM/53` leaving the `[Client]` lines.
3. **Per-notification-type switches, per phone.** Delivery step, not the cache.
4. **iOS prints the full device token in Debug.**
5. **`build_and_deploy.sh` builds Release.** Worked around all day by building Debug directly
   with `xcodebuild -configuration Debug` + `devicectl`.
6. **The detail screen refetches instead of rendering the cached row when offline.**
7. **Does the app clear its own notifications on launch?**
8. **The two SE experiments.**
9. **C13's lab measurement.** Not unasked.
10. **The 09-19 security tail.**
11. **New — the webhook-insert race** (above).
12. **New — a reopen keeps a green chip on an OPEN row until the next enrichment.** Seen on 30058:
    served OPEN at 16:06:32Z, Thomas saw red at 16:08:35Z. **[INFERENCE]** The list path recolours
    from the last severity snapshot, and that snapshot read the alarm UP. Per-incident enrichment
    results are not logged, so this is unconfirmed. Evidence:
    `docs/evidence/2026-09-23-reopen-30058.md`.
13. **New — `notification_number` is not logged**, so RENOTIFY cannot be read after the fact.
14. **New — the unidentified iOS test failure** (above).
15. **From memory, NOT re-checked 2026-09-23:**
    - **LAN DNS:** the Synology at `192.168.2.11` answers NXDOMAIN for `benem.hurrikap.org`.
    - **`upgrade.sh` rebuilds the middleware** for `*.md` changes under `middleware/`.
    - **The WebART HTTP step never runs** when the check is run from a remote Service Engine.

### BHNM tickets — EXTERNAL, not ours to fix

Two are **recorded as opened by Thomas** (09-18 handoff §9):

1. **`ha_status_api.php` behind a terminating proxy.** It answers "API require HTTPS connection."
   over real HTTPS and ignores `X-Forwarded-Proto`. Worked around.
   `docs/evidence/2026-09-18-bhnm-ha-status-https-bug.md`.
2. **No api_key-readable version endpoint on-prem.** The topology shows "version unknown" there by
   design.

Two more BHNM behaviours are **measured, but NOT recorded anywhere as filed tickets.** Thomas to
confirm:

3. **No webhook for the OPEN→ALARMS CLEARED transition.** 30008–30011 on BHNM-B (2026-09-21), and
   both clears of 30058 (2026-09-23).
4. **No webhook when an incident re-opens (ALARMS CLEARED→OPEN).** 30058, 16:06:30Z: same incident
   id, no notification of any kind. `docs/evidence/2026-09-23-reopen-30058.md`.

---

**Earlier state lives in `docs/superpowers/2026-09-22-incident-list-filter-handoff.md`** and is
not repeated. Read its (f) WITHDRAWN table before resurrecting anything.

**Every state claim below was observed between 14:45Z and 14:52Z on 2026-09-23, not recalled.**
Where a fact comes from Thomas it says so.

---

## (a) What is deployed, observed 2026-09-23T14:49:53Z

```
### /health (public, unauthenticated)
{"status":"running","version":"2.21.0"}
benem-admin 1.6.5

### PWA
bundle: /assets/index-JDGroW7A.js      "0.19.7"

### containers
benem-middleware  Up 3 hours
benem-admin       Up 3 hours
benem-pwa         Up 22 hours
benem-proxy       Up 8 days

### per server — read BY KEY, never counted
                     retain_closed   list_poll_seconds
SaaS Demo Server     False           <absent>
ThomasLabServer      True            <absent>
Steve                False           <absent>
Luiz                 False           <absent>

effective, read through the live code path inside the container:
  ThomasLabServer  list_poll=30s  retain_closed=True

### device_tokens — 5 rows
0c56a19b production | 86587674 production | 018ab51d production
a53f7cc1 production | 10882c55 sandbox   <- the 13 Pro Max
web_push_subscriptions: 1
```

**`list_poll_seconds` is absent on all four and resolves to the 30 s default.** Absent is the
intended state — the key exists to be set when a server needs something else, and the default is
the ruling.

**`retain_closed` is ON for ThomasLabServer only.** The other three are `False` as a materialised
default, not `<absent>`: `save_servers` writes the full key set, so the portal round-trip of
2026-09-22 made them explicit. Semantically identical.

**Rollback tags, each written from the OBSERVED running version and verified by reading the
version back OUT of the tagged image:**

| tag | holds |
|---|---|
| `bhnm-apns-bhnm-apns:pre-2.21.0` | middleware 2.20.3 |
| `bhnm-apns-benem-admin:pre-1.6.5` | benem-admin 1.6.4 |
| `bhnm-apns-benem-pwa:pre-0.19.7` | PWA 0.19.6 |

`pre-2.20.0` … `pre-2.20.3` and `pre-0.19.1` … `pre-0.19.6` all still present and untouched.

`local == remote` at **`686ab03`**. Tree clean — the two sampler JSONLs are untracked since
`18aa638` and `docs/evidence/*.jsonl` is gitignored.

---

## (b) What shipped, in order

| build | hash | state |
|---|---|---|
| **middleware 2.21.0** | **`686ab03`** | **LIVE.** C16–C20 |
| **benem-admin 1.6.5** | `686ab03` | **LIVE.** `list_poll_seconds` round-trips a portal save |
| **PWA 0.19.7** | `c6c8e74` | **LIVE.** CLSD pill relabelled CLOSED |
| **iOS 2.14.0 (54)** | **`7b76c8e`** | **Debug on the 13 Pro Max. NOT submitted, not on any other phone.** |

**Test counts, all three run at the end of the session: middleware 367, PWA 475, iOS 73**,
benem-admin 40.

Design note for 2.21.0: `docs/superpowers/specs/2026-09-23-cache-publish-and-cadence.md`
(committed alone at `d602201`).

### What C16–C20 are, in one line each

- **C16** newest confirmation wins — a publish from a list taken at `T` may not overwrite a row
  whose `state_confirmed_at` is newer than `T`, nor call it disappeared.
- **C17** disappearance is confirmed by one `getincidentdetail`, not inferred. CLOSED retains,
  OPEN/ALARMS CLEARED keeps it active, not found retains, **a FAILED check keeps it active and
  retries**.
- **C18** the list publishes immediately; enrichment updates rows one at a time as each detail
  lands.
- **C19** `list_poll_seconds` (30, min 15) beside `cache_refresh_seconds` (unchanged, enrichment).
- **C20** the `[State:]` line is written after the overrides and reports the SERVED value, with
  the raw list value alongside when they differ; the refresh endpoint logs a `[Client]` line.

### The correction 2.21.0 took in review, and the second bug it uncovered

The first cut **retained on a failed absence check**. Thomas ruled it must keep the row active and
retry. Implementing that exposed a second defect the new test caught:
**`_fetch_incident_detail` swallows its own transport errors** and returns `confirmed: False`,
while a successful call with no incident returns `confirmed: True` and no state — **both leave
`bhnm_state` as `None`**, so the `try/except` wrapped around it was dead code and a failed call
was still being read as "not found". The verdict is now taken from `confirmed`, never from the
state.

---

## (c) The raspi-050 verification, incident 30053 — MEASURED

Run by Thomas this afternoon. BHNM's own `incident_log` is local CEST, converted at −2 h.

```
14:34:13Z  BHNM      OPEN                              (16:34:13 local)
14:34:14.061Z  [Webhook] PROBLEM — raspi-050 — Incident 30053
14:34:14.068Z  [Webhook] Queued delivery to 6 target(s)
14:34:35.937Z  [State:] 30053: None -> OPEN (source: list)     +21.9 s after the webhook
14:35:24.982Z  [Client] BeNeM/54 on /api/v1/incidents          +70.9 s — the phone sees it

14:40:15Z  BHNM      primary alarm UP                  (16:40:15 local)
14:40:50Z  BHNM      ALARMS CLEARED                    (16:40:50 local)
14:41:10.700Z  [State:] 30053: OPEN -> ALARMS CLEARED (source: list)   +20.7 s

14:45:52Z  BHNM      CLOSED                            (16:45:52 local)
14:45:53.889Z  [Webhook] RECOVERY — raspi-050 — Incident 30053
14:45:53.889Z  [Webhook] Cache patched: incident 30053 -> CLOSED (1 server(s))
```

**NO FALSE CLOSED.** 30053 went `OPEN -> ALARMS CLEARED -> CLOSED` with nothing in between, and
the retained count through the whole window tracked real closes only (`1 retained` while 30051 was
still open, `2 retained` from 14:36:08 when it closed). The 2026-09-23 morning defect — a stale
cycle publishing over a refresh and calling the row disappeared — did not recur.

**The state moves in ~21 s server-side, at both ends.** That is the list cadence doing what C18
and C19 were for: the old end-of-cycle publish cost 101 s on 30046 yesterday.

**The close is immediate** — the RECOVERY webhook patched the cache in the same millisecond, and
the CLOSED count moved with it.

**`Retained N` is now `List published: A active, C closed, R retained`.** The old line is gone.
Observed before the deploy: `Retained 11 incident(s)`. Observed after: `1 retained`. That is not a
regression — see (d).

---

## (d) VERIFIED vs NOT VERIFIED

### VERIFIED — measured, not argued

| thing | how |
|---|---|
| **2.21.0 and 1.6.5 are what is running** | `/health` reads `2.21.0`; `benem-admin` reads `1.6.5` |
| **The list poll is 30 s for ThomasLabServer** | four consecutive `List published` lines 30.21 / 30.20 / 30.21 s apart |
| **Enrichment runs on its own cadence** | `Enrichment loop started (cache_refresh=120s)` beside `Enriching 4 incidents (pacing: 24.0s)`, and `Enrichment sweep done: oldest enrichment 97s, 0 unconfirmed` — four list publishes fit inside one sweep |
| **The refresh endpoint logs a `[Client]` line** | `14:34` direct POST → `[Client] not-BeNeM on /api/v1/incidents/refresh`; the phone's own foreground resume → `[Client] BeNeM/54 on /api/v1/incidents/refresh` |
| **`retain_closed` and `list_poll_seconds` per server** | read by key from `servers.json` AND through `config.server_list_poll_seconds` inside the live container |
| **The raspi-050 cycle** | (c) above, against BHNM's own `incident_log` |
| **The three headline tests fail against 2.20.3** | run before the fix, failing on behaviour rather than on a missing import; quoted in the 2.21.0 commit body |

### NOT VERIFIED

| thing | why, and what would close it |
|---|---|
| **2.20.3's list-path recolour, in the field** | Still unexercised. It only fires when a list publish changes a state *without* an enrichment landing at the same moment. Every cleared incident observed since 2.20.3 went through the enrichment path. **With C18 it should now fire on every list publish** — the next cleared incident is the check, and nobody has looked |
| **`list_poll_seconds` at any value but the default** | Absent on all four servers, so the min-15 clamp and the non-integer fallback are covered by unit tests only |
| **C17's failed-check retry, in the field** | No absence check has failed in production yet. Unit-tested both ways |
| **iOS 54 on any phone but the 13 Pro Max** | One Debug install. Not submitted |
| **Everything in the 09-22 handoff's NOT VERIFIED table** | carried forward unchanged |

---

## (e) Open, in priority order

1. **A new incident's row is not inserted before the push goes out.** **[MEASURED]** On 30053 the
   `PROBLEM` webhook queued delivery to 6 targets at `14:34:14.068Z` and the row did not exist in
   the cache until the next list poll at `14:34:35.937Z` — **21.9 s later**, and **70.9 s** before
   the phone fetched it. A user who taps the notification inside that window lands on an incident
   the middleware cannot serve. The webhook already carries the incident id; inserting a
   provisional row at webhook time, ahead of the push, is the fix. **Next build.**

2. **TOTAL goes darker, `#6D28D9`.** Thomas's ruling. Both platforms, both suites assert the
   literal string, re-render the 375 pt snapshots.

3. **CLOSED gets a white frame when UNSELECTED.** Reverses the frameless rule of 0.19.6. The glow
   was not mentioned and is not assumed — ask before adding one. Selected can keep the frame;
   Thomas said the inversion makes it moot.

4. **The client wave: the silent poll to 30 s on both platforms.** Step 3 of the 2.21.0 design
   note's build order, not started. It is the last term in the lag now that the middleware carries
   ~21 s — on 30053 the phone was 49 s behind a cache that already had the answer.

---

## (f) Parked — recorded, not scheduled

1. **CLSD retention lives in memory and is lost on every deploy.** **[MEASURED]** `Retained 11
   incident(s)` before the 2.21.0 deploy, `1 retained` after — the 24-hour window restarts from
   empty each release. Persisting it to the existing SQLite database is the fix. **Parked**: it
   changes what a deploy means for the CLOSED pill, and nobody has asked for it.

2. **`M1-drop`** — remove the `ACKNOWLEDGED`/`CLOSED` writes into `incident_state`. Gated on
   `BeNeM/53` being absent from the `[Client]` lines, which have been running since 2.20.1 on
   `/register` and `/api/v1/incidents` and since 2.21.0 on the refresh route. **The gate now has a
   signal**; it needs long enough to be meaningful, and Thomas's word about who is on what.

3. **Per-notification-type switches, per phone** — Open always on, Recovery and Acknowledgement
   optional. **Belongs in the middleware's DELIVERY step, not the cache**: suppressing a
   notification must never suppress a state change.

4. **The iOS app prints the FULL device token to the Debug console** —
   `[APNs] Device token: <64 hex>`. `middleware/CLAUDE.md` rules that tokens are always truncated
   to `token[-8:]`; the client side does not follow its own rule. DEBUG-only, physical device.

5. **`build_and_deploy.sh` builds Release, not Debug** (`ios/build_and_deploy.sh:36`). Asked for a
   Debug install it produces a Release build and installs it. Either take a configuration argument
   or rename the script. **The hazard is not hypothetical** — a Release build carrying a
   development profile is the 2026-09-20 shape that killed push on this phone once.

### Carried forward, unchanged

6. **The detail screen refetches instead of rendering the cached row when offline** (2026-09-20).
7. **Does the app clear its own notifications from Notification Centre on launch?** Unanswered.
8. **The two SE experiments.** **[MEASURED 2026-09-23]** The samplers were stopped on 2026-09-22
   and their files are on disk but untracked. The message-watch file shows **BHNM-A-SE02 was never
   shut down** — `UP` in all 556 samples, `currentStateDuration 1d 18h 18m 4s`. **BHNM-A-SE01** went
   DOWN `2026-09-20 16:14:06Z` and back UP `2026-09-21 06:37:03Z`. The 15 s exp2 sampler holds **no
   usable SE02 row at all** across 11,072 samples, so it is not evidence about either SE.
   Whole-group failure remains unmeasured.
9. **C13's lab measurement.** Do not run it unasked.
10. **The 09-19 security tail**, unchanged: credential rotation for the short api_keys, S1 1b
    per-server webhook secrets, Caddy's cleartext header logging, the five unlogged refusal paths,
    restricting `/health`.

---

## (g) What must be true before the next thing starts

1. **Nothing is mid-deploy.** Currently true: 2.21.0, 1.6.5 and 0.19.7 live and verified, tree
   clean, `local == remote` at `686ab03`.
2. **`retain_closed` is ON for ThomasLabServer only**, and its retained rows date from after the
   2.21.0 deploy — anything older was lost with the container.
3. **Counts are not evidence in the BHNM UI.** Search for the object by name.
4. **Do not touch App Store Connect.** Processing, review and approval come from Thomas.
5. **iOS 54 is not submitted**, and items (e)2, (e)3 and (e)4 all change the client — so the next
   client build carries them together, not one at a time.
