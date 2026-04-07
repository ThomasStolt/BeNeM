# Cloudflare Origin Certificates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Caddy's automatic Let's Encrypt TLS with Cloudflare Origin Certificates mounted as static files, behind Cloudflare's proxy (Full Strict mode).

**Architecture:** Cloudflare terminates public TLS at the edge with its own certificate. Caddy terminates the origin connection using a Cloudflare-signed Origin Certificate (15-year validity). No more automatic cert issuance or renewal.

**Tech Stack:** Caddy 2.9, Docker Compose, Cloudflare Dashboard, bash

**Spec:** `docs/superpowers/specs/2026-04-07-cloudflare-origin-certificates-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `middleware/Caddyfile` | Modify | Add global `auto_https off`, add `tls` directives per domain |
| `middleware/docker-compose.yml` | Modify | Mount origin cert volume, remove Let's Encrypt volumes |
| `middleware/upgrade.sh` | Modify | Add pre-flight cert file check |
| `middleware/setup.sh` | Modify | Add cert path prompt, update deployment checklist |

---

### Task 1: Generate Origin Certificate in Cloudflare Dashboard

This is a manual task performed in the Cloudflare web UI. No code changes.

- [ ] **Step 1: Open Cloudflare Dashboard**

Navigate to the Cloudflare dashboard for `hurrikap.org`.

- [ ] **Step 2: Generate Origin Certificate**

Go to SSL/TLS -> Origin Server -> Create Certificate.

Settings:
- Private key type: RSA (2048) or ECDSA
- Hostnames: `*.hurrikap.org` and `hurrikap.org` (wildcard covers both domains)
- Certificate validity: 15 years

Click Create.

- [ ] **Step 3: Save certificate and key to the Linode**

Copy the certificate PEM block and save it:

```bash
sudo mkdir -p /etc/cloudflare-origin
sudo nano /etc/cloudflare-origin/origin-cert.pem
# Paste the certificate PEM block, save
```

Copy the private key PEM block and save it:

```bash
sudo nano /etc/cloudflare-origin/origin-key.pem
# Paste the private key PEM block, save
```

Lock down permissions:

```bash
sudo chmod 600 /etc/cloudflare-origin/origin-cert.pem
sudo chmod 600 /etc/cloudflare-origin/origin-key.pem
sudo chmod 700 /etc/cloudflare-origin
```

- [ ] **Step 4: Verify files exist**

```bash
ls -la /etc/cloudflare-origin/
```

Expected output: two files, `origin-cert.pem` and `origin-key.pem`, both with `600` permissions.

---

### Task 2: Update Caddyfile

**Files:**
- Modify: `middleware/Caddyfile`

- [ ] **Step 1: Add global options block and TLS directives**

Replace the entire Caddyfile with:

```
{
    auto_https off
}

{$DOMAIN} {
    tls /etc/ssl/origin/origin-cert.pem /etc/ssl/origin/origin-key.pem

    # ── Security headers ─────────────────────────────────────────────────
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }

    # Admin console — protected by Caddy Basic Auth (first factor).
    # TOTP is the second factor enforced by the app itself.
    # Generate bcrypt hash: docker run --rm caddy:2-alpine caddy hash-password --plaintext 'yourpassword'
    handle /admin* {
        basic_auth {
            {$BASIC_AUTH_USER} {$BASIC_AUTH_HASH}
        }
        reverse_proxy benem-admin:8001
    }

    # Static assets served by benem-admin (favicon, CSS, etc.)
    handle /static* {
        reverse_proxy benem-admin:8001
    }

    # bhnm-apns push middleware (all other paths, unchanged)
    handle {
        reverse_proxy bhnm-apns:8889
    }
}

{$PWA_DOMAIN} {
    tls /etc/ssl/origin/origin-cert.pem /etc/ssl/origin/origin-key.pem

    # ── Security headers ─────────────────────────────────────────────────
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'"
        -Server
    }

    # Same-origin API path — proxied to the bhnm-apns container.
    # `handle_path` strips the `/bhnm` prefix before forwarding,
    # mirroring the Vite dev proxy's rewrite.
    handle_path /bhnm/* {
        reverse_proxy bhnm-apns:8889
    }

    # Everything else → static PWA bundle served by nginx.
    handle {
        reverse_proxy benem-pwa:80
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add middleware/Caddyfile
git commit -m "feat(middleware): switch Caddy TLS to Cloudflare Origin Certificates"
```

---

### Task 3: Update docker-compose.yml

**Files:**
- Modify: `middleware/docker-compose.yml`

- [ ] **Step 1: Update caddy service volumes**

In the `caddy` service, replace the volumes section. Remove `caddy-data:/data` and `caddy-config:/config`, add the origin cert mount:

```yaml
  caddy:
    container_name: benem-proxy
    # Pin to a specific version to prevent supply-chain attacks via tag mutation.
    # Update periodically: docker pull caddy:2.9-alpine && docker compose up -d caddy
    image: caddy:2.9-alpine
    env_file: .env
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - /etc/cloudflare-origin:/etc/ssl/origin:ro
    restart: unless-stopped
```

- [ ] **Step 2: Remove unused named volumes**

Remove `caddy-data` and `caddy-config` from the top-level `volumes:` section at the bottom of the file. The result should be:

```yaml
volumes:
  db-data:
  benem-admin-log:
```

- [ ] **Step 3: Commit**

```bash
git add middleware/docker-compose.yml
git commit -m "feat(middleware): mount origin cert, remove Let's Encrypt volumes"
```

---

### Task 4: Update upgrade.sh

**Files:**
- Modify: `middleware/upgrade.sh`

- [ ] **Step 1: Add cert file pre-flight check**

After the existing preflight block (after line 28: `command -v git >/dev/null || die "git not found."`), add:

```bash
# Verify Cloudflare Origin Certificate files exist
[ -f /etc/cloudflare-origin/origin-cert.pem ] || die "Origin cert missing: /etc/cloudflare-origin/origin-cert.pem"
[ -f /etc/cloudflare-origin/origin-key.pem ]  || die "Origin key missing: /etc/cloudflare-origin/origin-key.pem"
```

The preflight section should now read:

```bash
# ── Preflight ──────────────────────────────────────

[ -f "docker-compose.yml" ] || die "Run this script from the bhnm-apns repo root."
[ -f ".env" ]               || die ".env not found — run ./setup.sh first."
command -v docker    >/dev/null || die "docker not found."
command -v git       >/dev/null || die "git not found."

# Verify Cloudflare Origin Certificate files exist
[ -f /etc/cloudflare-origin/origin-cert.pem ] || die "Origin cert missing: /etc/cloudflare-origin/origin-cert.pem"
[ -f /etc/cloudflare-origin/origin-key.pem ]  || die "Origin key missing: /etc/cloudflare-origin/origin-key.pem"
```

- [ ] **Step 2: Commit**

```bash
git add middleware/upgrade.sh
git commit -m "feat(middleware): add origin cert pre-flight check to upgrade.sh"
```

---

### Task 5: Update setup.sh

**Files:**
- Modify: `middleware/setup.sh`

- [ ] **Step 1: Add cert path prompt**

After the Domain section (after line 49: `DOMAIN=$(ask "Domain for this service" "bhnm-apns.example.com")`), add a new section:

```bash
# ── Origin Certificate ────────────────────────────
echo ""
echo -e "${CYAN}── Origin Certificate ────────────────────────────${NC}"
CERT_PATH=$(ask "Cloudflare Origin Certificate directory" "/etc/cloudflare-origin")
```

- [ ] **Step 2: Update the deployment checklist**

Replace the "Next steps" block (lines 73-92) with:

```bash
echo ""
echo -e "${GREEN}✓ .env written.${NC}"
echo ""
echo "┌──────────────────────────────────────────────┐"
echo "│   Next steps                                  │"
echo "│                                               │"
echo "│  1. Generate Cloudflare Origin Certificate:   │"
echo "│     - Hostnames: $DOMAIN                      │"
echo "│     - Validity: 15 years                      │"
echo "│                                               │"
echo "│  2. Save cert files:                          │"
echo "│     $CERT_PATH/origin-cert.pem                │"
echo "│     $CERT_PATH/origin-key.pem                 │"
echo "│     chmod 600 on both files                   │"
echo "│                                               │"
echo "│  3. Cloudflare Dashboard:                     │"
echo "│     - SSL/TLS mode: Full (Strict)             │"
echo "│     - Always Use HTTPS: On                    │"
echo "│     - DNS: Proxied (orange cloud)             │"
echo "│                                               │"
echo "│  4. Start the service:                        │"
echo "│     docker compose up -d                      │"
echo "│                                               │"
echo "│  5. Generate a secret per BHNM server:        │"
echo "│     openssl rand -hex 32                      │"
echo "│                                               │"
echo "│  6. Configure BHNM webhook URL:               │"
echo "│     https://$DOMAIN/webhook?secret=<secret>   │"
echo "│                                               │"
echo "│  7. In BeNeM Settings → BHNM Server:          │"
echo "│     Middleware URL: https://$DOMAIN            │"
echo "│     Webhook Secret: <same secret>             │"
echo "└──────────────────────────────────────────────┘"
echo ""
```

- [ ] **Step 3: Commit**

```bash
git add middleware/setup.sh
git commit -m "feat(middleware): update setup.sh for Cloudflare Origin Certificates"
```

---

### Task 6: Configure Cloudflare Dashboard

Manual task — no code changes.

- [ ] **Step 1: Set SSL/TLS encryption mode**

Cloudflare Dashboard -> SSL/TLS -> Overview -> Set to **Full (Strict)**.

- [ ] **Step 2: Enable Always Use HTTPS**

Cloudflare Dashboard -> SSL/TLS -> Edge Certificates -> Enable **Always Use HTTPS**.

- [ ] **Step 3: Set DNS records to Proxied**

Cloudflare Dashboard -> DNS -> For both `bhnm-apns.hurrikap.org` and the PWA domain, click the cloud icon to switch from grey (DNS only) to orange (Proxied).

- [ ] **Step 4: Recommended — Set minimum TLS version**

Cloudflare Dashboard -> SSL/TLS -> Edge Certificates -> Minimum TLS Version -> **TLS 1.2**.

---

### Task 7: Deploy and Verify

- [ ] **Step 1: Deploy on the Linode**

```bash
cd /opt/bhnm-apns
git pull
./upgrade.sh
```

- [ ] **Step 2: Verify HTTPS end-to-end**

From any machine (not the Linode), test both domains:

```bash
curl -I https://bhnm-apns.hurrikap.org/health
```

Expected: HTTP 200 with `strict-transport-security` header. The `server` header should NOT say "caddy" (it's stripped).

```bash
curl -I https://<pwa-domain>/
```

Expected: HTTP 200, HTML content.

- [ ] **Step 3: Verify Cloudflare is proxying**

```bash
curl -I https://bhnm-apns.hurrikap.org/health 2>&1 | grep -i cf-ray
```

Expected: A `cf-ray` header is present, confirming traffic goes through Cloudflare.

- [ ] **Step 4: Test the PWA**

Open the PWA in a browser. Verify the dashboard loads and API calls succeed (no 401s, incidents load, tactical overview loads).

- [ ] **Step 5: Test the iOS app**

Open BeNeM on the test phone. Verify incidents load and push notifications still arrive.

---

### Task 8: Clean Up Let's Encrypt Volumes

Only after verifying everything works.

- [ ] **Step 1: Remove old Docker volumes**

```bash
cd /opt/bhnm-apns
docker volume rm middleware_caddy-data middleware_caddy-config 2>/dev/null || true
```

Note: The volume names may have a different prefix depending on the docker compose project name. Check with:

```bash
docker volume ls | grep caddy
```

- [ ] **Step 2: Verify volumes are gone**

```bash
docker volume ls | grep caddy
```

Expected: No output (no caddy volumes remain).
