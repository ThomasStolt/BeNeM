# Cloudflare Origin Certificates for Caddy

**Date:** 2026-04-07
**Status:** Approved
**Approach:** Manual Origin Certificate files mounted into Caddy (Approach A)

## Goal

Replace Caddy's automatic Let's Encrypt TLS with Cloudflare Origin Certificates. This simplifies certificate management (15-year validity, no renewal chasing) and enables Cloudflare's proxy (orange cloud) for edge TLS termination. The setup should be replicable in business contexts.

## Architecture

```
Browser ──TLS──▶ Cloudflare Edge (public cert) ──TLS──▶ Caddy (origin cert) ──HTTP──▶ backends
```

- Cloudflare terminates the public-facing TLS connection with its own edge certificate
- Cloudflare connects to the origin (Linode) using a Cloudflare-signed Origin Certificate
- Caddy no longer manages certificate issuance or renewal
- SSL/TLS mode: **Full (Strict)** — Cloudflare verifies the origin cert is valid and Cloudflare-signed

## Section 1: Certificate Generation & Storage

### Cloudflare Dashboard

1. SSL/TLS → Origin Server → Create Certificate
2. Let Cloudflare generate a private key (RSA 2048 or ECDSA P-256)
3. Hostnames: `bhnm-apns.hurrikap.org` and the PWA domain (or `*.hurrikap.org` wildcard)
4. Validity: 15 years
5. Save the PEM certificate and private key

### On-Disk Layout (Linode)

```
/etc/cloudflare-origin/
├── origin-cert.pem    # Certificate
└── origin-key.pem     # Private key
```

Permissions: `chmod 600`, owned by root. Mounted read-only into the Caddy container.

## Section 2: Caddyfile Changes

### Global Block

Disable Caddy's automatic HTTPS since certificates are managed externally:

```
{
    auto_https off
}
```

This prevents Caddy from attempting Let's Encrypt ACME challenges.

### Per-Domain TLS Directive

Each domain block gets an explicit `tls` directive pointing to the mounted cert files:

```
{$DOMAIN} {
    tls /etc/ssl/origin/origin-cert.pem /etc/ssl/origin/origin-key.pem
    # ... rest of config unchanged
}

{$PWA_DOMAIN} {
    tls /etc/ssl/origin/origin-cert.pem /etc/ssl/origin/origin-key.pem
    # ... rest of config unchanged
}
```

All other Caddyfile configuration (security headers, reverse proxy routes, Basic Auth for admin) remains unchanged.

### HTTP→HTTPS Redirect

With `auto_https off`, Caddy no longer redirects HTTP→HTTPS automatically. Cloudflare handles this via the "Always Use HTTPS" edge setting. Port 80 is kept open on the host for debugging purposes but is not strictly required.

## Section 3: docker-compose.yml Changes

### Add Origin Certificate Volume

Mount the host certificate directory into Caddy as read-only:

```yaml
caddy:
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile:ro
    - /etc/cloudflare-origin:/etc/ssl/origin:ro
```

### Remove Let's Encrypt Volumes

The following named volumes are no longer needed and should be removed from the `volumes` section:

- `caddy-data` (was `/data` — Let's Encrypt cert storage)
- `caddy-config` (was `/config` — Caddy state)

### Unchanged

All backend service definitions (bhnm-apns, benem-admin, benem-pwa), their ports, environment variables, and volume mounts remain unchanged. Port 80 and 443 stay exposed on the Caddy container.

## Section 4: upgrade.sh Changes

### Add Pre-Flight Certificate Check

Before the rebuild step, verify that origin certificate files exist:

```bash
if [ ! -f /etc/cloudflare-origin/origin-cert.pem ] || [ ! -f /etc/cloudflare-origin/origin-key.pem ]; then
    echo "ERROR: Origin certificate files missing in /etc/cloudflare-origin/"
    exit 1
fi
```

### Unchanged

Caddyfile validation (`caddy validate`), rebuild, restart, and health checks (which hit internal ports bypassing Caddy) remain as-is.

## Section 5: Cloudflare Dashboard Configuration

### Required

| Setting | Value |
|---|---|
| SSL/TLS → Overview → Encryption mode | Full (Strict) |
| SSL/TLS → Edge Certificates → Always Use HTTPS | On |
| DNS → `bhnm-apns.hurrikap.org` | Proxied (orange cloud) |
| DNS → PWA domain | Proxied (orange cloud) |
| SSL/TLS → Origin Server | Generate Origin Certificate (see Section 1) |

### Recommended

| Setting | Value |
|---|---|
| SSL/TLS → Edge Certificates → Minimum TLS Version | TLS 1.2 |
| Security → Settings → WAF | Enable free tier rules |

## Section 6: setup.sh Changes

### New Prompt

Add a prompt for the origin certificate path:

```
Origin certificate path [/etc/cloudflare-origin]:
```

### Updated Deployment Checklist

Replace the Let's Encrypt DNS instructions with:

```
- Generate Cloudflare Origin Certificate for $DOMAIN and $PWA_DOMAIN
- Save cert to /etc/cloudflare-origin/origin-cert.pem
- Save key to /etc/cloudflare-origin/origin-key.pem
- Set Cloudflare SSL/TLS mode to Full (Strict)
- Enable "Always Use HTTPS" in Cloudflare dashboard
- Set DNS records to Proxied (orange cloud)
```

All other prompts (APNs, VAPID, webhook secrets, domain names) remain unchanged.

## Section 7: Migration Path

Zero-downtime migration from Let's Encrypt to Origin Certificates:

1. **Generate** Origin Certificate in Cloudflare dashboard, save files to `/etc/cloudflare-origin/` on the Linode
2. **Switch DNS to proxied** (orange cloud) — Cloudflare now terminates edge TLS. Let's Encrypt still works on origin during transition.
3. **Deploy** updated Caddyfile + docker-compose — Caddy switches to Origin Certificate files
4. **Verify** HTTPS works end-to-end through Cloudflare
5. **Clean up** old Let's Encrypt volumes:
   ```bash
   docker volume rm middleware_caddy-data middleware_caddy-config
   ```

**Rollback:** Flip DNS back to grey cloud and restore the previous Caddyfile to return to Let's Encrypt.

## Files Changed

| File | Change |
|---|---|
| `middleware/Caddyfile` | Add global `auto_https off`, add `tls` directives with cert paths |
| `middleware/docker-compose.yml` | Mount `/etc/cloudflare-origin` read-only, remove `caddy-data`/`caddy-config` volumes |
| `middleware/upgrade.sh` | Add pre-flight cert file existence check |
| `middleware/setup.sh` | Add cert path prompt, update deployment checklist |
