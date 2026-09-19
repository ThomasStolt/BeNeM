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
