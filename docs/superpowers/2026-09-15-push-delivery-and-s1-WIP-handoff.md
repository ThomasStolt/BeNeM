# Push Delivery, S1 and Incident Freshness — WIP Handoff

**Date:** 2026-09-15
**Status:** CLEAN CHECKPOINT. Nothing is half-built, the lab is restored, the deployment is
healthy. Everything below is either shipped, designed-and-awaiting-approval, or blocked on a
measurement that needs Thomas and a phone.

Written for a reader with **no memory of the work that produced it**. Every item names its file.

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

## b. Lab and deployment state (verified by observation, 2026-09-15 ~19:30 UTC)

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

## c. The queue, in order

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
6. **Push relay spec — READY TO START, stop at design.** Target the encrypted variant (relay
   sees only a token and an opaque blob), not the plaintext one. Context in the memory note
   `push-delivery-defects-sept-2026`.
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
11. **Coverage is scoped in BHNM and invisible from inside BeNeM — FINDING, not yet designed.**
    Measured 2026-09-15 in one window on one server: incident 29585 (`BHNM-B-SE01`, host, 21:51Z)
    produced **no webhook**, while incident 29586 (`raspi-050`, host, 22:05Z) paged all four
    targets. Two host-down incidents minutes apart; one paged, one did not. Whether the cause is
    per-device action-group attachment or notification criteria is **not** yet established — the
    finding holds either way.
    Why it outranks its queue position: every other doctrine case renders unverified state as
    healthy in a UI. This one makes *absence of a page* indistinguishable from *no incident*. An
    engineer watching a silent phone cannot tell "nothing is wrong" from "this device was never
    wired to page me", and that distinction is the entire product. There is no affordance to be
    suspicious of.
    Minimum fix is documentation: `INSTALL.md` §7 does not tell an administrator to attach the
    action group to everything they expect to be paged about. The real fix is that BeNeM cannot
    answer "which of my devices will page me?" — and until it can, users assume "all of them".
    Evidence: `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` §8.8.
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

---

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
