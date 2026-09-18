# Deploy record — middleware 2.18.0 and PWA 0.17.0

**Deployed 2026-09-18.** Middleware and PWA together at **21:18:05Z**, both `RestartCount=0`, from
commit `1b87765`, pushed before deploying. The PWA was then redeployed alone as **0.17.0** — see
the rule below.

**Rollback images, tagged before the deploy:** `bhnm-apns-bhnm-apns:pre-2.18.0` and
`bhnm-apns-benem-pwa:pre-0.16.3`.

---

## THE RULE THIS DEPLOY ADDED

**Every deploy bumps the version of what it deploys, and the pre-deploy check reads the version
BEFORE tagging the rollback image.**

**The miss:** the PWA shipped a new bundle with none of its version changed. `package.json` read
`0.16.3` before the deploy and `0.16.3` after it, so the Settings screen said the same thing
either side and **the deploy could not state what it had deployed**. That is the `/health` defect
this very release was fixing, wearing a different label: `/health` was reduced to
`{"status", "version"}` precisely because a deploy needs one authoritative, readable answer to
"what is running", and then the PWA went out without one.

**It also produced a rollback tag naming a version that never existed** — `pre-0.16.4` — because
the tag was written from the version I expected to ship rather than from the version actually
running. The tag has been corrected to `pre-0.16.3`, which is what that image really is.

Two halves, both required:

1. **Bump the version of the thing being deployed**, every time, even when the change is "only"
   strings or a payload. The bundle hash changing is evidence for someone with shell access on the
   VPS; the version string is evidence for everyone else, including the operator holding the phone.
2. **Read the running version before tagging**, and name the tag after *that*. A rollback tag is a
   claim about an image's contents, and a claim written from expectation rather than observation is
   the failure mode in the root `CLAUDE.md`.

The bundle hash did change both times, so this deploy is verified either way — but it was verified
by a signal only one person can see, which is exactly what the doctrine warns about.

## Verified — observed

### `/health`, unauthenticated, exact bytes

```
before: {"status":"running","version":"2.17.0","registered_devices":5,"apns_environment":"per-device",
         "cache":{"ThomasLabServer":{"active":15,"closed":0,"age_seconds":23}},"tactical_cache":{...}}
after:  {"status":"running","version":"2.18.0"}
```

Fields: `['status', 'version']`. **None of the four configured server ids appears anywhere in the
body** — checked against `servers.json` rather than by eye.

### `/api/v1/diagnostics`

```
middleware keys: ['server_time', 'version']   registered_devices present: False
  incidents        cached=True age=20 count=13 fails=0 err=None
  tactical         cached=True age=14 count=15 fails=0 err=None
  thresholds       cached=True age=14 count=37 fails=0 err=None
  maintenance_map  cached=True age=6  count=41 fails=0 err=None
```

### `bhnm.version`, both server classes

```
Thomas' Lab Server (on-prem) → None                      → rendered "version unknown"
SaaS Demo Server             → '26.3-01.17.el8.noarch'
```

The on-prem `None` is the designed answer, not a failure: `/cloudversion` is session-gated there
and no api_key-readable alternative exists. Enhancement request open with BHNM —
`docs/evidence/2026-09-18-bhnm-ha-status-https-bug.md` is the sibling report.

### PWA

| | first deploy | after the bump |
|---|---|---|
| bundle | `index-Bif67NTx.js` (was `index-VqVnjPpv.js`) | see below |
| version string in bundle | `0.16.3` — **unchanged, the miss** | `0.17.0` |

New strings confirmed present in the served bundle: `version unknown`, `Stored: `, `not set`.
Confirmed **absent**: `Scan again to update`, `registered_devices`, `Middleware · /health`.

### Health after the deploy

Both containers `RestartCount=0`. **Zero errors or tracebacks** in the log since 21:16, and the log
proven to be writing during the window — last lines at 21:20:16Z, cache cycles continuing.
