# Two records: a withdrawn cause, and a named blind spot

**Written 2026-09-17, after the second iPhone 15 stall.**

---

## 1. WITHDRAWN — the 2.16.0 deploy window as the cause of the morning iPhone 15 incident

The 2026-09-17 morning incident (iPhone 15, "connection lost") was recorded as fitting inside the
2.16.0 client-visible degradation window, **11:19:45 → 11:23:02Z**. It did fit. That is not why it
happened.

**It recurred at ≈14:16Z with no deploy anywhere near it**, on the same device, with the same
signature: `api/v1/diagnostics` → `ERR`, `status: -1`, **10,015 ms** — the URLSession `catch`
branch hitting `timeoutInterval: 10` at `NetreoAPIService.swift:182` exactly. No HTTP status is
ever received in either case, so neither was a rejected request.

**Two occurrences, same device, same signature, only one near a deploy: coincidence, not cause.**
The deploy window was a true statement about time that was read as a statement about causation.
Do not reuse it.

Ruled client-side on 2026-09-17: **pushes landed on that phone during the same seconds its HTTPS
calls were timing out** — Apple's path fine while its own path stalled — and its configured
middleware URL is identical to the two clients that were working. Server side was measurably
healthy throughout: four feeds cached with 0 failures, another client's call served in the same
minute, Caddy silent, cache writes continuing either side of the event.

## 2. OPEN ITEM — nothing here can answer "did that client's request reach the VPS"

**Named, not designed.** This is a gap in the instrument, not a defect in a code path.

- **Caddy has no access log**, only an error log. Its silence means *"nothing errored"*, never
  *"nothing arrived"*.
- **A successful proxy prints nothing.** The middleware logs refusals, webhooks, registrations and
  cache cycles — not served requests.

So when a client reports a failure that leaves no trace, the stack cannot distinguish **"the
request never arrived"** from **"it arrived and was served fine"**. Both look identical: silence.
That is exactly the shape the root `CLAUDE.md` doctrine warns about, and it is **the same blind
spot that forced a packet capture** on port 8889 to answer "which clients send `X-BHNM-Target`" —
a capture that had to be time-boxed and destroyed because that port carries `X-Proxy-Token`,
`?secret=` and `pwd=` in plaintext (withdrawn-belief 13).

It has now cost two investigations: the wire capture, and the iPhone 15.

**Deserves its own design note. DO NOT DESIGN IT NOW.** Two constraints for whoever does:

1. An access log must not repeat `benem-proxy`'s existing problem — its `http.log.error` entries
   store the **complete request header block, including `X-Proxy-Token` and `Cookie`**, in
   `docker logs`, permanently (parked item (e)2). A new log that records headers un-redacted would
   turn a one-entry exposure into a continuous one.
2. The question to answer is narrow — *did this client reach us, and when* — so the cheapest thing
   that answers it is the right size. Method, path, status, timing, client `User-Agent`. **Not**
   headers, **not** bodies.
