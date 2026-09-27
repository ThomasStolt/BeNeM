# App-token onboarding: the phone holds no BHNM credential

**Date:** 2026-09-27. **Status:** design note, not approved, no code.

## The ruling (Thomas, 2026-09-27)

**The phone must hold no BHNM credential.** The QR carries an **app token** issued per QR by the
portal, plus the middleware URL, server name, symbol, colour and ack user. The middleware maps the
token to a server record, and that record holds `bhnm_url`, `api_key`, `pin` and the webhook
secret. **Push fan-out is by server, reached through the token, not by webhook secret.** That also
retires the shared-secret problem from S1 1b. The Test & Save probe becomes a middleware endpoint
that checks the token and the server's BHNM reachability.

**Transition:** the middleware keeps accepting the legacy `api_key` as `X-Proxy-Token` and the
legacy secret on `/register` until no `BeNeM/53` or `BeNeM/55` appears in the `[Client]` lines.
That is Thomas's word, the same gate as M1-drop.

## What the phone holds today

Read from the code at `8b2e915`:

- **The QR** (`benem-admin/main.py:229-244`) carries `bhnm_url`, `middleware_url`,
  `notifications`, **`api_key`**, **`pin`**, `user`, `name`, **`push_secret`**, `symbol` and
  `color`. It is AES-256-GCM encrypted, but the key ships inside the app
  (`DeepLinkHandler.swift:156`). **The encryption is obfuscation, not protection.**
- **iOS** keeps `apiKey`, `pin` and `webhookSecret` in the Keychain per connection
  (`SavedConnection.swift:73-94`), plus the legacy AppStorage keys `netreo_api_key`, `netreo_pin`
  and `netreo_webhook_secret` (`ContentView.swift:4-9`, `ServerConfigView.swift:9-10`).
- **The PWA** keeps the same fields in field-encrypted `localStorage` (`storage-crypto.ts`). The
  key for that is in the same browser, so this is obfuscation too.
- **Every BHNM call carries the credential in its body.** For example
  `NetreoAPIService.swift:73-74` sends `password=<api_key>` and `pin`. The catch-all proxy
  (`main.py:1767`) forwards the client's body **verbatim** and uses the `password` in it to pick
  the target (`_target_for_api_key`).
- **The api_key doubles as the proxy token.** `X-Proxy-Token: <api_key>` resolves the server
  (`main.py:100`), and `X-BHNM-Target: <bhnm_url>` is the fallback.
- **Registration is by secret.** `/register` stores `X-Webhook-Token` as `active_secret`
  (`main.py:432`), and fan-out selects devices by secret (`get_tokens_for_secrets`).
- **The Test & Save probe** (`ServerConfigView.swift:300-345`) posts to
  `/api/incident_api.php` through the proxy with the draft api_key. It relies on BHNM answering
  `Method not supported.` (51 B) for a good key and `Password failed.` (46 B) for a bad one.

**So a phone today holds everything needed to call BHNM directly, from anywhere, for as long as
the key is valid.** A lost phone means rotating the BHNM api_key, which breaks every other phone
at once.

## The token table

A new table in the middleware's SQLite (`/data/bhnm_apns.db`), next to `device_tokens`:

```sql
CREATE TABLE IF NOT EXISTS app_tokens (
    token_hash   TEXT PRIMARY KEY,      -- sha256 hex of the token; the token itself is never stored
    server_id    TEXT NOT NULL,         -- servers.json id
    label        TEXT NOT NULL,         -- the QR Username, for the portal's list and the logs
    issued_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP,             -- written at most once a minute per token
    revoked_at   TIMESTAMP              -- NULL = live
);
```

- **Format:** `bnm_` followed by 32 random bytes as base64url, 47 characters in all. The prefix
  makes a leaked token greppable and tells it apart from a BHNM api_key at a glance.
- **It is stored hashed.** A database copy yields no usable token, and the plaintext exists only
  in the QR and on the phone.
- **Logs** show `...<last 4>` and the label, the same rule as device tokens (`token[-8:]` there).
- **The middleware is the only issuer.** The portal calls a new
  `POST /internal/app-tokens {server_id, label}`, authenticated with `PROXY_TOKEN` as
  `/internal/cache/reload` already is. It receives the plaintext once. One store, one writer.
- **Revocation** is `revoked_at`. A revoked token gets 401 on every route, and its devices stop
  receiving push at the next fan-out. It does not wait for a re-registration.

## Middleware changes

1. **A new header, `X-App-Token`.** It is the only thing a new client sends. It resolves to the
   server record and nothing else is consulted: no `X-BHNM-Target`, no body `password`.
   - **A new header rather than a new value in `X-Proxy-Token`,** so the two are never ambiguous.
     Any `X-Proxy-Token` is by definition legacy, and the legacy path can be counted and later
     deleted whole.
2. **The proxy injects the credential.** On an app-token request, every route that talks to BHNM
   strips `password`, `pwd` and `pin` from whatever the client sent and writes the server
   record's own. The client body then carries no credential, and a client that still sends one
   cannot pick a different target with it.
3. **`/register` and `/register-webpush` accept `X-App-Token`.** The row stores
   `app_token_hash` and `server_id` and leaves `active_secret` empty.
   - **New columns only:** `app_token_hash TEXT NOT NULL DEFAULT ''`, added the same safe way as
     `active_secret`.
   - **Re-registering an existing device** with a token overwrites its legacy secret. That write
     is the migration.
4. **Fan-out by server.** The webhook resolves its server as today, from the secret via
   `webhook_secrets` (S1 1a). It then selects devices by `server_id` through live
   (non-revoked) tokens, **in union with** today's by-secret selection. Duplicates are removed by
   device token.
   - The union goes when the legacy path does.
   - **An unresolved webhook keeps today's fallback.** Paging nobody is the worse failure.
5. **The probe endpoint, `POST /api/v1/probe`.** It takes `X-App-Token` and answers:
   ```json
   {"token": "valid", "server": "ThomasLabServer",
    "bhnm": {"reachable": true, "checked_at": "2026-09-27T21:04:11Z", "detail": "credential accepted"}}
   ```
   - **The BHNM half** is the same constant-size check the app makes today (an unsupported
     method, and read which error comes back), now run server-side with the server record's key.
   - **Three distinct failures:** token unknown or revoked (401), BHNM unreachable (`reachable:
     false` with the error), and BHNM rejecting the server's own key
     (`detail: "credential rejected"`). The last one is an admin problem, not a phone problem,
     and the app says so.
6. **Every legacy-auth request logs one line:**
   `[Auth] legacy api_key from BeNeM/<build> server=<id>`, rate-limited per build per hour. The
   M1-drop gate reads `[Client]` lines, and this line makes the legacy path's own traffic readable
   the same way. **An absence of legacy lines is then a measurement, not a silence.** Before the
   gate is called, show the line appearing for a known legacy client.

**Payload rule:** the only client-visible change is the new probe route. No existing response
loses a field, so the GAIN rule is not engaged.

## Portal change

- **Generate** issues a token through `/internal/app-tokens` and builds a **v2 QR**:
  ```json
  {"v": 2, "middleware_url": "...", "app_token": "bnm_...", "name": "...",
   "symbol": "...", "color": "#...", "user": "...", "notifications": true}
  ```
  - `user` stays required, as today (`generate.html:329`). It becomes the token's `label`.
  - **No `bhnm_url`, `api_key`, `pin` or `push_secret`.**
- **A token list per server:** label, issued, last seen, and a **Revoke** button. Tokens are
  shown masked. The plaintext is never shown again after the QR page.
- **The v1 QR stays available during the transition**, behind an explicit "legacy app (build 55
  or older)" option.
  - **The QR is a client-decoded payload.** Build 55's `DeepLinkHandler` expects `api_key`, so a
    v2 QR on a 55 phone is a removed field on a shipped decoder.
  - **Check the shipped decoder before relying on this** (`git show c09c64b:ios/...`), both for
    the missing keys and for the unknown `v`. The expected result is that 55 refuses the v2 QR,
    which is safe but must be shown.
- **`admin.jsonl`** records the token's last 4 and label alongside today's entry.

## What the app stores and shows

**Stored per connection:** middleware URL, server name, symbol, colour, ack user, app token.
- **iOS:** the token in the Keychain, the rest where it lives today.
- **PWA:** in its existing storage.
- **Nothing else.** `bhnmURL` goes too: the server is resolved from the token, so the client has
  no reason to know BHNM's address, and `X-BHNM-Target` is not sent.

**Deleted on migration:** `apiKey`, `pin` and `webhookSecret` from the Keychain and the PWA
store, plus the legacy AppStorage keys `netreo_api_key`, `netreo_pin`, `netreo_webhook_secret`
and `netreo_bhnm_url`. They are deleted only **after** a successful probe and a successful
`/register` with the token (see Migration).

**Shown** (doctrine: nothing green that has not been verified and dated):
- **Connection:** server name, middleware host and ack user.
  - The status reads `Connected · confirmed 14:03`, from the probe's `checked_at`.
  - Or `Can't reach BHNM · last confirmed 13:40`, or `Access revoked — ask your admin for a
    new QR`.
  - **Never a bare "Connected".**
- **Push:** `Registered · confirmed <time>` from the `/register` response, as Part 11 of the
  webhook-secret design already requires.
- **Support view only:** the token masked as `bnm_…a1b2`, its issue date if the probe returns
  it, and the build number. Nothing more. **No secret is ever displayed, copied or logged in
  full,** Debug included (the item 4 rule, `51e80aa`).
- **Manual entry of `api_key`, `pin` and `bhnm_url` disappears from Settings.** A connection is
  created by QR or not at all. There is nothing left for a person to type that the phone should
  hold.

## Migration: four phones and the PWA

**Order:** middleware, then portal, then store release, then each device.

1. **Middleware and portal deployed.** Legacy clients are unaffected: their `X-Proxy-Token`,
   `X-BHNM-Target` and `X-Webhook-Token` paths are unchanged.
2. **The new iOS build reaches the store,** and each phone updates. It keeps working on its v1
   connection, because legacy is still accepted.
3. **Per phone:**
   - Thomas generates a v2 QR under that person's Username, and the phone scans it.
   - The app probes, then re-registers its APNs token with `X-App-Token`, then deletes the legacy
     fields for that connection.
   - **If either the probe or the registration fails, nothing is deleted.** The phone stays on
     its working v1 connection.
4. **Verified per phone, in the middleware log,** not on the phone:
   - `[Register] app token ...<last4> label=<Username> server=<id>`, and
   - the `device_tokens` row carrying an `app_token_hash` and an empty `active_secret`.
   - **Then one test push per phone,** confirmed by the `[APNs] Sent to ...<last8>` line **and**
     by the person.
5. **The PWA:** same sequence. A new bundle, then the v2 link or QR, then re-subscribe Web Push
   with the token, then delete the stored fields. The version bump is per the deploy rule.
6. **The gate:** Thomas's word that no `BeNeM/53` or `BeNeM/55` appears in `[Client]` lines, and
   no `[Auth] legacy` line for a stated window.

## Tests

**Middleware:**
- A token resolves to its server, and a revoked token gets 401 on every route family: cache,
  proxy, register, probe.
- **Credential injection:**
  - A client body carrying `password=<other server's key>` under a valid app token still reaches
    **its own** server with **its own** key.
  - The forwarded body contains exactly one `password`, the server's.
- `/register` with a token writes `app_token_hash` and `server_id`, and clears `active_secret` on
  an existing row.
- **Fan-out union:** a token-registered device and a secret-registered device on the same server
  both get the push, and a device registered both ways gets it **once**.
- A revoked token's device is excluded at the next fan-out, with no re-registration.
- **The probe's three failure cases, each distinct.** The BHNM half is asserted against the
  measured 46 B and 51 B answers.
- The legacy line appears for a legacy request and not for a token request. Its absence case is
  shown capable of being non-empty first.
- `/internal/app-tokens` refuses without `PROXY_TOKEN`, and the plaintext never reaches the log.
- `tests/test_no_credentials_in_repo.py` still passes with the `bnm_` fixtures. Fixture tokens
  are built at runtime, not written as literals.

**Portal:**
- A v2 QR contains none of `bhnm_url`, `api_key`, `pin` or `push_secret`.
- `user` is still required.
- A revoke is visible to the middleware on the next request.

**iOS and PWA:**
- v2 import stores exactly the six fields.
- Legacy fields are deleted **only** after probe and register both succeed.
- A failed probe leaves the v1 connection intact and working.
- The support view never renders more than the last 4 characters.
- **`AckAttributionTests` and `ack-user.test.ts` still pass:** the Username still reaches BHNM
  as `user`.

## Build order

1. **Middleware:** table, internal issuer, `X-App-Token` resolution, credential injection,
   token `/register`, union fan-out, probe, and the legacy line. Deploy with the usual rollback
   tag.
   - **Verify the assertion the change makes about itself:** issue a token by hand, register a
     test device with it and send a push. Seeing that the legacy phones still work proves
     nothing.
2. **Portal:** v2 QR, the token list with revoke, and the v1 option. Deploy.
3. **iOS:** v2 import, the probe UI, the support view and the post-migration cleanup. It still
   reads v1. Then export, verify and upload, and the store release is Thomas's.
4. **PWA:** the same. Deploy.
5. **Migration,** device by device, as above.
6. **The gate, on Thomas's word:**
   - delete the legacy auth, the by-secret fan-out, the v1 QR option and the clients' v1 import;
   - **rotate every BHNM api_key** that was ever in a QR, because until then each of them is on
     phones and in QR images.
7. **S1 1b becomes phone-free.** A unique webhook secret per server is now a BHNM Action change
   plus a `servers.json` change. No device carries the secret any more, so rotating it touches no
   phone.

## Open questions

1. **Token lifetime:** no expiry with revocation only, or an expiry with re-issue? An expiry is a
   paging outage waiting for a calendar date. The recommendation is revocation only.
2. **One QR on two devices:** should a token bind to its first device registration and refuse a
   second, or is one token per person across their devices acceptable?
3. **Should the v1 QR option exist at all during the transition,** or should legacy phones simply
   keep the connection they have until they update?
4. **Keep the AES wrapper on the v2 QR?** It protects nothing against someone holding the app
   binary, but it does keep a photographed QR from being read by eye. It costs nothing to keep.
5. **The PWA as a desktop dashboard:** one token per browser, like a phone, or a separate
   read-only token kind?
