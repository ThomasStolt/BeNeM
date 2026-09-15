# One sitting, two measurements — iPhone + lab + middleware log

Batched so Thomas's involvement is a single session. Both need one phone, the lab BHNM, and the
middleware log open. Everything below is ready to paste; nothing needs writing on the day.

**Before starting**, open a terminal with the log tailing and leave it visible:

```bash
ssh root@bhnm-apns.hurrikap.org \
  'docker logs -f --since 1m benem-middleware 2>&1 | grep -E "\[Register\]|\[Unregister\]|\[APNs\]|\[Webhook\]|\[Deliver\]"'
```

Since 2.14.0 `[Register]` prints the token suffix, so every line below is attributable to a
specific device without guesswork.

---

## Measurement 1 — does turning notifications off actually stop the paging?

Tests evidence item 5: all three unregister call sites are gated on the in-memory
`cachedDeviceToken`, which is `nil` for the first moments of every launch.

**Arm A — the suspected failure. Toggle off FAST.**

1. Confirm the phone is registered: note its token suffix from the log, or run
   `ssh root@bhnm-apns.hurrikap.org 'docker exec benem-middleware python -c "
   import sqlite3;print([r[0] for r in sqlite3.connect(\"/data/bhnm_apns.db\").execute(
   \"SELECT substr(token,-8) FROM device_tokens ORDER BY id\")])"'`
2. **Force-quit BeNeM** (swipe up from the app switcher).
3. Relaunch and **immediately** — inside a second, before APNs can answer — go to
   Settings → the server → switch notifications **off** → Save.
4. Watch the log. **Expect no `[Unregister]` line.**
5. Confirm the row is still there (command in step 1).
6. Fire a probe:
   `ssh root@bhnm-apns.hurrikap.org 'docker exec benem-middleware python /tmp/fanout_probe.py'`

**If the phone buzzes, the defect is confirmed:** the app says notifications are off and the
device is still being paged.

**Arm B — the control. Toggle off SLOWLY.**

7. Switch notifications back on, Save, confirm a `[Register]` line with this phone's suffix.
8. Force-quit. Relaunch and **wait ~10 seconds** doing nothing.
9. Now switch notifications off → Save.
10. **Expect `[Unregister] Token removed: ...<suffix>`**, the row to disappear, and the probe in
    step 6 to leave the phone silent.

**Record:** whether each arm produced an `[Unregister]`, whether the row survived, and whether
the phone buzzed. A and B differing is the whole result.

---

## Measurement 2 — what does the app show on a 401 versus a dead network?

Tests S1 spec Part 10.5. The question is whether stale-data-while-disconnected is **already** a
defect today, independent of revocation. Do not assume it is.

Warm the cache first: open the app, let the incident list and tactical screens load fully.

**Arm A — the server refuses the credential.** Retire the proxy token server-side so the app's
requests start failing authentication, without touching the network:

```bash
ssh root@bhnm-apns.hurrikap.org \
  'cd /root/BeNeM/middleware && cp .env /root/.env.bak.$(date -u +%H%M%S) && \
   sed -i "s/^PROXY_TOKEN=.*/PROXY_TOKEN=temporarily-rotated-for-measurement/" .env && \
   docker compose up -d bhnm-apns && sleep 5 && curl -s localhost/health | head -c 60'
```

With the phone **unlocked and the app foregrounded**, record, with timings:

- What does the incident list show — stale incidents, a spinner, an error, an empty state?
- How long before anything on screen changes at all?
- Does any screen say something is wrong, or does it keep asserting the last good state?
- Pull to refresh: what then?
- Background the app for 30 s and return: does it change?

**Restore immediately afterwards:**

```bash
ssh root@bhnm-apns.hurrikap.org \
  'cd /root/BeNeM/middleware && cp /root/.env.bak.* .env && docker compose up -d bhnm-apns && \
   sleep 5 && curl -s localhost/health | head -c 60'
```

**Arm B — the network is simply gone.** Put the phone in Airplane Mode with the app foregrounded
and record **exactly the same six observations**.

**The result that matters:** if Arm A and Arm B are indistinguishable to the user, that is a
defect **today** — the app cannot tell "the server refused me" from "I have no signal", and per
the doctrine in `CLAUDE.md` it is rendering unverified state as healthy in both.

The PWA half of this can be done in a browser without Thomas, and should be run the same way so
the two platforms are compared on identical arms.

---

## Afterwards

- Restore the phone's notification switch to ON and confirm a `[Register]` line.
- Confirm `.env` is restored and `/health` reports the expected version.
- Record both results in `docs/evidence/2026-09-14-bhnm-recovery-close-call-measurement.md`,
  whichever way they come out.
