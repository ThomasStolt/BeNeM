# Design: a tapped push must land on the incident it names

**Status:** DESIGN ONLY — awaiting Thomas's approval. No code.
**Date:** 2026-09-15
**Reported:** in real use — tapping a push lands on an incident the cache has not polled yet.

Three parts, deliberately separable. Part 3 is worth shipping even if 1 and 2 are deferred,
because it stops the app lying; Parts 1 and 2 are worth shipping without each other.

---

## What is actually wrong

`incident_cache` runs one task per server, `while True: await _run_one_cycle(...)`, and the cycle
**paces itself across the refresh interval** — `max(60, min(900, cache_refresh_seconds or 120))`.
So a brand-new incident is absent from the cache for up to that interval, **120 s by default**.
The webhook, meanwhile, is delivered within about a second of BHNM raising the alert.

The push therefore routinely arrives before the data it points at exists. This is not an edge
case; it is the normal ordering.

**Correcting one premise:** the middleware has no fetch-by-id *route*, but it does already have
the upstream call — `incident_cache._fetch_incident_detail(client, server, incident_id)`, posting
`method=getincidentdetail` to `/api/incident_api.php`. Part 2 exposes an existing function; it
does not write a new integration.

**Non-goal, stated so it is not re-proposed later as an optimisation:** *the incident must never
be constructed from the webhook payload.* It would be instant, and it would render a
half-populated detail screen as though it were complete — the `CLAUDE.md` doctrine violation in a
faster costume. The webhook **triggers a fetch**; it is not a data source for display.

---

## Part 1 — Fast path: the webhook refreshes the list

### Why this rather than a client-side fetch on notification arrival

- After any alert, the **incident list and the home screen** are stale for the same interval, not
  just the tapped incident. One server-side refresh fixes the whole surface; a client-side fetch
  fixes one row.
- It runs **whether or not the phone is awake**. iOS gives no guarantee that a background
  notification handler executes, and a paging product cannot depend on one.
- It benefits every client at once, including the PWA and a second engineer who opens the app
  without tapping anything.

### Mechanism — reuse the existing loop, do not add a second one

On webhook receipt, after delivery is enqueued, request a **targeted list refresh** for the
server concerned:

1. Call `_fetch_incidents` once — a single upstream call, **not** the paced enrichment cycle.
2. Merge the result by **replacing** `_cache[server_id]` with a newly built `CachedIncidents`
   rather than mutating it in place. Both writers live on the same event loop, so an atomic
   rebind needs no lock; an in-place merge would risk a torn read between awaits.
3. Leave the paced enrichment loop untouched. It continues and enriches on its normal schedule.

This is one extra API call per alert, and it does not abandon work in progress. **Do not restart
the cycle** — that would discard partially completed enrichment and make the list worse.

### Debounce

One refresh per server per **15 s**, however many webhooks arrive. A site outage raising ten
correlated alerts produces one refresh, not ten. 15 s is comfortably below the 120 s default
interval, so it is a real improvement, and comfortably above the cost of one upstream call.

### Concurrency discipline

Reuse 2.14.0's *discipline* — single consumer, bounded work, per-job timeout, loud failure — but
**not its queue instance.** A cache refresh must never sit in front of a push in the same queue:
the whole point of 2.14.0 is that nothing delays a page. The refresh runs as its own debounced
task per server, and a failure is logged and dropped, never retried into the delivery path.

### The dependency nobody will expect

**The webhook cannot currently tell which BHNM server it came from.** Measured 2026-09-15: the
webhook secret is global — one value across all four configured servers — and `servers.json` has
no webhook-secret field at all. `active_secret` maps to *devices*, not to a server.

Three options, in preference order:

1. **After S1 change 1** (per-server secrets, that spec's Part 17) the mapping is exact: secret →
   server. This is the target.
2. **Refresh every cached server.** Correct, wasteful, and with four servers and a 15 s debounce,
   cheap. **Recommended as the interim** — it ships Part 1 without waiting on S1.
3. Use the `{SERVERNAME}` macro, which the live Method already sends as `server`. **Unmeasured** —
   nobody has checked what it resolves to or whether it matches a `servers.json` id. Do not build
   on it without a measurement.

---

## Part 2 — Correctness path: fetch a single incident

The kick still loses these races, so the deterministic path is needed regardless:

- a tap within a second of the push arriving;
- a server with caching disabled, where there is no cache to refresh;
- a cold cache after a middleware restart;
- an **old** notification tapped hours later, for an incident since closed and gone from the list.

### The route

`GET /api/v1/incidents/{incident_id}` — authenticated exactly like the other `/api/v1/*` routes,
via `_verify_proxy_token`, with the server resolved the same way they resolve it. Returns the same
shape as a list row plus detail, so clients render it with existing code.

On success it **also merges the incident into the cache**, so the list benefits from the tap.

Responses:

| case | status | body |
|---|---|---|
| found | `200` | the incident |
| BHNM says it does not exist | `404` | `{"error": "incident_not_found"}` |
| BHNM unreachable / upstream error | `502` | `{"error": "upstream_unavailable"}` |

`404` and `502` **must** be distinguishable: one is a terminal fact, the other is "ask again
later", and collapsing them is what produces the lie in Part 3.

### The ID question — decided, not inherited

Three identifiers are in play and they are **not reliably the same string**:

| where | form | example |
|---|---|---|
| push payload `{INCIDENTID}` | bare numeric | `29570` |
| cache / incident list | may be prefixed per server | `NetreoCloudDemo-24090` |
| BHNM `getincidentdetail` | bare numeric | `24090` |

**Decision: the canonical key is the bare numeric id, normalised at exactly one place** — a single
`normalise_incident_id()` in the middleware that strips a leading `<prefix>-` if present. The
route accepts either form, normalises on entry, and everything downstream sees the numeric.

**The ambiguity, and why it matters more than it looks.** Suffix tolerance is only safe *within
one server*. Two servers can both hold an incident `24090`. `IncidentListView.swift:101` currently
does `first(where: { $0.incidentID.hasSuffix("-\(id)") })` **across the whole loaded list**, so
with two servers configured it can silently open the wrong incident — a defect that cannot appear
until a customer has a second server, which is exactly how it survives review.

Rules:

- The route is **always scoped to one server** (from the proxy token / target, as the other
  routes are), so `(server, numeric_id)` is unique and no ambiguity exists server-side.
- Client-side list lookup must match **within the active server's incidents only**, prefer an
  exact match, and fall back to suffix matching only if exact fails.
- **If suffix matching yields more than one candidate, treat it as no match** and go to the
  fetch route. Never guess between two. Silently picking the first is how this half-works.

---

## Part 3 — Stop the app lying, on both platforms

Today:

| | PWA | iOS |
|---|---|---|
| on a cache miss | renders **"Incident not found."** | **nothing** — lands on the list, `print` to a console nobody sees on release |
| attempts a fetch | no | no |

**Silence is not the better state.** An engineer who taps an alert and lands on a blank list
concludes the app is broken and stops trusting the notification — which is worse for a paging
product than a wrong message, because it generalises. Both platforms get the **same** states.

### The states and the exact copy

| state | when | primary | secondary | action |
|---|---|---|---|---|
| **Looking** | fetch in flight | **"Loading incident 29570…"** | — | spinner; no Back suppression |
| **The incident** | resolved | the detail screen | — | — |
| **Gone** | route returned `404 incident_not_found` | **"Incident 29570 no longer exists."** | "It was closed and removed from BHNM." | "Back to incidents" |
| **Unreachable** | `502`, timeout, offline | **"Can't load incident 29570."** | "The server didn't respond." | "Try again" |

The fourth row is not padding. The doctrine requires *verified good*, *verified bad* and
*unverified* to be distinguishable, and "gone" versus "couldn't ask" is exactly that distinction.
Collapsing them reproduces today's defect with better wording.

**Never use the string "Incident not found."** It is true only in the `404` case and is the
current lie in the other three.

### The connection badge is the same lie, in one ternary — PWA (measured 2026-09-15)

**Part 3's scope now covers the list screen and the badge, not only the detail screen.** This was
measured, not deduced: with a warm cache, a server that refuses the credential (real `401` from
the middleware) and a dead network are **indistinguishable to a user** — same green badge, same
fifteen stale rows, no message in either. With a cold cache both are a blank screen with a grey
`unknown` badge and no control to tap.

The whole derivation is `components/AppHeader.tsx:34`:

```tsx
const derivedStatus: ConnectionStatus =
  !config.isConfigured ? 'disconnected' :
  isLoading             ? 'checking'     :
  isError               ? 'disconnected' :
  dataUpdatedAt > 0     ? 'connected'    :
                          'unknown';
```

Recorded verbatim, because it states the defect better than a paraphrase:

> the badge's entire derivation is in AppHeader.tsx — `dataUpdatedAt > 0 ? 'connected' :
> 'unknown'`, with isError the only path to 'disconnected'. dataUpdatedAt never resets once data
> has loaded, so a warm cache reads CONNECTED permanently regardless of what happens next. The
> badge does not report the connection; it reports that data arrived at some point in the past.

That is the doctrine violation as one ternary, and **it explains the warm-cache measurement
without needing the paused-query question answered at all** — `dataUpdatedAt` stays non-zero, so
the badge stays green whatever `isError` does.

**Design direction — do NOT build yet, it belongs with this part.** The badge infers connection
health from one query's state, while the middleware already serves a real two-hop signal that the
PWA's own diagnostics screen consumes: `GET /api/v1/diagnostics` returns `server.bhnm.reachable`
as **`true` / `false` / `null`**, where `null` means the background monitor has no verdict yet —
a tri-state that already encodes *unverified* — plus `last_success_age_seconds` and per-feed
`age_seconds`. iOS has a genuine connection monitor. The badge should derive from **that signal
plus a freshness judgement on the data on screen**, not from "we once had data". Practical form
follows the doctrine in `CLAUDE.md`: green only for a hop confirmed good recently, its own
appearance while a check is in flight or has no verdict, and stale-but-rendered data marked as
stale rather than left looking current.

### iOS specifically

`IncidentListView.navigateToPendingIncident()` must **always navigate** to the detail screen in
the *Looking* state and let that screen resolve the incident, rather than searching the loaded
list and doing nothing on a miss. The list is an optimisation — if the incident is already loaded,
show it immediately — not the source of truth.

### PWA specifically

`IncidentDetailScreen.tsx:105` is the current lie and becomes the four-state renderer. The PWA
already distinguishes loading from loaded; it needs the *Gone* and *Unreachable* split.

---

## Sequencing and verification

| | ships | verified by |
|---|---|---|
| Part 3 | first, alone if need be | tap a push for an incident that is not cached: the screen says *Loading*, then resolves or says why |
| Part 1 | second | an alert arrives; the list contains it within ~1 s rather than up to 120 s |
| Part 2 | third | with caching disabled on a server, a tapped push still opens the incident |

Part 3 first is deliberate: it is the only part that removes a falsehood, and it makes 1 and 2
observable — with the four states in place, a failure says which of them it was.

## Decisions — DECIDED 2026-09-15. Do not reopen.

Ruled in the decision sitting of 2026-09-15 (Thomas's calls and the reviewer's rulings, relayed).
Recorded with reasoning so the reasoning is not re-derived.

1. **Interim server resolution for Part 1: refresh ALL cached servers. Do not wait for S1
   change 1.** *Reviewer.* Cheap at four servers, and it stops a usability fix blocking on a
   security migration. **Ceiling, stated explicitly:** this is wrong at scale — every webhook
   refreshes every server, so the upstream cost is O(servers) per alert and a server that never
   raises alerts is polled because a different one did. **S1 change 1 retires it** by giving each
   server its own secret, at which point the webhook identifies its origin and this fan-out is
   replaced by a single targeted refresh. Do not build anything on top of the all-servers
   behaviour that would make it hard to remove.
2. **Debounce interval: 15 s. Accepted.** *Reviewer*, with a condition: **the first webhook of a
   burst must refresh immediately** — the interval governs only the ones after it.
   **Leading-edge, and the design text above did not say so.** "One refresh per server per 15 s"
   is ambiguous between leading and trailing edge; a trailing-edge implementation would delay
   *every* alert by 15 s, including a single isolated one, which inverts the entire purpose of
   Part 1. Binding reading: **refresh on the first webhook, then suppress for 15 s, then the
   next webhook refreshes immediately again.** No timer runs when no burst is in progress.
3. **Copy: Thomas owns the wording; the four strings in "The states and the exact copy" above are
   the draft submitted for approval.** *Thomas's call.* Drafted short and factual on the argument
   that they are read at 3am. The four to approve or amend, verbatim:
   - Looking — *"Loading incident 29570…"*
   - Gone — *"Incident 29570 no longer exists."* / *"It was closed and removed from BHNM."*
   - Unreachable — *"Can't load incident 29570."* / *"The server didn't respond."*
   - And the prohibition that survives any rewording: **never "Incident not found."**
   Amending a string does not reopen the four-state split, which is settled by the doctrine.
4. **Part 2 ID handling: accept BOTH the bare numeric and the prefixed form. Tolerant in, strict
   out.** *Reviewer.* Normalise to numeric at **exactly one place**, and store only the numeric.
   Rejecting the prefixed form would break shipped clients for no gain. The rule already recorded
   in "The ID question" — **more than one suffix candidate means no match** — stands for the
   ambiguous case.
