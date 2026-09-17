# Key–target binding — design, 2.17.0

**Defect and ruling:** `docs/evidence/2026-09-17-cross-server-key-reachability-defect.md`
(§1–§5 the defect, §6 the ruling, §7 the duplicate-key ruling). **Not restated here.**
This file is the *shape* of the change and the things the ruling did not decide.

**Status: BUILT, NOT DEPLOYED.**

---

## 1. Where the gate lives, and why there is only one

**One guard, in `_validate_proxy_target`.** All six call sites already route through it —
the catch-all proxy, `_proxy_to_bhnm`, `_resolve_bhnm_target_and_key`, and the three
cold-cache fall-throughs. Adding the binding there closes every proxy route at once,
including the two that are not "the proxy".

The alternative — a check at each call site, or beside `bhnm_api_key = server_cfg["api_key"]`
where the leak physically happens — was rejected. Six copies of one rule is six places for it
to drift, and `main.py:794` needs no fix once the target can only be the key's own server.
Ruling 3 says this in the note; the docstring says it at the function; and
`test_every_validate_call_site_passes_the_request` already pins the call-site count at six, so
a seventh route cannot be added without the test naming it.

**Order inside the guard: config → allowlist → binding.** A caller whose target is not
configured at all is refused by the allowlist before binding is consulted, so the two refusals
stay independently testable.

## 2. The response says less than the log

Both refusals return **403** with the **same constant detail**,
`"Proxy target is not a configured server."` A caller must not be able to tell *"not
configured"* from *"configured, but not yours"* — that difference is exactly the map of other
tenants' servers, and an endpoint that reveals it by probe is an enumeration oracle.

The **log** carries the distinction, the full target and the `User-Agent`:

```
[Proxy] REFUSED target not in servers.json: '<target>' user-agent='<ua>'
[Proxy] REFUSED target not owned by this key: '<target>' user-agent='<ua>'
[Proxy] OPERATOR TOKEN selected target: '<target>' user-agent='<ua>'
[Proxy] CONFIG AMBIGUOUS: <path> (N api_key(s) shared … fingerprints: …) — refusing all proxy targets
[Proxy] CONFIG UNREADABLE: <path> (<err>) — refusing all proxy targets
```

Three of these are new. **No line carries a key**, an operator token, or a duplicate's value —
duplicates are named by `secret_fingerprint`, and two tests assert the absence.

This also does something parked item (e)3 asked for: the count of *silent* refusal paths drops.
It does not close (e)3 — the 401, 400 and 502 paths are still unlogged.

## 3. Fail closed, including on our own mistakes

`own != target` refuses when `own` is `None` — an unmatched token, or no request object at all.
`_verify_proxy_token` should already have rejected an unknown token, but the validator does not
assume a check in another function ran. `test_unmatched_token_fails_closed` and
`test_validator_without_a_request_is_refused` pin it.

## 4. What the ruling left open, and how it was decided

| open point | decision |
|---|---|
| duplicate keys: refusal or startup error | **runtime refusal (503), loud log, no crash.** Reasons in the note §7: servers.json is a runtime-rewritten bind mount, and a crash would stop paging for every server over one bad admin edit |
| does a server with **no** api_key count as a duplicate of another such server | **no.** Empty keys are skipped; two unconfigured servers must not take proxy routing down. `test_empty_api_keys_are_not_duplicates_of_each_other` |
| does the operator token still obey the allowlist | **yes.** Multi-server, not any-server. 2.16.0 is unchanged for it |
| do the allowlist tests still test the allowlist | **yes, via the operator token**, so an allowlist pass can never mask a binding regression. The two gates have two files |

## 5. The deploy risk this change creates — read before deploying

**A client holding server A's api_key while configured with server B's URL works today and
will get a 403 after 2.17.0.** That combination is not hypothetical: QR onboarding is a known
source of half-applied connections (`push-delivery-defects-sept-2026`), and 2.16.0 — deployed
this morning — accepted it, because its allowlist matched a target against *any* configured
server rather than the caller's.

**That is the defect being fixed, not a regression.** Such a client was already sending its
key to someone else's server. But it means the post-deploy verification is not "does the
middleware still answer":

1. Exercise **every** client — iPhone 15, iPhone 13 Pro Max, Android PWA, admin portal — as
   after 2.16.0.
2. Then `grep 'not owned by this key' /logs/middleware.log`. **A hit names a real
   misconfigured client by `User-Agent`**, and that client needs its connection re-imported,
   not a rollback.
3. `grep 'OPERATOR TOKEN selected'` — expected only for admin/operator traffic. A client
   `User-Agent` on that line would mean a client is holding the operator token, which is its
   own finding.

**The instrument is the log, not the absence of complaints.** A phone that silently stops
refreshing looks exactly like a phone nobody picked up.

## 6. Tests

`tests/test_proxy_key_target_binding.py`, 20 tests. The named regression test is
**`test_key_a_may_not_target_server_b`** — both servers configured, so 2.16.0's allowlist
passes both, which is precisely the case the allowlist cannot see.

`test_cold_cache_path_never_sends_key_a_to_any_host_but_a` asserts on the **outgoing request**,
not the response: a response assertion would pass even if the credential had already left the
process. It also asserts the legitimate fetch still goes out, to A, carrying A's key — the
binding must close the leak without closing the feature.
