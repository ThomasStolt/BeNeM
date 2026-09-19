# Phase 1 batch — closing handoff

**Date:** 2026-09-19, written at 17:10Z. **Phase 1 is closed.**

**`docs/superpowers/2026-09-18-security-hardening-and-diagnostics-handoff.md` remains current for
everything before today** — the security hardening, the connection probe, the withdrawn claims 1–18
and the parked items. This file covers 2026-09-19 only and points at that one rather than repeating
it. Read it first if you have no memory of this work.

**Sixteen commits, `483a5d9..632738d`, all pushed.** Every state claim below was observed at
17:05Z, not recalled; the raw output is inline.

---

## (a) What landed today

| commit | what changes in behaviour |
|---|---|
| `a9b3034` | `.gitignore` takes `Claude outputs/` — the credential guard scans tracked files, so a stray output file is one `git add -A` from a red history |
| `586af63` | **middleware 2.18.1.** A token APNs rejects as `400 BadDeviceToken` is now removed, not retried forever. **Only that reason** — `BadTopic`/`PayloadEmpty` come back for every token, so removing on any 400 would empty the fleet on a bad deploy. Also corrects the `[1.0.0]` entry, which claimed this cleanup already existed; it never did |
| `c58bb41` | **PWA: the iOS banner links to the real App Store listing.** It pointed at `href="#"` for every iOS visitor. Says **BHNM**, the name on the page they land on. URL recorded in `docs/appstore-metadata.md`, since it was in neither the repo nor its history |
| `add4df2` | **PWA 0.17.1: the app shell loads offline.** `sw.ts` precached `index.html` but registered no `NavigationRoute`, so a reload replaced the app with the browser's error page — worst exactly when an on-call user taps a notification on a bad network |
| `51cfca3` | **Both platforms: Home status cards navigate.** Whole card is the target, chevron affordance, accessibility labels. iOS switches tabs rather than pushing a duplicate. "Active Incidents" lands filtered to match the number it showed. The PWA tile counted `severity critical\|major` under a label saying active — now `status === 'active'` on both |
| `3cc2fa0` | **iOS 2.13.3: Settings → API Configuration removed, with its three keys.** The API Version picker broke device-detail incidents on any value but `legacy`; Retry Count was read by nothing; Timeout was ignored by two of three timeouts. A one-time migration **deletes** the stored keys, because a phone left on `v1` would otherwise keep a broken path with no UI to fix it |
| `3c5b053` | **User-facing "BeNeM" → "BHNM"** across seven strings on the PWA. Console prefixes deliberately unchanged |
| `ae0f377` | **Rollback tag convention ruled** — see (g) |
| `6cabd24` | **THE BREAK.** Ack user replaced with the constant `"BHNM Mobile"` on both platforms. Wrong — see (f)19 |
| `3786b69` | **iOS 2.13.4: one save, one success signal.** The "Connection successful" card was the old Test Connection indicator, never removed when the alert arrived. The **failure** row stays: it outlives its alert, which is what keeps a bad URL on screen |
| `2fd88ff` | **PWA 0.17.2: a save states its verdict and waits for OK.** `onSave` navigated in the same tick it set the verdict, so `ServerForm` unmounted and **both result panels were dead code** — a successful save confirmed nothing, and "saved anyway, not verified" had never been seen by anyone |
| `d352084` | The anomaly rate is a hand-operated knob, not a health signal — see (c) |
| `81add37` | The build-44 inference **confirmed** by direct observation — see (d) |
| `c4e9a4d` | **THE REPAIR (PWA 0.17.3, iOS build 48).** Ack user restored to the per-connection QR Username on both platforms |
| `632738d` | The true history of the ack user, the two new rules, and `(e)3d` |

**Builds and where they are:**

- **middleware 2.18.1** — deployed 09:40:18Z, live.
- **PWA 0.17.1 → 0.17.2 → 0.17.3** — three deploys today; **0.17.3 is live**.
- **iOS 2.13.3 (46)** — installed on the 13 Pro Max, field-tested by Thomas: server edit and save
  work, the migration did not disturb the connection.
- **iOS 2.13.4 (48)** — built Release, **not installed, not released.**
- **iOS 2.13.2 (45)** — **with Apple**, submitted 2026-09-18. Store build is still 2.13.1 (36).

---

## (b) Deployed state — observed 2026-09-19T17:05Z

```
### /health (unauthenticated)
{"status":"running","version":"2.18.1"}

### PWA
bundle: /assets/index-C-R83G5t.js
"0.17.3"

### containers
benem-middleware StartedAt=2026-09-19T09:40:18.146Z Restarts=0
benem-pwa        StartedAt=2026-09-19T10:39:12.852Z Restarts=0
benem-admin      StartedAt=2026-09-18T10:40:39.233Z Restarts=0
benem-proxy      StartedAt=2026-09-14T15:36:58.253Z Restarts=0

### device_tokens
0c56a19b production
86587674 production
a53f7cc1 production
018ab51d production
10882c55 sandbox      <- the 13 Pro Max, since the Debug build of 2.13.3 (46)

### today
tracebacks: 0 | webhooks: 32 | APNs 400s since the 2.18.1 deploy: 0
```

**Rollback images:** `bhnm-apns-bhnm-apns:pre-2.18.1`, `bhnm-apns-benem-pwa:pre-0.17.1`,
`pre-0.17.2`, `pre-0.17.3`, plus `pre-0.17.0` (renamed from the mis-named `pre-0.16.3`) and
`benem-pwa:0.14.1` (rescued from two PWA images tagged with middleware version numbers; the image
was inspected before the bad names were deleted).

---

## (c) Lab state — observed 2026-09-19T17:05Z

Devices **searched by name, never counted**, per the root `CLAUDE.md` rule:

```
raspi-050    rows found: 1 | UP | lastUpdateTime 2026-09-19 19:05:11 | dur 2d 21h 10m 12s
BHNM-B-SE01  rows found: 1 | UP | lastUpdateTime 2026-09-19 19:05:09 | dur 3d 3h 39m 21s

0 in maintenance, 41 host rows, 0 down        (17:04:42Z)
incidents: 6 active, 0 closed, cache_age 45 s
  24951 OPEN DrayTek · 25076 OPEN · 25482 OPEN Windows_2016_Server
  27190 ACKNOWLEDGED raspi-059 · 27516 OPEN C9200CX · 29546 ACKNOWLEDGED Synology920
last webhook: 16:45:37Z, incident 29868, 6 targets
servers.json: 4 servers, 4 distinct keys
```

**The anomaly knob is ON as of 2026-09-19 10:00:00Z (12:00 CEST), and it is hand-operated in both
directions.** It was OFF overnight, which is why 2026-09-18 22:45Z → 2026-09-19 10:00Z is silent.
**That silence was not an outage and not a baseline.** From the middleware, "no webhooks arrived"
and "the setting is off" are indistinguishable, and nothing in the log separates them — **ask
before drawing any conclusion from a quiet period.** A reader comparing anomaly counts across days
is comparing a knob position, not the network.

**Incident 24951 was acknowledged and unacknowledged today** as the ack-attribution test (see (d));
it is back to `OPEN`, `acknowledged = 0`, `ack_user = ''`.

---

## (d) Verified vs unverified

### VERIFIED — measured, not argued

| thing | how |
|---|---|
| **The QR Username reaches BHNM as the acknowledging user** | end to end through the PWA's own middleware endpoint: incident 24951 `ack_user ''` → ack as `Thomas Android PWA` → BHNM reads back `ack_user = 'Thomas Android PWA'` → unacknowledged, state restored. Independently, incident **29546** already carried `ack_user = 'Thomas iPhone 13 ProMax'` from a real ack predating all of this |
| **PWA 0.17.3 is what is serving** | bundle hash **and** version both changed; `config.ackUser\|\|` appears twice in the shipped bundle |
| **middleware 2.18.1 carries the 400 branch** | read inside the running container: `apns.py:128`, and `inspect.getsource(apns.send_to_all)` on the live module |
| **iOS 2.13.3 (46) on the 13 Pro Max** | the **device** reports `BHNM com.tstolt.benem 2.13.3 46`. Thomas field-tested: edit and save work, migration did not disturb the connection |
| **Build 45's IPA was signed for production push** | unpacked and read: `aps-environment: production`, `get-task-allow false`, Apple Distribution. **The `.xcarchive` itself read `development`** — only the distribution re-sign flips it |
| **The build-44 environment mismatch** | two `[Register]` lines four minutes apart for the **same** token — `production` at 09:45:31Z from the old app, `sandbox` at 09:49:04Z from 2.13.3 (46). `device_tokens` stayed at 5 rows, which proves the token string is byte-identical (`INSERT OR REPLACE` keyed on token) |
| **2.18.1's `BadDeviceToken` cleanup — VERIFIED IN THE FIELD, first fire 2026-09-19T20:38:15Z** | deployed 09:40:18Z and never exercised until an Xcode **Release** install on the 13 Pro Max produced a token the production host refuses. Three lines, in order: `[APNs] Failed (400) via production: {"reason":"BadDeviceToken"}` → `[APNs] Token bad (400 BadDeviceToken) ...10882c55 env=production — removing` → `[Cleanup] Removed stale APNs token ...10882c55`. **`device_tokens` 5 → 4**, and the four survivors were untouched — the "only `BadDeviceToken`" narrowing did its job rather than emptying the fleet. Restored to 5 at 20:59:50Z by a Debug reinstall |

### NOT VERIFIED

| thing | why, and what would verify it |
|---|---|
| ~~**The 2.18.1 cleanup branch — DEPLOYED, NEVER FIRED**~~ | **MOVED TO VERIFIED 2026-09-19. It fired at 20:38:15Z.** See the VERIFIED table above and the mechanism below. |

#### WITHDRAWN 2026-09-19: "a Release build on the 13 Pro Max will strand the sandbox token"

**It does not, and the reason was already written in this file.** A Release build was installed on
the 13 Pro Max at 19:14Z (iOS 2.13.5 build 49) and launched. **[MEASURED]** `device_tokens` stayed
at **5 rows**, and the existing row simply flipped column:

```
2026-09-19 18:08:02,688Z [Register] Token saved: ...10882c55 for iPhone (APNs: sandbox)
2026-09-19 19:20:08,492Z [Register] Token saved: ...10882c55 for iPhone (APNs: production)
```

**Same token, byte-identical — only `apns_environment` changed.** APNs issues one device token per
device and app; Debug and Release do not get different token *strings*, they get different
*environments that will accept the same string*. §(d) VERIFIED already recorded exactly this
mechanism for build 44 — *"`device_tokens` stayed at 5 rows, which proves the token string is
byte-identical (`INSERT OR REPLACE` keyed on token)"* — and the prediction above was written
anyway, from the shape of the story rather than from the row.

#### AND THIS WITHDRAWAL WAS ITSELF WRONG — corrected 2026-09-19T20:38Z

**I withdrew the correct conclusion along with the wrong mechanism.** Written above at ~19:30Z:
*"No token is stranded… `device_tokens` will not drop to 4… the 2.18.1 cleanup branch is still
DEPLOYED AND NEVER FIRED."* **All three are false.** 78 minutes later:

```
2026-09-19 20:38:15,640Z [APNs] Failed (400) via production: {"reason":"BadDeviceToken"}
2026-09-19 20:38:15,641Z [APNs] Token bad (400 BadDeviceToken) ...10882c55 env=production — removing
2026-09-19 20:38:15,643Z [Cleanup] Removed stale APNs token ...10882c55
device_tokens: 4 rows
```

**2.18.1 fired, for the first time, and it did the right thing.** The original prediction was
wrong about the *mechanism* (no new token string, no extra row) and **right about the outcome**
(a 400, the cleanup, four rows). Discarding the outcome because the mechanism was wrong is the
error, and it is the second unforced one on this single token in one session — both times from
reasoning about the mechanism instead of waiting for the row.

#### The real mechanism — [MEASURED 2026-09-19, not inferred]

**An Xcode-installed Release build declares `production` while holding a `development`
entitlement, so its token is a sandbox token sent to the production host.**

| fact | evidence |
|---|---|
| the installed binary's entitlement is **development** | `codesign -d --entitlements -` on the installed `BeNeM.app`: `aps-environment` = `development`; the embedded profile agrees |
| the app declares **production** | `AppDelegate.swift:132-136` — `#if DEBUG` → `"sandbox"`, `#else` → `"production"`. A local Release build takes the `#else` branch |
| APNs refuses it at the production host | `400 BadDeviceToken`, above |

The token string really is the same across Debug and Release — that part of the withdrawal holds.
**What is environment-specific is not the string, it is which host will accept it**, and that is
decided by the *entitlement*, not by the build configuration.

#### The latent defect this exposes — NOT FIXED, reported

**`AppDelegate` infers the APNs environment from the BUILD CONFIGURATION rather than from its own
entitlement.** Those are different things, and `-configuration Release` from Xcode is precisely
the case where they disagree. `2026-09-18`'s record already said *"the `.xcarchive` itself read
`development` — only the distribution re-sign flips it"*, which is the same fact seen from the
other end.

**RULED 2026-09-19 (Thomas): FIX IT. Next client wave, not now.**

> Read `aps-environment` from the **embedded provisioning profile at runtime**. **No profile means
> App Store, which means `production`.** The app states what it holds, not what its compiler flags
> imply.

**[MEASURED]** The profile is at `BeNeM.app/embedded.mobileprovision`, a CMS-signed plist —
`security cms -D -i` decodes it, and `Entitlements.aps-environment` is the key. A store build has
no `embedded.mobileprovision`, which is exactly why "absent ⇒ production" is the right default
rather than a guess.

Replaces `AppDelegate.swift:132-136`. The `#if DEBUG` fork is the **only** behavioural
Debug/Release fork in the app (2026-09-18 §(d)), so this removes it entirely — after which a
build's configuration no longer changes what the app tells the middleware about itself, and the
Debug-vs-Release install distinction stops being a push hazard.

**Not built in this wave.** Recorded here and in the build order as the first item of the next
client wave.

#### Practical consequences

- **Any Xcode Release install kills push on that phone** until the row is re-registered, and the
  re-registration re-creates the same broken row: launch → register as `production` → next
  incident 400s → removed → launch → … It flaps rather than settling.
- **A Debug install works** — it declares `sandbox`, which matches the `development` entitlement.
  That is why 2.13.3 (46) delivered and 2.13.5/2.13.6 do not.
- **A TestFlight or App Store build works**, because the distribution re-sign flips
  `aps-environment` to `production` and the declaration becomes true.

#### Restored 2026-09-19T20:59:50Z — [MEASURED]

A **Debug** build of the same 2.13.6 (50) source was installed on the 13 Pro Max and launched:

```
2026-09-19 20:59:50,710Z [Register] Token saved: ...10882c55 for iPhone (APNs: sandbox) …
device_tokens: 5 rows   (…10882c55 sandbox, back)
no 400 since
```

**`sandbox`, matching the `development` entitlement** — the two agree again and push delivers.
The device still reports `BHNM com.tstolt.benem 2.13.6 50`; only the configuration differs, so
the deep-link work is on the phone and testable. **The cost of the Debug install is
optimisation-level coverage only** — Release compiles `-O` against Debug's `-Onone`, and the
step 4b code has no build-configuration branch.

**Note on timestamps here:** `device_tokens.registered_at` and the log are **UTC**; the laptop is
CEST (+2). A launch at 22:59:49 local is the 20:59:50Z row. Written down because an earlier grep
in this session filtered a UTC log with a local timestamp and returned an empty result that the
row beside it disproved.
| **iOS build 45 has never run on any device** | submitted straight to review with no TestFlight install, by decision. The changed code has no build-configuration branches, so the residual gap is **optimisation level only** — Release `-O` against the field-tested Debug `-Onone`. That is a conclusion from a grep, not from a running app |
| **iOS build 48 is not installed** | built Release only. Nothing on a device has exercised the removed "Connection successful" card or the restored ack user on iOS |
| **The `"BHNM Mobile"` fallback in the field** | reachable but never observed firing. See (e)3d — it needs a QR generated with an empty Username |
| **Everything in the 09-18 handoff's NOT VERIFIED table** | carried forward unchanged: Steve's and Luiz's clients, the inconclusive verdict branch, `/internal/cache/reload` after the rotation, a RECOVERY while an override is PENDING, S1 1b per-server isolation |

---

## (e) Parked items, RANKED

**Carried forward from the 09-18 handoff (e)** — that list is still the authority for items 1, 2
and 4–9. Today's additions are marked NEW.

1. **Credential strength — rotate the short api_keys.** `ThomasLabServer` 15 chars, `Luiz` 9. Both
   too short to mask safely. Touches `servers.json`, the QR codes and the phones.
2. **§8.8 coverage-visibility, decision 1** — now the single next action, see (h).
3. **Smoke-test build 45 via TestFlight once processed** — optional, minutes, and it is also the
   event that would verify the 2.18.1 branch (see (d)).
3b. **NEW — the 10 s / 15 s timeouts are now the whole timeout policy.** The Settings slider is
   gone (`3cc2fa0`), leaving `NetreoAPIService.swift:182` (diagnostics, 10 s) and
   `ServerConfigView.swift:324,356` (save probe, 15 s), chosen independently and never compared.
   The 10 s is the value in the iPhone 15 stall signature. **Rule all three as a set.**
3c. **NEW — the PWA incident list has no filter at all.** `IncidentListScreen.tsx` renders every
   incident sorted by id, so the "Active Incidents" tile lands on the full list where iOS now lands
   filtered. **If that list includes closed incidents the change belongs to the list, not the
   tile.** Unruled.
3d. **NEW — the admin portal's Username field: the hint, and the enforcement.** It says
   `e.g. Thomas` and nothing about what it is for; a phone name was typed into it because nothing
   said it would appear in BHNM as the acknowledging user. **One line under the field — "shown in
   BHNM as the user who acknowledged" — would have prevented (f)19.** And it is required in
   **JavaScript only**: `main.py` declares `user: str = Form("")`, so a QR can carry `"user": ""`,
   which both clients turn into the fallback (`DeepLinkHandler.swift:215` casts `""` successfully;
   `qr-parser.ts:61` treats `''` as falsy) — and **QR import bypasses the form on both platforms**.
   Do **not** fix it by deleting the client fallback: an empty username makes BHNM record the ack
   as nobody.
4. Caddy's error log stores full request headers, `X-Proxy-Token` and `Cookie` included.
5. The five unlogged refusal paths — 401, 400, 502.
6. Restricting `/health` to the Docker network.
7. The incident cache cost model note — written, unshipped.
8. The 2.15.2 recovery-while-pending field check — two minutes.
9. **EXTERNAL — BHNM tickets.** Not ours to fix.

**Also carried, low:** iOS `notificationsEnabled` → `pushEnabled`, approved as canonical and
deliberately not renamed — **apply at the next natural touch of each file**, with a
`decodeIfPresent` fallback. S1 spec Part 12.

---

## (f) Withdrawn claims and known-wrong beliefs

**Items 1–18 are in the 09-18 handoff §(f) and still stand.** Do not resurrect them — in
particular **"the Service Engine sends webhooks"** (it does not), **"anomaly incidents cannot
page"** (they can), and **"the rotation's blast radius is one diagnostic button"**.

### New today

19. **"The ack user reads as the device name, so the device-name path is winning over the QR
    username."** **Wrong, and it was never true.** `Thomas iPhone 13 ProMax` and
    `Thomas Android PWA` are the **QR Usernames typed into the admin portal** — its own link log
    records them (`/app/log/admin.jsonl`, issued 2026-09-15T10:48:24 and 2026-09-02T13:53:03).
    Both clients had been sending the per-connection `ackUser` correctly and continuously: iOS
    since before the monorepo move (`57a8e6e`, 2026-04-05), the PWA since `4ec53db` (2026-04-08).

    **There is no commit where the track was lost, because it was never lost.** The archaeology
    returned nothing: `UIDevice.current.name` has one use, the `device_name` field of the **push
    registration** payload, and has never touched an ack.

    **The failure is on the reviewer's side of the loop.** An assertion was offered in review as
    though it were a measurement, accepted without a check, a constant was ruled on it, **0.17.2
    shipped the break** and **0.17.3 shipped the repair** — a released build lost per-person ack
    attribution in between. The record that settled it was one `docker exec` away the whole time.

    Full detail in the 09-18 handoff §(f)19, which carries the evidence inline.

---

## (g) Rules added today — pointers, not restatements

- **Root `CLAUDE.md`** — *`pre-<version being deployed>` holds the version that was running before
  it.* Ruled canonical because the middleware already worked this way and the PWA did not, so the
  next deploy would have had to guess.
- **Root `CLAUDE.md`** — *the ack user is the QR Username, and it is not decorative.* Names the
  path from the admin portal's required field through to BHNM, with the `admin.jsonl` evidence and
  both test files, and says explicitly not to replace it with a constant.
- **`middleware/CLAUDE.md`**, beside *never trust a silence* — *an empty result must first be shown
  capable of returning a non-empty one*, and *an assertion must first be shown to have been
  checked*. Both carry their instances from today: a watch whose filter matched a startup banner, a
  probe that read `d["incidents"]` when the key is `active_incidents` and reported an empty lab
  while the log beside it said `Cache updated: 6 active`, and (f)19.

---

## (h) The single next action

**Phase 2 — the decision sitting. Nothing is built in Claude Code before that ruling arrives.**

Thomas rules the **~15 open decisions across four design notes**, from a brief, away from the
keyboard:

| design | open |
|---|---|
| `specs/2026-09-16-coverage-visibility-design.md` | 3 |
| `specs/2026-09-16-push-relay-design.md` | 4 — including *is the relay a product at all* |
| `specs/2026-09-16-incident-cache-cost-model-design.md` | 5 of 6 |
| `specs/2026-09-16-engine-down-stale-data-design.md` | 3 of 4, plus an **OPEN FORK** that decides the feature's shape |

All four are **STOP AT DESIGN**. No build may start from any of them.

**The first act in Claude Code after the ruling is §8.8 decision 1** — the read-only probe of
whether the BHNM API exposes action-group assignment. It needs no lab change and no deploy, and it
decides whether BeNeM can state its coverage as fact or must admit it cannot know. Deferred three
times already.

**What must be true before it starts:**

1. **Thomas's ruling is in hand.** This is the gate; there is nothing to do in CC without it.
2. **Nothing is mid-deploy.** Currently true: middleware 2.18.1 and PWA 0.17.3 live and verified,
   tree clean, `local == remote`.
3. **It is read-only.** No lab change, no deploy, no `servers.json` edit. If a step seems to need
   one, stop and re-read the design.
4. **The reader has read (d) NOT VERIFIED, (f), and the 09-18 handoff's (f) 1–18.**
5. **Counts are not evidence in the BHNM UI.** Search for the object by name; the Actions
   Administration counter has been wrong twice.

**Do not start §8.8's build** — STOP AT DESIGN until decisions 2 and 3 are ruled. **Do not rotate
the short api_keys** without a plan. **Do not install or release iOS build 48** — it waits.
