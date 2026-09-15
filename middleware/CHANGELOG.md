# Changelog

All notable changes to bhnm-apns are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.14.0] - 2026-09-15

### Fixed

- **2.13.4 did not fix the fan-out — concurrent webhooks still wedged it.** Sends were made sequential *inside* one fan-out, but nothing serialised **two** fan-outs: each `/webhook` spawned its own `BackgroundTask`, and two webhooks arriving in the same second raced on the shared HTTP/2 client. Measured 2026-09-15: two requests 255 ms apart both stalled after ~3 sends, sat for 60 s and were abandoned by the `FANOUT_TIMEOUT` guard; the two most recently registered devices and the Web Push subscription received nothing. A control run with a single webhook served all 8 targets in 1.4 s. Full write-up in `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` §3.9.

  Root cause is not an httpx bug and **no dependency upgrade is available** — `httpx 0.28.1`, `httpcore 1.0.9` and `h2 4.4.1` are all the newest released versions. It is an APNs constraint: Apple documents that APNs caps HTTP/2 stream concurrency per connection and that with token authentication it "allows only one stream until you post a request with a valid authentication token". Serialising is the correct design, not a workaround.

### Changed

- **Delivery now runs through one bounded queue and a single long-lived worker task**, replacing the per-request `BackgroundTask`. The webhook still enqueues and returns immediately, so BHNM is answered well inside its ~30 s timeout. Deliberately a queue rather than a lock: a lock would put every alert behind every other one with no way to distinguish lock-wait from send-stall, and `FANOUT_TIMEOUT` would then be measuring the wrong thing. With a queue nothing waits on anything, so the per-job timeout covers only that job's own sending. It also gives ordering, back-pressure, and one place to add retry later.
- **Queue bounded at 256 jobs** (`DELIVERY_QUEUE_MAX`), with a `[Deliver] BACKLOG` warning from depth 32. The bound is **not** sized to absorb a legitimate flood: BHNM does its own alarm reduction (correlation, parenting, incident-criteria rules), so a healthy server does not emit hundreds of notifications at once — if it does, that is a BHNM misconfiguration and the middleware should not paper over it. The bound exists to stop unbounded growth when *delivery* is stalled, and the depth-32 warning is the real signal: a queue that ever gets near full means either a stalled APNs or a misconfigured BHNM, and both should be loud. A drop is logged as `[Deliver] QUEUE FULL … Nobody was paged for it.` and the endpoint returns `{"status": "dropped", "notified": 0}` — a dropped page is survivable, a silent one is not.
- One failing job can no longer kill the worker and silence every alert behind it.

### Added

- `tests/test_delivery_queue.py` — the concurrent case is now tested **deliberately**, against a stub APNs transport rather than a mocked `send_to_all`, because the defect lived below `send_to_all`. The stub asserts that **no two APNs requests are ever in flight at once**; a test that only checked "every device was served" would have passed against the broken code, since a mock transport never stalls. Includes a teeth check that reproduces the pre-2.14 concurrent shape and asserts the detector fires on it.
- `tests/test_no_credentials_in_repo.py` — fails the suite on credential-shaped strings in tracked files. Added after the 2.13.2 redaction filter was found to have been tested with the **live** lab webhook secret, leaving a 33-character fragment in a test and an 8+8-character fragment in the evidence file. Both replaced with synthetic values. Rule: never test a redaction filter with the string it is meant to redact.

### Known issue — carried forward

- **The delivery queue discards by count, not by age, so an APNs stall delivers pages after they stop mattering.** While APNs is healthy a job takes ~1 s and the queue never builds. While APNs is stalled every job burns the whole `FANOUT_TIMEOUT` of 60 s, and each queued job pushes the next one a further minute late. **Ten queued alerts is ten minutes of drain**; the alert at the back is delivered when it is already history. A late page is worse than a dropped one, because a drop is logged loudly and a late page looks like a working system.

  Magnitude, stated honestly: this is *not* the four-hour scenario a full 256-job queue would imply. BHNM performs its own alarm reduction, so a correctly configured server does not produce hundreds of simultaneous notifications — reaching the bound at all would itself be a misconfiguration. The realistic case is a handful of jobs and a drain of minutes, which is still long enough to matter for a paging product.

  Not hypothetical: the fan-out defect this release fixes stalled for exactly the 60 s the guard allows, twice in one run.

  **Proposed fix:** stamp each job with its arrival time on enqueue, and discard on dequeue anything older than a staleness threshold, logging `[Deliver] STALE — dropped incident N, queued Xs ago`. Suggested threshold **5 minutes** — longer than BHNM's own Incident Close Delay Timer (also 5 minutes, so a recovery that would cancel the page has had time to arrive) and still inside the window where an engineer wants to be woken. Worth pairing with exposing queue depth and oldest-job age in `/health` and `/api/v1/diagnostics`, so a backlog is visible to an operator and not only in the log.

  **Warn on estimated drain time, not on queue depth** — designed here, not built, and it ships with the stale-job discard above.

  Depth is the wrong unit. A job is a fan-out to *every* registered device, so the quantity that matters is `queued_targets x per_send_seconds`. Depth 32 with two devices is trivial; the same depth with a fifty-device fleet is minutes of pages arriving too late to act on. The alert count stays bounded by BHNM's correlation — but the **device count grows with adoption and nothing watches it**, so a threshold in jobs silently becomes stricter or looser as the fleet changes. Measured per-send latency today is ~0.14 s (seven targets served in 1.4 s on 2026-09-15).

  Design:

  - Keep a running `queued_targets` count, incremented by `len(tokens) + len(subs)` on enqueue and **decremented on every exit path — normal completion, `FANOUT_TIMEOUT`, an unhandled exception in the job, and a queue-full or no-worker drop.** A counter that only ever rises would latch the warning on permanently after the first busy minute and train the operator to ignore it, which is worse than no warning. The decrement belongs in the worker's `finally` alongside `task_done()`, and in the drop path of `_enqueue_delivery` where the job never reaches the queue at all. Worth an explicit test that the count returns to zero after a timed-out job and after a rejected one.
  - Hold `per_send_seconds` as an exponentially weighted average of recent completed sends, seeded at 0.15. A stalled fan-out drives it toward `FANOUT_TIMEOUT`, so the estimate rises on its own exactly when it should; do not update it from a job that timed out, or one stall would poison the average permanently.
  - **Warn when `queued_targets x per_send_seconds` exceeds 60 seconds.** Chosen to sit an order of magnitude below the 5-minute discard threshold: the operator is told while the backlog is still recoverable, and discarding only begins four minutes later. A minute of queue is also roughly where the last page in it stops being worth acting on.
  - Keep raw depth as a **secondary** signal, not the trigger.

  Expose all of it in `/health` and `/api/v1/diagnostics`, so a backlog is visible where an operator looks rather than only in the log:

  ```json
  "delivery": {
    "queued_jobs": 3,
    "queued_targets": 18,
    "oldest_job_age_seconds": 4.2,
    "estimated_drain_seconds": 2.7,
    "per_send_seconds": 0.15,
    "dropped_total": 0
  }
  ```

  No secrets are involved and `/health` already publishes `registered_devices`, so this adds no exposure. Known ceiling of the estimate: it assumes every queued job fans out at the current average rate, which is wrong the moment one device is slow or a token is dead — it is a monitoring signal, not an SLA.

  Not done in 2.14.0 deliberately — the concurrency fix is the live defect and is worth shipping alone. Next in line.

- **An operator cannot tell which humans are being paged.** Every row in `device_tokens` reports `device_name` as the literal `iPhone` — measured 2026-09-15 across all six live registrations, `SELECT DISTINCT device_name` returns exactly one value. iOS 16 removed the per-device name from `UIDevice.current.name` unless the app holds a special entitlement, so `AppDelegate` has been sending a constant since long before anyone noticed.

  The same measurement retired a plausible explanation for the duplicates: `apns_environment` is `production` for **all six** rows, so none of them is an Xcode debug build. A single phone cannot be appearing twice as a sandbox/production pair — these are six distinct install events on TestFlight or App Store builds.

  Why it is a real gap rather than cosmetic: for a paging product the question an admin must be able to answer is *"is my on-call engineer reachable?"*, and today the Push Config page answers it with six identical rows of truncated hex. It is also why three of four devices could be silently not receiving for three different reasons without anyone noticing, and why identifying which registration belongs to which colleague currently requires sending a distinct push to one token at a time and asking people what appeared on their screen.

  **Proposed fix:** the QR already carries a username — the app stores it and uses it as the ACK user — so have the client send it on `/register` as a `user_label` alongside the token, store it in a new nullable column, and render it in the admin portal. That is a small change at both ends, it needs no entitlement, it survives reinstalls because the label comes from the QR rather than the device, and it turns six anonymous rows into named ones. Pair it with the `last_push_at` / `last_status` / `last_error` columns already proposed in the evidence file's follow-up 1, and the Push Config page can finally answer the on-call question directly. Ties in with queue item 5 (admin portal device overview).

### Housekeeping

- `test_database.py`, `test_proxy_auth.py` and `test_webpush.py` moved from `middleware/` into `middleware/tests/`, so **`pytest tests` now collects the whole suite**. They were never collected by the documented command, which is how `test_webpush.py` sat red: it called `build_payload()` with a fourth `severity` argument removed from the function long ago, and pinned an exact `webpush_send` signature. Both fixed.
- Suite: **179 passed** (`pytest tests`, exit code 0).

---

## [2.13.4] - 2026-09-15

### Fixed

- **Only the first registered device was ever notified.** `send_to_all` fired every token concurrently through `asyncio.gather` on one shared HTTP/2 connection to APNs. Tracing showed the first request completing in ~430 ms and the remaining four never returning from `await client.post(...)` — no result, no exception, and **no timeout despite `timeout=10.0` on both the client and the request**, so they sat there indefinitely. Because `get_tokens_for_secret` had no `ORDER BY`, the served row was always the same device (the oldest registration), which is why this looked like working delivery. Sends are now **sequential**: one POST at a time, ~0.5 s per device, inside a background task nothing waits on.
- **`get_tokens_for_secret` now has an explicit `ORDER BY id`.** Relying on SQLite's rowid order is what kept the above invisible.

### Added

- **`asyncio.wait_for` around the whole fan-out** (`FANOUT_TIMEOUT`, 60 s), logging `[Deliver] TIMEOUT after 60.0s — fan-out abandoned for incident N, X token(s), Y subscription(s)`. The previous stall was silent for months; a future one will not be.
- `[APNs] Token gone (410) …` logged alongside the existing `[Cleanup]` line.

### Note

- Two devices were previously written off as having device-side notification problems (iPhone Focus, Android setup). That conclusion is **retired** — they may simply never have been sent to. Retest before changing any setting on them.

---

## [2.13.3] - 2026-09-14

### Changed

- **`clean_bhnm_text()` preserves line breaks instead of flattening them.** `<br>`, `<br/>`, `<br />` and `</p>` become a real newline; remaining tags become a space; entities are decoded; only spaces and tabs are collapsed; three or more newlines cap at two. The previous version collapsed all whitespace, so if BHNM fixes the underlying defect by emitting a newline instead of `<br />`, that fix would have been flattened back to a space and never reached the screen. Tested against the captured strings, every break spelling, and a newline-bearing variant. Suite 146 passed.

  BHNM 26.3.01 emits HTML in the plain-text `{OUTPUT}` macro; the incident API's own data is clean, so this is scoped to Action macro text. The defect is being filed with BMC.

---

## [2.13.2] - 2026-09-14

### Fixed

- **The webhook secret was being written to the log.** Now that `/webhook` returns a response, uvicorn writes an access line for it — and the secret travels in the query string, so the full credential appeared in stdout and would have been persisted to the host log file. A redaction filter on `uvicorn.access`/`uvicorn.error` and on the stdout mirror rewrites `secret=`, `token=`, `password=`, `pwd=` and `key=` values to `<redacted>`. This is the logging half of security-board item S1; the secret still travels in the URL.
- **Host log fell back to stdout only.** Docker creates the `./logs` bind mount as `root`, and the container runs as `appuser`, so the file could not be opened. The installer now tries `HOST_LOG_PATH` and then `/data/middleware.log` on the SQLite volume, which is always writable and also survives container recreation.

### Known issue — next thing to fix

- **The APNs fan-out still does not complete.** 2.13.1 moved it to a background task, so BHNM gets its response in ~0.3 s and no longer retries — the user-visible fault is fixed. But no `[APNs] Sent to …` line has ever been printed, before or after the change, which means the task still hangs after the sends leave the process. Replacing the per-request `AsyncClient` with a shared one did not change this, so the teardown hypothesis was wrong and the cause is currently unknown. Deliveries themselves arrive.

  Consequences while it stands: **stale-token cleanup never runs**, so dead tokens accumulate and every notification fans out to all of them; and **one background task is leaked per notification**. This is the top open item for the next release — ahead of token cleanup, which it blocks, and ahead of the richer-macros work. Full chain in `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md` §3.6.

---

## [2.13.1] - 2026-09-14

### Fixed

- **`/webhook` never returned a response, so BHNM retried every notification three times.** With at least one registered token the handler entered `send_to_all`, which wrapped the fan-out in a per-request `async with httpx.AsyncClient(http2=True)`. The sends completed — devices received the push — but the block never exited, so the response was never sent, no `[APNs]` line was ever printed, and uvicorn never logged the request. BHNM waited ~30 s, timed out and retried three times, stamping `Retry action by system N of 3.` into `{OUTPUT}`; every engineer got four alerts per incident. Two fixes, both kept: the fan-out now runs in a `BackgroundTasks` job so the response goes back to BHNM immediately, and `apns.py` uses one long-lived shared `AsyncClient` instead of building and tearing one down per request (which is also what Apple asks for). Requests with no registered devices always returned normally, which is why the fault stayed invisible in testing.
- **Literal HTML on the lock screen.** BHNM puts markup in `{OUTPUT}` (`<br />Ping CRITICAL: Packet Loss 100%`). `clean_bhnm_text()` strips tags, decodes entities and collapses whitespace before the title and body are built — which also removes the double space in `Host recovered.  (Host check…`.

### Added

- **Host-side log.** Everything printed is mirrored to `/logs/middleware.log` on a bind mount (`./logs`), rotated at 5 MB × 5, alongside container stdout. Container recreation erased the webhook evidence being measured on 2026-09-03 and again on 2026-09-14; `docker logs` is no longer the only copy. Override the path with `HOST_LOG_PATH`. Failure to open the file is logged and ignored — it can never take the service down.

### Changed

- `/webhook` returns `notified` as the number of targets **queued** for delivery rather than the number confirmed sent, because the response no longer waits for delivery. Stale-token and expired-subscription cleanup still happen, in the background path.

### Tests

- 9 more in `tests/test_webhook_notification_types.py`: the captured HTML string, entity decoding, whitespace collapsing, no markup in a PROBLEM body, no double space in a RECOVERY body, BHNM's own retry wording surviving as text, the response not awaiting delivery, and stale-token cleanup still running in the background. Suite 130 passed.

---

## [2.13.0] - 2026-09-14

### Added

- **`DEACKNOWLEDGEMENT` handling.** Un-acknowledging an incident in BHNM sends `notification_type: DEACKNOWLEDGEMENT` (BHNM's macro reference documents the value as `UNACKNOWLEDGEMENT`; both spellings are accepted). It now pushes `Unacknowledged: {hostname}` with the notification output as the body, falling back to `primary_alarm_status`. Previously it fell to the problem branch, and because BHNM leaves `host_state` at `DOWN` on that notification, it was delivered as `🔴 {hostname} — DOWN` — indistinguishable from a fresh outage.
- **Renotification titles.** `notification_number` is read when present; from the second notice onward the title becomes `{emoji} {hostname} — still {host_state} (notice {n})`. Absent or unparseable counts as the first notice. No suppression — that is a per-user setting for a later spec.
- **Webhook-driven cache patch.** `ACKNOWLEDGEMENT`, `DEACKNOWLEDGEMENT`/`UNACKNOWLEDGEMENT` and `RECOVERY` patch the cached incident by `incident_id` (→ `ACKNOWLEDGED` / `OPEN` / `CLOSED`) so the list reflects the change before the next poll. Reuses the 2.10.1 state-override mechanism via a new `incident_cache.note_state_override_any_server()`, since webhooks are routed by shared secret and carry no server id. The poll remains the source of truth and overwrites.

### Changed

- **`RECOVERY` body reads as English for hosts.** `{service_desc or 'Host'} recovered. {output}` — host recoveries previously rendered `UP recovered.` because `service_desc` is empty on host alerts.
- **`notification_type` is compared case-insensitively** after stripping.

### Tests

- `tests/test_webhook_notification_types.py` — 19 tests covering every literal observed on the wire from BHNM 26.3, including `host_state` carrying `"ACKNOWLEDGEMENT"` on ack notifications, empty `service_*` on host alerts, both un-ack spellings, renotification counts, and the cache patch (including that `PROBLEM` does not patch and an unknown incident id is a no-op). Full suite 121 passed.

---

## [2.12.1] - 2026-09-03

### Added

- **`status` on `POST /api/proxy/maintenance/status`** (spec rev 5 §11.1). The per-device read already fetched the host row for the maintenance button; it now passes the row's `status` literal through untouched as an additive field, absent when there is no row or the row carries no string status. The detail screens use it (UP/DOWN) ahead of the list's map-or-fallback colour — live, zero extra BHNM calls, works on cache-off servers.

### Changed

- **Diagnostics `maintenance_map` count is now host rows** classified UP/DOWN by the last crawl (38 on the lab) — the same number as the cycle log line — instead of the in-maintenance count, which read as "no count" on a healthy day. Clients label it "N hosts".

## [2.12.0] - 2026-09-03

### Added

- **`host_down` on `GET /api/v1/maintenance-map`** (Wave B, spec `docs/superpowers/specs/2026-09-03-host-status-overlay-design.md` rev 4). The same per-category `get-host-and-service-status` crawl that builds `in_maintenance` now also keeps the names whose host row carries the literal `"DOWN"`, served as a fourth, additive top-level key — a sorted name list in the exact shape clients already parse for `in_maintenance`. `UP` is never served (the clients' Wave A rule already paints monitored devices green), so the payload is `[]` on a healthy network and scales with outages, not fleet size. Cold cache, unresolved server, or `cache_enabled: false` → `[]` with `cache_age_seconds: null`; clients must treat the list as unusable when the age is null or above 300 s. Any status literal other than `UP`/`DOWN` is neither counted nor listed and is logged once per cycle (`host rows: ignored literals [...]`); `null` is dropped silently.

### Changed

- The cycle log line now reads `Cache updated: N in maintenance, M host rows, K down` — `M` is the on-call signal that the crawl still sees host rows at all.
- Docstrings: the maintenance-map route summary and the `maintenance_cache` module/dataclass now describe both name lists.

## [2.11.1] - 2026-09-03

### Fixed

- **`/webhook` rejects bodies it cannot notify about.** A body that decodes to something other than an object (a JSON scalar or array — previously a 500), or to an object without a non-empty `hostname` (garbage, or an empty body, which form-decodes to `{}` — previously pushed to every registered device as a `⚠️ Unknown device — PROBLEM`), now returns **422** and sends nothing. The rejection is logged as one scrubbed line (content-type and body length only, never the body). The form-encoded fallback for BHNM's missing-content-type case is unchanged. **This is hygiene, not security:** the request still needs a valid `?secret=`; the open item about the query-string secret on the board is not addressed by this release. If a BHNM notification template ever posts without `$HOSTNAME` (e.g. an application-service incident with no device), it is now rejected and visible in the log rather than pushed as "Unknown device" — watch for `[Webhook] Rejected` after deploy.

## [2.11.0] - 2026-09-03

### Changed

- **Per-server caching is ON by default.** A `servers.json` entry without `cache_enabled`, and a server added through the admin portal, now cache. The default lives in exactly one place (`config.CACHE_ENABLED_DEFAULT`, read through `server_cache_enabled()` by the incident, tactical, threshold and maintenance crawlers and by `/api/v1/diagnostics`), mirrored by the admin app's `Server` dataclass. Set `"cache_enabled": false` to opt a server out. Honest cost: the flag gates **four** crawlers — incidents (getincidents + one detail call per incident, paced over `cache_refresh_seconds`), tactical (3 calls), thresholds (1 CSV), and the maintenance map (category/list + one paged host-status call per category, **every 60 s**, per server).
- **Existing entries are not rewritten.** The admin portal writes `cache_enabled` explicitly on every save, so a server previously saved with the toggle off stays off until re-saved (or edited in `servers.json`) and `/internal/cache/reload` is called.

### Added

- `/api/v1/diagnostics` now reports a fourth feed, `maintenance_map` (cached / age / count / failures), alongside incidents, tactical and thresholds. The crawler already recorded its telemetry; the payload just did not include it.

### Fixed

- `/api/v1/maintenance-map` docstring listed only `in_maintenance`; the response has carried `scheduled` since 2.10.0.

## [2.10.1] - 2026-09-02

### Fixed

- **Acknowledgements now show in the incident list instantly.** The cached list is a snapshot up to ~2 cache cycles (~4 min) old, so a successful ACK/UnACK looked lost until the cache caught up. The ack/unack proxy routes (dedicated and the restful catch-all path iOS uses) now patch the cached incident's state immediately on BHNM success, and a 5-minute override shields the patch from being reverted by an in-flight refresh cycle whose snapshot predates the ack. No client update needed.

---

## [2.10.0] - 2026-09-02

### Added

- **Scheduled-window registry — everyone sees planned maintenance.** BHNM has no list-scheduled API (`action=list` is active-only), but every app create flows through this middleware, so it now remembers its own creates (in-memory; the snapped start is ≤5 min out, so a restart merely degrades one window to creator-only visibility). `GET /api/v1/maintenance-map` gains `"scheduled": [{name, start_time, end_time}]` (served even on a cold cache) and `POST /api/proxy/maintenance/status` gains `"scheduled": {start_time, end_time} | null`, so ALL users' clients show the blinking wrench and "Starts at HH:MM", not just the creator's. Close clears the entry; entries auto-expire once active or ~4 min past start. Windows created directly in the BHNM UI remain invisible until active (no API exists for them).

---

## [2.9.1] - 2026-09-02

### Changed

- **Maintenance map refresh is a fixed 60 s** — it no longer inherits the per-server `cache_refresh_seconds` (up to 900 s). The map drives visible UI freshness (device-list wrenches), and its cost is bounded: 1 + #categories cheap calls per minute per server.

---

## [2.9.0] - 2026-09-02

### Added

- **`maintenance_cache.py`** — background maintenance map cache, twin of `threshold_cache`: one task per `cache_enabled` server iterates `category/list` + one bulk `get-host-and-service-status` call per category (name-keyed, paged at 500) and stores the set of device names whose host row carries `inMaintenance: true`. Record-don't-raise: a failed cycle keeps the previous set. Started on lifespan, restarted via `/internal/cache/reload`, telemetry via `diagnostics` like the other caches. On BHNM < 26.3.01 (no `inMaintenance` field) the set is empty by construction.
- **`GET /api/v1/maintenance-map`** — `{cache_age_seconds, in_maintenance: [names]}` for device-list badges. Deliberately NO live fall-through on a cold cache (that would be one upstream call per category in-request): cold or unresolved server returns an empty list, which clients render as "no maintenance state shown".

---

## [2.8.0] - 2026-09-02

### Added

- **`POST /api/proxy/maintenance/status`** — merged maintenance read for Device Detail: makes both BHNM calls server-side (`get-host-and-service-status` for the `inMaintenance` boolean, `maint_window_api.php action=list` for the active windows) and returns `{inMaintenance, windows}`. Best-effort: a failed upstream call degrades to `false` / `[]` instead of 5xx-ing the read. A host row without an `inMaintenance` key (BHNM < 26.3.01) reads as `false` — clients never show a maintenance state older servers can't confirm.
- **`POST /api/proxy/maintenance/close`** — ends maintenance for a device (`action=close` passthrough, same auth/key-resolution as create). Note: BHNM's `action=close` ends **all** windows for the device, scheduled ones included (verified live).
- **`X-Maintenance-Start` response header on `/api/proxy/maintenance/create`** — echoes the computed start epoch so clients can show "Starts at HH:MM" without duplicating the boundary math. Body remains a verbatim BHNM passthrough.

### Changed

- **Maintenance windows now start at the next 5-minute wall-clock boundary** instead of a flat +15 minutes (`snap_start`): press 10:00:00 → start 10:05:00; 10:05:01 → 10:10:00. If the next boundary is <60 s away it uses the following one (10:04:59 → 10:10:00) — BHNM rejects non-future start times. Server-side only; reaches iOS and PWA without a client release.

---

## [2.7.0] - 2026-09-01

### Added

- **Background BHNM health monitor** (`diagnostics.py`) — one shared, bounded `asyncio` probe loop per `servers.json` entry (every `DIAG_PROBE_INTERVAL` s, default 15; 4 s probe timeout; failures recorded, never raised) posting a lightweight `ha_status` call. Any HTTP response `< 500` counts as alive (a Traefik 5xx means the BHNM app is down). Down is declared only after `DIAG_DOWN_THRESHOLD` consecutive failures (default 2, flap resistance). Monitor tasks start on lifespan for **all** servers regardless of `cache_enabled`, and `/internal/cache/reload` starts/stops them like the caches.
- **`GET /api/v1/diagnostics`** — connection diagnostics for the app's 📱 App → 🖥 Middleware → 🗄 BHNM pipeline. Reads the monitor's cached result and passive per-feed cache telemetry only — it never awaits a live probe, so it is uniformly fast (~50 ms) and safe for clients to poll every 30 s. Payload carries counts/booleans/timestamps/latency and scrubbed, truncated error strings; no secrets, host only. Auth via `X-Proxy-Token` like the other `/api/v1/*` routes.
- **Per-feed cache telemetry** — the incident/tactical/threshold cache loops now record last-success time, upstream latency, last (secret-scrubbed) error, and consecutive-failure counts; the incident cycle raises on fetch failure so a failed cycle is recorded instead of masquerading as success.



### Fixed

- **Connection test ignored `BHNM_TLS_VERIFY`, producing false negatives for BHNM servers with self-signed or expired certificates** — `connection_test.py` hard-coded `verify=True` on both the reachability GET and the API-auth POST, so on-prem BHNM appliances (whose certs are typically self-signed *and* often expired) failed the test even when the runtime cache/proxy reached them fine. The test now reads `BHNM_TLS_VERIFY` from the environment (inherited by the admin container via `env_file: .env`), matching the rest of the middleware. Set `BHNM_TLS_VERIFY=false` to test such servers.
- **Reachability step mislabelled "HTTPS" regardless of scheme** — the step is now labelled "HTTPS Reachability" or "HTTP Reachability" based on the configured URL's actual scheme, so an `http://` URL pointed at a TLS-only port (Apache `400: You're speaking plain HTTP to an SSL-enabled server port`) is no longer disguised as an HTTPS check.

### Documentation

- Added a **Troubleshooting** section to `README.md` covering the HTTPS-only-port `400`, the self-signed/expired-cert `502 Bad Gateway` (and the global, startup-read nature of `BHNM_TLS_VERIFY`), and the requirement to `docker compose up -d --force-recreate` **both** containers after editing `.env`.

---

## [benem-admin 1.6.2] - 2026-06-16

### Fixed

- **Connection test and health-dot reported false `HTTP 400` failures against working BHNM servers** — both the detailed connection test (`connection_test.py`) and the passive health-dot check (`server_health`) posted to the Open 3.0 endpoint `/api/incident_api.php` using the *Legacy* API auth parameter `password=`. That endpoint requires `pwd=`, so BHNM rejected every probe with `400 Bad Request` even when the server, credentials, and scheme were correct. Switched both probes to `pwd=`, matching what the production incident/tactical caches already send. (The scheme is irrelevant — `http://` BHNM servers on non-standard ports such as `:9443` work fine.)

---

## [benem-admin 1.6.1] - 2026-06-01

### Fixed

- **Edit / Delete / Save / Cancel buttons silently broken for servers whose ID contains special CSS characters** (e.g. a dot, colon, or bracket) — `hx-target="#server-prod.main"` was parsed by the browser as a CSS selector requiring both `id="server-prod"` and `class="main"`, causing `htmx:targetError` before any network request was sent. Fixed by replacing all server-ID-based `hx-target` values with DOM-relative selectors (`closest .server-card`, `next .test-results`) that are independent of the ID string.
- **HTMX CDN dependency removed** — `htmx.min.js` (1.9.12) is now bundled in `static/`; a CDN outage or network restriction previously caused all admin interactions to silently fail.
- **Silent session-expiry on HTMX fragments** — `server_edit_form` now returns a visible "Session expired" error fragment on 401 instead of an empty body; `htmx:beforeSwap` allows 401 responses to swap into the DOM so the error is shown.

---

## [2.6.1] - 2026-05-16

### Security

- **Authenticated `/internal/cache/reload`** — endpoint now requires `X-Proxy-Token` (matching all other protected endpoints); Caddyfile blocks all `/internal*` paths externally as defence-in-depth
- **Server-side QR decryption** — new `POST /api/v1/qr-redeem` endpoint decrypts compact QR blobs using `BENEM_SECRET_KEY` on the server; `BENEM_SECRET_KEY` is no longer passed as a Docker build arg or embedded in the PWA JS bundle

---

## [2.6.0] - 2026-04-12

### Added

- **Threshold counts cache** (`threshold_cache.py`) — new background cache module that pre-fetches `list-thresholds-csv` from BHNM once per refresh interval, parses the CSV server-side in Python, and stores `{deviceName: count}` per server. At 10 000 devices this reduces per-client payload from ~50 MB of raw CSV to ~200 KB of compact JSON.
- **`GET /api/v1/threshold-counts`** — new cached endpoint that returns threshold counts as `{"cache_age_seconds": N, "counts": {"deviceName": count, ...}}`. Falls through to a live BHNM fetch (with server-side CSV parse) if the cache is cold. Activated by the same per-server `cache_enabled` toggle in the admin portal.
- **`postFormText()` helper** in PWA client (`pwa/src/lib/api/client.ts`) for endpoints that return CSV or plain text instead of JSON.

### Fixed

- **Content-Length header stripped** when forwarding maintenance create requests to BHNM — prevents BHNM from rejecting requests whose content-length changed during proxy rewriting.

---

## [2.5.0] - 2026-04-09

### Added

- **Tactical overview background cache** (`tactical_cache.py`) — pre-fetches category/site/app grouping data from BHNM, stores raw JSON in memory; one asyncio.Task per enabled server with `cache_refresh_seconds` interval.
- **`GET /api/v1/tactical-overview`** — cached tactical overview endpoint; falls through to live BHNM on cache miss.
- **`POST /api/proxy/maintenance/create`** — middleware proxy that creates BHNM maintenance windows. Resolves BHNM credentials server-side so the PWA never sends the raw API key.
- **Admin cache management** (benem-admin v1.6.0) — per-server cache toggle (enable/disable) and refresh interval input (60–900 s). Saving triggers `POST /internal/cache/reload` to restart the background loop.

### Fixed

- **Webhook payload parsing** — middleware now accepts both JSON and form-encoded webhook payloads and tries JSON parsing first regardless of `Content-Type`, preventing dropped notifications from BHNM servers that send incorrect content types.
- **Server config resolution via BHNM URL** — when `X-Proxy-Token` is a webhook secret rather than an API key, the middleware now correctly resolves the server config via `X-BHNM-Target` header to obtain real BHNM credentials for cache fallthrough requests.
- **Web push urgency** — `Urgency: high` header now set on all web push notifications, improving delivery reliability on Android.
- **Incident cache fallthrough** — builds a correct form-encoded BHNM request when the cache is cold and the client sends a header-only GET.
- **Cache lookup by BHNM URL** — `_server_id_for_bhnm_url()` now correctly resolves server IDs for both incident and tactical caches when the request includes an `X-BHNM-Target` header.

---

## [2.4.0] - 2026-04-07

### Security

- **Proxy authentication enforced** — all BHNM API proxy routes (`/api/proxy/*` and catch-all `/{path}`) now require a valid `X-Proxy-Token` header. Accepts either the global `PROXY_TOKEN` env var or any `api_key` from `servers.json`.
- **SSRF protection with DNS rebinding prevention** — `_validate_proxy_target()` resolves hostnames to IPs via `socket.getaddrinfo()` and blocks RFC 1918, loopback, link-local, and cloud metadata addresses. Hostnames explicitly configured in `servers.json` are always allowed.
- **CSRF middleware** (benem-admin v1.4.0) — `CSRFMiddleware` validates `Origin`/`Referer` headers against `Host` for all state-changing requests to `/admin/*`. Defense-in-depth alongside `SameSite=strict` session cookies.
- **HTTP security headers** — Caddy now sets `Strict-Transport-Security` (HSTS with preload), `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`, and strips the `Server` header on both domains. PWA domain additionally gets a `Content-Security-Policy`.
- **Non-root Docker containers** — both `bhnm-apns` and `benem-admin` Dockerfiles create a dedicated `appuser` system account and run as that user.
- **Session secret independence** — `SESSION_SECRET` no longer falls back to `BENEM_SECRET_KEY`; it must be set independently. Session lifetime reduced from 24 hours to 8 hours.
- **Admin log no longer stores full links** — `append_entry()` now stores a truncated prefix and SHA-256 hash instead of the full encrypted `benem://` URL. The `log/show` endpoint returns metadata only.
- **Container image pinning** — Caddy image pinned to `caddy:2.9-alpine` instead of floating `caddy:2-alpine`.

### Added

- `PROXY_TOKEN` environment variable in `config.py` and `.env.example` for global proxy authentication.
- PWA `nginx.conf` security headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`).

---

## [2.3.0] - 2026-04-02

### Added

- **Generate Link page redesign** (benem-admin v1.2.0) — two-column layout with a form panel on the left and an always-visible result panel on the right, connected by a fat arrow-shaped Generate button with glass shimmer animation. Icon and colour selectors replaced with custom dropdowns showing actual SVG icons and colour swatches. Username is now required before generation (disabled button with tooltip). Result URL is truncated with CSS ellipsis and a copy button; full URL shown on hover after 0.5 s delay. Accessibility improvements (`aria-disabled`), safe DOM construction (no `innerHTML`), and SVG 2.0 standard `href` attributes throughout.
- **Favicon** — BMC red hexagon logo served as SVG via `/static/` mount, displayed on all admin portal pages.

### Improved

- **`upgrade.sh` now health-checks both containers** — after rebuild and restart, the script verifies that both `bhnm-apns` (port 8889) and `benem-admin` (port 8001) return healthy status. If either fails, the relevant container logs are shown before exiting with an error.
- **Cleaner upgrade output** — Docker build progress lines and empty lines are filtered from the build output for a more readable upgrade experience.

---

## [2.2.0] - 2026-04-01

### Added

- **Per-device APNs environment routing** — each device token is now stored with its own `apns_environment` (`sandbox` or `production`). The middleware routes notifications to the correct APNs host per token, allowing Xcode debug builds (sandbox) and TestFlight/App Store builds (production) to coexist on a single middleware instance.
- `POST /register` accepts a new `environment` field (`"sandbox"` or `"production"`, defaults to `"production"`). Invalid values are silently normalised to `"production"`.
- Database migration: `apns_environment TEXT NOT NULL DEFAULT 'production'` column added to `device_tokens`. Existing tokens are treated as production (safe default).

### Changed

- `send_notification` and `send_to_all` now select the APNs host per token instead of using a global setting.
- `/health` response `apns_environment` field now returns `"per-device"` instead of the former global value.

### Removed

- **`APNS_USE_SANDBOX`** environment variable — no longer needed. Removed from `config.py`, `.env.example`, `setup.sh`, and documentation. The APNs environment is now determined per device at registration time.

---

## [2.1.2] - 2026-03-31

### Security

- **Webhook secret no longer written to logs** — partial secret suffix was previously included in `[Webhook]`, `[Register]`, and `[Unregister]` log lines; removed to prevent secrets appearing in server access logs or log aggregators.
- **Reachability check returns generic error messages** — the `/admin/reachability-check` endpoint previously reflected raw `httpx` exception strings back to the browser (leaking internal hostnames or network details); errors are now logged server-side and a generic `"Connection failed"` message is returned to the client.
- **XSS fix in Generate Link page** — BHNM and middleware URLs were previously injected into JavaScript `onclick` string literals; replaced with `data-url`/`data-result` HTML attributes read by JavaScript via `dataset`, eliminating the injection vector.
- **Login brute-force protection** — added `slowapi` rate limiting (5 attempts/minute per IP) to `POST /admin/login`; exceeding the limit renders the login page with a friendly error rather than a raw 429 response.
- **`servers.json` added to `.gitignore`** — this file stores server URLs, API keys, and PINs and must never be committed; it was previously untracked but not explicitly excluded.

### Changed

- **benem-admin dark mode UI** (benem-admin v1.1.0) — complete visual redesign of all 7 admin portal templates. Replaced Tailwind CDN with a custom CSS design system using CSS variables. New typography stack: Syne (headings), IBM Plex Sans (body), JetBrains Mono (code/tokens). Dark colour palette (`#0c0c14` base, `#131320` cards), electric blue accent (`#4f8ef7`) with glow, pulsing green operational status dot in sidebar, active nav item shown via left-border glow instead of background fill, glowing success/fail icons on connection test results.
- **HTMX server-URL fragment updated** — the dynamically injected HTML returned by `GET /admin/server-url` now uses the new dark CSS classes and the `data-url` attribute pattern consistent with the XSS fix above.
- `slowapi` added to `benem-admin/requirements.txt`.

---

## [2.1.1] - 2026-03-27

### Fixed

- **Event loop blocking during APNs delivery** — `send_notification` used a synchronous `httpx.Client` inside the async `receive_webhook` route handler, blocking FastAPI's event loop for the full APNs round-trip (up to 10 s per token). Converted to `httpx.AsyncClient` with `async`/`await` throughout `send_notification` and `send_to_all`.
- **Webhook accepts any non-empty secret** — `/webhook` checked only that `?secret=` was present, not that it matched any registered device; an unknown secret now returns HTTP 403 instead of HTTP 200 with `{"status": "no_devices"}`, preventing endpoint probing.

---

## [2.1.0] - 2026-03-26

### Added

- **BHNM API proxy** — catch-all `/{path}` route forwards all BHNM API requests from BeNeM through the middleware, enabling access to BHNM servers on private networks. Authenticated via `X-Proxy-Token` header; target server supplied per-request via `X-BHNM-Target` header.

### Fixed

- Proxy now returns a proper `Response` object to avoid FastAPI tuple serialisation error
- Proxy timeout increased to 60 s to accommodate slow BHNM responses
- `content-encoding` and `content-length` hop-by-hop headers stripped from proxied responses so Starlette correctly sets `Content-Length` from the decompressed body
- Proxy returns HTTP 504 on timeout and HTTP 502 on connection/request errors with descriptive messages

---

## [2.0.0] - 2026-03-26

### Changed
- **Per-device active-secret routing**: each BHNM server now uses its own unique webhook secret. `/webhook` forwards only to devices whose `active_secret` matches the incoming `?secret=` value.
- `/register` now stores the `active_secret` from the `X-Webhook-Token` header on a per-device basis. An empty header returns HTTP 400.
- `/webhook` now requires `?secret=` query parameter. An empty value returns HTTP 400.
- Removed global `WEBHOOK_SECRET` environment variable — authentication is now implicit and per-server (knowing the secret is the proof of authorisation).
- Database migration: `active_secret TEXT NOT NULL DEFAULT ''` column added to `device_tokens`. Existing installs are migrated automatically on first startup (safe `ALTER TABLE` with `OperationalError` ignored).
- `/health` response now includes `version` field.
- Startup log now prints middleware version and confirms per-device routing is enabled.

### Removed
- `WEBHOOK_SECRET` from `config.py` and `.env.example`
- `require_auth` function and `APIKeyHeader` dependency from `main.py`

---

## [1.0.0] - 2026-03-25

### Added
- Initial release: FastAPI middleware bridging BHNM webhooks to Apple Push Notifications (APNs).
- APNs HTTP/2 delivery via `httpx` with automatic token cleanup on 410 Gone / 400 BadDeviceToken.
- Incident deep-link support: `incident_id` embedded in APNs payload for direct navigation in BeNeM.
- Docker + Caddy deployment: automatic TLS via Let's Encrypt, single `docker compose up -d` setup.
- SQLite persistence via Docker volume (`/data/bhnm_apns.db`).
- Single shared-secret authentication via `X-Webhook-Token` header or `?secret=` query parameter.
- `setup.sh` interactive setup wizard generating `.env` from prompts.
