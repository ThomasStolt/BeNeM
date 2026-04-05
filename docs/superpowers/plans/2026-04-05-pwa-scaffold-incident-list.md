# PWA v0.1.0 — Scaffold + Incident List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the BeNeM PWA under `pwa/` with Vite + React + TypeScript + Tailwind + vite-plugin-pwa and ship a working Incident List screen fetching from BHNM via the existing middleware proxy. Stop for user review before continuing.

**Architecture:** Single Vite-built SPA. TanStack Query owns server state (120s auto-refresh, pull-to-refresh via `invalidateQueries`). API client talks to middleware (`bhnm-apns.hurrikap.org`) through a Vite dev proxy under `/bhnm`, using form-urlencoded POSTs to BHNM's `incident_api.php`. Config is read from `.env.local` (`VITE_BHNM_API_KEY`, `VITE_BHNM_PIN`, `VITE_MIDDLEWARE_BASE`). iOS browsers see a sticky banner recommending the native app; no Web Push code in v0.1.0.

**Tech Stack:** Vite 5, React 18, TypeScript (strict), Tailwind CSS v3, vite-plugin-pwa, TanStack Query v5, React Router v6, Vitest, @testing-library/react, jsdom.

**Spec:** `docs/superpowers/specs/2026-04-05-pwa-scaffold-incident-list-design.md`

---

## Conventions (read before starting)

- **Working directory for every command:** `pwa/` unless explicitly stated otherwise.
- **Package manager:** `npm`. (If the repo later standardises on pnpm, migrate in a separate task.)
- **Commit messages:** Conventional commits (`feat(pwa): …`, `chore(pwa): …`, `test(pwa): …`, `docs(pwa): …`).
- **Every task ends with a commit.** No mixed-concern commits.
- **Every test step includes the exact command and expected outcome.**
- **Never commit `.env.local`.** Only `.env.example` is committed.

---

## File map

| Path | Responsibility | Task |
|---|---|---|
| `pwa/package.json` | Dependencies, scripts, version 0.1.0 | 1 |
| `pwa/tsconfig.json`, `pwa/tsconfig.node.json` | TS strict config | 1 |
| `pwa/vite.config.ts` | Vite + PWA plugin + dev proxy + Vitest config | 1, 2, 3 |
| `pwa/tailwind.config.js`, `pwa/postcss.config.js` | Tailwind wiring | 1 |
| `pwa/index.html` | HTML entry | 1 |
| `pwa/.gitignore`, `pwa/.env.example` | Env hygiene | 1 |
| `pwa/public/icons/` | PWA icon placeholders | 2 |
| `pwa/src/main.tsx` | React root + providers | 1, 4 |
| `pwa/src/App.tsx` | Layout shell, routes, banner | 4, 13 |
| `pwa/src/index.css` | Tailwind directives | 1 |
| `pwa/src/vite-env.d.ts` | Env type defs | 1 |
| `pwa/src/lib/platform.ts` | `isIOS()` UA detection | 5 |
| `pwa/src/lib/platform.test.ts` | UA detection tests | 5 |
| `pwa/src/lib/config.ts` | `useConfig()` hook reading import.meta.env | 6 |
| `pwa/src/lib/api/types.ts` | `Incident`, `Severity`, `IncidentStatus` | 7 |
| `pwa/src/lib/api/client.ts` | `apiPost()` fetch wrapper | 8 |
| `pwa/src/lib/api/incidents.ts` | `getIncidents()` + parser | 9 |
| `pwa/src/lib/api/incidents.test.ts` | Parser unit tests | 9 |
| `pwa/src/lib/mock/incidents.json` | Fixture (active + closed) | 7 |
| `pwa/src/features/incidents/useIncidents.ts` | TanStack Query hook, 120s refetch | 10 |
| `pwa/src/features/incidents/SeverityBadge.tsx` | Color-coded severity pill | 11 |
| `pwa/src/features/incidents/IncidentRow.tsx` | Single row | 11 |
| `pwa/src/features/incidents/IncidentListScreen.tsx` | Screen root: list, empty states, pull-to-refresh | 12 |
| `pwa/src/features/incidents/__tests__/IncidentListScreen.test.tsx` | Smoke test | 12 |
| `pwa/src/components/IOSRedirectBanner.tsx` | Sticky top banner for iOS | 5 |
| `pwa/src/components/EmptyState.tsx` | Shared empty/error placeholder | 11 |
| `pwa/src/components/PullToRefresh.tsx` | Touch gesture wrapper | 12 |
| `pwa/src/features/incidents/IncidentDetailStub.tsx` | `/incident/:id` placeholder | 13 |
| `pwa/README.md` | Dev setup notes | 14 |
| `shared/feature-spec.md` | Mark PWA Incident List in-progress | 14 |

---

## Task 1: Create Vite + React + TS + Tailwind scaffold

**Files:**
- Create: `pwa/package.json`
- Create: `pwa/tsconfig.json`
- Create: `pwa/tsconfig.node.json`
- Create: `pwa/vite.config.ts`
- Create: `pwa/tailwind.config.js`
- Create: `pwa/postcss.config.js`
- Create: `pwa/index.html`
- Create: `pwa/.gitignore`
- Create: `pwa/.env.example`
- Create: `pwa/src/main.tsx`
- Create: `pwa/src/App.tsx`
- Create: `pwa/src/index.css`
- Create: `pwa/src/vite-env.d.ts`

- [ ] **Step 1: Create `pwa/package.json`**

```json
{
  "name": "benem-pwa",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc -b --noEmit"
  },
  "dependencies": {
    "@tanstack/react-query": "^5.51.0",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.0"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.4.8",
    "@testing-library/react": "^16.0.0",
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.19",
    "jsdom": "^24.1.1",
    "postcss": "^8.4.40",
    "tailwindcss": "^3.4.7",
    "typescript": "^5.5.4",
    "vite": "^5.3.5",
    "vite-plugin-pwa": "^0.20.0",
    "vitest": "^2.0.5"
  }
}
```

- [ ] **Step 2: Create `pwa/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vite/client", "vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

- [ ] **Step 3: Create `pwa/tsconfig.node.json`**

```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 4: Create minimal `pwa/vite.config.ts`** (PWA plugin + proxy added in later tasks)

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
  },
});
```

- [ ] **Step 5: Create `pwa/tailwind.config.js`**

```js
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        severity: {
          critical: '#dc2626',
          major: '#ea580c',
          minor: '#ca8a04',
          warning: '#eab308',
          informational: '#2563eb',
        },
      },
    },
  },
  plugins: [],
};
```

- [ ] **Step 6: Create `pwa/postcss.config.js`**

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
```

- [ ] **Step 7: Create `pwa/index.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
    <meta name="theme-color" content="#0f172a" />
    <title>BeNeM</title>
  </head>
  <body class="bg-slate-950 text-slate-100">
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 8: Create `pwa/.gitignore`**

```
node_modules
dist
dist-ssr
.env.local
.env.*.local
*.log
.vite
coverage
```

- [ ] **Step 9: Create `pwa/.env.example`**

```
# Middleware base URL (BHNM proxy endpoint). Vite dev server proxies /bhnm/* here.
VITE_MIDDLEWARE_BASE=https://bhnm-apns.hurrikap.org

# BHNM API key (maps to servers.json entry in middleware). REQUIRED for real data.
VITE_BHNM_API_KEY=

# Optional BHNM PIN.
VITE_BHNM_PIN=
```

- [ ] **Step 10: Create `pwa/src/vite-env.d.ts`**

```ts
/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
  readonly VITE_MIDDLEWARE_BASE?: string;
  readonly VITE_BHNM_API_KEY?: string;
  readonly VITE_BHNM_PIN?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
```

- [ ] **Step 11: Create `pwa/src/index.css`**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

html, body, #root {
  height: 100%;
}
```

- [ ] **Step 12: Create `pwa/src/App.tsx`** (minimal, expanded in Task 13)

```tsx
export default function App() {
  return (
    <div className="min-h-full flex items-center justify-center p-8">
      <h1 className="text-2xl font-semibold">BeNeM PWA</h1>
    </div>
  );
}
```

- [ ] **Step 13: Create `pwa/src/main.tsx`**

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

- [ ] **Step 14: Create `pwa/src/test-setup.ts`**

```ts
import '@testing-library/jest-dom';
```

- [ ] **Step 15: Install dependencies**

Run (from `pwa/`): `npm install`
Expected: lockfile created, `node_modules/` populated, no peer-dep errors that abort install.

- [ ] **Step 16: Verify typecheck and build**

Run: `npm run typecheck`
Expected: exits 0 with no output.

Run: `npm run build`
Expected: `dist/` produced, no errors.

- [ ] **Step 17: Commit**

```bash
git add pwa/package.json pwa/package-lock.json pwa/tsconfig.json pwa/tsconfig.node.json \
  pwa/vite.config.ts pwa/tailwind.config.js pwa/postcss.config.js pwa/index.html \
  pwa/.gitignore pwa/.env.example pwa/src/main.tsx pwa/src/App.tsx pwa/src/index.css \
  pwa/src/vite-env.d.ts pwa/src/test-setup.ts
git commit -m "feat(pwa): scaffold Vite + React + TS + Tailwind base"
```

---

## Task 2: Add vite-plugin-pwa and manifest

**Files:**
- Modify: `pwa/vite.config.ts`
- Create: `pwa/public/icons/.gitkeep`

- [ ] **Step 1: Replace `pwa/vite.config.ts`**

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/*'],
      manifest: {
        name: 'BeNeM',
        short_name: 'BeNeM',
        description: 'BHNM incident monitoring',
        theme_color: '#0f172a',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: '/',
        icons: [],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
      },
    }),
  ],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
  },
});
```

- [ ] **Step 2: Create `pwa/public/icons/.gitkeep`**

Empty file — real icons land in a later iteration. The manifest `icons: []` explicitly accepts no icons for now; Workbox still builds.

- [ ] **Step 3: Verify build**

Run: `npm run build`
Expected: build succeeds, `dist/sw.js` and `dist/manifest.webmanifest` exist.
Verify: `ls dist/sw.js dist/manifest.webmanifest`

- [ ] **Step 4: Commit**

```bash
git add pwa/vite.config.ts pwa/public/icons/.gitkeep
git commit -m "feat(pwa): add vite-plugin-pwa manifest and service worker"
```

---

## Task 3: Add dev proxy for BHNM middleware

**Files:**
- Modify: `pwa/vite.config.ts`

- [ ] **Step 1: Update `pwa/vite.config.ts` to add the `server.proxy` block**

Replace the exported config with:

```ts
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const middlewareBase = env.VITE_MIDDLEWARE_BASE ?? 'https://bhnm-apns.hurrikap.org';

  return {
    plugins: [
      react(),
      VitePWA({
        registerType: 'autoUpdate',
        includeAssets: ['icons/*'],
        manifest: {
          name: 'BeNeM',
          short_name: 'BeNeM',
          description: 'BHNM incident monitoring',
          theme_color: '#0f172a',
          background_color: '#0f172a',
          display: 'standalone',
          start_url: '/',
          icons: [],
        },
        workbox: {
          globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        },
      }),
    ],
    server: {
      proxy: {
        '/bhnm': {
          target: middlewareBase,
          changeOrigin: true,
          secure: true,
          rewrite: (p) => p.replace(/^\/bhnm/, ''),
        },
      },
    },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: ['./src/test-setup.ts'],
    },
  };
});
```

- [ ] **Step 2: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add pwa/vite.config.ts
git commit -m "feat(pwa): dev-proxy /bhnm to middleware base URL"
```

---

## Task 4: Wire React Query + Router providers

**Files:**
- Modify: `pwa/src/main.tsx`
- Modify: `pwa/src/App.tsx`

- [ ] **Step 1: Replace `pwa/src/main.tsx`**

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import './index.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: true,
      retry: 1,
      staleTime: 30_000,
    },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>
);
```

- [ ] **Step 2: Replace `pwa/src/App.tsx`** (still a placeholder — real routes land in Task 13)

```tsx
import { Routes, Route } from 'react-router-dom';

export default function App() {
  return (
    <div className="min-h-full">
      <Routes>
        <Route path="/" element={<Placeholder />} />
      </Routes>
    </div>
  );
}

function Placeholder() {
  return (
    <div className="flex items-center justify-center p-8">
      <h1 className="text-2xl font-semibold">BeNeM PWA</h1>
    </div>
  );
}
```

- [ ] **Step 3: Verify typecheck and build**

Run: `npm run typecheck && npm run build`
Expected: both exit 0.

- [ ] **Step 4: Commit**

```bash
git add pwa/src/main.tsx pwa/src/App.tsx
git commit -m "feat(pwa): add React Query and Router providers"
```

---

## Task 5: Platform detection + iOS redirect banner

**Files:**
- Create: `pwa/src/lib/platform.ts`
- Create: `pwa/src/lib/platform.test.ts`
- Create: `pwa/src/components/IOSRedirectBanner.tsx`

- [ ] **Step 1: Write the failing test `pwa/src/lib/platform.test.ts`**

```ts
import { describe, it, expect } from 'vitest';
import { isIOSUserAgent } from './platform';

describe('isIOSUserAgent', () => {
  it('returns true for iPhone UA', () => {
    const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15';
    expect(isIOSUserAgent(ua)).toBe(true);
  });

  it('returns true for iPad UA', () => {
    const ua = 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15';
    expect(isIOSUserAgent(ua)).toBe(true);
  });

  it('returns false for Android UA', () => {
    const ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36';
    expect(isIOSUserAgent(ua)).toBe(false);
  });

  it('returns false for desktop Chrome UA', () => {
    const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0';
    expect(isIOSUserAgent(ua)).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- platform`
Expected: FAIL with module not found / `isIOSUserAgent is not a function`.

- [ ] **Step 3: Create `pwa/src/lib/platform.ts`**

```ts
export function isIOSUserAgent(ua: string): boolean {
  return /iPad|iPhone|iPod/.test(ua);
}

export function isIOS(): boolean {
  if (typeof navigator === 'undefined') return false;
  // @ts-expect-error — legacy IE flag, absence is meaningful on iOS
  if (typeof window !== 'undefined' && window.MSStream) return false;
  return isIOSUserAgent(navigator.userAgent);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- platform`
Expected: 4 passed.

- [ ] **Step 5: Create `pwa/src/components/IOSRedirectBanner.tsx`**

```tsx
import { useState } from 'react';
import { isIOS } from '../lib/platform';

const DISMISS_KEY = 'benem:ios-banner-dismissed';

export function IOSRedirectBanner() {
  const [dismissed, setDismissed] = useState(
    () => typeof sessionStorage !== 'undefined' && sessionStorage.getItem(DISMISS_KEY) === '1'
  );

  if (dismissed || !isIOS()) return null;

  const dismiss = () => {
    sessionStorage.setItem(DISMISS_KEY, '1');
    setDismissed(true);
  };

  return (
    <div className="sticky top-0 z-40 bg-amber-500 text-slate-950 px-4 py-2 flex items-center justify-between text-sm">
      <span>
        For reliable incident alerts, install the{' '}
        {/* TODO: replace with App Store URL when listing is live */}
        <a href="#" className="underline font-semibold">
          BeNeM iOS app
        </a>
        .
      </span>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss"
        className="ml-4 font-bold text-lg leading-none"
      >
        ×
      </button>
    </div>
  );
}
```

- [ ] **Step 6: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 7: Commit**

```bash
git add pwa/src/lib/platform.ts pwa/src/lib/platform.test.ts pwa/src/components/IOSRedirectBanner.tsx
git commit -m "feat(pwa): iOS detection and redirect banner"
```

---

## Task 6: Config hook

**Files:**
- Create: `pwa/src/lib/config.ts`

- [ ] **Step 1: Create `pwa/src/lib/config.ts`**

```ts
export interface BhnmConfig {
  /** Base URL the client should hit. In dev this is "/bhnm" (Vite proxy). */
  baseUrl: string;
  apiKey: string;
  pin?: string;
  isConfigured: boolean;
}

export function useConfig(): BhnmConfig {
  const apiKey = import.meta.env.VITE_BHNM_API_KEY ?? '';
  const pin = import.meta.env.VITE_BHNM_PIN || undefined;
  // Dev proxy mounted at /bhnm in vite.config.ts. In production this will need
  // a proper absolute URL + CORS on middleware — deferred to v0.1.1.
  const baseUrl = '/bhnm';
  return {
    baseUrl,
    apiKey,
    pin,
    isConfigured: apiKey.length > 0,
  };
}
```

- [ ] **Step 2: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/lib/config.ts
git commit -m "feat(pwa): add useConfig hook reading Vite env"
```

---

## Task 7: API types + mock fixture

**Files:**
- Create: `pwa/src/lib/api/types.ts`
- Create: `pwa/src/lib/mock/incidents.json`

- [ ] **Step 1: Create `pwa/src/lib/api/types.ts`**

```ts
export type Severity = 'critical' | 'major' | 'minor' | 'warning' | 'informational';
export type IncidentStatus = 'active' | 'acknowledged' | 'resolved' | 'closed';

export interface Incident {
  incidentId: string;
  displayId: string;
  deviceName: string | null;
  deviceIp: string | null;
  summary: string;
  severity: Severity;
  status: IncidentStatus;
  incidentState: string;
  startTime: Date;
  acknowledgedBy: string | null;
}

export type ApiError =
  | { kind: 'network'; message: string }
  | { kind: 'auth'; message: string }
  | { kind: 'server'; status: number; message: string }
  | { kind: 'parse'; message: string };

export class ApiException extends Error {
  constructor(public readonly error: ApiError) {
    super(error.message);
    this.name = 'ApiException';
  }
}
```

- [ ] **Step 2: Create `pwa/src/lib/mock/incidents.json`**

Real-shape fixture matching the BHNM legacy `active_incidents` / `closed_incidents` format so parser tests exercise real paths.

```json
[
  {
    "active_incidents": [
      {
        "incident_id": 58431,
        "title": "CPU utilization high on core-switch-01",
        "name": "core-switch-01",
        "ip": "10.0.0.1",
        "incident_state": "OPEN",
        "severity": "critical",
        "start_time": 1712332800
      },
      {
        "incident_id": "NetreoCloudDemo-58432",
        "title": "Interface Gi0/1 down",
        "name": "edge-router-02",
        "ip": "10.0.0.2",
        "incident_state": "ACKNOWLEDGED",
        "alert_level": "major",
        "start_time": 1712329200,
        "acknowledged_by": "oncall@example.com"
      }
    ],
    "closed_incidents": [
      {
        "incident_id": 58400,
        "title": "Memory usage warning",
        "name": "app-server-03",
        "ip": "10.0.1.5",
        "incident_state": "CLOSED",
        "level": "minor",
        "start_time": 1712300000
      }
    ],
    "success": true
  }
]
```

- [ ] **Step 3: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add pwa/src/lib/api/types.ts pwa/src/lib/mock/incidents.json
git commit -m "feat(pwa): incident types and mock fixture"
```

---

## Task 8: API client (fetch wrapper)

**Files:**
- Create: `pwa/src/lib/api/client.ts`

- [ ] **Step 1: Create `pwa/src/lib/api/client.ts`**

```ts
import { ApiException } from './types';

/**
 * POST form-urlencoded to the BHNM middleware proxy.
 * Returns parsed JSON (may be object or array — caller handles shape).
 */
export async function postForm(
  baseUrl: string,
  path: string,
  params: Record<string, string>
): Promise<unknown> {
  const body = new URLSearchParams(params).toString();
  let response: Response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
  } catch (err) {
    throw new ApiException({
      kind: 'network',
      message: err instanceof Error ? err.message : 'Network error',
    });
  }

  if (response.status === 401 || response.status === 403) {
    throw new ApiException({ kind: 'auth', message: `HTTP ${response.status}` });
  }
  if (!response.ok) {
    throw new ApiException({
      kind: 'server',
      status: response.status,
      message: `HTTP ${response.status}`,
    });
  }

  try {
    return await response.json();
  } catch (err) {
    throw new ApiException({
      kind: 'parse',
      message: err instanceof Error ? err.message : 'JSON parse error',
    });
  }
}
```

- [ ] **Step 2: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/lib/api/client.ts
git commit -m "feat(pwa): add form-urlencoded API client with error taxonomy"
```

---

## Task 9: Incidents parser + tests

BHNM returns either a plain object OR a one-element array wrapping that object. The object may contain `active_incidents` + `closed_incidents`, or `incidents`, or `data`. Severity comes from one of several possible keys. The parser must be robust to all of these, matching iOS behaviour in `NetreoAPIService.swift:856-999`.

**Files:**
- Create: `pwa/src/lib/api/incidents.ts`
- Create: `pwa/src/lib/api/incidents.test.ts`

- [ ] **Step 1: Write the failing test `pwa/src/lib/api/incidents.test.ts`**

```ts
import { describe, it, expect } from 'vitest';
import { parseIncidentsResponse, buildDisplayId } from './incidents';
import mock from '../mock/incidents.json';

describe('buildDisplayId', () => {
  it('strips prefix before last dash and prepends #', () => {
    expect(buildDisplayId('NetreoCloudDemo-58431')).toBe('#58431');
  });
  it('prepends # to bare numeric ids', () => {
    expect(buildDisplayId('58431')).toBe('#58431');
  });
  it('preserves leading # if already present', () => {
    expect(buildDisplayId('#58431')).toBe('#58431');
  });
});

describe('parseIncidentsResponse', () => {
  it('parses array-wrapped response with active + closed incidents', () => {
    const incidents = parseIncidentsResponse(mock);
    expect(incidents).toHaveLength(3);
    expect(incidents[0].incidentId).toBe('58431');
    expect(incidents[0].severity).toBe('critical');
    expect(incidents[0].status).toBe('active');
    expect(incidents[0].displayId).toBe('#58431');
  });

  it('forces closed_incidents to resolved status', () => {
    const incidents = parseIncidentsResponse(mock);
    const closed = incidents.find((i) => i.incidentId === '58400');
    expect(closed).toBeDefined();
    expect(closed!.status).toBe('resolved');
  });

  it('maps alert_level=major to severity=major', () => {
    const incidents = parseIncidentsResponse(mock);
    const ack = incidents.find((i) => i.displayId === '#58432');
    expect(ack).toBeDefined();
    expect(ack!.severity).toBe('major');
    expect(ack!.status).toBe('acknowledged');
    expect(ack!.acknowledgedBy).toBe('oncall@example.com');
  });

  it('handles plain object (non-array) response', () => {
    const plain = {
      active_incidents: [
        { incident_id: 1, title: 'x', name: 'host', incident_state: 'OPEN', severity: 'warning', start_time: 1712000000 },
      ],
      success: true,
    };
    const incidents = parseIncidentsResponse(plain);
    expect(incidents).toHaveLength(1);
    expect(incidents[0].severity).toBe('warning');
  });

  it('falls back to critical when severity is missing', () => {
    const plain = {
      active_incidents: [
        { incident_id: 2, title: 'y', name: 'h', incident_state: 'OPEN', start_time: 1712000000 },
      ],
    };
    const incidents = parseIncidentsResponse(plain);
    expect(incidents[0].severity).toBe('critical');
  });

  it('throws ApiException kind=server when success=false', () => {
    const plain = { success: false, error: 'Bad key' };
    expect(() => parseIncidentsResponse(plain)).toThrow(/Bad key/);
  });

  it('returns empty array on unrecognised shape', () => {
    expect(parseIncidentsResponse({})).toEqual([]);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npm test -- incidents`
Expected: FAIL (module not found).

- [ ] **Step 3: Create `pwa/src/lib/api/incidents.ts`**

```ts
import { postForm } from './client';
import { ApiException, Incident, IncidentStatus, Severity } from './types';
import type { BhnmConfig } from '../config';

const SEVERITY_MAP: Record<string, Severity> = {
  critical: 'critical', '1': 'critical',
  major: 'major', '2': 'major',
  minor: 'minor', '3': 'minor',
  warning: 'warning', '4': 'warning',
  informational: 'informational', info: 'informational', '5': 'informational',
};

export function buildDisplayId(rawId: string): string {
  const bare = rawId.startsWith('#') ? rawId.slice(1) : rawId;
  const dash = bare.lastIndexOf('-');
  if (dash >= 0) return '#' + bare.slice(dash + 1);
  return '#' + bare;
}

function coerceId(raw: unknown, index: number): string {
  if (typeof raw === 'number') return String(raw);
  if (typeof raw === 'string' && raw.length > 0) return raw;
  return `unknown_${index}`;
}

function coerceSeverity(row: Record<string, unknown>): Severity {
  const candidates = [row.severity, row.alert_level, row.level, row.priority, row.type_name];
  for (const c of candidates) {
    if (typeof c === 'string') {
      const mapped = SEVERITY_MAP[c.toLowerCase()];
      if (mapped) return mapped;
    }
    if (typeof c === 'number') {
      const mapped = SEVERITY_MAP[String(c)];
      if (mapped) return mapped;
    }
  }
  // iOS fallback: active service-check failures default to critical.
  return 'critical';
}

function coerceStartTime(raw: unknown): Date {
  if (typeof raw === 'number') return new Date(raw * 1000);
  if (typeof raw === 'string') {
    const asNum = Number(raw);
    if (!Number.isNaN(asNum)) return new Date(asNum * 1000);
    const parsed = Date.parse(raw);
    if (!Number.isNaN(parsed)) return new Date(parsed);
  }
  return new Date();
}

function coerceString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function parseRow(row: Record<string, unknown>, index: number, forcedStatus?: IncidentStatus): Incident {
  const incidentId = coerceId(row.incident_id ?? row.id, index);
  const stateString = typeof row.incident_state === 'string' ? row.incident_state : 'OPEN';
  let status: IncidentStatus;
  if (forcedStatus) status = forcedStatus;
  else if (stateString === 'ACKNOWLEDGED') status = 'acknowledged';
  else status = 'active';

  return {
    incidentId,
    displayId: buildDisplayId(incidentId),
    deviceName: coerceString(row.name) ?? coerceString(row.device_name),
    deviceIp:
      coerceString(row.ip) ??
      coerceString(row.device_ip) ??
      coerceString(row.ip_address) ??
      coerceString(row.host_ip),
    summary: typeof row.title === 'string' ? row.title : (typeof row.summary === 'string' ? row.summary : 'Unknown'),
    severity: coerceSeverity(row),
    status,
    incidentState: stateString,
    startTime: coerceStartTime(row.start_time ?? row.startTime),
    acknowledgedBy: coerceString(row.acknowledged_by) ?? coerceString(row.acknowledgedBy),
  };
}

export function parseIncidentsResponse(raw: unknown): Incident[] {
  // BHNM may wrap the response in a single-element array. See project memory.
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];
  const obj = root as Record<string, unknown>;

  if (obj.success === false) {
    const msg =
      (typeof obj.error === 'string' && obj.error) ||
      (typeof obj.failure === 'string' && obj.failure) ||
      'Unknown BHNM error';
    throw new ApiException({ kind: 'server', status: 200, message: msg });
  }

  const result: Incident[] = [];

  if (Array.isArray(obj.active_incidents)) {
    (obj.active_incidents as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    if (Array.isArray(obj.closed_incidents)) {
      (obj.closed_incidents as unknown[]).forEach((row, i) => {
        if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i, 'resolved'));
      });
    }
    return result;
  }

  if (Array.isArray(obj.incidents)) {
    (obj.incidents as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    return result;
  }

  if (Array.isArray(obj.data)) {
    (obj.data as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    return result;
  }

  return [];
}

export async function getIncidents(config: BhnmConfig): Promise<Incident[]> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'getincidents',
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/incident_api.php', params);
  return parseIncidentsResponse(raw);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- incidents`
Expected: all parser tests pass.

- [ ] **Step 5: Run full test suite**

Run: `npm test`
Expected: all tests across `platform` and `incidents` pass.

- [ ] **Step 6: Commit**

```bash
git add pwa/src/lib/api/incidents.ts pwa/src/lib/api/incidents.test.ts
git commit -m "feat(pwa): incidents fetch + robust response parser"
```

---

## Task 10: useIncidents hook

**Files:**
- Create: `pwa/src/features/incidents/useIncidents.ts`

- [ ] **Step 1: Create `pwa/src/features/incidents/useIncidents.ts`**

```ts
import { useQuery } from '@tanstack/react-query';
import { getIncidents } from '../../lib/api/incidents';
import { useConfig } from '../../lib/config';
import mockData from '../../lib/mock/incidents.json';
import { parseIncidentsResponse } from '../../lib/api/incidents';

const REFETCH_INTERVAL_MS = 120_000;

function useMockMode(): boolean {
  if (typeof window === 'undefined') return false;
  return new URLSearchParams(window.location.search).get('mock') === '1';
}

export function useIncidents() {
  const config = useConfig();
  const mockMode = useMockMode();

  return useQuery({
    queryKey: ['incidents', mockMode ? 'mock' : config.apiKey, config.baseUrl],
    queryFn: async () => {
      if (mockMode) return parseIncidentsResponse(mockData);
      if (!config.isConfigured) {
        return parseIncidentsResponse(mockData); // show fixture when no key set
      }
      return getIncidents(config);
    },
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
```

- [ ] **Step 2: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/incidents/useIncidents.ts
git commit -m "feat(pwa): useIncidents hook with 120s refetch and mock fallback"
```

---

## Task 11: Row, badge, and empty state components

**Files:**
- Create: `pwa/src/features/incidents/SeverityBadge.tsx`
- Create: `pwa/src/features/incidents/IncidentRow.tsx`
- Create: `pwa/src/components/EmptyState.tsx`

- [ ] **Step 1: Create `pwa/src/features/incidents/SeverityBadge.tsx`**

```tsx
import type { Severity } from '../../lib/api/types';

const LABELS: Record<Severity, string> = {
  critical: 'CRIT',
  major: 'MAJ',
  minor: 'MIN',
  warning: 'WARN',
  informational: 'INFO',
};

const CLASSES: Record<Severity, string> = {
  critical: 'bg-severity-critical text-white',
  major: 'bg-severity-major text-white',
  minor: 'bg-severity-minor text-slate-900',
  warning: 'bg-severity-warning text-slate-900',
  informational: 'bg-severity-informational text-white',
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  return (
    <span
      className={`inline-block rounded px-2 py-0.5 text-xs font-semibold tracking-wide ${CLASSES[severity]}`}
      aria-label={`Severity: ${severity}`}
    >
      {LABELS[severity]}
    </span>
  );
}
```

- [ ] **Step 2: Create `pwa/src/features/incidents/IncidentRow.tsx`**

```tsx
import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { SeverityBadge } from './SeverityBadge';

function relativeTime(d: Date): string {
  const diffMs = Date.now() - d.getTime();
  const min = Math.round(diffMs / 60_000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const days = Math.round(hr / 24);
  return `${days}d ago`;
}

export function IncidentRow({ incident }: { incident: Incident }) {
  const ackPrefix = incident.status === 'acknowledged' ? '✓ ' : '';
  return (
    <Link
      to={`/incident/${encodeURIComponent(incident.incidentId)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      <div className="flex items-center gap-3">
        <SeverityBadge severity={incident.severity} />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium truncate">
            {ackPrefix}
            {incident.deviceName ?? incident.deviceIp ?? 'Unknown device'}
          </div>
          <div className="text-xs text-slate-400 truncate">{incident.summary}</div>
        </div>
        <div className="text-xs text-slate-500 shrink-0">{relativeTime(incident.startTime)}</div>
      </div>
    </Link>
  );
}
```

- [ ] **Step 3: Create `pwa/src/components/EmptyState.tsx`**

```tsx
import type { ReactNode } from 'react';

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center text-center p-12 text-slate-400">
      <div className="text-lg font-semibold text-slate-200">{title}</div>
      {description && <div className="mt-2 text-sm max-w-sm">{description}</div>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}
```

- [ ] **Step 4: Verify typecheck**

Run: `npm run typecheck`
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/incidents/SeverityBadge.tsx pwa/src/features/incidents/IncidentRow.tsx pwa/src/components/EmptyState.tsx
git commit -m "feat(pwa): severity badge, incident row, empty state"
```

---

## Task 12: Incident list screen + pull-to-refresh + smoke test

**Files:**
- Create: `pwa/src/components/PullToRefresh.tsx`
- Create: `pwa/src/features/incidents/IncidentListScreen.tsx`
- Create: `pwa/src/features/incidents/__tests__/IncidentListScreen.test.tsx`

- [ ] **Step 1: Create `pwa/src/components/PullToRefresh.tsx`**

Minimal, hand-rolled touch gesture. Only engages at `scrollTop === 0`.

```tsx
import { useRef, useState, type ReactNode, type TouchEvent } from 'react';

const THRESHOLD = 70;

export function PullToRefresh({ onRefresh, children }: { onRefresh: () => Promise<unknown> | void; children: ReactNode }) {
  const startY = useRef<number | null>(null);
  const [pull, setPull] = useState(0);
  const [refreshing, setRefreshing] = useState(false);

  const onTouchStart = (e: TouchEvent<HTMLDivElement>) => {
    if (window.scrollY > 0) return;
    startY.current = e.touches[0].clientY;
  };

  const onTouchMove = (e: TouchEvent<HTMLDivElement>) => {
    if (startY.current == null) return;
    const dy = e.touches[0].clientY - startY.current;
    if (dy > 0) setPull(Math.min(dy, THRESHOLD * 1.5));
  };

  const onTouchEnd = async () => {
    if (pull >= THRESHOLD && !refreshing) {
      setRefreshing(true);
      try {
        await onRefresh();
      } finally {
        setRefreshing(false);
      }
    }
    startY.current = null;
    setPull(0);
  };

  return (
    <div onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd}>
      <div
        aria-hidden
        style={{ height: pull }}
        className="flex items-center justify-center text-xs text-slate-500 transition-[height]"
      >
        {refreshing ? 'Refreshing…' : pull >= THRESHOLD ? 'Release to refresh' : pull > 0 ? 'Pull to refresh' : ''}
      </div>
      {children}
    </div>
  );
}
```

- [ ] **Step 2: Create `pwa/src/features/incidents/IncidentListScreen.tsx`**

```tsx
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { IncidentRow } from './IncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { useConfig } from '../../lib/config';

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
        <button
          type="button"
          onClick={onRefresh}
          className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
          aria-label="Refresh"
        >
          Refresh
        </button>
      </header>

      {isLoading && (
        <EmptyState title="Loading…" description="Fetching incidents from BHNM." />
      )}

      {isError && (
        <EmptyState
          title="Could not reach BHNM"
          description={(error as Error).message}
          action={
            <button
              type="button"
              onClick={onRefresh}
              className="px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-sm"
            >
              Retry
            </button>
          }
        />
      )}

      {!isLoading && !isError && data && data.length === 0 && (
        <EmptyState title="No open incidents" description="All clear." />
      )}

      {!isLoading && !isError && !config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30">
          Not configured — showing mock data. Set <code>VITE_BHNM_API_KEY</code> in <code>.env.local</code>.
        </div>
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

- [ ] **Step 3: Write the failing test `pwa/src/features/incidents/__tests__/IncidentListScreen.test.tsx`**

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { IncidentListScreen } from '../IncidentListScreen';

vi.mock('../useIncidents', () => ({
  useIncidents: () => ({
    data: [
      {
        incidentId: '58431',
        displayId: '#58431',
        deviceName: 'core-switch-01',
        deviceIp: '10.0.0.1',
        summary: 'CPU utilization high',
        severity: 'critical',
        status: 'active',
        incidentState: 'OPEN',
        startTime: new Date(Date.now() - 5 * 60_000),
        acknowledgedBy: null,
      },
      {
        incidentId: '58432',
        displayId: '#58432',
        deviceName: 'edge-router-02',
        deviceIp: '10.0.0.2',
        summary: 'Interface down',
        severity: 'major',
        status: 'acknowledged',
        incidentState: 'ACKNOWLEDGED',
        startTime: new Date(Date.now() - 60 * 60_000),
        acknowledgedBy: 'oncall@example.com',
      },
    ],
    isLoading: false,
    isError: false,
    error: null,
    refetch: vi.fn(),
  }),
}));

function renderScreen() {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <IncidentListScreen />
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('IncidentListScreen', () => {
  it('renders a row for each incident', async () => {
    renderScreen();
    await waitFor(() => {
      expect(screen.getByText(/core-switch-01/)).toBeInTheDocument();
      expect(screen.getByText(/edge-router-02/)).toBeInTheDocument();
    });
    const list = screen.getByTestId('incident-list');
    expect(list.querySelectorAll('li')).toHaveLength(2);
  });

  it('renders severity badges', () => {
    renderScreen();
    expect(screen.getByLabelText('Severity: critical')).toBeInTheDocument();
    expect(screen.getByLabelText('Severity: major')).toBeInTheDocument();
  });
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test`
Expected: all prior tests plus 2 new `IncidentListScreen` tests pass.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/components/PullToRefresh.tsx pwa/src/features/incidents/IncidentListScreen.tsx pwa/src/features/incidents/__tests__/IncidentListScreen.test.tsx
git commit -m "feat(pwa): incident list screen with pull-to-refresh and smoke test"
```

---

## Task 13: Detail stub + App routing + banner wiring

**Files:**
- Create: `pwa/src/features/incidents/IncidentDetailStub.tsx`
- Modify: `pwa/src/App.tsx`

- [ ] **Step 1: Create `pwa/src/features/incidents/IncidentDetailStub.tsx`**

```tsx
import { Link, useParams } from 'react-router-dom';

export function IncidentDetailStub() {
  const { id } = useParams();
  return (
    <div className="p-6">
      <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">
        ← Back
      </Link>
      <h1 className="mt-4 text-xl font-semibold">Incident {id}</h1>
      <p className="mt-2 text-sm text-slate-400">Incident detail coming in v0.1.1.</p>
    </div>
  );
}
```

- [ ] **Step 2: Replace `pwa/src/App.tsx`**

```tsx
import { Routes, Route } from 'react-router-dom';
import { IOSRedirectBanner } from './components/IOSRedirectBanner';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailStub } from './features/incidents/IncidentDetailStub';

export default function App() {
  return (
    <div className="min-h-full">
      <IOSRedirectBanner />
      <Routes>
        <Route path="/" element={<IncidentListScreen />} />
        <Route path="/incident/:id" element={<IncidentDetailStub />} />
      </Routes>
    </div>
  );
}
```

- [ ] **Step 3: Run full test suite**

Run: `npm test`
Expected: all tests pass.

- [ ] **Step 4: Run typecheck and build**

Run: `npm run typecheck && npm run build`
Expected: both exit 0. `dist/` contains `sw.js`, `manifest.webmanifest`, `index.html`, and a JS bundle.

- [ ] **Step 5: Smoke-test dev server manually (developer action)**

Run: `npm run dev`
Expected: Vite reports a local URL (typically `http://localhost:5173`). Visit it in a browser — you should see the "Incidents" header and three rows from the mock fixture (because `.env.local` has no key yet).

Kill the dev server with `Ctrl+C` when done.

- [ ] **Step 6: Commit**

```bash
git add pwa/src/features/incidents/IncidentDetailStub.tsx pwa/src/App.tsx
git commit -m "feat(pwa): wire incident list, detail stub, and iOS banner routes"
```

---

## Task 14: Docs — README and feature-spec update

**Files:**
- Create: `pwa/README.md`
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Create `pwa/README.md`**

```markdown
# BeNeM PWA

React/TypeScript Progressive Web App for BHNM incident monitoring.
Targets Android via Web Push (future). iOS users are directed to the
native app via an in-app banner — Web Push is unreliable on iOS.

Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules
and `../shared/feature-spec.md` for the canonical feature list.

## v0.1.0 scope

- Incident List screen (read-only, 120s auto-refresh, pull-to-refresh, tap-to-detail stub)
- iOS redirect banner
- PWA manifest + service worker (offline scaffolding only — no data caching)

Deferred to later versions:
- Swipe ACK / UnACK (v0.1.1)
- Incident detail screen (v0.1.1)
- Settings screen (v0.1.1)
- Web Push subscription for Android (v0.2.0)

## Prerequisites

- Node 20+
- `npm`
- A reachable BeNeM middleware instance with an entry for your BHNM server in `servers.json`

## Setup

```bash
cd pwa
cp .env.example .env.local
# Edit .env.local with your middleware URL and BHNM API key
npm install
npm run dev
```

Without a real `VITE_BHNM_API_KEY`, the list shows mock fixture data so
you can still work on the UI. Append `?mock=1` to the URL to force mock
data even when a key is set.

## Commands

| Command | Purpose |
|---|---|
| `npm run dev` | Vite dev server with hot reload and BHNM proxy |
| `npm run build` | TypeScript typecheck + production build |
| `npm run preview` | Serve `dist/` locally |
| `npm test` | Run Vitest once |
| `npm run test:watch` | Vitest in watch mode |
| `npm run typecheck` | TypeScript check only |

## Architecture

- **Stack:** Vite 5 + React 18 + TypeScript strict + Tailwind v3 + vite-plugin-pwa + TanStack Query v5 + React Router v6.
- **Dev proxy:** `/bhnm/*` is forwarded to `VITE_MIDDLEWARE_BASE` (default `https://bhnm-apns.hurrikap.org`) with `changeOrigin: true`. This avoids CORS during development.
- **Production deployment / CORS:** not yet designed — see v0.1.1.
- **BHNM contract:** `POST /api/incident_api.php` with `pwd`/`method=getincidents` (form-urlencoded). The parser handles array-wrapped responses, `active_incidents`/`closed_incidents`, and multiple severity key names — mirroring the iOS client.

## Middleware coupling

The BHNM API key you set in `VITE_BHNM_API_KEY` must exist in the
deployed middleware's `servers.json`. The middleware proxy looks up the
target BHNM server by that key.
```

- [ ] **Step 2: Update `shared/feature-spec.md`** — change the PWA-specific line for Incident List

Find in `shared/feature-spec.md`:

```markdown
### Feature: Incident List
**Status:** shipped-ios
```

Change to:

```markdown
### Feature: Incident List
**Status:** shipped-ios, in-progress-pwa
```

And find:

```markdown
#### PWA-specific
- Not yet implemented
```

Change to:

```markdown
#### PWA-specific
- v0.1.0: read-only list, 120s auto-refresh, pull-to-refresh, tap navigates to detail stub
- v0.1.1 (planned): swipe ACK / UnACK, real incident detail screen, Settings screen
- No native-style swipe gesture library — touch-based pull-to-refresh is hand-rolled in `components/PullToRefresh.tsx`
```

- [ ] **Step 3: Commit**

```bash
git add pwa/README.md shared/feature-spec.md
git commit -m "docs(pwa): add README and update feature spec for v0.1.0"
```

---

## Task 15: Final verification

No files change. This is the stop gate.

- [ ] **Step 1: From `pwa/` run the full verification matrix**

```bash
npm run typecheck
npm test
npm run build
```

Expected output for each:
- `typecheck` → exits 0, no output
- `test` → all suites pass (platform, incidents parser, IncidentListScreen smoke)
- `build` → `dist/` produced with `sw.js`, `manifest.webmanifest`, `index.html`, JS/CSS bundles

- [ ] **Step 2: From repo root confirm clean git state**

```bash
git status
```
Expected: working tree clean. Every change from tasks 1–14 is already committed.

- [ ] **Step 3: Stop and hand off for user review**

Do **not** start implementing swipe gestures, incident detail, Web Push, or a Settings screen. Report:
- Tasks completed
- Test/build results from Step 1
- Commits created (`git log --oneline pwa/` since the first PWA commit)

Wait for the user's review before proceeding to any v0.1.1 work.
