# Design: the middleware must never contact a server that is not configured

**Status:** DESIGN ONLY. STOP AT DESIGN — nothing built, nothing deployed, no config touched.
**Date:** 2026-09-17
**Subject:** `middleware/main.py` — `_validate_proxy_target` (lines 203–242) and its six call sites.
**Ruling by:** Thomas, 2026-09-17. This note records a decided design, not options.
**Evidence:** §8.18 (the symptom), §8.19 (the wire capture that makes the change safe).

---

## Provenance

| mark | meaning |
|---|---|
| **[MEASURED]** | Observed against the live deployment or read from this repository on 2026-09-16/17 |
| **[RULED]** | Thomas's decision. Not to be re-litigated by a later session |
| **[INFERENCE]** | My reasoning. Attack this separately from the measurements |

---

## 1. The defect, in one sentence

**[MEASURED]** `servers.json` is not an allowlist. It is a **bypass list**, and the actual gate is
"does this hostname resolve to a non-private address" — so a token-holder can make the middleware
issue arbitrary requests to **any public host on the internet**.

```python
203: def _validate_proxy_target(target_url: str) -> None:
204:     """Block SSRF: only allow targets whose hostname is in servers.json or is non-private.
...
224:     if hostname.lower() in allowed_hosts:
225:         return  # Explicitly configured — always allowed
...
232:     infos = socket.getaddrinfo(hostname, None, proto=socket.IPPROTO_TCP)
...
241:         if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_reserved:
242:             raise HTTPException(status_code=403, detail="Proxy target address is not allowed")
     # ← falls off the end and returns None: ALLOWED
```

**Line 243 is the defect: the implicit `return` after the loop.** Any public address arrives here
and is permitted.

**[MEASURED]** This is not theoretical. `vpn.hurrikap.org:8888` is in `servers.json` **nowhere**,
resolves to the public address `87.166.74.218`, and the middleware attempted to reach it **71
times over three days** — 44 of them on 2026-09-16 alone, every ~2 minutes, 60 s per attempt
(§8.18).

---

## 2. The ruling

### 2.1 `servers.json` becomes the allowlist. The fall-through is deleted. **[RULED]**

A target whose **hostname and port** are not in `servers.json` is **refused**. The
"resolves-to-public-therefore-allowed" path at the end of `_validate_proxy_target` is removed
entirely. There is no residual "public hosts are probably fine" branch.

### 2.2 Refuse **before** resolving. **[RULED]**

Today an unconfigured, client-supplied hostname is handed straight to `socket.getaddrinfo`
(line 232). That **leaks client-supplied names to DNS** — every attacker-chosen hostname becomes a
lookup from the VPS's resolver, which is both an information disclosure and a free oracle. Once the
allowlist decides first, the resolution is unnecessary for refused targets and must not happen.

**Order:** normalise → allowlist check → *refuse here if absent* → only then, for configured hosts,
the existing private-IP handling.

### 2.3 **KEEP** the `servers.json` bypass of the private-IP check. **[RULED — do not tidy this away]**

Lines 224–225 let a configured host skip the private-address check. **This is deliberate and must
survive.** An on-prem BHNM legitimately sits on a private address — **Thomas's own lab server is
one** — and removing the bypass would refuse real, correct deployments.

> **To the future session that spots this and reaches for it:** the private-IP check exists to stop
> *client-supplied* targets reaching internal services. A host in `servers.json` is not
> client-supplied; it is operator-supplied. The check is about provenance, not about address range.
> Removing the bypass does not harden anything — it breaks on-prem. **Leave it.**

### 2.4 Match on hostname **and port**, normalised. **[RULED]**

**[MEASURED]** Today only `hostname` is compared (line 224), so a configured host named on a
*different port* passes the allowlist — `https://bhnm-b.tstolt.com:9999` is accepted today because
`bhnm-b.tstolt.com` is configured.

Normalisation, applied identically to both sides:

| aspect | rule |
|---|---|
| case | hostname lowercased |
| trailing slash | stripped before parsing |
| port | **explicit default** — `https` → 443, `http` → 80, so `https://h` and `https://h:443` are the same key |
| scheme | see below |

**[MEASURED]** the four configured URLs exercise three of these: one has a trailing slash
(`portal-netreo-ash-np2.onbmc.com/`), one an explicit non-default port
(`lpolli.ddns.info:9443`), two neither.

**[INFERENCE] — one addition beyond the ruling, for Thomas to accept or drop.** Include the
**scheme** in the key, so `http://configured-host:80` cannot match an entry configured as `https`.
The argument is concrete: `X-Proxy-Token` and `pwd=` ride on these requests (§8.19 measured 285 and
67 of 292), so an http downgrade to a configured hostname would put a BHNM credential on the wire
in cleartext to the public internet. Cost: one more field in a tuple.

### 2.5 The refusal must be **visible**. **[RULED]**

**[MEASURED]** Today a client naming a bad target gets a **60-second hang** (`PROXY_TIMEOUT = 60.0`)
and then a 504 — and the app renders nothing distinguishable. Thomas exercised that phone on
2026-09-17 and reported *"everything loaded, no visible timeouts"* while the middleware was
returning a 502 on `timeseries-metrics` at 09:21:27Z. The client does not surface proxy failure.

Three requirements:

1. **Immediate and distinguishable at the API.** A refused target returns at once — no DNS, no
   connection attempt, no 60-second wait — with a status and detail that a client can tell apart
   from "the server is down". `403` with a distinct detail string, not the generic
   `"Proxy target address is not allowed"` reused from the private-IP branch.
2. **Distinguishable in the client.** "This server is not configured on the middleware" is a
   different condition from "can't reach the server", and must not render as the second. **This is
   queue item 5 / the connection-status work**, and it is the *fifth* instance of the same failure:
   the device icon, the "registered and active" label, the push toggle, the migration that had not
   taken — and now a proxy target the app cannot reach and does not say so about.
3. **Loud in the log, every time.** A refusal today prints **nothing** — `HTTPException` raises
   without a log line. The refusal must log the refused target and the client's User-Agent.

**[INFERENCE] — and this is the part worth more than the fix itself.** Requirement 3 turns the
refusal log into **the enumeration the log structurally cannot produce today.** §8.19 needed a
packet capture — with its credential exposure — purely to answer "is any client naming an
unconfigured host?", because the target is printed only on failure. Once every refusal is logged by
target and User-Agent, that question is answerable from `grep` forever, for every client, including
ones that are idle today. **The fix creates the instrument that makes the next capture unnecessary.**

### 2.6 Blast radius — the allowlist fixes *who can be reached*, not just *what was named* **[RULED]**

**[MEASURED]** `_verify_proxy_token` (lines 182–200) accepts the `PROXY_TOKEN` env var **or any
`api_key` in `servers.json`**. Those api_keys are BHNM credentials that live **on phones and inside
onboarding QR codes**.

- **Today:** holding any one of them grants a relay to **any public host on the internet**, with
  arbitrary method, path, body and headers, originating from the BeNeM VPS's IP address.
- **Under the allowlist:** holding one grants exactly what that key is already for — reaching the
  BHNM servers the operator configured.

That is the real change. The stale-URL incident is a *symptom*; the blast radius is the defect. The
allowlist collapses "every public host" down to "the four servers in `servers.json`".

---

## 3. What is in scope, and what must still route through the check

Six call sites: `766`, `874`, `968`, `1106`, `1375`, `1449`. All six keep the call.

Two internal paths produce targets **from `servers.json` itself** — `_target_for_api_key` (61–74)
and `_single_server_url` (165–178). They are allowlisted by construction, **and they must still be
validated**, for two reasons: the URL text has to normalise through the same function so a trailing
slash or default port cannot cause a mismatch elsewhere, and a single unconditional gate is the only
kind that stays true after the next refactor. **Do not optimise the check away for them.**

### Fail closed, and say so

**[MEASURED]** Today `except (FileNotFoundError, json.JSONDecodeError, Exception): pass` (221–222)
leaves `allowed_hosts` empty, and an empty set plus the public fall-through means **everything is
allowed**. Under the allowlist an empty set means **everything is refused**.

**[INFERENCE] That is correct, and it adds no new outage mode.** A `servers.json` that cannot be
read already breaks registration, webhook fan-out, the caches and the admin portal — the proxy
continuing to work in that state is not a feature. But the failure must be **loud and specific**:
"servers.json unreadable — refusing all proxy targets" is a different log line from "target not
configured", and conflating them would waste an incident.

---

## 4. Migration risk — argued from the capture, not from confidence

**[MEASURED, §8.19]** A 35-minute packet capture on 2026-09-17, taken while Thomas exercised three
clients:

| | |
|---|---|
| HTTP requests reassembled | **292** |
| distinct `X-BHNM-Target` values | **1** |
| that value | `https://bhnm-b.tstolt.com` — **in `servers.json`** |
| requests to anything else | **0** |
| requests to `vpn.hurrikap.org` | **0** |
| clients observed | 2 iPhones (CFNetwork `3860.700.1` / `.2`) + Android PWA |
| header-less requests resolved by api_key | 45, with **zero** `No target header/key found` fallback lines |

**Every request every observed client made would pass the allowlist unchanged.** The change is
behaviourally inert for the entire measured population, which is what makes it safe to ship
quickly rather than stage.

**The honest limit, stated rather than buried:** a capture sees only clients that transmit. **Four
iOS tokens are registered and three clients spoke**, so at least one registered client is
**unexamined, not cleared**. If that client is naming an unconfigured host, the allowlist will
refuse it — **which is the desired outcome, not a regression.** The change cannot silently break a
working client; it can only make an already-broken one loud. That asymmetry is the migration
argument.

---

## 5. Recorded, deliberately not designed now

### 5.1 DNS rebinding — the shape of this changed when the resolver was deleted **[UPDATED 2026-09-17]**

**As first written, this item said:** lines 227–230 assert that resolving the hostname *"prevents
DNS rebinding attacks"*, and it does not, because `getaddrinfo` in the validator and httpx's own
resolution at request time are two separate lookups with a window between them.

**That description is now obsolete.** The implementation deletes the resolution entirely (§7.4) —
`getaddrinfo`, the private-address loop, and the `socket`/`ipaddress` imports are gone, along with
the comment that made the false claim. **The two-lookup window no longer exists, because there is
only one lookup: httpx's.**

**What remains, and it is a different thing:** a host that *is* in `servers.json` whose DNS later
resolves somewhere hostile. That is **admin-trust territory** — the same trust level as an operator
typing a private address into `servers.json` directly (§5.2). A client can no longer steer it,
which is the part that mattered.

**Still not designed, and the mitigation is unchanged in principle:** pin the validated address and
connect to that. But note it is now a *smaller* and *lower-priority* item than when it was written:
it is no longer a client-reachable weakness, and the false comment that motivated recording it has
been deleted rather than corrected.

### 5.2 A server pointed at a private address re-opens the internal surface for that hostname

**[MEASURED]** By §2.3's deliberate bypass, adding a `servers.json` entry whose URL resolves to a
private address makes that hostname reachable through the proxy, internal ranges included. The admin
portal can write `servers.json`, so this is **admin-controlled and acceptable** — it is the same
trust level as editing the file by hand.

**Written down so it is a known property rather than a later surprise.** Any future "let the portal
accept arbitrary server URLs from a less-trusted role" idea inherits this and must revisit it.

---

## 6. Ranking — where this goes

Asked for directly, so answered directly.

**Against the incident-cache cost model: this outranks it, clearly.** The cost model is an
efficiency problem with a slow-burning correctness edge; this is a credential-relay path that is
live in production right now.

**Against §8.8 coverage visibility: they do not compete for the same slot, and I would not delay
§8.8 for this.** §8.8 is the product's central open *question* and its next step is a read-only
measurement. This is a small, bounded, behaviourally-inert *code change* — hours, not weeks, with a
packet capture already proving it inert.

**[INFERENCE] Recommended order: ship this first, because it is cheap and finishes; keep §8.8 as
the highest-priority design; the cost model waits.** Shipping this also *helps* §8.8 — §2.5's
refusal logging is the instrument that answers "which clients are misconfigured", and §8.8 is
entirely about what the product can honestly claim to know about its own wiring.

**Severity, stated without inflation:** this is **authenticated** relay to **public** hosts. It is
not unauthenticated SSRF, and it is not reach into the appliance or the admin portal — the
private-IP check does block the docker bridge, and redirects are not followed (`follow_redirects`
is never set, so httpx's `False` holds). What makes it more than cosmetic is §2.6: the credential
that authenticates it is distributed to every phone that has ever onboarded.

---

## 7. Decisions — all three RULED 2026-09-17

### 7.1 Scheme **is** in the key. **[RULED]**

The key is **`(scheme, host, port)`**, normalised. An entry configured as `https` is **not** matched
by `http`. Thomas accepted the §2.4 argument over his own earlier ruling: §8.19 measured
`X-Proxy-Token` on 285 of 292 requests and `pwd=` on 67, so an http downgrade to a configured host
would put a BHNM credential in cleartext on the public internet.

### 7.2 Two distinct status codes, and the response echoes nothing. **[RULED]**

| condition | status | detail | log |
|---|---|---|---|
| target not in the allowlist | **403** | **constant** — `"Proxy target is not a configured server."` | the **full** target **and** the client `User-Agent` |
| `servers.json` unreadable | **503** | its own distinct detail | its own distinct line |

**The response must not echo the requested target.** Echoing client-supplied strings buys nothing,
and a constant also stops the endpoint confirming by probe **which** hosts are configured.

**Unreadable config is never 403.** Conflating *"I cannot read my config"* with *"your target is
wrong"* is how an incident gets spent on the wrong thing — and **the status code is where that has
to be visible, not only the log**.

### 7.3 The client change does **not** ship with this. **[RULED]**

The middleware refuses loudly first. Three reasons, recorded because they will be questioned later:

1. **It is provably inert for the measured population (§4), so it ships alone at near-zero risk.**
   Coupling it to an iOS release would delay a security fix by App Store latency.
2. **The refusal log is the instrument, and it only starts producing data once this ships.** Design
   the client's message from that data, not from a guess about what clients are doing.
3. **Even with zero client work this is already an improvement.** A misconfigured client goes from a
   60-second hang and a blank screen to an immediate, distinguishable error. **Fast and loud beats
   slow and silent**, today, with no app change.

### 7.4 Consequence of §2.3 + §2.1: the private-IP check becomes unreachable

**[INFERENCE — flagged because it looks like the thing §2.3 forbids, and is the opposite]** Once
only configured hosts pass the allowlist (§2.1) **and** configured hosts bypass the private-address
check (§2.3), **no code path can reach that check.** It is dead code, and the implementation deletes
it along with the `getaddrinfo` call.

**This is §2.3 being honoured, not tidied away.** §2.3 says a configured host is allowed whatever it
resolves to; making that total is exactly what the ruling asks for. It also satisfies §2.2 in the
strongest possible form: **there is no resolution anywhere in the validator**, so a refused target
cannot reach DNS even by accident.

The code comment says all of this at the function, so the next reader does not have to find this
file.
