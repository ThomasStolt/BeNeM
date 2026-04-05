# PWA Hosting + Minimal Settings

**Date:** 2026-04-05
**Status:** Design
**Scope:** Host the BeNeM PWA at `https://benem.hurrikap.org` as a dedicated container on the existing middleware Linode box, and ship a minimal in-app Settings screen so real users can enter their BHNM API key.

## Goal

Make the PWA actually usable by end users. v0.1.0 shipped a working Incident List but only ran on a developer's laptop via `npm run dev`. This release deploys the built bundle to a public URL, wires production API access through the same Caddy that fronts `bhnm-apns`, and adds the smallest possible Settings screen so someone installing the PWA from `benem.hurrikap.org` can enter their key and start seeing incidents.

**Version:** PWA `0.1.0.5` (interim between v0.1.0 and v0.1.1). No middleware code changes — all middleware-side work is infrastructure (Caddyfile, docker-compose, new image).

## Out of scope

- Polished Settings UI (multi-profile, server URL picker, test-connection, theming) — v0.1.1
- PIN field (optional BHNM second factor — not needed until a PIN-enabled BHNM server appears)
- Swipe ACK/UnACK, Incident Detail screen — v0.1.1
- Web Push / VAPID — v0.2.0
- BHNM API caching layer inside `bhnm-apns` — separate future spec; this design is deliberately careful not to touch that container
- CI/CD — deploys remain `git pull && docker compose up -d`
- Rate limiting, WAF, additional auth on `/bhnm/*` — future hardening spec

## Context

- Middleware already runs `bhnm-apns` (FastAPI), `benem-admin`, and `caddy:2-alpine` under `middleware/docker-compose.yml`.
- Caddy terminates TLS for `bhnm-apns.hurrikap.org` with Let's Encrypt and reverse-proxies by path prefix (`/admin*`, `/static*`, and catch-all to `bhnm-apns:8889`).
- PWA v0.1.0 already builds to a static bundle (`pwa/dist/` — `index.html`, hashed JS/CSS, `sw.js`, `manifest.webmanifest`). `vite-plugin-pwa` is configured with `registerType: 'autoUpdate'`.
- In dev the PWA talks to BHNM via a Vite proxy (`/bhnm/*` → middleware). In prod the bundle has no proxy — it needs an equivalent path on its own origin.
- `VITE_BHNM_API_KEY` is currently baked at build time. A public bundle makes that approach a data leak.

## Decisions

- **(D1) Dedicated container** `benem-pwa`, independent from `bhnm-apns` and `benem-admin`. Lifecycle divergence (PWA rebuilds on every frontend change; push service rarely), blast-radius isolation (PWA restart must never touch push delivery), and clean room for the future BHNM caching layer.
- **(D2) Build on the server** via multi-stage `pwa/Dockerfile` (`node:20-alpine` builder → `nginx:alpine` server). Matches existing `bhnm-apns` / `benem-admin` deploy model. No CI infrastructure to maintain.
- **(D3) Same-origin API** at `benem.hurrikap.org/bhnm/*`, reverse-proxied by Caddy to `bhnm-apns:8889`. No CORS, no preflight, zero PWA code changes — the existing `/bhnm/...` URLs keep working. iOS app's `bhnm-apns.hurrikap.org` URL is untouched.
- **(D4) Minimal Settings screen promoted from v0.1.1.** API key only (PIN deferred). Stored in `localStorage`, read by a refactored `useConfig()` hook with env-var fallback for dev continuity.

## Architecture

### Container graph (after this release)

```
caddy (80/443, Let's Encrypt for both hostnames)
  ├── DOMAIN=bhnm-apns.hurrikap.org
  │     ├── /admin*, /static* → benem-admin:8001
  │     └── /*                → bhnm-apns:8889
  └── PWA_DOMAIN=benem.hurrikap.org
        ├── /bhnm/*           → bhnm-apns:8889 (prefix stripped by handle_path)
        └── /*                → benem-pwa:80   (nginx:alpine serving /usr/share/nginx/html)
```

No new ports on the host. No shared volumes. `benem-pwa` has no environment variables (the bundle is static). All secrets remain in `bhnm-apns` / `benem-admin`.

### New service in `middleware/docker-compose.yml`

```yaml
  benem-pwa:
    build:
      context: ..
      dockerfile: pwa/Dockerfile
    expose:
      - "80"
    restart: unless-stopped
```

The build context is the monorepo root (`..` from `middleware/`) so the Dockerfile can `COPY pwa/` into the builder stage.

### `pwa/Dockerfile` (new, multi-stage)

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY pwa/package.json pwa/package-lock.json ./
RUN npm ci
COPY pwa/ ./
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY pwa/nginx.conf /etc/nginx/conf.d/default.conf
```

### `pwa/nginx.conf` (new)

SPA fallback + correct cache headers for Vite + Workbox updates:

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location = /index.html              { add_header Cache-Control "no-cache"; }
    location = /sw.js                   { add_header Cache-Control "no-cache"; }
    location = /manifest.webmanifest    { add_header Cache-Control "no-cache"; }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Hashed `/assets/*` files cache forever (Vite rewrites their names on every build); the app shell, service worker, and manifest are re-fetched every visit so Workbox can detect updates and swap in new bundles.

### `pwa/.dockerignore` (new)

Excludes `node_modules`, `dist`, `.env.local`, `.git`.

### Updated `middleware/Caddyfile`

```caddyfile
{$DOMAIN} {
    handle /admin* {
        basic_auth {
            {$BASIC_AUTH_USER} {$BASIC_AUTH_HASH}
        }
        reverse_proxy benem-admin:8001
    }
    handle /static* {
        reverse_proxy benem-admin:8001
    }
    handle {
        reverse_proxy bhnm-apns:8889
    }
}

{$PWA_DOMAIN} {
    handle_path /bhnm/* {
        reverse_proxy bhnm-apns:8889
    }
    handle {
        reverse_proxy benem-pwa:80
    }
}
```

`handle_path` strips the `/bhnm` prefix before proxying, so `POST /bhnm/api/incident_api.php` becomes `POST /api/incident_api.php` on `bhnm-apns` — matching the Vite dev proxy's rewrite.

### Updated `middleware/.env.example`

Adds one line:

```
PWA_DOMAIN=benem.example.com
```

## Settings screen & config refactor (PWA side)

### New files

```
pwa/src/features/settings/
├── SettingsScreen.tsx
├── settingsStorage.ts
└── __tests__/
    ├── settingsStorage.test.ts
    └── SettingsScreen.test.tsx
```

### `settingsStorage.ts`

Tiny localStorage wrapper, fully isolated for testing:

```ts
const KEY = 'benem:bhnm-api-key';

export function loadApiKey(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(KEY);
}

export function saveApiKey(value: string): void {
  window.localStorage.setItem(KEY, value.trim());
}

export function clearApiKey(): void {
  window.localStorage.removeItem(KEY);
}
```

### `useConfig()` refactor (`pwa/src/lib/config.ts`)

Becomes a `useSyncExternalStore` hook so Save/Clear re-renders consumers automatically. TanStack Query picks up the new key via its query key (already includes `config.apiKey`) and refetches without manual invalidation.

```ts
import { useSyncExternalStore } from 'react';
import { loadApiKey } from '../features/settings/settingsStorage';

const listeners = new Set<() => void>();
function subscribe(cb: () => void) { listeners.add(cb); return () => listeners.delete(cb); }
export function notifyConfigChanged() { listeners.forEach((cb) => cb()); }

function getSnapshot(): BhnmConfig {
  const storedKey = loadApiKey();
  const envKey = import.meta.env.VITE_BHNM_API_KEY ?? '';
  const envPin = import.meta.env.VITE_BHNM_PIN ?? '';
  const apiKey = storedKey ?? envKey;
  return {
    baseUrl: '/bhnm',
    apiKey,
    pin: envPin || undefined,
    isConfigured: apiKey.length > 0,
  };
}

export function useConfig(): BhnmConfig {
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
```

**Precedence:** `localStorage` wins over `import.meta.env`. Dev workflow is unchanged because dev machines have nothing in `localStorage` unless the developer explicitly uses the Settings screen. Prod builds can ship with no env vars at all — the fallback is empty string.

### `SettingsScreen.tsx`

Single-column Tailwind form:
- One `<input type="password">` labelled "BHNM API key", pre-populated from `loadApiKey()` on mount.
- Help text: "This key is stored in your browser only. It is never sent anywhere except BHNM via the BeNeM middleware."
- Save button → trims, calls `saveApiKey()`, calls `notifyConfigChanged()`, shows inline "Saved" (`aria-live="polite"`), optional navigate back to `/`.
- Clear button → `clearApiKey()`, `notifyConfigChanged()`, status flips to "Not configured".
- Status line: ✓ Configured / Not configured, driven by `useConfig().isConfigured`.
- Accessibility: `<label htmlFor>`, `aria-describedby` for the help text, keyboard-focusable buttons with visible focus rings.
- No network calls from this screen. Wrong keys surface as auth errors on the list screen, which is the right place for that feedback.

### Routing (`App.tsx`)

```tsx
<Routes>
  <Route path="/" element={<IncidentListScreen />} />
  <Route path="/settings" element={<SettingsScreen />} />
  <Route path="/incident/:id" element={<IncidentDetailStub />} />
</Routes>
```

### `IncidentListScreen` additions

- The "Not configured" empty state grows a `<Link to="/settings">Configure API key</Link>` button.
- The auth-error empty state gains the same button.
- The header gets a small gear icon linking to `/settings` (inline SVG, ~10 lines) so users can reach Settings after configuring.

## Data flow (production)

```
Browser (https://benem.hurrikap.org)
  1. GET /                      → Caddy → benem-pwa (nginx static)
  2. GET /assets/index-*.js     → Caddy → benem-pwa
  3. GET /sw.js                 → Caddy → benem-pwa
  4. POST /bhnm/api/incident_api.php (form-encoded: pwd=<key>&method=getincidents)
                                → Caddy (handle_path /bhnm/*)
                                → bhnm-apns:8889 (/api/incident_api.php)
                                → BHNM server (looked up by pwd in servers.json)
  5. JSON response back up the chain
```

App code is unchanged from v0.1.0 in URL construction — it still posts to `/bhnm/api/incident_api.php`. In dev that path is Vite's proxy; in prod it's Caddy's `handle_path`. Same-origin, no preflight, no CORS.

### Config resolution at runtime

1. `useConfig()` calls `getSnapshot()`.
2. `loadApiKey()` reads `localStorage['benem:bhnm-api-key']`.
3. If present → becomes `pwd=<key>` in every request body.
4. If absent → `VITE_BHNM_API_KEY` env fallback (empty in prod builds).
5. `isConfigured` drives the "Not configured" empty state with its "Configure API key" link.

## Error handling

Inherits v0.1.0's `ApiException` taxonomy unchanged. No new error kinds.

| Scenario | Behaviour | Change |
|---|---|---|
| No key in localStorage or env | Mock fixture shown, "Not configured" banner | Banner gains "Configure API key" button → `/settings` |
| Wrong key → BHNM 401/403 | "Invalid API key. Check configuration." | Same "Configure API key" button added |
| Network failure | "Could not reach BHNM. Retrying in 120s." with Retry | Unchanged |
| Server 5xx / parse error | Existing `server` / `parse` empty states | Unchanged |
| Caddy can't reach `bhnm-apns` | 502 → mapped to `server` kind | Unchanged |
| Caddy can't reach `benem-pwa` | Caddy default 502 page | Acceptable — operational failure |

The only UI change is making the not-configured dead-end actionable.

## Service-worker update behaviour

1. User loads the hosted PWA → nginx serves current `sw.js`; Workbox precaches the hashed asset bundle.
2. You deploy a new build → old clients re-fetch `sw.js` on next visit (no-cache headers), Workbox detects the new precache manifest, downloads new hashed assets, swaps on next navigation.
3. Installed PWAs (Add to Home Screen) update the same way — no store review, no manual steps.

If a user has the site open when you deploy, the new SW takes effect on their next tab focus / navigation, not mid-session. This is standard Workbox behaviour.

## Deploy flow

### First-time (once per server)

1. `git pull` the monorepo on the Linode box.
2. Add `PWA_DOMAIN=benem.hurrikap.org` to `middleware/.env`.
3. Create DNS A record `benem.hurrikap.org` → Linode IP (at registrar).
4. Wait for DNS to propagate (`dig +short benem.hurrikap.org`).
5. `cd middleware && docker compose up -d`. Caddy picks up the new site block and provisions a Let's Encrypt cert automatically (30–60 s first time).
6. Verify `https://benem.hurrikap.org/` returns the PWA shell and `POST https://benem.hurrikap.org/bhnm/api/incident_api.php` reaches the middleware.

### Ongoing (`upgrade.sh` additions)

After the existing rebuild block:

```bash
docker compose build benem-pwa
docker compose up -d benem-pwa

if ! curl -fsS "https://${PWA_DOMAIN}/" > /dev/null; then
    echo "❌ benem-pwa smoke check failed"
    exit 1
fi
echo "✅ benem-pwa is serving"
```

A Caddyfile validation step is added before restart:

```bash
docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile
```

### Rollback

`git checkout <previous-sha> && docker compose up -d benem-pwa`. Rolling `benem-pwa` back never touches `bhnm-apns` or `benem-admin`.

## Testing

Small and targeted — this is infrastructure plus ~100 lines of React, not new business logic.

| Layer | Tests |
|---|---|
| `settingsStorage` | load-empty returns null; save trims whitespace; save→load round-trip; clear removes; SSR guard returns null when `window` undefined |
| `useConfig` precedence | localStorage key wins over env key; empty localStorage falls back to env; both empty → `isConfigured: false`; `notifyConfigChanged()` triggers re-render |
| `SettingsScreen` smoke | Field pre-populated from storage; Save writes and shows "Saved" confirmation; Clear wipes and flips status line |
| Nginx / Dockerfile | Manual verification in the final task: `docker compose build benem-pwa && docker compose up -d benem-pwa && curl -fsS http://benem-pwa/` inside the compose network, plus the `upgrade.sh` smoke check |
| Caddyfile | `docker compose exec caddy caddy validate` as a pre-deploy check in `upgrade.sh` |

No E2E tests, no Playwright, no Docker-in-test. The existing `IncidentListScreen` smoke test already covers the end-to-end render path in jsdom.

## File map

| Path | Responsibility | Status |
|---|---|---|
| `pwa/Dockerfile` | Multi-stage build: node → nginx | New |
| `pwa/nginx.conf` | SPA fallback + cache headers | New |
| `pwa/.dockerignore` | Exclude node_modules, dist, .env.local, .git | New |
| `pwa/src/features/settings/SettingsScreen.tsx` | Settings UI | New |
| `pwa/src/features/settings/settingsStorage.ts` | localStorage wrapper | New |
| `pwa/src/features/settings/__tests__/settingsStorage.test.ts` | Storage tests | New |
| `pwa/src/features/settings/__tests__/SettingsScreen.test.tsx` | Screen smoke test | New |
| `pwa/src/lib/config.ts` | `useConfig()` + `notifyConfigChanged()` via `useSyncExternalStore` | Modified |
| `pwa/src/lib/config.test.ts` | Precedence tests | New |
| `pwa/src/App.tsx` | Add `/settings` route | Modified |
| `pwa/src/features/incidents/IncidentListScreen.tsx` | "Configure API key" buttons, header gear icon | Modified |
| `pwa/package.json` | Bump version `0.1.0` → `0.1.0.5` | Modified |
| `middleware/docker-compose.yml` | Add `benem-pwa` service | Modified |
| `middleware/Caddyfile` | Add `{$PWA_DOMAIN}` site block with `handle_path /bhnm/*` | Modified |
| `middleware/.env.example` | Add `PWA_DOMAIN=benem.example.com` | Modified |
| `middleware/upgrade.sh` | Build + smoke-check `benem-pwa`; validate Caddyfile | Modified |
| `pwa/README.md` | Production hosting section | Modified |
| `shared/feature-spec.md` | Note hosted at `benem.hurrikap.org` on Incident List PWA line | Modified |

Ten new, seven modified. All changes localised to `pwa/` and `middleware/`. `ios/` untouched; `shared/` receives only a one-line feature-spec update.

## Risks & open items

1. **First-time TLS depends on DNS propagation.** If `PWA_DOMAIN` isn't resolvable when Caddy starts, Let's Encrypt HTTP-01 fails and Caddy backs off. Mitigation: deploy checklist explicitly sequences DNS record before `docker compose up`.
2. **`localStorage` key persistence.** Users changing their BHNM API key must manually Clear + Save. Acceptable for v0.1.0.5; v0.1.1 Settings screen will add a "Test connection" button.
3. **No rate-limiting on `/bhnm/*`.** Caddy proxies straight through. Anyone with a valid key could hit the endpoint without loading the PWA — same as iOS today. Future hardening spec, not this one.
4. **Monorepo-root build context busts cache broadly.** Any change under `pwa/` rebuilds the `benem-pwa` image on the server. Correct behaviour; worth knowing.
5. **Publicly discoverable deployment.** `benem.hurrikap.org` loads for any visitor; without a key they see "Not configured". No data leak, but the existence of a BeNeM instance becomes public. Acceptable.
6. **SW precache scope is safe.** `globPatterns` in `vite-plugin-pwa` is `**/*.{js,css,html,svg,png,ico}` — API responses are never precached. No change needed to v0.1.0 config.

## Version

- `pwa/package.json`: `0.1.0` → `0.1.0.5`
- `middleware/VERSION`: unchanged (infrastructure-only changes to middleware files; no Python changes)
- `shared/feature-spec.md`: Incident List PWA-specific section updated with "hosted at `benem.hurrikap.org` from v0.1.0.5"
