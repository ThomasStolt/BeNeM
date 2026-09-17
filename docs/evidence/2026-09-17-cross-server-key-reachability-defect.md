# DEFECT — a server's api_key reaches the OTHER configured servers on the proxy path

**Found:** 2026-09-17, by code reading at `main.py` HEAD `28bba34` (= deployed 2.16.0).
**Method:** read-only. No probe was sent; no log line was written by this analysis.
**Answer to the question asked:** **CROSS**, not ISOLATED.

> **Scope note.** This is *reachability*, not a read of another server's authenticated data.
> The distinction is the whole finding and section 4 states it exactly. Writing "CROSS" without
> section 4 would repeat withdrawn-belief #10's error in the opposite direction.

---

## 1. The proxy path — CROSS

Two functions, neither of which compares the token to the target.

`_verify_proxy_token`, `main.py:179-198` — accepts **any** api_key in `servers.json` and returns
nothing about *which* server the key belongs to:

```python
188:    if PROXY_TOKEN and token == PROXY_TOKEN:
189:        return
190:    # Accept if it matches any api_key in servers.json
192:        with open(SERVERS_JSON_PATH) as f:
193:            for s in json.load(f):
194:                if s.get("api_key") == token:
195:                    return
```

The catch-all proxy, `main.py:1446-1475` — the target comes **straight from the client header**,
and the key is never consulted:

```python
1447: async def proxy(path: str, request: Request):
1448:     _verify_proxy_token(request)
1451:     target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")
1475:     _validate_proxy_target(target_base, request)
```

`_validate_proxy_target`, `main.py:232-267`, is a membership test against the **whole** allowlist —
all four servers, not the caller's one:

```python
260:    if _target_key(target_url) not in allowed:
```

**So: key A + `X-BHNM-Target: <server B>` passes auth (A is a valid key) and passes the allowlist
(B is configured) and is relayed to B.** `_proxy_to_bhnm` (`main.py:1112-1132`), which backs the
dedicated routes, has the identical shape — same header, same absence of any key/target check.

2.16.0 narrowed the blast radius from *the whole public internet* to *the four configured
servers*. It did not make a key reach only its own server, and it was not designed to.

## 2. The cached endpoints — ISOLATED, and **the supplied key decides**

`/api/v1/incidents`, `main.py:762-768`:

```python
763:    api_key = request.headers.get("X-Proxy-Token", "").strip()
764:    server_id = incident_cache._server_id_for_api_key(api_key)
765:    if not server_id:
766:        bhnm_target = request.headers.get("X-BHNM-Target", "").strip()
768:            server_id = incident_cache._server_id_for_bhnm_url(bhnm_target)
```

**The key wins; the header is only a fallback for `if not server_id`** — unreachable for an
api_key-authenticated request, because `_verify_proxy_token` already required the key to match a
server, so `_server_id_for_api_key` cannot return `""`. `_resolve_server_config`
(`main.py:100-109`) has the same key-first precedence.

Identical shape at `main.py:875-879` (tactical), `942-946` (maintenance-map), `971-975`
(thresholds), and `_registry_server_id` (`1369-1375`) for the scheduled-window writes.

**No server key can select another server's cache.** That part of the question is ISOLATED.

### 2a. THE SHARP END — the cold-cache fall-through sends the caller's credential to another server

`main.py:784-794`, reached when the resolved server has no warm cache:

```python
784:    server_cfg = _resolve_server_config(request)          # -> A (by key)
785:    target_base = request.headers.get("X-BHNM-Target", "").strip().rstrip("/")   # -> B
786:    if not target_base:
787:        target_base = (server_cfg or {}).get("url", "").rstrip("/") if server_cfg else ""
794:    bhnm_api_key = server_cfg["api_key"] if server_cfg else api_key               # -> A's key
```

**The header overrides the key's own URL, and the credential sent is the caller's own.** Key A +
target B makes the middleware POST `pwd=<A's api_key>` to **B**'s `/api/incident_api.php`.

B does not return A's data — wrong `pwd` — so this is not a data read. It is **A's BHNM credential
transmitted to B**. Reachable for any key whose server has no warm cache, which is **three of the
four**: `cache_enabled` is `true` only for `ThomasLabServer`.

**This is not a qualifier on §1. It is the sharp end of the defect, and it needs no attacker.**
The trigger is an ordinary misconfigured client — a stale or wrong `X-BHNM-Target`, which is
**exactly the `vpn.hurrikap.org` shape observed on the morning of 2026-09-17**, a phone naming a
host it had no business naming. The only reason that one leaked nothing is that
`vpn.hurrikap.org:8888` **did not answer**; the request hung for 60 s and died on `PROXY_TIMEOUT`.

**Configured hosts answer.** Point the same mistake at one of the other three entries in
`servers.json` — all reachable, all allowlisted since 2.16.0 — and the middleware completes the
POST, delivering one operator's BHNM api_key into another operator's access log, in a request the
client believed was aimed at its own server. Nothing in the system reports that this happened:
the client sees an ordinary failed fetch, and no log line names it.

A credential leak whose trigger is a typo, not an exploit, is not a corner case. It is the case.

### 2b. `PROXY_TOKEN` is set, and it *is* a master key

Observed in the running container: `PROXY_TOKEN` set, **64 characters**.

It is exempted at `main.py:188-189` before the per-server lookup, so `_server_id_for_api_key`
returns `""` for it — which means the `X-BHNM-Target` fallback at `766-768` **does** fire, and
`_resolve_server_config` returns **B's** config, so `bhnm_api_key = server_cfg["api_key"]` is
**B's real stored key**. PROXY_TOKEN therefore reads any server's cache and spends any server's
stored credential.

That is presumably deliberate for an operator token. It is recorded here because it is the one
path that *does* match "other people's incident data readable without their credential", and
because nothing in the code or the docs says it is intended.

## 3. Severity, stated plainly

**Medium, not critical — and the reason it is not low is Steve's server, not key strength.**

- The **leak** (§2a) needs no attacker and no weak key — a wrong `X-BHNM-Target` is enough.
- It is **not** a read of another tenant's incident data with a server key. Cache selection is
  strictly key-driven (§2) and the catch-all injects no credential, so B's own API auth still
  gates B's data.
- It **is** an authenticated relay, from the VPS's IP and network position, to three servers the
  key holder has no relationship with — arbitrary method, path, body and headers, reaching
  anything those hosts expose without auth (login pages, error surfaces, version banners), and
  probing their reachability.
- It **is**, via §2a, a path that hands one operator's BHNM api_key to another operator's server.
- `bhnm-b.tstolt.com` and `lpolli.ddns.info:9443` are dev servers that can be rebuilt — Thomas's
  ruling, recorded. **`im-ui-server-netreo.qa.sps.secops.bmc.com` is a third party's host inside
  BMC**, and a relay pointed at it is not covered by "we'll rebuild it".

Key *strength* is explicitly out of scope per Thomas's ruling and is not what makes this a defect.
The defect is that the **binding between key and target does not exist**; it would be equally
present if every key were 64 random characters.

**No fix is designed here, by instruction.**

## 4. What this defect is NOT

Reachability is not readability. A server key does **not** yield another server's incidents,
tactical data, thresholds or maintenance state. Anyone citing this note must carry §2 with §1.

## 5. Recorded for (e)1 — rotation scope

`servers.json` holds **four** servers, **four distinct keys** (no accidental duplicates —
verified by fingerprint, `distinct keys: 4 of 4`). Key lengths as deployed:

| id | server | url | key length | cache |
|---|---|---|---|---|
| `SaaS Demo Server` | SaaS Demo Server | `https://portal-netreo-ash-np2.onbmc.com/` | 59 | false |
| `ThomasLabServer` | Thomas' Lab Server | `https://bhnm-b.tstolt.com` | **15** | true |
| `Steve` | Steve's SaaS Dev Server | `https://im-ui-server-netreo.qa.sps.secops.bmc.com` | 60 | false |
| `Luiz` | Luiz's Lab Server | `https://lpolli.ddns.info:9443` | **9** | false |

**(e)1 rotation covers all four, not only Thomas's.** Handoff (e)1 named the 15-character key
alone; **Luiz's is 9 characters**, and **Steve's server belongs to a third party**, so rotation is
not a single-owner change. Every one of these keys is simultaneously a proxy token (`main.py:194`).

*Note the ordering hazard, since `_server_id_for_api_key` (`incident_cache.py:38-47`) returns the
**first** match: two servers sharing a key would silently resolve to whichever is first in the
file. Not the case today — stated so a rotation does not create it.*

---

## 6. The ruling — Thomas, 2026-09-17. Decided, not options

1. **KEY–TARGET BINDING.** A request authenticated with a server's `api_key` may target **only that
   server**. Mismatch is **403**, logged with target and `User-Agent`, **constant** detail string
   that does not echo input. **Same shape as 2.16.0's refusal — reuse it, do not invent a second
   style.**
2. **`PROXY_TOKEN` keeps multi-server access.** It is the operator token and that is its job. But
   **log when it selects a server**, so operator cross-server use is visible rather than
   indistinguishable from a client.
3. **§2a is fixed BY CONSTRUCTION once binding lands** — the target can only ever be the key's own
   server, so A's key can only ever go to A. **`main.py:794` is not patched separately, on purpose.**
   Anyone reading `bhnm_api_key = server_cfg["api_key"]` next to a header-supplied `target_base`
   and reaching for a second guard should stop: the guard is upstream, at
   `_validate_proxy_target`, and every one of the six call sites goes through it. **Do not fix
   this twice** — a second, redundant check would be a new place for the two to disagree.
4. **Duplicate `api_key`s are detected at load and fail loudly** — see §7 for the ruling on *how*.
5. **Version 2.17.0.**

## 7. Duplicate api_keys — refusal, not startup error

**Ruled: a runtime REFUSAL (503), with a loud startup log line as a secondary.** Not a startup
crash.

Two reasons, both specific to this deployment:

- **`servers.json` is edited at runtime.** `benem-admin` writes it and calls
  `/internal/cache/reload`; the file is a bind mount, not baked into the image. A startup-only
  check passes at boot and is **silently wrong for every edit afterwards** — which is the failure
  shape in the root `CLAUDE.md` doctrine, a green signal measuring something other than the thing
  that matters.
- **A crash-on-boot would take paging down for every server** because one admin edit was
  ambiguous. Webhook ingestion and APNs delivery do not depend on proxy routing. Refusing proxy
  requests while continuing to page is strictly the better failure.

The refusal reuses the existing config-failure status and detail (**503**, `"Server configuration
unavailable"`), because "I cannot route safely" is the same class of incident as "I cannot read my
config" — and it stays distinct from the 403, which is about the caller's target. The **log lines
differ**: `CONFIG AMBIGUOUS` against `CONFIG UNREADABLE`. Duplicate keys are named by
**fingerprint** (`secret_fingerprint`), never by value.

Under binding, a duplicate is no longer a curiosity: `_server_id_for_api_key`
(`incident_cache.py:38-47`) returns the **first** match, so two servers sharing a key would bind a
caller to whichever entry sorts first in the file — routing one operator's request to another
operator's server **and calling it correct**. That is a correctness bug, and it is refused rather
than warned.
