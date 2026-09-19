# Changelog

All notable changes to the BHNM PWA are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Started at 0.17.0 on 2026-09-19.** The PWA shipped from 0.1.0 to 0.17.0 with no changelog —
> its history lives in `package.json` and git. Rather than reconstruct sixteen releases from
> commits, this file starts where the record becomes reliable. For anything before 0.17.0, use
> `git log -- pwa/`.
>
> The version shown in Settings comes from `package.json` (`SettingsScreen.tsx` imports it), so
> the number on screen and the number here cannot drift.

---

## [0.17.3] - 2026-09-19

### Fixed

- **The acknowledging user is the QR Username again.** 0.17.2 replaced it with the constant
  "BHNM Mobile" on the reasoning that values like "Thomas Android PWA" were device names leaking
  into the payload. They were not — `benem-admin`'s link log records them as the usernames someone
  typed into the QR generator, where the field is **required** for exactly this purpose. The
  constant threw away the only per-person attribution BeNeM has. `config.ackUser` is sent again for
  every acknowledge and unacknowledge; the constant survives only as a fallback for an empty field,
  which `ServerForm` already prevents. Four tests now assert the username reaches BHNM.

---

## [0.17.2] - 2026-09-19

### Fixed

- **A successful save now confirms itself, and a failed one is visible at all.** `onSave` navigated
  back to the list in the same tick that set the verdict, so `ServerForm` unmounted before either
  result panel could render — **both were dead code**. A successful save returned silently, and the
  "saved anyway, but this connection is not verified" warning, written precisely so an unverified
  server is never drawn like a verified one, **had never been seen by anyone**. The form now shows
  the verdict with an **OK** button and leaves only when it is pressed, matching iOS. The server is
  still persisted immediately, before the acknowledgement, exactly as iOS does it.
- **The success wording matches iOS** — "Connection verified", then "BHNM is reachable through the
  middleware and accepted the credentials."

### Changed

- **The ack user is the constant "BHNM Mobile", always — not a fallback.** The per-connection
  `ackUser` was sent, so a phone name ("Thomas iPhone 13 ProMax") reached BHNM's incident history.
  That was never an identity: BHNM has one API token per server, not per user, so nothing about an
  acknowledgement has ever identified a person. A constant says truthfully what it is, and iOS
  sends the same string.

---

## [0.17.1] - 2026-09-19

### Fixed

- **The iOS banner pointed at `href="#"`.** Every iOS visitor was told to install the native app
  behind a link that did nothing. It now goes to the real listing, and says **BHNM** rather than
  BeNeM because that is the name on the App Store page they land on.
- **The app shell would not load offline.** `sw.ts` precached `index.html` but registered no
  `NavigationRoute`, so nothing routed navigations to it: an already-open PWA kept running from
  the precache, and a reload replaced it with the browser's own error page. Worst exactly when an
  on-call user taps a notification on a bad network. Fixed with
  `NavigationRoute(createHandlerBoundToURL('/index.html'))`.
- **"Active Incidents" counted the wrong thing.** It counted `severity === 'critical' || 'major'`
  under a label that says active, so it disagreed with the iOS tile, which counts
  `status === 'active'`. Now `status === 'active'` on both platforms.

### Changed

- **The "Total Devices" tile navigates**, to `/devices`. Both tiles are full-card `Link`s with a
  `›` affordance, an `aria-label` and a focus ring — a card that navigates has to look like it
  does, and a `Link` keeps middle-click, open-in-new-tab and keyboard access that an `onClick`
  handler would throw away.
- **User-facing "BeNeM" is now "BHNM"** — the QR scanner prompt, the app-mark `alt` text, the QR
  parser's error messages and the push-notification title fallback. Console prefixes are
  deliberately unchanged: they are for us, not for users.
- **The ack user fallback is "BHNM Mobile"**, matching iOS, so an acknowledgement from either
  client attributes the same way in BHNM's incident history. It was "BeNeM PWA" here and "mobile"
  there.

---

## [0.17.0] - 2026-09-18

### Changed

- **The version is stated where a user can see it.** 0.16.3 shipped a changed bundle with
  `package.json` reading `0.16.3` before it and `0.16.3` after, so the Settings screen said the
  same thing either side and the deploy could not state what it had deployed. That produced the
  rule now in the root `CLAUDE.md`: every deploy bumps the version of what it deploys, and the
  pre-deploy check reads the running version **before** tagging the rollback image.
