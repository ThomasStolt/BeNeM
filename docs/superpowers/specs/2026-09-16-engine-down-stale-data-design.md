# Design: what BeNeM shows when the engine behind the data is down

**Status:** DESIGN ONLY. STOP AT DESIGN — nothing built.
**Date:** 2026-09-16
**Queue:** item 13. **Ranked against item 11 below — it does not displace it.**

---

## Provenance, stated first

This document mixes three kinds of statement and they must not be read as equivalent.

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed by me, in this repository or against the live deployment, with the observation recorded |
| **[THOMAS]** | Thomas's account of how BHNM behaves. Not verified by me. The design's central premise is one of these |
| **[INFERENCE]** | My reasoning from the above. Wrong inferences have already cost this project one correction today |

## The premise

**[THOMAS]** The Service Engine manages **all** devices. If it is down, BHNM cannot reach
anything — so an SE outage is the *cause* of device-level symptoms, never the effect of one host
going away.

**[THOMAS]** When the Service Engine is down, **devices retain their last state in BHNM**. They do
not go unknown, they do not go down. They stay exactly as they were at the moment the engine
stopped.

**[MEASURED]** Wave B made BeNeM's device list mirror BHNM's host status
(`restful/devices/get-host-and-service-status`, fetched by `middleware/maintenance_cache.py:144`).

**[INFERENCE]** Therefore: engine down → every device row frozen at its last value → BeNeM
faithfully renders a screen full of green. **BeNeM is not wrong about BHNM; BHNM is not wrong
about what it last saw. The green is a faithful rendering of data that stopped being true.**

This is the doctrine — unverified state presented as healthy — **originating a layer below
anything BeNeM currently checks.** The two-hop diagnostics verify the middleware reaching BHNM's
front end. The front end answers perfectly while the engine behind it is dead.

## Establish first: is this knowable at all?

The reviewer asked for this to be established before designing. What follows was measured today.

### Is Service Engine health readable?

**[MEASURED] Yes — the SE appears as a monitored host in BHNM.** Incident **29585** carried
`name: "BHNM-B-SE01"`, `alert_type: "host"`, and appeared in `host_down` while it was down. So its
state is readable through exactly the API BeNeM already uses; no new integration is required to
*see* it.

**[MEASURED] But it did not page**, and the explanation previously recorded for that is wrong.
29585 produced no webhook, and neither did its controlled repeat 29628 on 2026-09-16. The
explanation "a crashed Service Engine cannot notify anyone of its own crash" **has collapsed**:
per Thomas, **the main BHNM appliance sends the webhooks, not the Service Engine**, so during
both outages the sender was healthy and able to page.

So: **the one device whose outage invalidates every other device's status is the one whose outage
reaches nobody, while the machine that would do the paging is up.** That belongs to queue item 11
(coverage), not here — see the dedicated section below.

**[INFERENCE, needs confirming]** Recognising *which* host row is the Service Engine is the open
part. `BHNM-B-SE01` is a name, and naming conventions are not an API. Candidates, in order:
a documented SE/poller endpoint (none found in `shared/BHNM_API_REFERENCE.md`); a device
`category` or `template` that identifies engines; or configuration — the user tells BeNeM which
device is the engine. **The last is unglamorous and would work.**

### Does a stale device row carry a freshness marker?

**[MEASURED] Yes, and BeNeM throws it away.** `get-host-and-service-status` rows carry
`lastUpdateTime` and `currentStateDuration` alongside `status` and `stateType`
(`shared/BHNM_API_REFERENCE.md`). Grepping `middleware/`, `pwa/src/` and `ios/` for
`lastUpdateTime`, `currentStateDuration` and `stateType` returns **nothing**. The middleware
fetches these rows and reads only the status.

**[INFERENCE]** This is the good news of the whole document: **staleness may be detectable without
identifying the Service Engine at all.** If `lastUpdateTime` stops advancing while the middleware
keeps successfully fetching, the data is stale whatever the cause — engine down, poller wedged,
one device stuck. A freshness test is more general than an engine test, and it needs no new
endpoint and no naming convention.

**Must be measured before building:** whether `lastUpdateTime` actually stops advancing during an
engine outage, or is rewritten on every fetch. **If it is rewritten, this entire approach fails**
and the design falls back to identifying the SE. That measurement is one engine outage and a
before/after read — and the lab has just had an unplanned one, so it may already be reproducible
from history.

## What BeNeM should show

Only the shape, since the mechanism above is unsettled.

**The rule, from the existing doctrine:** three states, and the third gets its own appearance.
For a device row: *verified up recently*, *verified down*, and **stale — last confirmed at
HH:MM**. Not green. Not red. Its own appearance.

- **Per-row staleness beats a global banner.** A row whose `lastUpdateTime` is older than some
  multiple of its `poll_intvl` reads as stale, dated. This works whether one device is stuck or
  the whole estate is frozen, and degrades gracefully when the cause is unknown.
- **When *everything* is stale, say so once, prominently**, because that is the engine case and a
  screen of individually-stale rows under-sells it: *"No device has been checked since 21:51. The
  data below is that old."*
- **The connection badge must participate.** Today it goes green on "data arrived at some point"
  (incident-freshness Part 3). Data arriving from a front end whose engine is dead is exactly the
  case it should refuse to call healthy.
- **Paging is the separate question.** If the SE can be identified, its outage is the single most
  page-worthy event on the system — it means *nothing else will page you either*. That belongs
  with item 11, not here.

## How this ranks against item 11 (coverage visibility)

**It does not displace item 11.** Both are "the user cannot tell that they are not being told",
and they differ in reach and in remedy:

| | item 11 — coverage | item 13 — engine down |
|---|---|---|
| when it bites | **always**, silently, from the day of install | only during an engine outage |
| what the user sees | a list that implies more coverage than exists | a screen of green that was true an hour ago |
| detectable today? | **no** — needs BHNM config BeNeM cannot read | **probably yes** — `lastUpdateTime` is already fetched and discarded |
| fix cost | design-heavy, may end in an admission | plausibly small, if the freshness field behaves |

**Item 11 stays first** because it is permanent and undetectable; item 13 is intermittent and,
on today's evidence, cheaply detectable. **But item 13 may well ship first**, precisely because a
freshness marker already in hand is a smaller change than a coverage story that may have no
answer. Ranked below 11 in *importance*, likely above it in *order*, and that is not a
contradiction.

## Decisions for Thomas

1. **Confirm the premise:** do devices really retain their last state during an engine outage,
   rather than going unknown? Everything here rests on it and it is marked **[THOMAS]**.
2. **Can the Service Engine be identified programmatically** — a category, a template, an
   endpoint — or should BeNeM simply ask the user which device it is?
3. Approve the `lastUpdateTime` measurement (read-only) as the first step: does it stop advancing
   during an engine outage, or is it rewritten on every fetch?
4. Is per-row staleness plus a single "nothing has been checked since HH:MM" banner the right
   shape, or should a frozen estate be a modal-level interruption?
