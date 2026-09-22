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

## [0.19.4] - 2026-09-22

### Fixed

- **The selected TOTAL pill did not read as selected.** Reported from the device: `#1B0F33` on
  slate-950 is a near-black block on a near-black page, and a filled pill that cannot be told
  from an empty one is the doctrine's own failure wearing a colour — a selected state asserting
  itself where nothing is visible to assert it.

  **`#1B0F33` is dropped entirely.** TOTAL is `#7C3AED` in both states and behaves exactly like
  the other four: outlined, violet-texted and 4 px-glowing when unselected; filled violet with
  white text and a 14 px glow when selected. No pill has a second colour any more — the
  `PALETTE` of `{fill, accent}` pairs collapsed to one `COLOUR` per pill, and iOS dropped its
  `accent` property in the same change.

  **The measurement was right and the reasoning was wrong.** `#1B0F33` genuinely is the app
  icon's dominant colour — 799,841 of 1,048,576 pixels, 76.3%, quantised to eight colours — and
  that is precisely because it is the icon's dark *background*. Sampling the dominant colour of
  an image whose subject is a thin bright line returns the field behind the subject. **A
  measured value is not automatically the right value.**

  Re-rendered at 375 px with every count at 99999: `docs/evidence/2026-09-22-pwa-pills-375pt.png`.

---

## [0.19.3] - 2026-09-22

### Changed

- **The pills glow.** Unselected: transparent fill, a 1.5 px border in the pill's own colour,
  text in that colour, and a soft 4 px outer glow at 55%. Selected: filled as before, white
  text, and a 14 px glow at 85%. **TOTAL's fill stays `#1B0F33`** — the measured app-icon
  purple — **but its border, text and glow are `#7C3AED`**, because a near-black outline and
  halo on a slate-950 page is nothing at all. iOS holds the identical two hexes and the
  identical two radii; both suites assert them.

  `box-shadow`, never `filter: drop-shadow` — a filter promotes the element to its own
  compositing layer and blurs everything inside it, digits included.

  **Colours moved from Tailwind classes to inline styles.** Tailwind's JIT only emits an
  arbitrary value it can see as a literal string, so a per-pill `bg-[${hex}]` compiles to no
  class at all and the pill renders transparent — with no error anywhere. Inline styles have no
  build step to fall through, and they let the fill, the border and the glow read one palette
  entry instead of three hand-synchronised strings.

  **`motion-reduce:transition-none`** turns off the 150 ms colour transition for a reader who
  asked for less movement. That is the only thing here that moves: the glow is static and
  nothing animates in or out.

  Re-rendered at 375 px with every count at 99999: `docs/evidence/2026-09-22-pwa-pills-375pt.png`.

---

## [0.19.2] - 2026-09-22

### Changed

- **TOTL is TOTAL, and the pill is two lines: the count on top, the label beneath in small
  caps.** Side by side stopped fitting the moment the label grew a letter — at 390 px the five
  pills share the width, ~72 px each, and after padding and a ~45 px `TOTAL` a single-line
  `TOTAL 99999` had room for about one digit. Stacking gives the number the whole pill width.
  Proved by rendering at 375 px with every count at 99999, not by arithmetic:
  `docs/evidence/2026-09-22-pwa-pills-375pt.png`. `tabular-nums` on the count so the five
  columns do not jitter as the numbers change.

- **TOTAL is `#1B0F33` with white text, replacing the gold `#c9a227`.** The hex is a
  **measurement**: quantise `ios/BeNeM/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` to
  eight colours and the largest cluster is `#1B0F33` — 799,841 of 1,048,576 pixels, 76.3%, the
  icon's background field. White sits at 18.1:1 on it, so the gold's dark-text exception is
  gone rather than inverted. iOS asserts the identical string, so the platforms cannot drift on
  it quietly.

- **A stale `/incidents?pill=TOTL` link still lands on TOTAL, with no alias code.** An
  unrecognised pill already falls back to `DEFAULT_PILL`, and that is TOTAL — so the links
  0.19.1 left in cached bundles and bookmarks arrive where they meant to. A test asserts it,
  which is what makes it a decision rather than a coincidence: it fails if the default moves.

> **This file has no 0.18.0 – 0.19.1 entries.** They were never written; the record for those
> releases is `git log -- pwa/` and the monorepo handoffs. Noted here rather than silently
> backfilled from commit messages.

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
