# BeNeM — Installation & Deployment Guide

**For someone who has never seen this project before.** Follow it top to bottom
and you end up with a working incident-alerting setup: a server on the internet,
an admin portal, an Android/desktop web app, and (optionally) the native iOS app.

No prior knowledge of BeNeM is assumed. Basic comfort with a terminal is.

---

## 0. First: are you sure you need this guide?

There are two ways to use BeNeM, and only one of them is this document.

**Hosted — someone else runs the server.** If your organisation already runs a BeNeM
middleware, you need no server, no domain and no Apple account. Install the iOS app from
the App Store, or open the PWA URL your administrator gives you and add it to your home
screen. Then ask whoever runs the middleware for a registration QR code or `benem://`
link, scan it, and you are done. Nothing else in this guide applies to you.

**Self-hosted — you run the server.** That is this guide: your own VPS, your own domain,
your own keys, your own BHNM servers. One caveat decides how much work it is, so read it
before you start: **the App Store build of BeNeM cannot receive push notifications from
your middleware.** An APNs device token is bound to the APNs key of the team that
published the app, so a middleware holding your `.p8` key cannot deliver to a binary
signed by someone else's team. Self-hosted iOS push therefore means *your own build*,
under *your own Bundle ID*, signed by *your own team*, distributed through TestFlight or
your own App Store listing (§10). Android and desktop have no such constraint — the PWA
you deploy in §5 talks to your middleware and nobody else's.

---

### 0.1 What you are actually building

```
 BHNM server            your VPS (one box, Docker)                phones
 (already exists) ──►  ┌──────────────────────────────┐  ──►  iPhone (APNs)
      webhook          │ bhnm-apns   push + API proxy │  ──►  Android (Web Push)
                       │ benem-admin admin portal     │
                       │ benem-pwa   the web app      │
                       │ caddy       TLS + routing    │
                       └──────────────────────────────┘
```

Everything server-side is **one `docker compose` stack** in `middleware/`.
The iOS app is separate — it is built in Xcode and shipped through TestFlight or
the App Store.

**Time:** ~1 hour for the server. Add a day or two if you need Apple approval.
**Cost:** a small VPS (~5 €/month) + a domain. Apple Developer Program (99 USD/yr)
**only** if you want iOS push.

---

## 1. Decide what you need before you start

Answer these three questions first — they decide how much work this is.

| Question | If yes | If no |
|---|---|---|
| Do your users have **iPhones** and need push? | You need an Apple Developer account (§3) and must build and distribute **your own** iOS binary (§10) — the App Store build cannot receive push from your middleware, because APNs device tokens are bound to the publishing team's key. | Skip §3 and §10 entirely. Android + desktop work without Apple. |
| Do your users have **Android** phones and need push? | You need VAPID keys (§4). | Skip the VAPID lines; the web dashboard still works without push. |
| Is your BHNM server reachable **from the internet**? | Good — nothing extra. | Fine too: put the VPS where it can reach BHNM (e.g. same network / VPN). The apps never talk to BHNM directly; they go through the middleware proxy. |

You also need, from whoever runs BHNM:

- The BHNM **URL** (e.g. `https://bhnm.corp.example:9443` — note the port, see §13)
- A BHNM **API key** (and a **PIN/LicenseID** if it is a SaaS instance)
- Permission to add a **webhook notification contact** in BHNM
- BHNM version **26.1.02 or newer** (older versions lack the device UID fields the app relies on)

---

## 2. The server, DNS and TLS

### 2.0 Where the middleware lives

Before renting anything, decide which of these three shapes matches your network. Most
real BHNM installs are (b) or (c), not (a). The phones always talk to the middleware, and
the middleware always talks to BHNM — what changes is who can reach whom.

#### (a) Public VPS, BHNM reachable from the internet

The simplest case, and what §2.1–§2.4 describe as written. The VPS resolves and reaches
your BHNM URL directly; Let's Encrypt works over the public internet; phones reach the
middleware from anywhere.

Nothing changes. Continue at §2.1.

#### (b) Public VPS, BHNM only on your LAN

Very common: BHNM sits inside the corporate network with no public address, but you want
push to reach phones on mobile data. Put the middleware on a public VPS anyway and give
*it* a way into the BHNM network — a WireGuard (or IPsec/OpenVPN) site-to-site tunnel from
the VPS to a gateway on the BHNM LAN, or an outbound-only tunnel from inside the LAN.

What changes in §2:

- §2.1–§2.4 are unchanged. TLS, DNS and phone access all still work publicly.
- Bring the tunnel up **before** §5.3, and make sure it restarts on boot — if it is down,
  every BHNM call fails with the `502` in §13.
- In `servers.json` (§5.1) use the address BHNM has **inside** the tunnel
  (e.g. `https://192.168.2.211:9443`), not a public one.
- BHNM's own outbound webhook (§7) must be able to reach the VPS — that direction is
  ordinary outbound HTTPS from BHNM, but a strict egress firewall will block it.
- The SSRF guard allows any hostname configured in `servers.json`, so a private
  tunnel address there is fine.

#### (c) On-prem box, no public exposure

The middleware runs inside your network — a VM or a small server next to BHNM. Phones
reach it only on the LAN or over the company VPN. Nothing is exposed to the internet.

What changes in §2:

- §2.1 becomes "provision a VM/host on the internal network" — the Docker and firewall
  steps (§2.3, §2.4) still apply.
- §2.2: the two hostnames must resolve **on your internal resolver** to the internal IP.
  Watch for a split-horizon gap: a name that resolves publicly but `NXDOMAIN`s on the LAN
  resolver leaves phones on Wi-Fi unable to load the PWA while everything looks healthy
  from outside. Add both records to the internal zone.
- **TLS is the real work.** Caddy's default HTTP-01 challenge needs port 80 reachable
  *from the internet*, which you do not have. Two options: switch the Caddyfile to a
  **DNS-01** challenge (Caddy solves it through your DNS provider's API — no inbound
  needed, and it still yields publicly-trusted certificates), or issue certificates from
  your **internal CA** and point Caddy at them with `tls /path/cert.pem /path/key.pem`.
  Both require editing `middleware/Caddyfile`; the stock file assumes HTTP-01.
- An internal CA means every phone must trust that CA, or the app's connection test and
  APNs registration calls fail on TLS. iOS additionally requires the root to be enabled
  under Settings → General → About → Certificate Trust Settings.
- Push still works: APNs and Web Push are *outbound* connections from the middleware to
  Apple and to the browser push services. The box needs outbound 443 to the internet even
  though nothing comes in.
- Phones off the LAN and off the VPN receive nothing. If engineers need alerts on mobile
  data, you want (a) or (b).

### 2.1 Rent a VPS

Any small Linux box works: Hetzner, DigitalOcean, Vultr, AWS Lightsail, a VM in
your own datacentre. Minimum: **1 vCPU, 1 GB RAM, 10 GB disk, Ubuntu 24.04 LTS**,
a **public IPv4 address**, and ports **80** and **443** open.

Write down the IP address. Log in:

```bash
ssh root@<your-server-ip>
```

### 2.2 Point two hostnames at it

You need **two** DNS names on a domain you control — one for the middleware/admin,
one for the web app. In your DNS provider create two `A` records:

| Name | Type | Value |
|---|---|---|
| `bhnm-apns.example.com` | A | `<your-server-ip>` |
| `benem.example.com` | A | `<your-server-ip>` |

Wait until both resolve before continuing — Caddy fetches TLS certificates from
Let's Encrypt over HTTP, and that fails if DNS is not live yet:

```bash
dig +short bhnm-apns.example.com
dig +short benem.example.com
```

Both must print your server IP.

### 2.3 Install Docker

On the VPS:

```bash
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

### 2.4 Open the firewall

If the VPS has a firewall (cloud panel or `ufw`), allow 22, 80 and 443:

```bash
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw enable
```

---

## 3. Apple setup — only if you want iOS push

Skip this whole section if you are Android/desktop only.

You need the **Apple Developer Program** (99 USD/year, enroll at
<https://developer.apple.com/programs/>). Approval can take a day or more, so
start it early. Then, at <https://developer.apple.com/account>:

**3.1 Team ID** — Membership details → copy the 10-character **Team ID**.
This becomes `APNS_TEAM_ID`.

**3.2 App ID (bundle identifier)** — Certificates, IDs & Profiles → Identifiers →
**+** → App IDs → App. Pick a bundle ID you control, e.g. `com.yourcompany.benem`.
Tick the **Push Notifications** capability. This becomes `APNS_BUNDLE_ID` and must
match the bundle ID in Xcode exactly (§10).

**3.3 APNs Auth Key (.p8)** — Certificates, IDs & Profiles → Keys → **+** →
tick **Apple Push Notifications service (APNs)** → Continue → Register.

> Make sure the key is valid for **Sandbox & Production**. A sandbox-only key
> cannot deliver to TestFlight or App Store builds — this is the single most
> common APNs mistake.

Download `AuthKey_XXXXXXXXXX.p8`. **Apple lets you download it exactly once.**
Store it in your password manager. Copy the 10-character **Key ID** shown on the
page — that becomes `APNS_KEY_ID`.

**3.4 Base64-encode the key** — the middleware takes the key as one line of text:

```bash
# macOS
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
# Linux
base64 -w 0 AuthKey_XXXXXXXXXX.p8
```

Copy the output — that is `APNS_PRIVATE_KEY_B64`.

---

## 4. Generate your secrets

Do this on the VPS. Each command prints one value; paste each into the `.env`
file in §5. Keep them in a password manager too.

```bash
# BENEM_SECRET_KEY — encrypts the benem:// onboarding links (64 hex chars)
openssl rand -hex 32

# SESSION_SECRET — signs admin portal login cookies
openssl rand -hex 32

# PROXY_TOKEN — authenticates app → middleware API proxy calls
openssl rand -hex 32

# WEBHOOK_SECRET — the per-BHNM-server push secret (see §7)
openssl rand -hex 32
```

**TOTP_SECRET** — the 2FA secret for the admin portal login:

```bash
docker run --rm python:3.11-alpine sh -c "pip -q install pyotp && python -c 'import pyotp; print(pyotp.random_base32())'"
```

**Admin portal basic-auth password** — Caddy asks for a username/password before
the portal is even reached. Pick a username, then hash a password:

```bash
docker run --rm caddy:2.9-alpine caddy hash-password --plaintext 'your-strong-password'
```

The output starting with `$2a$...` is `BASIC_AUTH_HASH`; your chosen username is
`BASIC_AUTH_USER`.

**VAPID keys** — only if you want Android/web push:

```bash
docker run --rm node:20-alpine npx -y web-push generate-vapid-keys
```

This prints a **Public Key** (`VAPID_PUBLIC_KEY`) and **Private Key**
(`VAPID_PRIVATE_KEY`).

> Keep every one of these. Rotating `BENEM_SECRET_KEY` later invalidates every
> onboarding QR code you have handed out, and rotating it means rebuilding the
> iOS app (§10.2).

---

## 5. Deploy the server stack

On the VPS:

```bash
git clone https://github.com/ThomasStolt/BeNeM.git
cd BeNeM/middleware
cp .env.example .env
nano .env
```

Fill in `.env` with the values from §3 and §4:

| Variable | What to put there | Needed for |
|---|---|---|
| `APNS_KEY_ID` | 10-char key ID from §3.3 | iOS push |
| `APNS_TEAM_ID` | 10-char team ID from §3.1 | iOS push |
| `APNS_BUNDLE_ID` | your bundle ID from §3.2 | iOS push |
| `APNS_PRIVATE_KEY_B64` | the long base64 blob from §3.4 | iOS push |
| `VAPID_PRIVATE_KEY` / `VAPID_PUBLIC_KEY` | from §4 | Android push |
| `VAPID_CONTACT_EMAIL` | `mailto:you@example.com` | Android push |
| `DOMAIN` | `bhnm-apns.example.com` | always |
| `PWA_DOMAIN` | `benem.example.com` | always |
| `MIDDLEWARE_URL` | `https://bhnm-apns.example.com` | always |
| `BENEM_SECRET_KEY` | 64 hex chars from §4 | always |
| `SESSION_SECRET` | 64 hex chars from §4 | always |
| `TOTP_SECRET` | base32 string from §4 | always |
| `WEBHOOK_SECRET` | 64 hex chars from §4 | always |
| `PROXY_TOKEN` | 64 hex chars from §4 | always |
| `BASIC_AUTH_USER` / `BASIC_AUTH_HASH` | from §4 | always |
| `BHNM_TLS_VERIFY` | `false` if your BHNM uses a self-signed certificate (very common on-prem), else leave `true` | as needed |

`BASIC_AUTH_USER` and `BASIC_AUTH_HASH` are not in `.env.example` — add them as
two extra lines. Put the bcrypt hash **in single quotes**; it contains `$`.

### 5.1 Tell the middleware about your BHNM servers

```bash
cp servers.json.example servers.json
nano servers.json
```

One entry per BHNM server. `pin` stays `""` for self-hosted instances:

```json
[
  {
    "id": "prod",
    "name": "Production",
    "url": "https://bhnm.corp.example:9443",
    "api_key": "your-bhnm-api-key",
    "pin": ""
  }
]
```

This file holds real API keys. It is gitignored — never commit it.

### 5.2 Check your configuration before starting

```bash
./check-env.sh
```

Fix every `ERROR` it reports. `WARN` lines for features you are not using
(e.g. VAPID when you are iOS-only) are fine to ignore.

### 5.3 Start everything

```bash
docker compose up -d
docker compose ps
```

Four containers should be running: `benem-middleware`, `benem-admin`,
`benem-pwa`, `benem-proxy`. The first start takes a few minutes (image builds +
TLS certificates).

### 5.4 Verify

```bash
curl https://bhnm-apns.example.com/health
```

Expected: `{"status":"running","version":"…","registered_devices":0,…}`

If TLS fails, watch Caddy get its certificate — DNS is almost always the cause:

```bash
docker compose logs caddy --tail 50
```

---

## 6. Log in to the admin portal

Open `https://bhnm-apns.example.com/admin/`.

1. The browser asks for the **basic auth** username/password from §4.
2. The portal then asks for a **6-digit TOTP code**.

To get codes, open **Settings** in the portal and scan the QR code with Google
Authenticator, 1Password, or Authy. (The QR encodes the `TOTP_SECRET` you set in
`.env`.) From then on, log in with the current 6-digit code.

Now open **Connection Test** and test each server in `servers.json`. Green means
the middleware can reach BHNM and the API key works. Red → see §13.

---

## 7. Configure the webhook in BHNM

This is what makes notifications *instant* instead of polled. It is also the step most
likely to look finished while silently doing nothing — see §7.3.

### 7.1 The action

In BHNM, create a webhook notification action (an "action" attached to an action group,
which is in turn attached to your host and service checks):

**URL** — the same secret you put in `WEBHOOK_SECRET`:

```
https://bhnm-apns.example.com/webhook?secret=YOUR_WEBHOOK_SECRET
```

**Method:** POST — **Content-Type:** `application/json`

**Body:**

```json
{
  "notification_type": "$NOTIFICATIONTYPE",
  "hostname": "$HOSTNAME",
  "host_state": "$HOSTSTATE",
  "site": "$HOSTALIAS",
  "service_desc": "$SERVICEDESC",
  "output": "$SERVICEOUTPUT",
  "incident_id": "$SERVICEPROBLEMID"
}
```

For host-only alerts use `$HOSTOUTPUT` and `$HOSTPROBLEMID` in place of the two service
macros.

> **Status of this template.** The **field names on the left are the verified contract** —
> they are what `middleware/main.py` reads, and a real BHNM body in this shape was accepted
> and pushed end to end on 2026-09-03 at 11:03:30 UTC (incident 27728, `[Webhook] PROBLEM —
> raspi-050 — Incident 27728`, iPhone title `🔴 raspi-050 — DOWN` confirmed on the device;
> see `docs/evidence/2026-09-03-bhnm-host-status-down-row.md`). The **`$MACRO` names on the
> right are not verified against a BHNM UI export** — macro spelling varies between BHNM
> versions. Check them against your server's own macro reference, and confirm the resulting
> body has a non-empty `hostname` (§7.3).

### 7.2 What the middleware does with each field

| Field | Required | Used for |
|---|---|---|
| `hostname` | **Yes** | The device name in the notification title. A body without a non-empty `hostname` is rejected with `422` and nothing is pushed (middleware 2.11.1 and later). |
| `notification_type` | No (defaults to `PROBLEM`) | Selects the title/body format: `PROBLEM` / `CRITICAL` / `WARNING`, `RECOVERY`, or `ACKNOWLEDGEMENT`. |
| `host_state` | No | `DOWN` / `UNREACHABLE` pick the 🔴 emoji; anything else gets ⚠️. |
| `incident_id` | No | Carried through to the push so tapping the notification opens that incident. Without it the tap only opens the app. |
| `service_desc`, `output`, `site` | No | Notification body text. |

The exact title and body strings are specified in
[`shared/push-payload-spec.md`](../shared/push-payload-spec.md) — that file, not this one,
is the contract.

The route accepts a JSON body, and falls back to form-encoded if the body does not parse as
JSON (BHNM does not always send `Content-Type: application/json`).

### 7.3 Enable all three notification types — check this explicitly

The action group must have **PROBLEM**, **RECOVERY** and **ACKNOWLEDGEMENT** enabled. They
are separate switches, and a group with only PROBLEM enabled looks completely healthy: your
users get alerted when things break and are never told they recovered.

This is not hypothetical. On 2026-09-03 the lab was measured end to end: raspi-050 came back
up at 18:37:04 UTC, BHNM moved incident 27728 to `ALARMS CLEARED` at 18:37:25 and to
`CLOSED` at 18:42:27 — and **no RECOVERY webhook ever reached the middleware**, by 18:49:26,
with no maintenance window active to suppress it. The same middleware had accepted and
pushed a PROBLEM earlier the same day. The absence was in BHNM's action configuration, not
in the middleware.

Also note the timing: **BHNM holds a recovered incident in `ALARMS CLEARED` for about five
minutes before firing the recovery notification.** If you take a device down and up to test,
wait out that window before concluding the recovery webhook is missing.

### 7.4 Multiple BHNM servers

Give each server its **own** secret (`openssl rand -hex 32` per server). A device only
receives alerts from the server whose secret it registered with. There is no global secret.

### 7.5 Which BHNM version gates which feature

| Feature | Minimum BHNM version |
|---|---|
| BeNeM at all — UID-based device identity, pagination, model/serial, interface details | **26.1.02** |
| Device DOWN icon and the red incident chip | any supported version (26.1.02+) |
| Maintenance status — the wrench badge and the in-maintenance button state | **26.3.01** (verified on the lab at 26.3.01; not verified on 26.1.x) |

---

## 8. Onboard a user (the easy path)

Never make users type URLs and API keys. Use the admin portal:

1. Portal → **Generate Link** → pick the server, enter the user's name, pick an
   icon and accent colour → generate.
2. You get a **QR code** and a `benem://configure?…` **deep link**. All the
   credentials inside are AES-256-GCM encrypted.
3. Send the link by mail/chat, or let the user scan the QR from inside the app
   (**Settings → Scan QR Code**).

The app decrypts it, saves the server, and registers for push. Done.

---

## 9. Android and desktop users (the PWA)

The web app is already deployed at `https://benem.example.com` by the same stack.

- **Android:** open that URL in Chrome → menu → **Add to Home screen**. Launch it
  from the home screen (not the browser tab) and accept the notification prompt —
  Web Push only works from the installed app.
- **Desktop:** just open the URL; it is a full dashboard. No push.
- **iPhone:** the site loads, but push is unreliable on iOS; a banner points
  users to the native app. See [`shared/DECISION.md`](../shared/DECISION.md).

Then onboard the server with the QR/deep link from §8.

Check push is wired up:

```bash
curl https://bhnm-apns.example.com/vapid-key
```

It must return a `publicKey`. A 404/empty means the VAPID variables are missing.

---

## 10. The iOS app — only if you want iOS push

You need a **Mac** with **Xcode 15+** and the Apple Developer account from §3.

### 10.1 Get the code

```bash
git clone https://github.com/ThomasStolt/BeNeM.git
cd BeNeM
open ios/BeNeM.xcodeproj
```

### 10.2 Add the encryption key

The app decrypts `benem://` links with the **same key** as the server. Without
this file it will not build.

```bash
cd ios
cp BeNeM/Secrets.swift.template BeNeM/Secrets.swift
```

Edit `BeNeM/Secrets.swift` and paste the **exact same** `BENEM_SECRET_KEY` value
you put in the server's `.env`:

```swift
enum Secrets {
    static let encryptionKey = "<the same 64-char hex key>"
}
```

Mismatched keys produce "Invalid Link" when scanning QR codes. `Secrets.swift` is
gitignored — every developer machine needs its own copy of the same value.
Details: [`ios/SETUP.md`](../ios/SETUP.md).

### 10.3 Sign and run

In Xcode: select the **BeNeM** target → **Signing & Capabilities** → choose your
Team → set the Bundle Identifier to the **same** value as `APNS_BUNDLE_ID` from
§3.2. Make sure the **Push Notifications** capability is present. Then pick a
device and press ▶.

> Push does not work in the Simulator for real APNs delivery — test on a physical
> iPhone.

Debug builds register as `sandbox`, TestFlight/App Store builds as `production`.
The middleware routes each device to the right Apple endpoint automatically, so
you do not configure anything for this.

### 10.4 Distribute

Archive in Xcode (**Product → Archive**) and upload to App Store Connect, then
invite testers via TestFlight. Notes on the CLI route and App Store metadata are
in [`docs/appstore-metadata.md`](appstore-metadata.md).

---

## 11. End-to-end test

Work down the list; stop at the first failure and jump to §13.

1. `curl https://bhnm-apns.example.com/health` → `status: running`
2. Admin portal → **Connection Test** → green for every server
3. Open the app (iOS or installed PWA), scan the QR → server appears in Settings
4. App Settings → **Test** → green dot
5. Dashboard shows real incident and device counts
6. Admin portal → **Push Config** → your device is listed
7. Trigger a real incident in BHNM (or take a test host down) → notification
   arrives → tapping it opens the incident detail

Watch what the server is doing while you test:

```bash
docker compose logs -f bhnm-apns
```

---

## 12. Day-2 operations

**Upgrade** (rebuilds only what changed, then health-checks):

```bash
cd ~/BeNeM/middleware && ./upgrade.sh
```

**After editing `.env`** a plain restart is not enough — the containers only read
`env_file` when they are *created*:

```bash
docker compose up -d --force-recreate
```

**Back up** — these are the things you cannot regenerate:

- `middleware/.env` and `middleware/servers.json`
- the `AuthKey_XXXXXXXXXX.p8` file (Apple lets you download it only once)
- the SQLite volume, if you care about registered devices:
  `docker run --rm -v middleware_db-data:/data -v $PWD:/backup alpine tar czf /backup/benem-db.tgz /data`
  (devices re-register on next app launch, so this is a convenience, not critical)

**Rotating secrets** — consequences, in increasing order of pain:

| Secret | Effect of rotation |
|---|---|
| Webhook secret | Update the BHNM webhook URL and re-issue links; devices re-register on next launch |
| APNs `.p8` | Update `APNS_KEY_ID` + `APNS_PRIVATE_KEY_B64`, recreate containers |
| `BENEM_SECRET_KEY` | **All existing QR codes and links stop working**, and the iOS app must be rebuilt and redistributed with the new `Secrets.swift` |

---

## 12.5 Known limitations — read this before deploying for a company

These are open items on the project's own security board
([`shared/credentials-and-keys-overview.md`](../shared/credentials-and-keys-overview.md) §3),
recorded 2026-09-03. None of them is fixed today. They are listed here so that the decision
to run BeNeM for a team is made with them in view, not discovered afterwards.

**The webhook secret travels in the URL.** BHNM calls
`…/webhook?secret=<secret>`, so the secret appears in BHNM's outbound logs, in any reverse
proxy or corporate egress proxy along the way, and in any access log that records query
strings. Anyone holding that URL can post a notification to every device registered with
that secret — they cannot read your BHNM data, but they can push arbitrary alert text to
your engineers' phones. Treat the webhook URL as a credential, and give each BHNM server
its own secret so the blast radius stops at one server.

**`servers.json` is world-writable on the host.** `upgrade.sh` runs `chmod 666` on it at
every upgrade, because the admin container writes it as a non-root user. The file holds
the BHNM API key (and PIN) for every configured server. Any local user on that box can
read and modify it. Do not put the middleware on a shared or multi-user host.

**Secrets are baked into the built image.** The middleware `Dockerfile` does `COPY . .`
with no `.dockerignore`, so `.env` — APNs private key, VAPID private key,
`BENEM_SECRET_KEY` — and `servers.json` end up in the image layers. This is harmless while
the images stay on the machine that built them, which is what `docker compose` does. It
stops being harmless the moment anyone pushes those images to a registry or exports them
with `docker save`. **Never publish the built images.**

**The QR encryption key is inside the iOS binary.** `BENEM_SECRET_KEY` is compiled into the
app as a string literal (`Secrets.swift`). Anyone who can run `strings` on the app bundle
can extract it and decrypt any BeNeM configuration QR code or `benem://` link produced by
your admin portal — including the BHNM API key inside it. Treat generated links as
confidential regardless of the encryption, and hand them out individually rather than
posting them where a group can see them.

**PWA credentials in the browser are recoverable from the same origin.** The PWA encrypts
`apiKey`, `pin` and `pushWebhookSecret` in `localStorage`, but the key is derived by PBKDF2
from `location.origin` — so anything already running on that origin can derive the same key:
an XSS, a compromised npm dependency in the bundle, or a browser extension with host access.
The encryption stops casual inspection of `localStorage`; it is not a defence against code
running on the page.

---

## 13. When something is broken

**`502 Bad Gateway: could not connect to BHNM server`, or a failing connection test**

This is the most common problem, and it is nearly always one of three things:

1. **Wrong scheme.** Many BHNM appliances serve HTTPS on a non-standard port such
   as `:9443`. `http://host:9443` fails on every request. Use `https://host:9443`.
2. **Self-signed or expired certificate.** Set `BHNM_TLS_VERIFY=false` in `.env`.
   Note this is **global** — it disables verification for every BHNM server.
3. **You edited `.env` but only restarted.** Run
   `docker compose up -d --force-recreate`. A green admin connection test together
   with a `502` in the app is the classic sign that only one container picked up
   the new value.

**TLS certificate never issues** → `docker compose logs caddy`. Check both DNS
records resolve to this server and that ports 80/443 are open to the internet.

**Admin login always fails** → `TOTP_SECRET` is unset or not valid base32, or your
phone's clock has drifted. Run `./check-env.sh`.

**No iOS notifications** → check, in this order: the `.p8` key is *Sandbox &
Production*; `APNS_BUNDLE_ID` matches the app's bundle ID exactly; the device
shows up in the portal's **Push Config**; `docker compose logs bhnm-apns` while
you trigger an incident.

**No Android notifications** → the PWA must be launched from the **home screen
icon**, not a browser tab; notification permission must be granted;
`/vapid-key` must return a key.

**Nothing arrives on any platform** → the BHNM webhook itself. Fire it by hand:

```bash
curl -X POST "https://bhnm-apns.example.com/webhook?secret=YOUR_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"notification_type":"PROBLEM","hostname":"test-host","host_state":"DOWN","output":"manual test","incident_id":"1"}'
```

A response of `{"status":"ok","notified":N}` with `N > 0` means the server side
is fine and the problem is in BHNM's webhook configuration.

More detail: [`middleware/README.md`](../middleware/README.md#troubleshooting).

---

## 14. Where to read more

| Document | What it covers |
|---|---|
| [`middleware/README.md`](../middleware/README.md) | Full middleware reference: every env var, API endpoints, security model |
| [`shared/credentials-and-keys-overview.md`](../shared/credentials-and-keys-overview.md) | Every secret in the system, where it lives, how it flows |
| [`ios/SETUP.md`](../ios/SETUP.md) | iOS developer setup and the link generator script |
| [`pwa/README.md`](../pwa/README.md) | PWA development and local build |
| [`shared/DECISION.md`](../shared/DECISION.md) | Why native iOS + PWA Android rather than one cross-platform app |
| [`shared/BHNM_API_REFERENCE.md`](../shared/BHNM_API_REFERENCE.md) | The BHNM endpoints BeNeM uses |
