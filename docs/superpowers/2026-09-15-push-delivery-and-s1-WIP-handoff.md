# Push Delivery, S1 and Incident Freshness — WIP Handoff

**Date:** 2026-09-15, updated **2026-09-16 after an overnight run**.
**Status:** CHECKPOINT — code and docs clean, **the lab is NOT restored.**

Nothing is half-built. Everything in the repository is committed, pushed and green. But two
things are deliberately left for the morning and must be read before anything else:

> ### State at 2026-09-16 07:52Z — measured, not remembered
>
> **The lab is healthy.** `raspi-050` answers 2/2 pings at 1.1 ms, BHNM's `host_down` list is
> empty, and no incident exists for `raspi-050`, `BHNM-B-SE01` or `Miele-T1`. Thomas reconnected
> the Pi before sleeping; BHNM has shown it reachable since ~00:25Z.
>
> An earlier version of this section claimed the Pi was "still unplugged" and the Service Engine
> "down as a result". **Both wrong**: the state was stale and the causality inverted. See evidence
> §8.12 — the Service Engine manages all devices, so an SE outage *causes* device-level symptoms
> and is never the effect of one host being unplugged.
>
> **One thing is genuinely open:** middleware **2.15.2 is committed and pushed but NOT deployed**.
> Live is **2.15.1**. The undeployed change is the ACK cache-patch fix (queue item 12), whose
> diagnosis is now confirmed by measurement — see §8.11. Deploy needs a human present; runbook in
> `middleware/CLAUDE.md`.

---

## a. State in one paragraph

BeNeM is a network monitoring and incident alerting app built on **BMC Helix Network Management
(BHNM)**, whose job is delivering timely push notifications to on-call engineers. A monorepo at
`/Users/thomasstolt/dev/BeNeM`: `ios/` (Swift/SwiftUI, App Store, the lead platform), `pwa/`
(React/TypeScript, Android via Web Push), `middleware/` (Python/FastAPI, ingests BHNM webhooks
and delivers APNs + Web Push), `shared/` (specs). The middleware runs in Docker on a Linode at
`bhnm-apns.hurrikap.org` behind Caddy, with `benem-admin` (admin portal), `benem-pwa` and
`benem-proxy` alongside. The lab BHNM is `bhnm-b.tstolt.com` → `192.168.2.211` on the LAN,
version **26.3**. What shipped this week: **middleware 2.14.0**, which fixed a delivery fan-out
that only ever served one device, plus credential hygiene, test-collection and documentation
corrections — 18 commits, all pushed, detailed in `middleware/CHANGELOG.md` and
`docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md`.

---

## b. Lab and deployment state (verified by observation, 2026-09-16 ~00:2x UTC)

| check | result |
|---|---|
| middleware live version | **2.15.1**, `/health` `running`, 3 registered devices + 1 Web Push subscription |
| middleware repo version | **2.15.2 — pushed, NOT deployed** |
| `raspi-050` | **UNPLUGGED.** Incident 29586 open and ACKNOWLEDGED |
| `BHNM-B-SE01` | **DOWN** — Service Engine, incident 29585, a consequence of the above |
| `servers.json` | all four servers seeded with `webhook_secrets`, fingerprint `95e54469` |
| `/etc/hosts` workaround | **removed and confirmed** (`grep` empty, `curl` fails to resolve) |
| middleware suite | `python -m pytest tests` → **208 passed**, exit 0 |
| PWA suite | `npx vitest run` → **405 passed**, exit 0 |
| admin suite | **34 passed**, exit 0 — needs its own venv, see `docs/DEVELOPING.md` |
| git | everything pushed through `f40e5b8`. `git status --porcelain` shows only ` M CLAUDE.md`, Thomas's own table reformat, deliberately untouched |

### Observed since — the RECOVERY contrast is in (§8.11)

The experiment ran unattended. raspi-050 recovered at 22:19:03Z and logged
`[Webhook] RECOVERY … Cache patched: incident 29586 -> CLOSED (1 server(s))` — **the same
incident id whose acknowledgement 72 minutes earlier produced no patch at all.** A second
independent instance followed overnight (Miele-T1, 29620, PROBLEM 05:50:25Z → RECOVERY 06:02:43Z,
patched). Item 12 is localised exactly: the ACK branch is not broken, the incident simply was not
cached yet. No further outage is needed to justify 2.15.2.

### Still unobserved / unmeasured

- **The BHNM Action configuration** (§8.10) — which devices or groups the `BeNeM` group is
  attached to, and its notification criteria. Four attempts through the browser extension failed
  to open Administration → Actions; no URL for it is recorded. **Needs a human with the UI.**
- **How long BHNM takes to detect a host down.** The earlier "~30 minutes" figure is **withdrawn
  as contaminated** — it spans a window in which the Service Engine was down. Unmeasured.

## b-old. Lab and deployment state (verified by observation, 2026-09-15 ~19:30 UTC — superseded)

| check | result |
|---|---|
| BHNM temporary objects | **none.** Searched Actions Administration for `temporary` → *"No actions match your search"*; for `8787` (the capture listener port) → no matches. Searching for `BeNeM` returns the `BeNeM` group with **exactly one** action, `Mobile BeNeM Notification`, one WEBHOOK method, SSL enabled, Auth Token disabled, 24X7, its original 16-field payload — untouched all week. |
| capture listener | **stopped.** No `capture_listener.py` process; TCP 8787 free. |
| `caffeinate` assertion | **released.** The `caffeinate -dimsu` started for the measurement is gone. Assertions still shown belong to `screensharingd`, the Claude app and `powerd` — unrelated. |
| middleware live version | **2.14.0**, `/health` reports `running`, 3 registered devices + 1 Web Push subscription. |
| containers | `benem-middleware`, `benem-admin`, `benem-proxy`, `benem-pwa` all up. |
| `PROXY_TOKEN` | **NOT rotated.** It is still byte-identical to `WEBHOOK_SECRET` — deliberate, see decision 9 in the S1 spec. Nothing is half-done here; rotating is a decision, not an unfinished task. |
| middleware suite | `cd middleware && python -m pytest tests` → **181 passed**, exit 0. |
| git | everything pushed. `git status --porcelain` shows only ` M CLAUDE.md`, which is **Thomas's own table reformat**, deliberately left alone. |

The three registered devices are `...0c56a19b` (iPhone 13 Pro Max, Thomas private), `...018ab51d`
(iPhone 15, Thomas work), `...86587674` (iPhone 13 Pro, Jonah), plus one FCM Web Push
subscription (Android, "Edge 60").

---

## c. The queue

**Numbers are stable identifiers, not priority.** Several other documents cite them
(`middleware/CHANGELOG.md`, the S1 spec), so items are never renumbered when priority changes.
Priority is stated here and here only.

**Priority order, 2026-09-16:**
**11** → **13** → 1 → 2 → 3 → 4 → 5 → **12** → 6 → 7 → 8 → 9 → 10.

Item 13 sits second by importance but may ship before 11: it is plausibly a small change (the
freshness field is already fetched), whereas 11 may end in an admission rather than a fix.

Item **11 (coverage visibility) is the most serious open item in the project** and sits above the
push relay spec (6) and the admin device overview (7). Item **12** sits above them too: it is a
small fix to a defect that makes a core feature work only on incidents older than two minutes.

1. **Two device measurements — BLOCKED ON THOMAS.** Both need one phone, the lab and the
   middleware log, batched into one sitting. Runbook, ready to run with no composing on the day:
   **`docs/runbooks/2026-09-15-one-sitting-device-measurements.md`**.
   - *Measurement 1 — the unregister A/B*: does switching notifications off in the app actually
     stop the paging? Timing-sensitive: toggle off within a second of launch vs after ten.
   - *Measurement 2 — 401 versus dead network*: what each client shows when the credential is
     refused versus when the network is gone. Decides whether stale-data-while-disconnected is
     already a defect. The PWA half can be done in a browser without Thomas.
2. **S1 change 1 — per-server secret split + rotation/allowlist — STOP-AT-DESIGN APPROVED,
   build not started.** `docs/superpowers/specs/2026-09-15-webhook-secret-header-auth-design.md`
   Parts 5 and 17.
3. **S1 change 2 — header transport — STOP-AT-DESIGN APPROVED, build not started.** Same spec,
   Parts 2–4. **Its gating measurement is done and passed** (spec Part 6 / evidence "Part 6"):
   `[header]` works on a plain WebHook method, a 64-character value survives intact,
   `Authorization` survives with `AUTHORIZATION TOKEN = None`, header block and JSON body
   coexist, and `Content-Type: application/json` arrives correctly.
4. **Incident freshness, three parts — DESIGN WRITTEN, AWAITING APPROVAL.**
   `docs/superpowers/specs/2026-09-15-incident-freshness-design.md`. Ships Part 3 (the four
   states) first.
5. **Revocation + verified registration state — DESIGN WRITTEN, AWAITING APPROVAL.** Same S1
   spec, Parts 10, 11, 18.
6. **Push relay — DESIGN WRITTEN 2026-09-16, awaiting approval. STOP AT DESIGN.**
   `docs/superpowers/specs/2026-09-16-push-relay-design.md`. Targets the encrypted variant (relay
   sees a token, a tenant id and an opaque blob); the plaintext variant is documented only to be
   rejected, and sharing the `.p8` is rejected outright.
   Two things the design establishes that were not obvious: **Android self-hosters need no relay
   at all** — Web Push has no vendor binding, so this is an iOS-only construct — and the existing
   QR already provides a key channel from the customer's server to the device that bypasses the
   relay. Four decisions for Thomas at the end, the first being whether the relay is a product at
   all or whether "publish your own build" is the honest answer for iOS self-hosters.
7. **Admin portal device overview — READY TO START.** Extend the existing Push Config page in
   `middleware/benem-admin/`; do not add a screen.
8. **Delivery-queue monitoring — DESIGNED, NOT BUILT.** Two paired changes, designed 2026-09-15
   and recorded *only* in `middleware/CHANGELOG.md` under 2.14.0 "Known issue — carried forward",
   which is why they appeared in neither this queue nor the parked list until now. The changelog
   entry is the pointer; it holds the full design and is not restated here.
   - **Stale-job discard.** The queue discards by count, not age, so an APNs stall delivers pages
     after they stop mattering. Stamp arrival time on enqueue, discard on dequeue anything older
     than **5 minutes** — longer than BHNM's own Incident Close Delay Timer, still inside the
     window where an engineer wants waking — logging `[Deliver] STALE`.
   - **Warn on estimated drain time, not queue depth.** Depth is the wrong unit: a job fans out
     to every device, so the quantity is `queued_targets × per_send_seconds` (EWMA, seeded 0.15).
     **Warn above 60 s**, an order of magnitude below the discard threshold. `queued_targets` must
     be decremented on *every* exit path or the warning latches on permanently. Expose both in
     `/health` and `/api/v1/diagnostics`.

   The changelog calls this "next in line" after 2.14.0. **Its position in this queue is
   unruled** — placed last only because that is where unranked items go, not as a priority claim.
9. **PWA cannot open offline — DESIGNED, NOT BUILT. Do not fix now.** `pwa/src/sw.ts` calls
   `precacheAndRoute(self.__WB_MANIFEST)` and **registers no `NavigationRoute`**, so a navigation
   is never served from the precache. Measured 2026-09-15: with DNS for `benem.hurrikap.org`
   failing, an already-open PWA kept running from the precache, but **reloading replaced the app
   with Chrome's `DNS_PROBE_FINISHED_NXDOMAIN` page**. An installable PWA whose users are on-call
   must open when the network is bad — that is when they tap the notification.
   **Adjacent to the stale-data work, not separate from it:** both are the same question of what
   the app does when it cannot reach the server, and the four-state work in the incident-freshness
   spec Part 3 assumes the app is *on screen* to show a state at all. A shell that will not load
   has no state to render.
   Fix shape: register a `NavigationRoute` bound to the precached `index.html`
   (`createHandlerBoundToURL('/index.html')`), so the shell always loads and the four states then
   do their job. Small; it is queued rather than done because it is not what is being shipped now.
10. **PWA Refresh hangs forever while offline — DEFECT, not fixed.** Measured 2026-09-15.
    `IncidentListScreen.onRefresh` is `await queryClient.invalidateQueries({queryKey:['incidents']})`
    followed by `await refetch()`. While React Query has the query paused, neither promise ever
    settles, so **the control hangs indefinitely with no timeout and no feedback** — the tap does
    nothing, nothing spins, nothing errors, and the user has no way to tell the refresh from a
    refresh that silently did not happen. Observed as two CDP evaluations timing out at 45 s after
    the tap, with the UI unchanged throughout.
    Why it matters beyond the annoyance: this is the *one* control a user reaches for when they
    suspect the data on screen is stale, which is exactly the situation it fails in. Fix shape:
    bound the refresh (timeout, or don't await a paused query) and give the control a terminal
    state — refreshed, or couldn't. Belongs with the incident-freshness Part 3 work, which now
    owns the list screen and the badge.
11. **Coverage is scoped inside BHNM and invisible from BeNeM — HIGHEST PRIORITY. Needs a design.**
    Design: `docs/superpowers/specs/2026-09-16-coverage-visibility-design.md`.
    Evidence: `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` §8.8.

    **The action group covers host-down only, while the incident list displays service checks,
    thresholds and anomalies too — with nothing marking which entries would ever reach a phone.**
    Measured from the deployment's own logs: every incident that has ever produced a webhook is a
    host event (29499, 29517, 29570, 29586), while the list at that moment held **18 active
    incidents, 16 of them types that have never caused a phone to ring** — 4 service, 2 threshold,
    10 anomaly, all rendered identically to the one row that would.
    An earlier draft rested this on 29585 (`BHNM-B-SE01`) producing no webhook. **Withdrawn:**
    that was the Service Engine crashing, and the SE is what fires actions, so no webhook is
    expected — correct behaviour, and the scenario the connection badge and two-hop diagnostics
    exist to surface. The finding is stronger without it: it is now about what the product
    displays, measured from its own logs, depending on no unestablished BHNM configuration.

    **This is not a fourth instance of the "never render unverified state as healthy" doctrine,
    and must not be filed beside the other three.** Those all rendered unverified state as healthy
    *somewhere a person could look* — a device icon, a status label, a toggle. Each had an
    affordance that made a claim, and the fix is to make that affordance tell the truth.

    **Here the failure mode is a phone that does not ring.** *Absence of a page* is
    indistinguishable from *absence of an incident*, and both look exactly like a quiet night.
    There is nothing on screen to doubt. The incident list is the nearest affordance and its
    defect runs the *opposite* way — it shows more than it will ever tell you about, so it
    reassures rather than alarms. A perfectly fresh, perfectly verified list of eighteen incidents
    is what a user sees today, and it is still misleading; no badge or timestamp reaches that.

    That is why it outranks everything else open: a paging product's entire value is the
    difference between "nothing is wrong" and "I was never going to hear about it", and BeNeM
    currently cannot express that difference at all.

    Minimum fix is documentation — `INSTALL.md` §7 does not tell an administrator to attach the
    action group to everything they expect to be paged about. That is not the fix, only the stop-
    gap. The real question the design has to answer: **what can BeNeM know about its own coverage,
    and what should it say when it cannot know?**
12. **The ACK cache patch silently no-ops for an incident the cache has not seen — DEFECT.**
    Measured 2026-09-15 (§8.9). `note_state_override_any_server()` patches only servers whose
    cache already holds the incident and returns the count; `main.py` logs `if n:`. An incident
    acknowledged before its first cache cycle therefore gets no override, no log line and no
    error. 29586 was raised at 22:05:23 and acked 93 s later, inside the 120 s refresh window.
    In the whole persisted log `Cache patched` appears three times and **every one is
    `-> CLOSED`** — zero observations of the ACKNOWLEDGED path working, against three of
    RECOVERY.
    It is the fast-acknowledgement case a paging product must expect: somebody is woken, looks,
    and acks within two minutes. Fix shape: record the override keyed by incident id whether or
    not the incident is cached and apply it when the incident first appears (the override already
    has a 5-minute TTL, two cycles), and make the zero-patch case loud — an unchecked return
    value of zero is how this stayed invisible.
13. **What BeNeM shows when the engine behind the data is down — DESIGN WRITTEN 2026-09-16.**
    `docs/superpowers/specs/2026-09-16-engine-down-stale-data-design.md`. **STOP AT DESIGN.**
    Measured in a controlled outage (§8.13/§8.14): devices **retain their last state** while the
    Service Engine is down — all four watched devices read `UP` with `lastUpdateTime` frozen for
    26 minutes — and BeNeM renders that green faithfully. Unverified state presented as healthy,
    originating a layer below anything BeNeM checks: the two-hop diagnostics verify the middleware
    reaching BHNM's *front end*, which answers perfectly while the engine is dead.
    **The hinge is measured and favourable:** `lastUpdateTime` **stalls**, so staleness is
    detectable from a field the middleware already fetches and discards, without identifying the
    engine. Open fork on `bhnm-apns.hurrikap.org` (stale a week, no outage) — do not close it.
    Service Engine **groups** reshape this (failover should keep timestamps advancing — a
    prediction, not a measurement); a planned measurement is written up, not scheduled.
14. **iOS renders a wrong incident duration, and cannot know it is wrong — DEFECT, not fixed.**
    Found 2026-09-16 during the 2.15.2 field test.
    `ios/BeNeM/Services/NetreoAPIService.swift:1273` parses `open_time` with two ISO8601
    formatters and falls back to **`?? Date()`**. `open_time` arrives as `"2026-09-16T21:42:12"`
    with no `Z` and no offset, both parsers fail, and the start time silently becomes **the moment
    of parsing** — so every duration reads as "time since the app last refreshed".
    **Measured, with a cross-platform control:** at 19:55:21Z incident 29656 was **13m 09s** old;
    **iOS showed 3m, the Android PWA showed 13m**, from identical data and middleware. The
    giveaway was ordering — the *oldest* incident showed the *smallest* number, which no timezone
    offset can produce. The PWA is right because it accepts more shapes:
    `coerceStartTime(row.start_time ?? row.startTime ?? row.incident_open_time ?? row.open_time)`.
    **Second defect, same root:** `ios/BeNeM/Models/IncidentDetail.swift:111` reads
    `incident_open_time`, while the cached list payload carries `open_time` — so the detail
    screen's *Created* and *Duration* rows are wrong or blank too.
    **Doctrine, not tidy-up:** a failed parse is rendered as a confident "3m" — no dash, no
    "unknown", no sign anything failed. The green badge hidden inside a `??`.
15. **A stale BHNM URL makes the app list incidents it cannot open — DEFECT, not fixed.**
    Found 2026-09-16. Thomas's iPhone 15 (`…018ab51d`) held a connection pointing at
    `https://vpn.hurrikap.org:8888` — an address the lab has since moved away from, in no
    `servers.json` entry, unreachable from the middleware.
    The phone **listed** incident 29656 but spun and failed to open it with *"The request timed
    out."* Nine `[Proxy] Timeout` lines in thirty minutes, each burning the full 60 s
    `PROXY_TIMEOUT`.
    **The defect is not the stale address — it is that two code paths on one device resolved to
    two different servers.** The list resolves by `api_key` → the lab → works; the detail sends
    `X-BHNM-Target` → the dead host → times out. Same family as incident-freshness Part 2: *two
    identifiers, two resolutions, no cross-check.* And the error said "timed out" where the truth
    was "this connection's server address no longer exists".

---

## c2. Decisions waiting for Thomas, 2026-09-16

Collected from the overnight run. **None was guessed at**; each is recorded where the work stopped.

**Operational, this morning:**

1. **Restore `raspi-050`** and confirm `BHNM-B-SE01` recovers. Watch for the RECOVERY webhook.
2. **Deploy 2.15.2** (ACK cache-patch fix), or hold it.
3. **Read the BHNM Action config** (§8.10) — the one measurement neither the extension nor the API
   could reach, and the thing that turns the coverage finding into a fix.
4. **Rotate `PROXY_TOKEN`?** Ruled *yes* on 2026-09-15 with a six-step procedure in the S1 spec,
   decision 9. Never executed. Still outstanding.

**Coverage visibility** — `specs/2026-09-16-coverage-visibility-design.md`:

5. Approve the read-only measurement of whether the BHNM API exposes action-group assignment? It
   decides the shape of the whole fix.
6. If coverage proves unknowable, is the onboarding sentence acceptable product copy?
7. Does the incident list get the per-row marker, or is Diagnostics enough for now?

**Push relay** — `specs/2026-09-16-push-relay-design.md`:

8. **Is the relay a product at all**, or is "publish your own build" the honest answer for iOS
   self-hosters? Android self-hosters need nothing.
9. Paid or free, decided before building?
10. Per-device or per-server encryption key, with its rotation story attached?
11. Approve the NSE measurement as the only next step?

**Incident freshness** — `specs/2026-09-15-incident-freshness-design.md`:

12. Approve the copy for the state strings — now **five** states, not four; the fifth is *paused*.

## d. Open decisions — recorded, do not re-derive

**These have been argued out already. Do not reason them afresh from first principles — read
them, and ask Thomas for a ruling.**

- **`docs/superpowers/specs/2026-09-15-webhook-secret-header-auth-design.md`, "Decisions needed
  from Thomas": numbers 1–10.** Includes the canonical name `pushEnabled`, whether to rotate
  `PROXY_TOKEN` now, whether `PROXY_TOKEN` should exist at all, and the Part 13 measurement
  sitting.
- **`docs/superpowers/specs/2026-09-15-incident-freshness-design.md`, "Decisions needed":
  numbers 1–4.** Interim server resolution, debounce interval, UI copy tone, and whether the
  fetch route accepts prefixed ids.

---

## e. Parked, with why

| item | why parked |
|---|---|
| `400 BadDeviceToken` cleanup | Only `410` triggers token removal, so a `400` token is retried forever. Real but low impact; queued behind the above. Evidence follow-up 3. |
| Android heads-up banner | Notifications arrive in the shade rather than as a banner — a notification-channel importance setting. Not yet prioritised. |
| Richer BHNM macros spec | Superseded in urgency by the delivery defects; no ruling yet. |
| `ServerConfigView.swift:309` sending the push secret as `X-Proxy-Token` | The one-line client fix is necessary but not sufficient — see the S1 spec Part 18. Waits on the decision about `PROXY_TOKEN`. |
| iOS rename `notificationsEnabled` → `pushEnabled` | Approved as canonical but **deliberately not renamed yet**; apply at the next natural touch of each file, with a `decodeIfPresent` fallback. S1 spec Part 12. |

---

## f. Doctrine added this week — read before designing any UI or touching the lab

Both are in the repository root **`CLAUDE.md`**:

- **"Doctrine: never render unverified state as healthy."** Three states always — verified good,
  verified bad, and *unverified* — with the third given its own appearance. Written as a rule
  because it shipped three times in three different places.
- **"Verifying a change in the BHNM lab."** Search for the object by name. **Never trust the
  count.**

---

## g. Working standards that are not obvious from the code

- **"Verified" means measured.** Not "the code looks right", not "the test passes in principle".
  State plainly what was observed and what was inferred, and label inconclusive results as
  inconclusive rather than rounding them up.
- **iOS "verified" means run on a device against the lab.** A simulator build only proves it
  compiles. Commits may exist before that; pushes may not.
- **Disclose inconclusive and negative results**, including one's own refuted hypotheses. Several
  findings this week came from a prediction being written down first and then failing.
- **Run the whole middleware suite**: `cd middleware && python -m pytest tests`. Gate on pytest's
  own exit code with **no pipe** — a commit chain gated on `tail` once committed a red suite.
- **Stage explicitly and split commits by content.** Never `git add -A`; the tree often carries
  unrelated pre-existing changes (`CLAUDE.md` right now). Show `git diff --cached` and stop for
  approval before committing anything that is not a deploy prerequisite.
- **This project's reviewer is a separate Claude session.** Its rulings reach the working session
  relayed by Thomas. Treat them as decisions, not suggestions — and when one rests on a wrong
  premise, say so with the measurement rather than complying silently.
- **Never echo the webhook secret**; redact before any screenshot. Do not test a redaction filter
  with the string it is meant to redact.
- **Dump `docker logs` before every deploy** — the runbook is in `middleware/CLAUDE.md`; dumps
  live in `/root/logdumps/` on the VPS.
- **Run `date`** rather than inferring the time.
- BHNM ack/un-ack buttons open a native `prompt()` that freezes the Chrome extension — a human
  must click those.

---

## h. Traps that cost time this week

| trap | where |
|---|---|
| `incident_time` carries the **original** incident time on a RECOVERY, not the recovery time — outage duration cannot be computed from it | `shared/push-payload-spec.md` (warning at the top of the payload section) |
| A stale `.git/index.lock` silently fails `git mv` with "Another git process seems to be running" when none is | repository root `.git/index.lock` — delete it after confirming no git process is live |
| `pytest tests` did not collect root-level test files, so `middleware/test_webpush.py` sat red unnoticed | fixed — the files moved into `middleware/tests/`; noted in `middleware/CLAUDE.md` |
| The BHNM Actions counter is wrong — it read 18 after deleting one from 17, while the Methods counter tracked correctly | repository root `CLAUDE.md`, "Verifying a change in the BHNM lab" |
| A Mac set to `sleep 1` on **both** battery and AC will kill a capture listener mid-measurement and produce an empty capture that looks like a failed feature | `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md`, Part 6 pre-flight |

---

## Resume checklist

1. Read `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` — every measurement,
   verbatim, Parts 1 through 6 plus follow-ups. It is long; it is the source of truth.
2. Read the memory note `push-delivery-defects-sept-2026` for the queue and working agreements.
3. Read the two specs named in section (d) before proposing anything in their areas.
4. Confirm section (b) still holds before touching the lab or the deployment.
