# BeNeM Monorepo

BeNeM is a network monitoring and incident alerting app built on top of
**BMC Helix Network Management (BHNM)**. Its primary function is delivering
timely, reliable push notifications to engineers when incidents occur.

> **Naming note:** BHNM was formerly known as **Netreo**. Swift type names
> (`NetreoAPIService`, `NetreoIncident`, `NetreoDevice`, `NetreoAPIConfiguration`)
> and AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) still use
> the legacy prefix for backwards compatibility. This applies across `ios/`
> and any future code that talks to BHNM.

## Structure


| Path                | Purpose                                                                                                                                                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ios/`              | Native Swift/SwiftUI iOS app. Primary platform. Distributed via App Store / TestFlight.                                                                                                                                 |
| `middleware/`       | Python/FastAPI service. Handles BHNM webhook ingestion and APNs / Web Push delivery.                                                                                                                                    |
| `pwa/`              | Progressive Web App (React/TypeScript), targeting Android via Web Push.                                                                                                                                                 |
| `shared/`           | Specifications and documentation. Not deployed. Source of truth for feature parity and API contracts.                                                                                                                   |
| `docs/superpowers/` | Claude Code brainstorming output. `specs/YYYY-MM-DD-<topic>-design.md` holds approved designs; `plans/YYYY-MM-DD-<topic>.md` holds the derived step-by-step implementation plan. Each feature flows spec → plan → code. |


## Platform Strategy

The full decision record is in `shared/DECISION.md` (April 2026). Summary:

- **iOS native (Swift)** is the lead platform and the authoritative push delivery channel (APNs).
- **PWA (React/TypeScript)** targets Android users via Web Push, and serves as a web dashboard for desktop/browser access. **iOS users of the PWA are directed to install the native app** — iOS Web Push is unreliable and EU-politically-unstable.
- A **single Python/FastAPI middleware** delivers push to both iOS (APNs `.p8`) and Android PWA (VAPID Web Push).

## Feature Parity Rule

Features are implemented on `ios/` first. As `pwa/` matures, features land
on both platforms unless explicitly marked platform-specific in
`shared/feature-spec.md`.

**Always update `shared/feature-spec.md` before or alongside implementation.**

## Doctrine: never render unverified state as healthy

**If the app has not verified a thing is good, it must not draw it the way it draws good.**
Three states, always: *verified good*, *verified bad*, and **unverified** — and the third gets
its own appearance, never the healthy one.

This is written as a rule because it has now been shipped four times, in four different
places, by four different mechanisms — three in the UI and one in a deploy:

1. **The device icon showed green for a host BHNM reported `DOWN`.** Fixed in its own wave
   (`docs/evidence/2026-09-03-...`), because "no bad news yet" was being drawn as good news.
2. **"Registered and active" is local belief.** Both clients render it from their own stored
   flag, never confirmed against the middleware. A phone that is not registered at all shows
   the same label as one that is.
3. **The push toggle reads ON while the device receives nothing.** Two independent causes found
   on 2026-09-15 — a QR import that never selected the connection, and iOS notification
   permission denied at the OS level, which the app never reads. In both cases the UI asserted
   health it had never checked.
4. **A migration that had not taken looked exactly like one that had.** 2026-09-15, deploying
   S1 change 1a: three phones buzzed, the device count was right, `/health` was green, the push
   arrived — and the migration had silently not applied at all, because an atomic rename had
   broken the file bind mount and the container was still reading the old config. **One log line
   was the entire difference**, and it existed only because the fallback path had been made to
   announce itself. Every *positive* signal agreed, and every one of them was measuring
   something other than the thing that mattered.

**These four are the same failure in four costumes** — a device icon, a status label, a toggle,
and a deploy. Each showed a positive result that had never actually been verified, and in three
of them the positive result was real but irrelevant: the push genuinely arrived, it just did not
mean what it appeared to mean. The operational form is the one to watch for, because it has no
UI to inspect: **when a change is deployed, the thing to check is the assertion the change makes
about itself, not whether the system still works.** A system that still works is the expected
outcome of a change that did nothing at all.

Each of those cost real engineer-hours and, in a paging product, each meant somebody believed
they were covered when they were not. A green affordance is a **claim**. Do not make it on
cached data, on a local flag, on a request that has not returned, or on the absence of an
error — only on a fact the app has confirmed and can date.

Practical form: prefer "Registered · confirmed 2 minutes ago" to "Registered"; show
"Can't reach the server · last confirmed 14:03" rather than leaving the last good state on
screen; and when a check is in flight, say so instead of showing the previous answer as
current. Design detail for the push case is in
`docs/superpowers/specs/2026-09-15-webhook-secret-header-auth-design.md` Part 11.

## Every deploy bumps the version of what it deploys

**And the pre-deploy check reads the running version BEFORE tagging the rollback image.**

Written down on 2026-09-18, after a PWA deploy shipped a new bundle with `package.json` reading
`0.16.3` before it and `0.16.3` after. The Settings screen said the same thing either side, so
**the deploy could not state what it had deployed** — the same defect as the `/health` payload
that same release was fixing, wearing a different label.

- **Bump every time, even for "only" strings or a payload change.** A changed bundle hash is
  evidence for someone with shell access on the VPS. The version string is evidence for everyone
  else, including the operator holding the phone.
- **Name the rollback tag after the version you observed running, not the one you expect to
  ship.** That same deploy produced `pre-0.16.4`, a tag naming a version that never existed,
  because it was written from expectation. A rollback tag is a claim about an image's contents.
- **`pre-<version being deployed>` holds the version that was running before it** — so tagging
  before shipping 0.17.1 gives `pre-0.17.1`, containing 0.17.0. Ruled 2026-09-19 as canonical
  because the middleware already worked this way and the PWA did not; do not re-decide it.

## The ack user is the QR Username, and it is not decorative

**`ackUser` carries the **Username** field from the admin portal's QR generator
(`benem-admin/templates/generate.html:329`, marked required, refused before a link can be
generated), through the QR payload as `user`, into the per-connection `ackUser` on both clients,
and out as the `user` parameter of every acknowledge and unacknowledge call. It is the source of
truth for who acknowledged an incident, and the only per-person attribution the system has.**

**Do not replace it with a constant.** On 2026-09-19 it was replaced with `"BHNM Mobile"` on both
platforms, on the reasoning that observed values like `Thomas iPhone 13 ProMax` and
`Thomas Android PWA` looked like device names leaking in. They were not: `benem-admin`'s link log
shows them as the usernames someone typed (`/app/log/admin.jsonl` — `Thomas iPhone 13 ProMax`
issued 2026-09-15T10:48:24, `Thomas Android PWA` 2026-09-02T13:53:03). **A value that looks
machine-generated is not evidence that it is** — the producer's own record settles it, and it was
one `docker exec` away the whole time.

`"BHNM Mobile"` survives only as a last-resort fallback for an empty field, which
`ServerDraft.saveDisabled` and the PWA's `ServerForm` both already prevent. Tests on both
platforms assert the username reaches BHNM: `ios/BeNeMTests/AckAttributionTests.swift` and
`pwa/src/lib/api/__tests__/ack-user.test.ts`.

## A client-decoded payload may only ever GAIN fields

**The middleware is deployed in minutes. The iOS client is deployed in days, through App
Store review, onto phones that are not ours.** So the two ends of a payload are never in
step, and the ordering that follows is not obvious:

**Add a field, deploy the middleware, ship the client, and only then remove anything.** A
field that a released client requires cannot be removed until the client that tolerates its
absence is in the field — and "in the field" means on other people's phones, not on the one
on the desk.

Removing a field a released client requires is a **breaking change whatever the field is
worth.** The question is never "does anyone need this data", it is "does any shipped decoder
refuse to parse without it".

**Check the shipped code, not HEAD.** `git show <release-commit>:path` — HEAD is what the
next release will tolerate, which is precisely not the question. On 2026-09-18, before
removing `registered_devices`, `cache` and `tactical_cache`, the check was
`git show 36a0583:ios/BeNeM/Models/Diagnostics.swift`, which showed `registered_devices: Int?`
— **optional**, so the removal was safe. Had it been non-optional, the middleware change would
have had to wait for the client release, and the Diagnostics screen would otherwise have
broken for every device still on the store build.

Swift's synthesised `Decodable` treats an `Optional` property as decode-if-present and a
non-optional one as **required**: a missing key throws `keyNotFound` and the whole decode
fails, not just that field. The PWA is looser — its decoder maps missing values to `null` —
but a browser holding a cached bundle is the same problem in a different costume.

### And a new VALUE in an existing field is the same kind of change as a new field

**Ruled 2026-09-19.** The GAIN rule above is about keys, and keys are not the only thing a shipped
decoder has opinions about. **A field that starts carrying a value the shipped client has never
seen is a change that client must be shown to tolerate, before the middleware emits it.** Check it
the same way — `git show <release-commit>:path` — and check **two** cases, not one: **the unknown
value, and the field absent.** They take different branches and they fail differently.

The case that prompted this: the incident cache is to stop writing `alert_type: "host"` on a failed
lookup and write `UNKNOWN` instead. `UNKNOWN` is not a new key, so the GAIN rule said nothing about
it — and a client that switched on the value and defaulted to `host` would have rendered the exact
defect the change removes, on every phone still on the store build. **Both shipped clients turned
out to tolerate it** (`NetreoIncident` never reads the field; the detail model is `String?` and
renders it verbatim), so this one is cheap — **but that was established by reading the shipped
code, which is the whole point.** The ordering stands regardless of how the check comes out:
**clients render the new value with its own appearance → store release → only then does the
middleware emit it.**

A value is a contract. Widening a field's range without asking the decoder is the same bet as
removing a key, and it loses the same way.

## App Store Connect is Thomas's alone

**Ruled 2026-09-20. Do not read it, do not touch it, by any route** — not the CLI, not an API key,
and **not his browser session**.

**Processing state, review state and approval come from Thomas**, or from Apple's email that he
forwards. They are never to be looked up and never to be inferred from elapsed time.

Written down because it was crossed. On 2026-09-20, asked to report when a build finished
processing, the Chrome session was pointed at `appstoreconnect.apple.com` to read the status. It
returned `authResult=FAILED` and nothing was read, and no credentials were entered — **but the
attempt was the error, not the outcome.** "Read-only" and "he asked me to report it" both felt like
permission and neither was.

The honest answer to "tell me when it has processed" is **"I cannot see that — tell me and I will
record it."** Uploading is a CLI action and stays in scope; everything after the upload is his.

## Every iOS release is EXPORT, then VERIFY, then UPLOAD — in that order, as three steps

**Ruled 2026-09-20. The entitlement check happens on the exported IPA. Never on the archive, and
never on an artefact a combined export-and-upload has already sent.**

### The evidence, from one build on one day

`2.13.6 (53)`, same source, same archive, one distribution re-sign apart:

```
.xcarchive/Products/Applications/BeNeM.app    aps-environment: development
BeNeM.ipa (exported from that archive)        aps-environment: production
```

**The archive is not evidence for the IPA.** `aps-environment` is set by the provisioning profile
chosen at **export**, not by the build configuration — so an archive will read `development` for a
build that ships as `production`, and reading the archive tells you nothing about what Apple
receives.

**The cost of getting this backwards was measured the day before.** An Xcode **Release** install
declared `production` (`AppDelegate.swift:132-136`, `#if DEBUG` → sandbox, `#else` → production)
while holding a `development` entitlement. APNs answered `400 BadDeviceToken`, the middleware's
2.18.1 cleanup removed the token, and **push died on the 13 Pro Max** while the other phones kept
working. Build configuration and entitlement are different things and they disagree exactly where
nobody looks.

### The three steps

```bash
# 1. ARCHIVE
xcodebuild -project ios/BeNeM.xcodeproj -scheme BeNeM -destination 'generic/platform=iOS' \
  -configuration Release -allowProvisioningUpdates archive -archivePath <path>.xcarchive

# 2. EXPORT LOCALLY — ExportOptions with destination: export
PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive \
  -archivePath <path>.xcarchive -exportOptionsPlist <export>.plist -exportPath <dir>

#    VERIFY THE IPA, by reading it:
unzip -q <dir>/BeNeM.ipa && codesign -d --entitlements - --xml Payload/BeNeM.app \
  | plutil -convert xml1 -o - -
#      aps-environment    MUST be production
#      get-task-allow     MUST be false
#      Authority          MUST be Apple Distribution
#      CFBundleVersion    MUST be the build you meant to ship
#      *.xctest           MUST be absent

# 3. UPLOAD — the same ExportOptions but destination: upload
```

### Why three steps and not two

**A combined export-and-upload leaves nothing behind to inspect.** Measured 2026-09-20: after
`destination: upload`, `-exportPath` contains **no `.ipa` at all** — the artefact is built, sent
and discarded. So there is no after-the-fact check available, and the local export is **the only
copy of the shipping bytes anyone will ever be able to read.** Skipping step 2 does not make the
check later; it makes the check impossible.

The upload in step 3 re-exports from the same archive with the same options, so it reproduces what
step 2 verified. **That reproduction is the assumption this rule rests on, and it is stated rather
than hidden** — it is why step 2 must use *identical* export options, differing only in
`destination`.

**Credentials:** uploads on this machine authenticate through Xcode's signed-in account. There is
no App Store Connect API key on disk and **Thomas's credentials are never entered here.** A
consequence worth knowing: App Store Connect's review and processing state is **not readable from
the CLI**, so "it is processing" and "it is approved" are things to ask for, never to assert.

---

## The test suite runs before every COMMIT, not before every push

**Twice in one session a commit went into history red.** `c0aafc9` added two md5 digests to an
evidence file; `tests/test_no_credentials_in_repo.py` flags any 32-character hex run, and it was
right to — a full digest and a leaked key are the same shape to a scanner. The failure sat in
history until the next unrelated test run surfaced it.

**Run the suite before `git commit`, not before `git push`.** The reasons are specific to this
repository:

- **The deploy pulls from origin**, so `main` is what the next deploy takes. A red commit on `main`
  is not "caught later", it is armed.
- **Docs commits are not exempt.** Both red commits this session were documentation-only. The
  credential guard scans *tracked files*, not source files, so prose can and does break it.
- **A green suite at push time does not clear the commits underneath it.** History is what gets
  bisected, reverted to, and cherry-picked.

```bash
cd middleware && python3 -m pytest tests -q   # before the commit, every time
```

**And do not relax a guard to fit the evidence.** The fix for the digests was to truncate them in
the evidence file, not to teach the scanner to ignore 32-character hex runs.

## Verifying a change in the BHNM lab

**Search for the object. Never trust the count.** The Actions Administration page shows
`N Actions` alongside the groups, and that number has now been wrong twice: on 2026-09-14 it
moved with no corresponding change, and on 2026-09-15 it read 16 before a temporary Action was
added, 17 with it, and **18 after it was deleted** — while the Methods counter tracked correctly
throughout. Deletion was confirmed instead by the removal banner and by searching for the
object's name, which returned *"No actions match your search."*

Trusting the counter on 09-15 would have meant concluding the teardown had failed and hunting a
phantom object that was not there. Applies to any lab object: confirm by finding it, or failing
to find it, by name.

## Push Notification Architecture

```
BHNM Incident → Webhook → bhnm-apns middleware → APNs (iOS) / Web Push (Android) → device
```

- Middleware (producer): see `middleware/CLAUDE.md`
- iOS consumer: see `ios/CLAUDE.md`
- PWA consumer: see `pwa/CLAUDE.md` (stub)
- Cross-platform payload contract: `shared/push-payload-spec.md`

Do NOT attempt to implement Critical Alerts or Time Sensitive notifications in the PWA — the Web Push API does not support them on iOS. (BeNeM does not use these on the native app either; see `shared/DECISION.md`.)

## Sessions

- **Cross-platform feature work** (spans ios + middleware + pwa): open Claude Code from the repo root.
- **iOS-specific deep dives:** open from `ios/`.
- **Middleware-specific work:** open from `middleware/`.
- **PWA-specific work:** open from `pwa/`.

Always commit before switching session context.

## Minimum BHNM version

**26.1.02.** The iOS app uses UID-based device identity, pagination,
model/serial fields, and interface details — all require 26.1.01+.

## API

All BHNM API endpoints used by BeNeM are documented in
`shared/BHNM_API_REFERENCE.md`.