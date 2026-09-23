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

## [0.19.9] - 2026-09-23

### Changed
- The incident list's silent poll re-reads every 30 s instead of 60 s while visible (C19).

## [0.19.8] - 2026-09-23

### Changed
- TOTAL's selected fill is `#6D28D9` (was `#7C3AED`); its tint stays `#A78BFA`.
- CLOSED keeps its white frame when unselected, with no glow (reverses 0.19.6's frameless CLOSED).

## [0.19.7] - 2026-09-22

### Changed

- **The CLSD pill is labelled CLOSED.** The four-letter abbreviation was a fit constraint from
  when the label sat beside the count on one line; the two-line pill has room for the word, and
  "CLSD" was the only label a reader had to decode. `Pill` is `'CLOSED'`, the `?pill=` URL value
  follows it, and the row badge reads CLOSED too — it takes the same string.

  **Re-proved at 375 px with every count at 99999**, because a two-letter-longer label is exactly
  the kind of change that stops fitting: every pill still measures `scrollWidth == clientWidth ==
  62`, with the label needing 41 px of it against CLRD's 27 and the count's 52.
  `docs/evidence/2026-09-22-pwa-pills-375pt.png`.

> **A stale `/incidents?pill=CLSD` link now lands on TOTAL, not CLOSED.** An unrecognised pill
> falls back to `DEFAULT_PILL`, which is how the `?pill=TOTL` links survived the earlier rename —
> they happened to be going to TOTAL anyway. `CLSD` does not, so that link loses its destination.
> No alias was added: the value is only ever written into the URL by tapping the pill, so the
> reach is a bookmark or a reload of a tab that is about to be replaced. Say the word and it is
> two lines in `isPill`.

---

## [0.19.6] - 2026-09-22

### Changed

- **Every pill now has two colours**: a `base` for the selected fill, and a brighter `tint` for
  the frame, the unselected text and the unselected glow. Round two of Thomas's mockup.

  | pill | base | tint |
  |---|---|---|
  | TOTAL | `#7C3AED` | `#A78BFA` |
  | OPEN | `#DC2626` | `#F87171` |
  | ACKD | `#2563EB` | `#60A5FA` |
  | CLRD | `#16A34A` | `#4ADE80` |
  | CLSD | `#F2F2F7` | `#FFFFFF` |

  Round one gave each pill one colour used for everything, which left an unselected pill
  outlined in the same value its selected neighbour was filled with — the two states separated
  only by fill, which is exactly what failed on TOTAL when `#1B0F33` went on a near-black page.
  A brighter frame is the difference that survives whatever the fill does. **iOS holds the same
  ten strings and both suites assert all ten.**

- **The unselected ground is `#1a1a1d`, not transparent.** Round one let the page through, so
  the row read as four outlines floating on nothing. A plate gives every pill the same footprint
  whether it is selected or not, which is what stops the row jumping as the selection moves.

- **CLSD is the exception, twice.** Selected, its text is `#111114` rather than white — its fill
  is nearly white, and white on white is the whole label gone. Unselected it has **no frame and
  no glow**: white text on the bare plate. It is the one tab you opt into, and a frame in
  `#FFFFFF` would make it the brightest thing in a row nobody is looking at. The border *width*
  stays, or the frameless pill would be 3 px narrower than the four beside it.

  Radii unchanged: 4 px at 55% unselected, 14 px at 85% selected.

  Re-rendered at 375 px with every count at 99999: `docs/evidence/2026-09-22-pwa-pills-375pt.png`.

> **One contradiction in the brief, resolved and stated.** Its summary line says the tint carries
> "the frame, the unselected text and both glows"; its per-state lines say "glow 14 px in **base**
> at 85%" selected and "glow 4 px in tint at 55%" unselected. Those disagree about exactly one
> value. The per-state lines are followed, being the more specific — a selected pill's halo is its
> own fill bleeding outwards. Both platforms resolve it the same way; say the word and it is one
> constant on each side.

---

## [0.19.5] - 2026-09-22

### Fixed

- **An open incident list had no way to learn that anything had changed.** Reported from the
  field on iOS 54 and true here for the same reason: with the list on screen, an acknowledgement
  made in the BHNM UI never reached it.

  **The 120 s `refetchInterval` was covering this by accident.** It re-read
  `GET /api/v1/incidents` whether or not anything had happened, and 0.19.0 removed it as part of
  removing the countdown. Removing the countdown was right — it was a promise nothing kept under
  webhook mode. Removing the *request* underneath it was not, because C4 (the push carrying the
  change itself) has not landed, so the last hop from the middleware's cache to an open screen
  had nothing to carry it. That left a tap as the only update path.

  Two paths back, **both cache reads, neither calling BHNM**:

  - **A push reloads the list.** The service worker posts `{type:'incidents-updated'}` to every
    open tab on every push, and again on a notification tap — a tap can arrive long after the
    notification, on a tab that was open the whole time. The message carries no incident data
    deliberately: the client re-reads the middleware's cache, which is the one place that decides
    what the list contains.
  - **A silent 60 s re-read while the tab is visible.** No countdown, no UI — the poll the
    countdown used to perform, minus the countdown. It stops on hide, so a backgrounded tab
    costs nothing.

  **Both use `useReloadIncidents`, a plain GET, never `useRefreshIncidents`** — which POSTs the
  refresh endpoint and makes the middleware call BHNM's `getincidents`. That belongs to a
  deliberate user action: a tap, a pull, a resume. These two fire on their own, and a
  self-firing BHNM call is a cost nobody asked for.

  **The timer's first tick is a full interval away, and that is load-bearing.** A resume fires
  `useRefreshOnForeground` in the same instant and restarts the timer; firing at zero would put
  two requests on the wire for one event, and the second would land inside the middleware's 30 s
  window and be answered from the first. Asserted, along with the timer stopping on hide and not
  stacking when visibility flaps.

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
