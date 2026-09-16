# Runbook: capture the first anomaly webhook, and the 2.15.2 pending-override case

**Written 2026-09-16. STOP AT DESIGN applies to fixes, not to this — this is observation only.**
**Nothing here changes code, config or a deployment.**

**Why now:** Thomas attached the BeNeM Action Group to the recurring `Bandwidth` anomaly on
`U6-Pro-EG` / `UAP-AC-LR` (see the handoff's LAB CHANGE record). **Every webhook payload BeNeM has
ever measured was host-down.** The first anomaly webhook is the first non-host payload this project
will have seen, and it also retires the raspi-050 pull: a recurring anomaly is a repeatable PROBLEM
generator, so the unverified 2.15.2 case no longer needs hardware.

---

## Part 1 — What the existing log can and cannot tell us

**[MEASURED — read from `middleware/main.py`, 2026-09-16.]** This matters because three of the five
questions cannot be answered from the log at all, and finding that out *after* the event wastes the
event.

| question | recoverable from `/logs/middleware.log`? |
|---|---|
| `{NOTIFICATIONTYPE}` wire literal | **PARTIALLY.** `main.py:588` does `.strip().upper()` before anything is printed, so the log shows the token but **the wire casing is destroyed**. `CRITICAL` and `Critical` log identically |
| which `SERVICE*` macros are populated | **NO.** Only `service_desc` is read at all (`main.py:592`); nothing is logged |
| `{OUTPUT}`, including whether HTML is present | **NO**, twice over. Not logged, and `clean_bhnm_text()` (`main.py:445–453`) strips tags and unescapes entities *before* the value is used — so even the rendered notification is post-processed. **Whether HTML arrived is exactly what is destroyed** |
| which branch of the cache-patch map it takes | **YES**, by inference — see Part 2 |
| title and body the app renders | **NO.** Not logged. The phone is the only witness |

**Conclusion: the log alone cannot answer this. A raw capture is required.**

Note the log's silence is deliberate, not an oversight — `main.py:583–586` says *"Logged scrubbed:
content-type and length only, never the body."* Any capture cuts across that decision on purpose
and for one event.

### The capture mechanism — proposed, NOT ARMED

Caddy terminates TLS in `benem-proxy` and forwards **plaintext HTTP** to `benem-middleware:8889`
over the docker bridge `br-722f981ebb8a`. `tcpdump` is installed at `/usr/bin/tcpdump`.

```
# on the VPS, as root — read-only, writes a pcap to local disk only
tcpdump -i br-722f981ebb8a -s0 -w /root/webhook-capture.pcap 'tcp port 8889'
```

Then extract the POST bodies:

```
tcpdump -r /root/webhook-capture.pcap -A -s0 | sed -n '/POST \/webhook/,/^$/p'
```

**Needs Thomas's go-ahead before arming, for one reason:** a pcap writes webhook bodies —
hostnames, site names, alarm output — to disk on the VPS, which is the thing the middleware
deliberately refuses to do. It is local-only, nothing leaves the host, and the file should be
deleted once the fields are transcribed.

**Do not report "worked as expected". Report the observed fields**, including the ones that come
back empty — an empty `SERVICE*` on a threshold alarm is a finding, not a gap in the notes.

### Documented ≠ wire — the standing warning

BHNM's macro reference documents `UNACKNOWLEDGEMENT`; **the wire carries `DEACKNOWLEDGEMENT`**
(`main.py:597–599`, which accepts both because of it). The docs have already been wrong once about
this exact macro family. **Report the literal that arrives.** Docs say `CRITICAL` / `WARNING` for
thresholds; that is a prediction to be tested, not a fact to be confirmed.

---

## Part 2 — The cache-patch branch, and a prediction worth recording before the event

`main.py:631–632`:

```python
cache_state = {"ACKNOWLEDGEMENT": "ACKNOWLEDGED", "RECOVERY": "CLOSED"}.get(
    notification_type, "OPEN" if unack else None)
if cache_state and incident_id:
```

**[INFERENCE — stated in advance so it can be wrong in public]** If a threshold/anomaly PROBLEM
arrives as `CRITICAL` or `WARNING` rather than `PROBLEM`, `cache_state` is **`None`** and the whole
patch block is skipped — so **no patch line of any kind is printed**. Absence of a line is then the
evidence for which branch was taken.

That is fine for `PROBLEM` too (also `None`), so the branch is only interesting on the ACK. But it
means **"no cache line appeared" must not be read as "the patch failed"** — it is the documented
behaviour of the `None` branch, and this file says so in advance so nobody re-derives it at 2am.

---

## Part 3 — Readiness kit: have these four things open BEFORE it fires

**1. The log tail, already running, filtered:**

```
ssh root@bhnm-apns.hurrikap.org \
  'docker exec benem-middleware tail -f /logs/middleware.log' \
  | grep --line-buffered -E "Webhook|Pending state override|Cache updated|Cache patched|Cache not patched"
```

**Use `/logs/middleware.log`. Not `/app/logs/middleware.log`** — that path holds a 1 MB orphan
frozen at 19:19:29Z which answers greps with silence. See the orphan-log defect.

**2. The BHNM incident open and ready to acknowledge**, so the ACK is one click, not a navigation.

**3. Your phone, visible**, to witness the rendered title and body — the log never carries them.

**4. This file**, for the four lines below.

### The four lines, in the order they should appear

```
(a) [Webhook] <TYPE> — <host> — Incident <id>
        ← the wire literal, uppercased. The first non-host payload this project has seen.

(b) [Webhook] ACKNOWLEDGEMENT — <host> — Incident <id>

(c) [Webhook] Cache not patched: incident <id> is in no cache yet — override -> ACKNOWLEDGED
    recorded as pending, applies on first sighting within 300s
        ← the pending branch. This is 2.15.2's fix firing.

(d) [Cache:ThomasLabServer] Pending state override applied on first sighting:
    incident <id> -> ACKNOWLEDGED
        ← the promotion, incident_cache.py:217.
```

### Timing — and the honest odds

The pending path requires the ACK to arrive **before the incident's first cache sighting**. The
cache cycle is currently ~110–120 s wall (**[MEASURED]** 110.5 s at n=9; n is now 13, pacing 8.6 s).

**The incident can open at any point in that cycle**, so the time available is not 120 s — it is
whatever remains of the current cycle, uniformly somewhere between 0 and ~120 s. **Acknowledge as
fast as possible, not "within 90 seconds".** If the incident happens to open just before a
`Cache updated` line, there may be only seconds, and the run produces the ordinary patch path
instead. That is not a failure of 2.15.2; it is the wrong half of the cycle. Watch for the
`Cache updated` lines in the tail and, if you can choose, act right after one.

### What is actually still unverified — the prize

(c) and (d) were **already field-verified** on 2026-09-16 (evidence
`2026-09-16-2.15.2-ack-cache-patch-field-test.md`, PASS). Re-seeing them is confirmation, not news.

**The case that has never been exercised is a RECOVERY arriving while the override is still
pending** — i.e. between (c) and (d). Last time the TTL expired twelve minutes before the RECOVERY
came. A recurring bandwidth anomaly that clears on its own is a much better generator for this than
a device that has to be physically unplugged.

**So the sequence to hope for is: (a) → (b) → (c) → RECOVERY → (d).** If that happens, capture the
whole block verbatim — it closes the last unverified line in the handoff's section (d).

### Also unverified and worth noting while you are there

Every `RECOVERY` this project has measured was a host recovery. **An anomaly RECOVERY payload is
itself unmeasured** — whether one is even sent for a threshold/anomaly alarm is an open question,
and a silent clear is a finding as much as a payload is.
