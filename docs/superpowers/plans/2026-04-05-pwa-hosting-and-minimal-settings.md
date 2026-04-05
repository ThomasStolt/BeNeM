# PWA Hosting + Minimal Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the BeNeM PWA at `https://benem.hurrikap.org` from the existing middleware Linode box as a dedicated `benem-pwa` container, and add a minimal in-app Settings screen so users can enter their BHNM API key at runtime.

**Architecture:** New `benem-pwa` service in `middleware/docker-compose.yml` built from a new multi-stage `pwa/Dockerfile` (`node:20-alpine` builder → `nginx:alpine` server). Existing Caddy gains a second site block for `$PWA_DOMAIN` that same-origin-proxies `/bhnm/*` to `bhnm-apns:8889` and serves everything else from `benem-pwa:80`. The PWA gains a `SettingsScreen` at `/settings` backed by a tiny `settingsStorage` localStorage wrapper; `useConfig()` is refactored to `useSyncExternalStore` so Save/Clear re-renders consumers and TanStack Query automatically refetches with the new key.

**Tech Stack:** Docker multi-stage build, nginx:alpine, Caddy (existing), React 18 + TypeScript strict, `useSyncExternalStore`, Vitest + @testing-library/react.

**Spec:** `docs/superpowers/specs/2026-04-05-pwa-hosting-and-minimal-settings-design.md`

---

## Conventions (read before starting)

- **Working directory:** repo root unless a task explicitly says otherwise. PWA build commands run from `pwa/`. Docker compose commands run from `middleware/`.
- **Package manager:** `npm`.
- **Commit messages:** Conventional commits (`feat(pwa):`, `feat(middleware):`, `chore:`, `test(pwa):`, `docs:`).
- **Every task ends with a commit.** No mixed-concern commits.
- **No `.env` changes committed.** Only `.env.example`.
- **Do not edit any `bhnm-apns` Python code, `benem-admin` code, or anything under `ios/`.** This release is infrastructure + PWA only.

---

## File map

| Path | Responsibility | Task |
|---|---|---|
| `middleware/.env.example` | Document new `PWA_DOMAIN` variable | 1 |
| `pwa/.dockerignore` | Exclude `node_modules`, `dist`, `.env.local`, `.git` from build context | 2 |
| `pwa/nginx.conf` | SPA fallback + asset cache headers | 2 |
| `pwa/Dockerfile` | Multi-stage build (node builder → nginx server) | 2 |
| `middleware/docker-compose.yml` | Add `benem-pwa` service | 3 |
| `middleware/Caddyfile` | Add `{$PWA_DOMAIN}` site block with `handle_path /bhnm/*` | 4 |
| `pwa/src/features/settings/settingsStorage.ts` | Typed localStorage wrapper | 5 |
| `pwa/src/features/settings/__tests__/settingsStorage.test.ts` | Storage tests | 5 |
| `pwa/src/lib/config.ts` | `useConfig()` via `useSyncExternalStore`, `notifyConfigChanged()` | 6 |
| `pwa/src/lib/config.test.ts` | Precedence + notify tests | 6 |
| `pwa/src/features/settings/SettingsScreen.tsx` | Settings UI | 7 |
| `pwa/src/features/settings/__tests__/SettingsScreen.test.tsx` | Screen smoke test | 7 |
| `pwa/src/App.tsx` | Add `/settings` route | 8 |
| `pwa/src/features/incidents/IncidentListScreen.tsx` | Header gear icon, Configure-API-key actions in empty states | 9 |
| `pwa/package.json` | Bump version `0.1.0` → `0.1.0.5` | 10 |
| `pwa/README.md` | Add Production Hosting section | 10 |
| `shared/feature-spec.md` | Note hosted at `benem.hurrikap.org` | 10 |
| `middleware/upgrade.sh` | Validate Caddyfile, build + smoke-check `benem-pwa` | 11 |
| (verification, no files) | Full typecheck + test + build + `docker compose config` | 12 |

---

## Task 1: Document new `PWA_DOMAIN` env var

**Files:**
- Modify: `middleware/.env.example`

- [ ] **Step 1: Add the new variable**

Find this block near the top of `middleware/.env.example`:

```
# ── Domain — used by Caddy for automatic TLS (Let's Encrypt) ──────────────────
DOMAIN=bhnm-apns.example.com
```

Replace with:

```
# ── Domain — used by Caddy for automatic TLS (Let's Encrypt) ──────────────────
DOMAIN=bhnm-apns.example.com

# ── PWA Domain — second hostname served by Caddy for the static PWA bundle ───
# Must resolve to this server (A/AAAA record) before `docker compose up`, or
# Caddy's Let's Encrypt HTTP-01 challenge will fail. Same-origin API calls
# from the PWA go to https://$PWA_DOMAIN/bhnm/* and are proxied to bhnm-apns.
PWA_DOMAIN=benem.example.com
```

- [ ] **Step 2: Commit**

```bash
git add middleware/.env.example
git commit -m "chore(middleware): document PWA_DOMAIN env var"
```

---

## Task 2: PWA Dockerfile, nginx config, and dockerignore

**Files:**
- Create: `pwa/.dockerignore`
- Create: `pwa/nginx.conf`
- Create: `pwa/Dockerfile`

- [ ] **Step 1: Create `pwa/.dockerignore`**

```
node_modules
dist
.env.local
.env
.git
.vite
coverage
*.tsbuildinfo
```

- [ ] **Step 2: Create `pwa/nginx.conf`**

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    # Long-cache for hashed assets (Vite rewrites filenames on every build)
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # No-cache for the app shell, service worker, and manifest so Workbox
    # can pick up new builds on the next visit.
    location = /index.html {
        add_header Cache-Control "no-cache";
    }
    location = /sw.js {
        add_header Cache-Control "no-cache";
    }
    location = /manifest.webmanifest {
        add_header Cache-Control "no-cache";
    }

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

- [ ] **Step 3: Create `pwa/Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1.6

# ─── Stage 1: Build ───────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

# Copy lockfile and manifest first for better layer caching
COPY pwa/package.json pwa/package-lock.json ./
RUN npm ci

# Copy source and build
COPY pwa/ ./
RUN npm run build

# ─── Stage 2: Serve ───────────────────────────────────────────────────────────
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY pwa/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

- [ ] **Step 4: Sanity-check the Dockerfile syntax (build context = monorepo root)**

```bash
cd middleware
docker build -f ../pwa/Dockerfile -t benem-pwa:local ..
```

Expected: build succeeds, final image tagged `benem-pwa:local`. (If `docker build` is unavailable in the environment, skip this manual step — Task 12 re-runs the build via `docker compose build`.)

- [ ] **Step 5: Commit**

```bash
git add pwa/.dockerignore pwa/nginx.conf pwa/Dockerfile
git commit -m "feat(pwa): multi-stage Dockerfile and nginx static server config"
```

---

## Task 3: Add `benem-pwa` service to `docker-compose.yml`

**Files:**
- Modify: `middleware/docker-compose.yml`

- [ ] **Step 1: Add the service**

Find the `caddy:` service block in `middleware/docker-compose.yml` and insert a new `benem-pwa:` service **above** it (after `benem-admin:`):

```yaml
  benem-pwa:
    build:
      context: ..
      dockerfile: pwa/Dockerfile
    expose:
      - "80"
    restart: unless-stopped
```

The full file should now list four services in order: `bhnm-apns`, `benem-admin`, `benem-pwa`, `caddy`.

- [ ] **Step 2: Validate the compose file parses**

```bash
cd middleware
docker compose config > /dev/null
```

Expected: exits 0, no output. (Warnings about the missing `.env` file are fine if `.env` doesn't exist locally — Compose just substitutes empty strings.)

- [ ] **Step 3: Commit**

```bash
git add middleware/docker-compose.yml
git commit -m "feat(middleware): add benem-pwa service to docker-compose"
```

---

## Task 4: Add `{$PWA_DOMAIN}` site block to Caddyfile

**Files:**
- Modify: `middleware/Caddyfile`

- [ ] **Step 1: Add the second site block**

Append this to the end of `middleware/Caddyfile` (after the closing `}` of the existing `{$DOMAIN}` block, keeping one blank line separator):

```caddyfile

{$PWA_DOMAIN} {
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

- [ ] **Step 2: Validate the Caddyfile using a throwaway caddy container**

```bash
cd middleware
docker run --rm -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -e DOMAIN=example.com \
  -e BASIC_AUTH_USER=user \
  -e BASIC_AUTH_HASH='$2a$14$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  -e PWA_DOMAIN=pwa.example.com \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Expected: `Valid configuration` on stdout, exit 0. (Warnings about placeholder bcrypt hash format are acceptable; a true validation error would be "adapter failed".)

- [ ] **Step 3: Commit**

```bash
git add middleware/Caddyfile
git commit -m "feat(middleware): add PWA_DOMAIN site block with /bhnm reverse proxy"
```

---

## Task 5: Settings localStorage wrapper (TDD)

**Files:**
- Create: `pwa/src/features/settings/settingsStorage.ts`
- Create: `pwa/src/features/settings/__tests__/settingsStorage.test.ts`

- [ ] **Step 1: Write the failing test**

Create `pwa/src/features/settings/__tests__/settingsStorage.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest';
import { loadApiKey, saveApiKey, clearApiKey } from '../settingsStorage';

describe('settingsStorage', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('returns null when no key is stored', () => {
    expect(loadApiKey()).toBeNull();
  });

  it('round-trips save and load', () => {
    saveApiKey('abc123');
    expect(loadApiKey()).toBe('abc123');
  });

  it('trims whitespace on save', () => {
    saveApiKey('  abc123  \n');
    expect(loadApiKey()).toBe('abc123');
  });

  it('clear removes the stored key', () => {
    saveApiKey('abc123');
    clearApiKey();
    expect(loadApiKey()).toBeNull();
  });
});
```

- [ ] **Step 2: Run and verify it fails**

```bash
cd pwa && npx vitest run src/features/settings/__tests__/settingsStorage.test.ts
```

Expected: FAIL with "Failed to resolve import '../settingsStorage'" or equivalent.

- [ ] **Step 3: Create the minimal implementation**

Create `pwa/src/features/settings/settingsStorage.ts`:

```ts
const KEY = 'benem:bhnm-api-key';

export function loadApiKey(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(KEY);
}

export function saveApiKey(value: string): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(KEY, value.trim());
}

export function clearApiKey(): void {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(KEY);
}
```

- [ ] **Step 4: Run tests — all green**

```bash
cd pwa && npx vitest run src/features/settings/__tests__/settingsStorage.test.ts
```

Expected: 4 passing.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/settings/settingsStorage.ts pwa/src/features/settings/__tests__/settingsStorage.test.ts
git commit -m "feat(pwa): add settingsStorage localStorage wrapper with tests"
```

---

## Task 6: Refactor `useConfig` to `useSyncExternalStore` (TDD)

**Files:**
- Modify: `pwa/src/lib/config.ts`
- Create: `pwa/src/lib/config.test.ts`

- [ ] **Step 1: Write the failing test**

Create `pwa/src/lib/config.test.ts`:

```ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useConfig, notifyConfigChanged } from './config';
import { saveApiKey, clearApiKey } from '../features/settings/settingsStorage';

describe('useConfig', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.unstubAllEnvs();
  });

  it('reads from localStorage when a key is stored', () => {
    saveApiKey('from-storage');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-storage');
    expect(result.current.isConfigured).toBe(true);
  });

  it('falls back to VITE_BHNM_API_KEY when localStorage is empty', () => {
    vi.stubEnv('VITE_BHNM_API_KEY', 'from-env');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-env');
    expect(result.current.isConfigured).toBe(true);
  });

  it('localStorage wins over env var', () => {
    vi.stubEnv('VITE_BHNM_API_KEY', 'from-env');
    saveApiKey('from-storage');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-storage');
  });

  it('is not configured when both are empty', () => {
    const { result } = renderHook(() => useConfig());
    expect(result.current.isConfigured).toBe(false);
    expect(result.current.apiKey).toBe('');
  });

  it('re-renders consumers when notifyConfigChanged is called after save', () => {
    const { result } = renderHook(() => useConfig());
    expect(result.current.isConfigured).toBe(false);

    act(() => {
      saveApiKey('new-key');
      notifyConfigChanged();
    });

    expect(result.current.apiKey).toBe('new-key');
    expect(result.current.isConfigured).toBe(true);
  });

  it('re-renders consumers when notifyConfigChanged is called after clear', () => {
    saveApiKey('initial');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('initial');

    act(() => {
      clearApiKey();
      notifyConfigChanged();
    });

    expect(result.current.apiKey).toBe('');
    expect(result.current.isConfigured).toBe(false);
  });
});
```

- [ ] **Step 2: Run and verify it fails**

```bash
cd pwa && npx vitest run src/lib/config.test.ts
```

Expected: FAIL. Most tests will fail either on the `notifyConfigChanged` import (symbol doesn't exist yet) or on localStorage precedence (current implementation ignores localStorage).

- [ ] **Step 3: Replace `pwa/src/lib/config.ts` entirely**

```ts
import { useSyncExternalStore } from 'react';
import { loadApiKey } from '../features/settings/settingsStorage';

export interface BhnmConfig {
  /** Base URL the client should hit. `/bhnm` in both dev (Vite proxy) and prod (Caddy handle_path). */
  baseUrl: string;
  apiKey: string;
  pin?: string;
  isConfigured: boolean;
}

const listeners = new Set<() => void>();

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

/**
 * Call after mutating config (e.g. from SettingsScreen Save/Clear) to force
 * every `useConfig()` consumer to re-read its snapshot.
 */
export function notifyConfigChanged(): void {
  listeners.forEach((cb) => cb());
}

function getSnapshot(): BhnmConfig {
  const storedKey = loadApiKey();
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  const envPin = (import.meta.env.VITE_BHNM_PIN as string | undefined) ?? '';
  const apiKey = storedKey && storedKey.length > 0 ? storedKey : envKey;
  return {
    baseUrl: '/bhnm',
    apiKey,
    pin: envPin.length > 0 ? envPin : undefined,
    isConfigured: apiKey.length > 0,
  };
}

// Server snapshot for SSR safety — returns the same shape with no storage access.
function getServerSnapshot(): BhnmConfig {
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  return {
    baseUrl: '/bhnm',
    apiKey: envKey,
    pin: undefined,
    isConfigured: envKey.length > 0,
  };
}

export function useConfig(): BhnmConfig {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
```

- [ ] **Step 4: Run the config test — all green**

```bash
cd pwa && npx vitest run src/lib/config.test.ts
```

Expected: 6 passing.

- [ ] **Step 5: Run the full test suite to confirm nothing else regressed**

```bash
cd pwa && npm test
```

Expected: all test files pass (platform, incidents parser, settingsStorage, config, IncidentListScreen smoke).

- [ ] **Step 6: Commit**

```bash
git add pwa/src/lib/config.ts pwa/src/lib/config.test.ts
git commit -m "feat(pwa): useConfig via useSyncExternalStore with localStorage precedence"
```

---

## Task 7: SettingsScreen (TDD)

**Files:**
- Create: `pwa/src/features/settings/SettingsScreen.tsx`
- Create: `pwa/src/features/settings/__tests__/SettingsScreen.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `pwa/src/features/settings/__tests__/SettingsScreen.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { SettingsScreen } from '../SettingsScreen';
import { saveApiKey, loadApiKey } from '../settingsStorage';

function renderScreen() {
  return render(
    <MemoryRouter>
      <SettingsScreen />
    </MemoryRouter>,
  );
}

describe('SettingsScreen', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('renders the API key input and Save button', () => {
    renderScreen();
    expect(screen.getByLabelText(/BHNM API key/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /clear/i })).toBeInTheDocument();
  });

  it('pre-populates the field from localStorage on mount', () => {
    saveApiKey('preloaded-key');
    renderScreen();
    expect(screen.getByLabelText(/BHNM API key/i)).toHaveValue('preloaded-key');
    expect(screen.getByText(/configured/i)).toBeInTheDocument();
  });

  it('saves a new key to localStorage and shows confirmation', async () => {
    const user = userEvent.setup();
    renderScreen();
    await user.type(screen.getByLabelText(/BHNM API key/i), 'new-key');
    await user.click(screen.getByRole('button', { name: /save/i }));
    expect(loadApiKey()).toBe('new-key');
    expect(screen.getByRole('status')).toHaveTextContent(/saved/i);
  });

  it('clears the stored key', async () => {
    const user = userEvent.setup();
    saveApiKey('initial');
    renderScreen();
    await user.click(screen.getByRole('button', { name: /clear/i }));
    expect(loadApiKey()).toBeNull();
    expect(screen.getByLabelText(/BHNM API key/i)).toHaveValue('');
  });
});
```

- [ ] **Step 2: Check for `@testing-library/user-event`**

```bash
cd pwa && npm ls @testing-library/user-event
```

If missing, install it as a dev dependency (exact version pinned to match the react testing library major):

```bash
cd pwa && npm install --save-dev @testing-library/user-event@^14.5.2
```

- [ ] **Step 3: Run the test — expect failure**

```bash
cd pwa && npx vitest run src/features/settings/__tests__/SettingsScreen.test.tsx
```

Expected: FAIL with "Failed to resolve import '../SettingsScreen'".

- [ ] **Step 4: Create `pwa/src/features/settings/SettingsScreen.tsx`**

```tsx
import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import { loadApiKey, saveApiKey, clearApiKey } from './settingsStorage';

export function SettingsScreen() {
  const config = useConfig();
  const [value, setValue] = useState<string>(() => loadApiKey() ?? '');
  const [statusMessage, setStatusMessage] = useState<string>('');

  const onSave = (event: FormEvent) => {
    event.preventDefault();
    saveApiKey(value);
    notifyConfigChanged();
    setValue(loadApiKey() ?? '');
    setStatusMessage('Saved.');
  };

  const onClear = () => {
    clearApiKey();
    notifyConfigChanged();
    setValue('');
    setStatusMessage('Cleared.');
  };

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-300 hover:text-white" aria-label="Back to incidents">
          ← Back
        </Link>
        <h1 className="text-lg font-semibold">Settings</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      <form className="p-4 space-y-4 max-w-md" onSubmit={onSave}>
        <div>
          <label htmlFor="bhnm-api-key" className="block text-sm font-medium text-slate-200">
            BHNM API key
          </label>
          <input
            id="bhnm-api-key"
            type="password"
            autoComplete="off"
            spellCheck={false}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            aria-describedby="bhnm-api-key-help"
            className="mt-1 w-full rounded bg-slate-900 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
          <p id="bhnm-api-key-help" className="mt-1 text-xs text-slate-400">
            Stored in your browser only. Sent to BHNM via the BeNeM middleware, nowhere else.
          </p>
        </div>

        <div className="flex gap-2">
          <button
            type="submit"
            className="px-3 py-1.5 rounded bg-sky-600 hover:bg-sky-500 text-sm"
          >
            Save
          </button>
          <button
            type="button"
            onClick={onClear}
            className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-sm"
          >
            Clear
          </button>
        </div>

        <div className="text-xs text-slate-400" aria-live="polite" role="status">
          {statusMessage || (config.isConfigured ? '✓ Configured' : 'Not configured')}
        </div>
      </form>
    </div>
  );
}
```

- [ ] **Step 5: Run the test — all green**

```bash
cd pwa && npx vitest run src/features/settings/__tests__/SettingsScreen.test.tsx
```

Expected: 4 passing.

- [ ] **Step 6: Commit**

```bash
git add pwa/package.json pwa/package-lock.json pwa/src/features/settings/SettingsScreen.tsx pwa/src/features/settings/__tests__/SettingsScreen.test.tsx
git commit -m "feat(pwa): add minimal SettingsScreen for BHNM API key"
```

(If `@testing-library/user-event` was already present, the `package.json`/`package-lock.json` paths drop out of the `git add`.)

---

## Task 8: Mount `/settings` route in `App.tsx`

**Files:**
- Modify: `pwa/src/App.tsx`

- [ ] **Step 1: Replace `App.tsx` with the new version**

```tsx
import { Routes, Route } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailStub } from './features/incidents/IncidentDetailStub';
import { SettingsScreen } from './features/settings/SettingsScreen';

export default function App() {
  return (
    <div className="min-h-full">
      <IOSRedirectBanner />
      <Routes>
        <Route path="/" element={<IncidentListScreen />} />
        <Route path="/settings" element={<SettingsScreen />} />
        <Route path="/incident/:id" element={<IncidentDetailStub />} />
      </Routes>
    </div>
  );
}
```

- [ ] **Step 2: Run typecheck + tests**

```bash
cd pwa && npm run typecheck && npm test
```

Expected: typecheck exits 0; all test files pass.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/App.tsx
git commit -m "feat(pwa): mount /settings route"
```

---

## Task 9: IncidentListScreen — header gear icon + actionable empty states

**Files:**
- Modify: `pwa/src/features/incidents/IncidentListScreen.tsx`

- [ ] **Step 1: Replace the file with the updated version**

```tsx
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { IncidentRow } from './IncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { useConfig } from '../../lib/config';

function GearIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="w-5 h-5"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51h0a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

function ConfigureLink() {
  return (
    <Link
      to="/settings"
      className="inline-block px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm"
    >
      Configure API key
    </Link>
  );
}

export function IncidentListScreen() {
  const { data, isLoading, isError, error, refetch } = useIncidents();
  const queryClient = useQueryClient();
  const config = useConfig();

  const onRefresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    await refetch();
  };

  return (
    <PullToRefresh onRefresh={onRefresh}>
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <h1 className="text-lg font-semibold">Incidents</h1>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onRefresh}
            className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
            aria-label="Refresh"
          >
            Refresh
          </button>
          <Link
            to="/settings"
            aria-label="Settings"
            className="p-1 rounded hover:bg-slate-800 text-slate-300 hover:text-white"
          >
            <GearIcon />
          </Link>
        </div>
      </header>

      {isLoading && (
        <EmptyState title="Loading…" description="Fetching incidents from BHNM." />
      )}

      {isError && (
        <EmptyState
          title="Could not reach BHNM"
          description={(error as Error).message}
          action={
            <div className="flex gap-2">
              <button
                type="button"
                onClick={onRefresh}
                className="px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-sm"
              >
                Retry
              </button>
              <ConfigureLink />
            </div>
          }
        />
      )}

      {!isLoading && !isError && !config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — showing mock data.</span>
          <ConfigureLink />
        </div>
      )}

      {!isLoading && !isError && data && data.length === 0 && (
        <EmptyState title="No open incidents" description="All clear." />
      )}

      <ul role="list" data-testid="incident-list">
        {data?.map((incident) => (
          <li key={incident.incidentId}>
            <IncidentRow incident={incident} />
          </li>
        ))}
      </ul>
    </PullToRefresh>
  );
}
```

- [ ] **Step 2: Run the full PWA test suite**

```bash
cd pwa && npm test
```

Expected: all passing. The existing `IncidentListScreen.test.tsx` smoke test mocks `useIncidents`; it must still pass without modification (it only asserts row/badge presence).

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/incidents/IncidentListScreen.tsx
git commit -m "feat(pwa): settings gear icon and configure-API-key actions"
```

---

## Task 10: Version bump, README, feature-spec

**Files:**
- Modify: `pwa/package.json`
- Modify: `pwa/README.md`
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Bump PWA version**

In `pwa/package.json`, change:

```json
  "version": "0.1.0",
```

to:

```json
  "version": "0.1.0.5",
```

- [ ] **Step 2: Add a Production Hosting section to `pwa/README.md`**

Append the following after the existing "Middleware coupling" section:

```markdown

## Production hosting

The PWA is deployed at `https://benem.hurrikap.org` as a dedicated
`benem-pwa` container managed by `middleware/docker-compose.yml`. The
same Caddy instance that fronts the `bhnm-apns` push middleware
terminates TLS for both hostnames and same-origin-proxies
`/bhnm/*` on the PWA host to the middleware container — so the PWA
has no CORS dependency and shares no code with the middleware image.

First-time deploy checklist (run on the server, repo root):

1. `git pull`
2. Add `PWA_DOMAIN=benem.hurrikap.org` to `middleware/.env`
3. Create a DNS A/AAAA record for `benem.hurrikap.org` pointing at the server
4. Wait for DNS to propagate (`dig +short benem.hurrikap.org`)
5. `cd middleware && docker compose up -d` (Caddy will provision a Let's Encrypt cert automatically)
6. Visit `https://benem.hurrikap.org/settings` and enter your BHNM API key

Subsequent deploys are `./middleware/upgrade.sh`, which rebuilds the
`benem-pwa` image from the current `pwa/` source on every run.

The API key you enter in Settings is stored in your browser's
`localStorage` (scoped to `benem.hurrikap.org`) and is never sent
anywhere except BHNM via the middleware proxy.
```

- [ ] **Step 3: Update `shared/feature-spec.md` PWA section**

Find:

```markdown
#### PWA-specific
- v0.1.0: read-only list, 120s auto-refresh, pull-to-refresh, tap navigates to detail stub
- v0.1.1 (planned): swipe ACK / UnACK, real incident detail screen, Settings screen
- No native-style swipe gesture library — touch-based pull-to-refresh is hand-rolled in `components/PullToRefresh.tsx`
```

Replace with:

```markdown
#### PWA-specific
- v0.1.0: read-only list, 120s auto-refresh, pull-to-refresh, tap navigates to detail stub
- v0.1.0.5: hosted at `https://benem.hurrikap.org` as a dedicated container alongside the middleware; minimal Settings screen for BHNM API key entry (localStorage)
- v0.1.1 (planned): swipe ACK / UnACK, real incident detail screen, polished Settings with PIN + test-connection
- No native-style swipe gesture library — touch-based pull-to-refresh is hand-rolled in `components/PullToRefresh.tsx`
```

- [ ] **Step 4: Commit**

```bash
git add pwa/package.json pwa/README.md shared/feature-spec.md
git commit -m "docs: bump PWA to 0.1.0.5 and document hosting + minimal settings"
```

---

## Task 11: upgrade.sh — Caddyfile validation + benem-pwa build & smoke check

**Files:**
- Modify: `middleware/upgrade.sh`

- [ ] **Step 1: Insert Caddyfile validation step**

In `middleware/upgrade.sh`, find the "Rebuild image" block:

```bash
# ── Rebuild image ──────────────────────────────────

echo ""
echo -e "${CYAN}── Rebuilding Docker image ───────────────────────${NC}"
docker compose build --no-cache 2>&1 | grep -v -e "^#" -e "^$" || die "docker compose build failed."
ok "Image built."
```

Insert a new block **above** it:

```bash
# ── Validate Caddyfile ─────────────────────────────

echo ""
echo -e "${CYAN}── Validating Caddyfile ──────────────────────────${NC}"
docker run --rm \
  --env-file .env \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile \
  || die "Caddyfile is invalid — aborting upgrade."
ok "Caddyfile valid."

```

- [ ] **Step 2: Add the benem-pwa smoke check to the health-check section**

In the same file, find the health-check block for `benem-admin` (ending with `FAILED=1` and the `fi`). Immediately after it (before the `if [ "$FAILED" -ne 0 ]` summary), add:

```bash

HEALTH_PWA=$(docker compose exec -T benem-pwa wget -q -O - http://localhost/ 2>/dev/null | head -c 50 || echo "")
if echo "$HEALTH_PWA" | grep -qi '<!doctype html'; then
    ok "benem-pwa is serving the SPA shell."
else
    warn "benem-pwa health check failed — check logs:"
    docker compose logs benem-pwa --tail 20
    FAILED=1
fi
```

`nginx:alpine` ships with `wget`, so no extra install is needed. The check verifies that nginx inside the container responds with an HTML document whose first bytes contain `<!doctype html` (case-insensitive).

- [ ] **Step 3: Shell-lint the script**

```bash
bash -n middleware/upgrade.sh
```

Expected: exits 0, no output.

- [ ] **Step 4: Commit**

```bash
git add middleware/upgrade.sh
git commit -m "feat(middleware): validate Caddyfile and smoke-check benem-pwa in upgrade"
```

---

## Task 12: Final verification + stop for review

No files change. This is the stop gate before the user deploys.

- [ ] **Step 1: Full PWA verification matrix (from `pwa/`)**

```bash
cd pwa
npm run typecheck
npm test
npm run build
```

Expected:
- `typecheck` → exit 0, no output
- `test` → all test files pass (platform, incidents parser, settingsStorage, config, SettingsScreen, IncidentListScreen smoke)
- `build` → `dist/` produced with `sw.js`, `workbox-*.js`, `manifest.webmanifest`, `index.html`, JS + CSS bundles

- [ ] **Step 2: Compose + Caddyfile static validation (from `middleware/`)**

```bash
cd ../middleware
docker compose config > /dev/null
docker run --rm \
  -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -e DOMAIN=example.com \
  -e BASIC_AUTH_USER=user \
  -e BASIC_AUTH_HASH='$2a$14$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  -e PWA_DOMAIN=pwa.example.com \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Expected: both exit 0. `caddy validate` prints `Valid configuration`.

- [ ] **Step 3: Full compose build of the new service (from `middleware/`)**

```bash
docker compose build benem-pwa
```

Expected: multi-stage build completes; final image is tagged by compose (`middleware-benem-pwa` or similar). No failures.

- [ ] **Step 4: Confirm clean git state (from repo root)**

```bash
cd ..
git status
```

Expected: working tree clean. Every change from Tasks 1–11 is already committed.

- [ ] **Step 5: Stop and hand off to the user**

Do **not** deploy to the Linode server automatically. Do **not** push to `origin` unless explicitly asked. Report:
- Commits created for this release (`git log --oneline main -20`)
- PWA verification results
- Compose + Caddy validation results
- The first-time deploy checklist from `pwa/README.md` (DNS record, `.env` edit, `docker compose up -d`)

Wait for the user's review and their go-ahead before any server-side deploy.
