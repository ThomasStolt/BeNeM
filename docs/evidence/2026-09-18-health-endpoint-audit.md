# Audit — what `/health` tells an unauthenticated caller

**Measured 2026-09-18** against the live middleware 2.17.0, with **no credential of any kind**:
`curl https://bhnm-apns.hurrikap.org/health`. `/health` has no auth check —
`main.py:801-827` calls no `_verify_proxy_token`.

---

## 1. Field by field, as returned today

| field | value observed | what it actually discloses | verdict |
|---|---|---|---|
| `status` | `"running"` | liveness | **keep** |
| `version` | `"2.17.0"` | the middleware version | **keep** |
| `registered_devices` | `5` | **fleet-wide** device count across every tenant. Thomas has 4 clients, so this is not "your devices" and never was | **remove** |
| `apns_environment` | `"per-device"` | internal delivery configuration | **remove** |
| `cache` | `{"ThomasLabServer": {"active": 6, "closed": 0, "age_seconds": 101}}` | **the server_id of every cache-enabled server**, its **live open-incident count** and cache freshness | **remove** |
| `tactical_cache` | `{"ThomasLabServer": {"category": {"groups": 15 …}, "site": {"groups": 3 …}, "app": {"groups": 8 …}}}` | the same server ids plus **estate topology sizes** — how many categories, sites and applications that customer monitors | **remove** |

**Today only `ThomasLabServer` appears, because it is the only server with `cache_enabled: true`.
That is a configuration accident, not a limit.** The shape enumerates *every* cache-enabled
server, so turning caching on for Steve or Luiz would publish their server ids and incident counts
to anyone who can reach the URL. This is the same cross-tenant theme as the proxy allowlist and the
key-target binding.

**What an anonymous caller can do with it today:** learn that a customer called `ThomasLabServer`
exists, watch its open-incident count rise and fall in real time, see the size of its estate and
tell whether the middleware is still polling. Incident counts moving is operational intelligence
about somebody's network, available with a single unauthenticated GET.

## 2. Proposed payload

Thomas's starting position, adopted: **`/health` answers "is this service up and what version",
and nothing else.**

```json
{"status": "running", "version": "2.18.0"}
```

Everything else moves behind authentication. It already has a home: `/api/v1/diagnostics` calls
`_verify_proxy_token` and, since 2.17.0's key-target binding, a server's api_key resolves **only to
that server** — so per-server cache state is already scoped to the caller. `registered_devices` is
dropped there too, per ruling 4, because a fleet-wide count is not the caller's business on any
endpoint.

## 3. Consumers checked before proposing removal

| consumer | uses | effect |
|---|---|---|
| `upgrade.sh:182-183` | greps `"status":"running"` only | **unaffected** |
| `benem-admin` | reads the device count from **its own database** — `push_db.get_registered_devices()` at `benem-admin/main.py:31,282`, never from `/health` | **unaffected**, and the count stays in the admin panel where it belongs |
| iOS `DiagnosticsView.swift:206-215` | renders the "Middleware · /health" card | the card is being **deleted** by ruling 3 |
| PWA `DiagnosticsScreen.tsx:136-141` | same card | same |
| `pwa/src/lib/api/diagnostics.ts:32,82` | decodes `registered_devices` | field becomes optional and unused; decoder already types it nullable |

**Nothing depends on the fields being removed.**

## 4. Note for the record

This was found while removing the device count, which Thomas had spotted as not belonging in a
user's app. The device count was the smaller half. **The larger half — server ids and live
incident counts to an anonymous caller — was sitting in the same response and nobody had read it
field by field.** Auditing the whole payload rather than the one field that prompted the question
is what turned it up.
