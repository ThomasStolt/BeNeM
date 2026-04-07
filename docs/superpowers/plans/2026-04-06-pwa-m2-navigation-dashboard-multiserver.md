# M2: Navigation + Dashboard + Multi-Server (v0.3.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bottom tab bar navigation, a dashboard with H/S/T/A aggregate status cards and incident ticker, and multi-server management to the PWA — bringing it to parity with the iOS app's navigation and dashboard experience.

**Architecture:** Multi-server config replaces the single-key localStorage layout with a `benem_servers` JSON array, migrating existing config on first load. The config hook (`useConfig`) is rewritten to read from the active server entry. A persistent bottom tab bar (Dashboard / Incidents / Devices) provides iOS-style navigation via React Router v6 layout routes. The Dashboard fetches aggregate H/S/T/A counts from the BHNM Legacy API's `tactical-overview/data` endpoint (summing all category rows), displays them as color-coded status cards, and includes a horizontal incident ticker. Settings is redesigned as a server-management screen with add/edit/delete/switch capabilities.

**Tech Stack:** React 18 + TypeScript + React Router v6 + React Query v5 + Tailwind CSS 3 + Vitest + Testing Library

**Spec:** `docs/superpowers/specs/2026-04-06-pwa-feature-parity-design.md` § M2

---

## File Structure

### New Files

| File | Responsibility |
|------|----------------|
| `pwa/src/lib/serverStorage.ts` | `ServerConfig` type, localStorage CRUD, legacy migration |
| `pwa/src/lib/__tests__/serverStorage.test.ts` | Tests for server storage + migration |
| `pwa/src/lib/api/tactical-overview.ts` | Tactical overview API call + response parser |
| `pwa/src/lib/api/tactical-overview.test.ts` | Tests for tactical overview parsing |
| `pwa/src/components/TabBar.tsx` | Bottom tab bar navigation component |
| `pwa/src/components/__tests__/TabBar.test.tsx` | Tab bar tests |
| `pwa/src/components/AppLayout.tsx` | Layout shell: header + `<Outlet>` + tab bar |
| `pwa/src/components/RefreshCountdown.tsx` | Visual countdown to next auto-refresh |
| `pwa/src/components/__tests__/RefreshCountdown.test.tsx` | Countdown tests |
| `pwa/src/features/dashboard/DashboardScreen.tsx` | Dashboard screen: cards + ticker + drill-downs |
| `pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx` | Dashboard screen tests |
| `pwa/src/features/dashboard/StatusCard.tsx` | Single H/S/T/A status card |
| `pwa/src/features/dashboard/IncidentTicker.tsx` | Horizontal auto-scrolling incident strip |
| `pwa/src/features/dashboard/useTacticalSummary.ts` | React Query hook for tactical overview |
| `pwa/src/features/settings/ServerListSection.tsx` | Server list with switch/delete |
| `pwa/src/features/settings/ServerForm.tsx` | Add/edit server form |
| `pwa/src/features/settings/__tests__/ServerForm.test.tsx` | Server form tests |

### Modified Files

| File | Changes |
|------|---------|
| `pwa/src/lib/config.ts` | Read from active server in `benem_servers` instead of individual keys |
| `pwa/src/lib/config.test.ts` | Update tests for new storage backend |
| `pwa/src/App.tsx` | Layout routes with `AppLayout`, move incidents to `/incidents` |
| `pwa/src/main.tsx` | Call legacy config migration on startup |
| `pwa/src/features/incidents/IncidentListScreen.tsx` | Remove header (moved to AppLayout), add countdown |
| `pwa/src/features/incidents/useIncidents.ts` | Add `serverId` to query key |
| `pwa/src/features/settings/SettingsScreen.tsx` | Redesign with server list + per-server form |
| `pwa/src/features/settings/settingsStorage.ts` | Keep for backward compat during migration, mark deprecated |
| `pwa/tailwind.config.js` | Add ticker animation keyframes, status card colors |
| `pwa/package.json` | Bump to 0.3.0 |
| `shared/feature-spec.md` | Mark M2 features as implemented |

---

## Task 1: Multi-Server Storage — Types and CRUD

**Files:**
- Create: `pwa/src/lib/serverStorage.ts`
- Create: `pwa/src/lib/__tests__/serverStorage.test.ts`

- [ ] **Step 1: Write failing tests for ServerConfig CRUD**

```typescript
// pwa/src/lib/__tests__/serverStorage.test.ts
import { describe, it, expect, beforeEach } from 'vitest';
import {
  type ServerConfig,
  loadServers,
  saveServers,
  addServer,
  updateServer,
  removeServer,
  getActiveServer,
  setActiveServer,
  createServerConfig,
} from '../serverStorage';

beforeEach(() => {
  localStorage.clear();
});

describe('serverStorage', () => {
  describe('loadServers / saveServers', () => {
    it('returns empty array when nothing stored', () => {
      expect(loadServers()).toEqual([]);
    });

    it('round-trips a server list', () => {
      const servers: ServerConfig[] = [
        createServerConfig({ name: 'Test', baseUrl: '/bhnm', apiKey: 'key1' }),
      ];
      saveServers(servers);
      const loaded = loadServers();
      expect(loaded).toHaveLength(1);
      expect(loaded[0].name).toBe('Test');
      expect(loaded[0].apiKey).toBe('key1');
    });
  });

  describe('addServer', () => {
    it('adds a server and sets it active if first', () => {
      const server = addServer({ name: 'First', baseUrl: '/bhnm', apiKey: 'k1' });
      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].isActive).toBe(true);
      expect(servers[0].id).toBe(server.id);
    });

    it('adds a second server as inactive', () => {
      addServer({ name: 'First', baseUrl: '/bhnm', apiKey: 'k1' });
      addServer({ name: 'Second', baseUrl: '/bhnm2', apiKey: 'k2' });
      const servers = loadServers();
      expect(servers).toHaveLength(2);
      expect(servers[0].isActive).toBe(true);
      expect(servers[1].isActive).toBe(false);
    });
  });

  describe('updateServer', () => {
    it('updates fields on existing server', () => {
      const server = addServer({ name: 'Old', baseUrl: '/bhnm', apiKey: 'k1' });
      updateServer(server.id, { name: 'New', apiKey: 'k2' });
      const loaded = loadServers();
      expect(loaded[0].name).toBe('New');
      expect(loaded[0].apiKey).toBe('k2');
      expect(loaded[0].baseUrl).toBe('/bhnm'); // unchanged
    });
  });

  describe('removeServer', () => {
    it('removes by id', () => {
      const s1 = addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      removeServer(s1.id);
      const servers = loadServers();
      expect(servers).toHaveLength(1);
      expect(servers[0].name).toBe('B');
    });

    it('activates next server if active one is removed', () => {
      const s1 = addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      removeServer(s1.id);
      const servers = loadServers();
      expect(servers[0].isActive).toBe(true);
    });
  });

  describe('getActiveServer', () => {
    it('returns null when no servers', () => {
      expect(getActiveServer()).toBeNull();
    });

    it('returns the active server', () => {
      addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      const s2 = addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      setActiveServer(s2.id);
      expect(getActiveServer()!.name).toBe('B');
    });
  });

  describe('setActiveServer', () => {
    it('deactivates other servers', () => {
      addServer({ name: 'A', baseUrl: '/a', apiKey: 'ka' });
      const s2 = addServer({ name: 'B', baseUrl: '/b', apiKey: 'kb' });
      setActiveServer(s2.id);
      const servers = loadServers();
      expect(servers[0].isActive).toBe(false);
      expect(servers[1].isActive).toBe(true);
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement serverStorage.ts**

```typescript
// pwa/src/lib/serverStorage.ts
const STORAGE_KEY = 'benem_servers';

export interface ServerConfig {
  id: string;
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushEnabled: boolean;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
  isActive: boolean;
}

export interface NewServerInput {
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushEnabled?: boolean;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
}

export function createServerConfig(input: NewServerInput): ServerConfig {
  return {
    id: crypto.randomUUID(),
    name: input.name,
    baseUrl: input.baseUrl,
    apiKey: input.apiKey,
    pin: input.pin,
    pushEnabled: input.pushEnabled ?? false,
    pushMiddlewareUrl: input.pushMiddlewareUrl,
    pushWebhookSecret: input.pushWebhookSecret,
    isActive: false,
  };
}

export function loadServers(): ServerConfig[] {
  if (typeof window === 'undefined') return [];
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveServers(servers: ServerConfig[]): void {
  if (typeof window === 'undefined') return;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(servers));
}

export function addServer(input: NewServerInput): ServerConfig {
  const servers = loadServers();
  const server = createServerConfig(input);
  // First server is automatically active
  server.isActive = servers.length === 0;
  servers.push(server);
  saveServers(servers);
  return server;
}

export function updateServer(
  id: string,
  updates: Partial<Omit<ServerConfig, 'id'>>,
): void {
  const servers = loadServers();
  const index = servers.findIndex((s) => s.id === id);
  if (index === -1) return;
  servers[index] = { ...servers[index], ...updates, id };
  saveServers(servers);
}

export function removeServer(id: string): void {
  let servers = loadServers();
  const wasActive = servers.find((s) => s.id === id)?.isActive ?? false;
  servers = servers.filter((s) => s.id !== id);
  // If the removed server was active, activate the first remaining
  if (wasActive && servers.length > 0) {
    servers[0].isActive = true;
  }
  saveServers(servers);
}

export function getActiveServer(): ServerConfig | null {
  const servers = loadServers();
  return servers.find((s) => s.isActive) ?? null;
}

export function setActiveServer(id: string): void {
  const servers = loadServers();
  for (const s of servers) {
    s.isActive = s.id === id;
  }
  saveServers(servers);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: all 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/serverStorage.ts pwa/src/lib/__tests__/serverStorage.test.ts
git commit -m "feat(pwa): add multi-server storage with CRUD operations"
```

---

## Task 2: Legacy Config Migration

**Files:**
- Modify: `pwa/src/lib/serverStorage.ts`
- Modify: `pwa/src/lib/__tests__/serverStorage.test.ts`
- Modify: `pwa/src/main.tsx`

- [ ] **Step 1: Write failing migration tests**

Append to `pwa/src/lib/__tests__/serverStorage.test.ts`:

```typescript
import { migrateFromLegacyConfig } from '../serverStorage';

describe('migrateFromLegacyConfig', () => {
  it('creates server from legacy keys', () => {
    localStorage.setItem('benem:bhnm-api-key', 'legacy-key');
    localStorage.setItem('benem:bhnm-pin', 'legacy-pin');
    localStorage.setItem('benem:webhook-secret', 'legacy-secret');
    localStorage.setItem('benem:push-enabled', 'true');

    migrateFromLegacyConfig();

    const servers = loadServers();
    expect(servers).toHaveLength(1);
    expect(servers[0].apiKey).toBe('legacy-key');
    expect(servers[0].pin).toBe('legacy-pin');
    expect(servers[0].pushWebhookSecret).toBe('legacy-secret');
    expect(servers[0].pushEnabled).toBe(true);
    expect(servers[0].baseUrl).toBe('/bhnm');
    expect(servers[0].isActive).toBe(true);
    expect(servers[0].name).toBe('BHNM Server');
  });

  it('skips migration if servers already exist', () => {
    addServer({ name: 'Existing', baseUrl: '/bhnm', apiKey: 'k1' });
    localStorage.setItem('benem:bhnm-api-key', 'legacy-key');

    migrateFromLegacyConfig();

    const servers = loadServers();
    expect(servers).toHaveLength(1);
    expect(servers[0].name).toBe('Existing');
  });

  it('skips migration if no legacy keys', () => {
    migrateFromLegacyConfig();
    expect(loadServers()).toEqual([]);
  });

  it('removes legacy keys after migration', () => {
    localStorage.setItem('benem:bhnm-api-key', 'legacy-key');
    migrateFromLegacyConfig();
    expect(localStorage.getItem('benem:bhnm-api-key')).toBeNull();
    expect(localStorage.getItem('benem:bhnm-pin')).toBeNull();
    expect(localStorage.getItem('benem:webhook-secret')).toBeNull();
    expect(localStorage.getItem('benem:push-enabled')).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: FAIL — `migrateFromLegacyConfig` not found

- [ ] **Step 3: Implement migrateFromLegacyConfig**

Add to `pwa/src/lib/serverStorage.ts`:

```typescript
const LEGACY_API_KEY = 'benem:bhnm-api-key';
const LEGACY_PIN = 'benem:bhnm-pin';
const LEGACY_WEBHOOK_SECRET = 'benem:webhook-secret';
const LEGACY_PUSH_ENABLED = 'benem:push-enabled';

export function migrateFromLegacyConfig(): void {
  if (typeof window === 'undefined') return;

  // Skip if servers already exist
  if (loadServers().length > 0) return;

  const apiKey = localStorage.getItem(LEGACY_API_KEY);
  if (!apiKey) return;

  const pin = localStorage.getItem(LEGACY_PIN) || undefined;
  const webhookSecret = localStorage.getItem(LEGACY_WEBHOOK_SECRET) || undefined;
  const pushEnabled = localStorage.getItem(LEGACY_PUSH_ENABLED) === 'true';

  const server = createServerConfig({
    name: 'BHNM Server',
    baseUrl: '/bhnm',
    apiKey,
    pin,
    pushEnabled,
    pushWebhookSecret: webhookSecret,
  });
  server.isActive = true;
  saveServers([server]);

  // Clean up legacy keys
  localStorage.removeItem(LEGACY_API_KEY);
  localStorage.removeItem(LEGACY_PIN);
  localStorage.removeItem(LEGACY_WEBHOOK_SECRET);
  localStorage.removeItem(LEGACY_PUSH_ENABLED);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: all tests PASS

- [ ] **Step 5: Wire migration into main.tsx**

In `pwa/src/main.tsx`, add the migration call before `ReactDOM.createRoot`:

```typescript
import { migrateFromLegacyConfig } from './lib/serverStorage';

// Migrate single-server config to multi-server format (one-time, idempotent)
migrateFromLegacyConfig();
```

- [ ] **Step 6: Commit**

```bash
git add pwa/src/lib/serverStorage.ts pwa/src/lib/__tests__/serverStorage.test.ts pwa/src/main.tsx
git commit -m "feat(pwa): add legacy config migration to multi-server storage"
```

---

## Task 3: Config Hook Migration

**Files:**
- Modify: `pwa/src/lib/config.ts`
- Modify: `pwa/src/lib/config.test.ts`

- [ ] **Step 1: Update config tests**

Replace `pwa/src/lib/config.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { getSnapshotForTest } from './config';
import { addServer, setActiveServer, saveServers } from './serverStorage';
import type { ServerConfig } from './serverStorage';

beforeEach(() => {
  localStorage.clear();
});

describe('config snapshot', () => {
  it('returns unconfigured when no servers exist', () => {
    const config = getSnapshotForTest();
    expect(config.isConfigured).toBe(false);
    expect(config.apiKey).toBe('');
  });

  it('reads from active server', () => {
    addServer({ name: 'Test', baseUrl: '/bhnm', apiKey: 'test-key', pin: 'pin123' });
    const config = getSnapshotForTest();
    expect(config.isConfigured).toBe(true);
    expect(config.apiKey).toBe('test-key');
    expect(config.pin).toBe('pin123');
    expect(config.baseUrl).toBe('/bhnm');
    expect(config.serverId).toBeTruthy();
    expect(config.serverName).toBe('Test');
  });

  it('reads from second server when it is active', () => {
    addServer({ name: 'First', baseUrl: '/a', apiKey: 'k1' });
    const s2 = addServer({ name: 'Second', baseUrl: '/b', apiKey: 'k2' });
    setActiveServer(s2.id);
    const config = getSnapshotForTest();
    expect(config.apiKey).toBe('k2');
    expect(config.serverName).toBe('Second');
  });

  it('includes webhook fields', () => {
    addServer({
      name: 'Push',
      baseUrl: '/bhnm',
      apiKey: 'k',
      pushWebhookSecret: 'secret',
      pushMiddlewareUrl: '/middleware',
    });
    const config = getSnapshotForTest();
    expect(config.webhookSecret).toBe('secret');
    expect(config.pushMiddlewareUrl).toBe('/middleware');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/config.test.ts`
Expected: FAIL — `serverId` / `serverName` not in `BhnmConfig`

- [ ] **Step 3: Rewrite config.ts to read from serverStorage**

```typescript
// pwa/src/lib/config.ts
import { useSyncExternalStore } from 'react';
import { getActiveServer } from './serverStorage';

export interface BhnmConfig {
  serverId: string;
  serverName: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  webhookSecret?: string;
  pushMiddlewareUrl?: string;
  isConfigured: boolean;
}

const listeners = new Set<() => void>();
let cachedSnapshot: BhnmConfig | null = null;

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

/**
 * Call after mutating server config (add/edit/delete/switch) to force
 * every `useConfig()` consumer to re-read its snapshot.
 */
export function notifyConfigChanged(): void {
  cachedSnapshot = null;
  listeners.forEach((cb) => cb());
}

function buildSnapshot(): BhnmConfig {
  const server = getActiveServer();
  if (!server) {
    // Fall back to env vars for unconfigured state
    const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
    return {
      serverId: '',
      serverName: '',
      baseUrl: '/bhnm',
      apiKey: envKey,
      isConfigured: envKey.length > 0,
    };
  }
  return {
    serverId: server.id,
    serverName: server.name,
    baseUrl: server.baseUrl,
    apiKey: server.apiKey,
    pin: server.pin,
    webhookSecret: server.pushWebhookSecret,
    pushMiddlewareUrl: server.pushMiddlewareUrl,
    isConfigured: server.apiKey.length > 0,
  };
}

function getSnapshot(): BhnmConfig {
  if (cachedSnapshot === null) {
    cachedSnapshot = buildSnapshot();
  }
  return cachedSnapshot;
}

/** Exported for tests only. */
export function getSnapshotForTest(): BhnmConfig {
  cachedSnapshot = null;
  return buildSnapshot();
}

function getServerSnapshot(): BhnmConfig {
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  return {
    serverId: '',
    serverName: '',
    baseUrl: '/bhnm',
    apiKey: envKey,
    isConfigured: envKey.length > 0,
  };
}

export function useConfig(): BhnmConfig {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/config.test.ts`
Expected: all tests PASS

- [ ] **Step 5: Update useIncidents query key**

In `pwa/src/features/incidents/useIncidents.ts`, change the query key to use `serverId`:

```typescript
// Replace the existing queryKey line:
queryKey: ['incidents', mockMode ? 'mock' : config.serverId, config.baseUrl],
```

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `cd pwa && npx vitest run`
Expected: Some tests may need `serverId`/`serverName` added to mocked config objects. Fix any failing tests by adding the new fields to test fixtures.

- [ ] **Step 7: Commit**

```bash
git add pwa/src/lib/config.ts pwa/src/lib/config.test.ts pwa/src/features/incidents/useIncidents.ts
git commit -m "feat(pwa): migrate config hook to multi-server storage backend"
```

---

## Task 4: Tactical Overview API Module

**Files:**
- Create: `pwa/src/lib/api/tactical-overview.ts`
- Create: `pwa/src/lib/api/tactical-overview.test.ts`

- [ ] **Step 1: Write failing tests for response parsing**

```typescript
// pwa/src/lib/api/tactical-overview.test.ts
import { describe, it, expect } from 'vitest';
import { parseTacticalResponse, sumTacticalGroups, type TacticalGroup } from './tactical-overview';

const MOCK_RESPONSE = {
  'Servers': {
    Status: {
      host_ok_count: 10, host_ack_count: 1, host_warn_count: 2, host_un_count: 0, host_crit_count: 3,
      service_ok_count: 20, service_ack_count: 0, service_warn_count: 1, service_un_count: 0, service_crit_count: 1,
      threshold_ok_count: 5, threshold_ack_count: 0, threshold_warn_count: 0, threshold_un_count: 0, threshold_crit_count: 0,
      anom_threshold_ok_count: 2, anom_threshold_ack_count: 0, anom_threshold_warn_count: 1, anom_threshold_un_count: 0, anom_threshold_crit_count: 0,
    },
  },
  'Network': {
    Status: {
      host_ok_count: 5, host_ack_count: 0, host_warn_count: 0, host_un_count: 1, host_crit_count: 0,
      service_ok_count: 8, service_ack_count: 2, service_warn_count: 0, service_un_count: 0, service_crit_count: 0,
      threshold_ok_count: 3, threshold_ack_count: 0, threshold_warn_count: 1, threshold_un_count: 0, threshold_crit_count: 0,
      anom_threshold_ok_count: 0, anom_threshold_ack_count: 0, anom_threshold_warn_count: 0, anom_threshold_un_count: 0, anom_threshold_crit_count: 0,
    },
  },
};

describe('parseTacticalResponse', () => {
  it('parses groups from BHNM response', () => {
    const groups = parseTacticalResponse(MOCK_RESPONSE);
    expect(groups).toHaveLength(2);
    expect(groups[0].name).toBe('Servers');
    expect(groups[0].hosts).toEqual({ ok: 10, ack: 1, warn: 2, un: 0, crit: 3 });
    expect(groups[0].services).toEqual({ ok: 20, ack: 0, warn: 1, un: 0, crit: 1 });
    expect(groups[1].name).toBe('Network');
    expect(groups[1].hosts.ok).toBe(5);
  });

  it('handles array-wrapped response', () => {
    const groups = parseTacticalResponse([MOCK_RESPONSE]);
    expect(groups).toHaveLength(2);
  });

  it('returns empty array for invalid input', () => {
    expect(parseTacticalResponse(null)).toEqual([]);
    expect(parseTacticalResponse({})).toEqual([]);
  });
});

describe('sumTacticalGroups', () => {
  it('sums counts across all groups', () => {
    const groups = parseTacticalResponse(MOCK_RESPONSE);
    const totals = sumTacticalGroups(groups);
    expect(totals.hosts).toEqual({ ok: 15, ack: 1, warn: 2, un: 1, crit: 3 });
    expect(totals.services).toEqual({ ok: 28, ack: 2, warn: 1, un: 0, crit: 1 });
    expect(totals.thresholds).toEqual({ ok: 8, ack: 0, warn: 1, un: 0, crit: 0 });
    expect(totals.anomalies).toEqual({ ok: 2, ack: 0, warn: 1, un: 0, crit: 0 });
  });

  it('returns zeros for empty groups', () => {
    const totals = sumTacticalGroups([]);
    expect(totals.hosts).toEqual({ ok: 0, ack: 0, warn: 0, un: 0, crit: 0 });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/api/tactical-overview.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement tactical-overview.ts**

```typescript
// pwa/src/lib/api/tactical-overview.ts
import { postForm } from './client';
import type { BhnmConfig } from '../config';

export interface StatusCounts {
  ok: number;
  ack: number;
  warn: number;
  un: number;
  crit: number;
}

export interface TacticalGroup {
  name: string;
  hosts: StatusCounts;
  services: StatusCounts;
  thresholds: StatusCounts;
  anomalies: StatusCounts;
}

export interface TacticalSummary {
  hosts: StatusCounts;
  services: StatusCounts;
  thresholds: StatusCounts;
  anomalies: StatusCounts;
}

function zeroCounts(): StatusCounts {
  return { ok: 0, ack: 0, warn: 0, un: 0, crit: 0 };
}

function extractCounts(
  status: Record<string, unknown>,
  prefix: string,
): StatusCounts {
  const num = (key: string) => {
    const v = status[key];
    return typeof v === 'number' ? v : 0;
  };
  return {
    ok: num(`${prefix}ok_count`),
    ack: num(`${prefix}ack_count`),
    warn: num(`${prefix}warn_count`),
    un: num(`${prefix}un_count`),
    crit: num(`${prefix}crit_count`),
  };
}

export function parseTacticalResponse(raw: unknown): TacticalGroup[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;
  const groups: TacticalGroup[] = [];

  for (const [name, value] of Object.entries(obj)) {
    if (!value || typeof value !== 'object') continue;
    const entry = value as Record<string, unknown>;
    const status = entry.Status;
    if (!status || typeof status !== 'object') continue;
    const s = status as Record<string, unknown>;

    groups.push({
      name,
      hosts: extractCounts(s, 'host_'),
      services: extractCounts(s, 'service_'),
      thresholds: extractCounts(s, 'threshold_'),
      anomalies: extractCounts(s, 'anom_threshold_'),
    });
  }

  return groups;
}

function addCounts(a: StatusCounts, b: StatusCounts): StatusCounts {
  return {
    ok: a.ok + b.ok,
    ack: a.ack + b.ack,
    warn: a.warn + b.warn,
    un: a.un + b.un,
    crit: a.crit + b.crit,
  };
}

export function sumTacticalGroups(groups: TacticalGroup[]): TacticalSummary {
  let hosts = zeroCounts();
  let services = zeroCounts();
  let thresholds = zeroCounts();
  let anomalies = zeroCounts();
  for (const g of groups) {
    hosts = addCounts(hosts, g.hosts);
    services = addCounts(services, g.services);
    thresholds = addCounts(thresholds, g.thresholds);
    anomalies = addCounts(anomalies, g.anomalies);
  }
  return { hosts, services, thresholds, anomalies };
}

export type GroupingType = 'category' | 'site' | 'app';

export async function fetchTacticalOverview(
  config: BhnmConfig,
  groupingType: GroupingType = 'category',
): Promise<TacticalGroup[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    grouping_type: groupingType,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/tactical-overview/data',
    params,
  );
  return parseTacticalResponse(raw);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/api/tactical-overview.test.ts`
Expected: all 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/api/tactical-overview.ts pwa/src/lib/api/tactical-overview.test.ts
git commit -m "feat(pwa): add tactical-overview API module with parser and aggregation"
```

---

## Task 5: Tab Bar Component

**Files:**
- Create: `pwa/src/components/TabBar.tsx`
- Create: `pwa/src/components/__tests__/TabBar.test.tsx`

- [ ] **Step 1: Write failing tab bar tests**

```typescript
// pwa/src/components/__tests__/TabBar.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { TabBar } from '../TabBar';

function renderWithRouter(initialEntry = '/') {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <TabBar />
    </MemoryRouter>,
  );
}

describe('TabBar', () => {
  it('renders three tabs', () => {
    renderWithRouter();
    expect(screen.getByRole('link', { name: /dashboard/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /incidents/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /devices/i })).toBeInTheDocument();
  });

  it('highlights active tab based on route', () => {
    renderWithRouter('/incidents');
    const incidentsTab = screen.getByRole('link', { name: /incidents/i });
    expect(incidentsTab.className).toContain('text-sky-400');
  });

  it('highlights dashboard on root route', () => {
    renderWithRouter('/');
    const dashTab = screen.getByRole('link', { name: /dashboard/i });
    expect(dashTab.className).toContain('text-sky-400');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/components/__tests__/TabBar.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Implement TabBar.tsx**

```typescript
// pwa/src/components/TabBar.tsx
import { NavLink } from 'react-router-dom';

function HomeIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round"
      strokeLinejoin="round" className={className ?? 'w-5 h-5'} aria-hidden="true">
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  );
}

function BellIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round"
      strokeLinejoin="round" className={className ?? 'w-5 h-5'} aria-hidden="true">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
      <path d="M13.73 21a2 2 0 0 1-3.46 0" />
    </svg>
  );
}

function ServerIcon({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round"
      strokeLinejoin="round" className={className ?? 'w-5 h-5'} aria-hidden="true">
      <rect x="2" y="2" width="20" height="8" rx="2" ry="2" />
      <rect x="2" y="14" width="20" height="8" rx="2" ry="2" />
      <line x1="6" y1="6" x2="6.01" y2="6" />
      <line x1="6" y1="18" x2="6.01" y2="18" />
    </svg>
  );
}

const tabs = [
  { to: '/', label: 'Dashboard', icon: HomeIcon, end: true },
  { to: '/incidents', label: 'Incidents', icon: BellIcon, end: false },
  { to: '/devices', label: 'Devices', icon: ServerIcon, end: false },
] as const;

export function TabBar() {
  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-slate-900 border-t border-slate-800 z-50"
      role="navigation" aria-label="Main navigation">
      <div className="flex justify-around items-center h-14 max-w-lg mx-auto">
        {tabs.map((tab) => (
          <NavLink
            key={tab.to}
            to={tab.to}
            end={tab.end}
            className={({ isActive }) =>
              `flex flex-col items-center gap-0.5 px-3 py-1 text-xs transition-colors ${
                isActive ? 'text-sky-400' : 'text-slate-500 hover:text-slate-300'
              }`
            }
            aria-label={tab.label}
          >
            <tab.icon />
            <span>{tab.label}</span>
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/components/__tests__/TabBar.test.tsx`
Expected: all 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/components/TabBar.tsx pwa/src/components/__tests__/TabBar.test.tsx
git commit -m "feat(pwa): add bottom tab bar navigation component"
```

---

## Task 6: App Layout + Routing Restructure

**Files:**
- Create: `pwa/src/components/AppLayout.tsx`
- Modify: `pwa/src/App.tsx`
- Modify: `pwa/src/features/incidents/IncidentListScreen.tsx`

- [ ] **Step 1: Create AppLayout with Outlet and TabBar**

```typescript
// pwa/src/components/AppLayout.tsx
import { Outlet } from 'react-router-dom';
import { Link } from 'react-router-dom';
import { TabBar } from './TabBar';
import { IOSRedirectBanner } from './IOSRedirectBanner';

function GearIcon() {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth="2" strokeLinecap="round"
      strokeLinejoin="round" className="w-5 h-5" aria-hidden="true">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51h0a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

export function AppLayout() {
  return (
    <div className="min-h-full pb-14">
      <IOSRedirectBanner />
      <Outlet />
      <TabBar />
    </div>
  );
}
```

- [ ] **Step 2: Restructure App.tsx with layout routes**

Replace `pwa/src/App.tsx`:

```typescript
// pwa/src/App.tsx
import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { AppLayout } from './components/AppLayout';
import { DashboardScreen } from './features/dashboard/DashboardScreen';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';
import { DevicesPlaceholder } from './features/devices/DevicesPlaceholder';

export default function App() {
  const navigate = useNavigate();

  // Listen for navigation messages from the service worker (push notification clicks)
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;

    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'navigate' && typeof event.data.url === 'string') {
        navigate(event.data.url);
      }
    };

    navigator.serviceWorker.addEventListener('message', handler);
    return () => navigator.serviceWorker.removeEventListener('message', handler);
  }, [navigate]);

  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route path="/" element={<DashboardScreen />} />
        <Route path="/incidents" element={<IncidentListScreen />} />
        <Route path="/incidents/:id" element={<IncidentDetailScreen />} />
        <Route path="/devices" element={<DevicesPlaceholder />} />
      </Route>
      <Route path="/settings" element={<SettingsScreen />} />
    </Routes>
  );
}
```

- [ ] **Step 3: Create DevicesPlaceholder**

```typescript
// pwa/src/features/devices/DevicesPlaceholder.tsx
import { EmptyState } from '../../components/EmptyState';

export function DevicesPlaceholder() {
  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800">
        <h1 className="text-lg font-semibold">Devices</h1>
      </header>
      <EmptyState
        title="Coming Soon"
        description="Device list and search will be available in v0.4.0."
      />
    </div>
  );
}
```

- [ ] **Step 4: Create a stub DashboardScreen**

Create a minimal stub so the app compiles (full implementation in Tasks 7–9):

```typescript
// pwa/src/features/dashboard/DashboardScreen.tsx
export function DashboardScreen() {
  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800">
        <h1 className="text-lg font-semibold">Dashboard</h1>
      </header>
      <div className="p-4 text-slate-500 text-sm">Loading dashboard...</div>
    </div>
  );
}
```

- [ ] **Step 5: Update IncidentListScreen — remove header nav, add settings link**

In `pwa/src/features/incidents/IncidentListScreen.tsx`, replace the header to remove the settings link (now in tab bar/settings route) and simplify:

Replace the `<header>` block (lines 51–70):

```typescript
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
```

- [ ] **Step 6: Update IncidentDetailScreen back link**

In `pwa/src/features/incidents/IncidentDetailScreen.tsx`, change the back link from `"/"` to `"/incidents"`:

Find: `<Link to="/"` → Replace with: `<Link to="/incidents"`

- [ ] **Step 7: Verify the app builds**

Run: `cd pwa && npx tsc --noEmit && npx vite build`
Expected: Build succeeds

- [ ] **Step 8: Commit**

```bash
git add pwa/src/components/AppLayout.tsx pwa/src/App.tsx \
  pwa/src/features/devices/DevicesPlaceholder.tsx \
  pwa/src/features/dashboard/DashboardScreen.tsx \
  pwa/src/features/incidents/IncidentListScreen.tsx \
  pwa/src/features/incidents/IncidentDetailScreen.tsx
git commit -m "feat(pwa): add tab bar layout with Dashboard/Incidents/Devices routing"
```

---

## Task 7: Auto-Refresh Countdown Component

**Files:**
- Create: `pwa/src/components/RefreshCountdown.tsx`
- Create: `pwa/src/components/__tests__/RefreshCountdown.test.tsx`

- [ ] **Step 1: Write failing countdown tests**

```typescript
// pwa/src/components/__tests__/RefreshCountdown.test.tsx
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { RefreshCountdown } from '../RefreshCountdown';

afterEach(() => {
  vi.useRealTimers();
});

describe('RefreshCountdown', () => {
  it('displays remaining seconds', () => {
    const now = Date.now();
    render(<RefreshCountdown lastUpdatedAt={now} intervalMs={120_000} />);
    expect(screen.getByText(/2:00/)).toBeInTheDocument();
  });

  it('counts down over time', () => {
    vi.useFakeTimers();
    const now = Date.now();
    render(<RefreshCountdown lastUpdatedAt={now} intervalMs={120_000} />);
    act(() => { vi.advanceTimersByTime(10_000); });
    expect(screen.getByText(/1:50/)).toBeInTheDocument();
  });

  it('shows 0:00 when past interval', () => {
    const past = Date.now() - 130_000;
    render(<RefreshCountdown lastUpdatedAt={past} intervalMs={120_000} />);
    expect(screen.getByText(/0:00/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/components/__tests__/RefreshCountdown.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Implement RefreshCountdown.tsx**

```typescript
// pwa/src/components/RefreshCountdown.tsx
import { useState, useEffect } from 'react';

interface Props {
  lastUpdatedAt: number; // timestamp ms
  intervalMs: number;    // e.g. 120_000
}

export function RefreshCountdown({ lastUpdatedAt, intervalMs }: Props) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(timer);
  }, []);

  // Reset "now" baseline when data refreshes
  useEffect(() => {
    setNow(Date.now());
  }, [lastUpdatedAt]);

  const elapsed = now - lastUpdatedAt;
  const remaining = Math.max(0, Math.ceil((intervalMs - elapsed) / 1_000));
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  const display = `${minutes}:${String(seconds).padStart(2, '0')}`;

  const fraction = Math.min(1, elapsed / intervalMs);

  return (
    <div className="flex items-center gap-1.5 text-xs text-slate-500" title="Time until next refresh">
      <div className="w-16 h-1.5 bg-slate-800 rounded-full overflow-hidden">
        <div
          className="h-full bg-sky-600 rounded-full transition-all duration-1000"
          style={{ width: `${(1 - fraction) * 100}%` }}
        />
      </div>
      <span className="tabular-nums w-8">{display}</span>
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/components/__tests__/RefreshCountdown.test.tsx`
Expected: all 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/components/RefreshCountdown.tsx pwa/src/components/__tests__/RefreshCountdown.test.tsx
git commit -m "feat(pwa): add auto-refresh countdown component"
```

---

## Task 8: Dashboard — Status Cards and Incident Ticker

**Files:**
- Create: `pwa/src/features/dashboard/StatusCard.tsx`
- Create: `pwa/src/features/dashboard/IncidentTicker.tsx`
- Create: `pwa/src/features/dashboard/useTacticalSummary.ts`
- Modify: `pwa/tailwind.config.js`

- [ ] **Step 1: Add ticker animation to Tailwind config**

In `pwa/tailwind.config.js`, inside `theme.extend`, add:

```javascript
animation: {
  ticker: 'ticker 30s linear infinite',
},
keyframes: {
  ticker: {
    '0%': { transform: 'translateX(0)' },
    '100%': { transform: 'translateX(-50%)' },
  },
},
```

- [ ] **Step 2: Create useTacticalSummary hook**

```typescript
// pwa/src/features/dashboard/useTacticalSummary.ts
import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import {
  fetchTacticalOverview,
  sumTacticalGroups,
  type TacticalSummary,
} from '../../lib/api/tactical-overview';

const REFETCH_INTERVAL_MS = 120_000;

export function useTacticalSummary() {
  const config = useConfig();

  return useQuery({
    queryKey: ['tactical-summary', config.serverId, config.baseUrl],
    queryFn: async (): Promise<TacticalSummary> => {
      const groups = await fetchTacticalOverview(config, 'category');
      return sumTacticalGroups(groups);
    },
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
```

- [ ] **Step 3: Create StatusCard component**

```typescript
// pwa/src/features/dashboard/StatusCard.tsx
import type { StatusCounts } from '../../lib/api/tactical-overview';

interface Props {
  label: string;
  counts: StatusCounts;
}

interface BadgeProps {
  value: number;
  color: string;
  bgColor: string;
}

function Badge({ value, color, bgColor }: BadgeProps) {
  if (value === 0) {
    return <span className="text-xs text-slate-600 tabular-nums w-8 text-center">0</span>;
  }
  return (
    <span className={`text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded ${color} ${bgColor} min-w-[2rem] text-center`}>
      {value}
    </span>
  );
}

export function StatusCard({ label, counts }: Props) {
  const total = counts.ok + counts.ack + counts.warn + counts.un + counts.crit;

  return (
    <div className="bg-slate-900 rounded-lg p-3">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-medium text-slate-300">{label}</span>
        <span className="text-xs text-slate-500 tabular-nums">{total}</span>
      </div>
      <div className="flex items-center gap-1">
        <Badge value={counts.ok} color="text-emerald-400" bgColor="bg-emerald-500/20" />
        <Badge value={counts.ack} color="text-sky-400" bgColor="bg-sky-500/20" />
        <Badge value={counts.warn} color="text-yellow-400" bgColor="bg-yellow-500/20" />
        <Badge value={counts.un} color="text-orange-400" bgColor="bg-orange-500/20" />
        <Badge value={counts.crit} color="text-red-400" bgColor="bg-red-500/20" />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Create IncidentTicker component**

```typescript
// pwa/src/features/dashboard/IncidentTicker.tsx
import { Link } from 'react-router-dom';
import { SeverityBadge } from '../incidents/SeverityBadge';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

export function IncidentTicker({ incidents }: Props) {
  // Only show critical and major incidents
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-900 rounded-lg p-3 text-sm text-slate-500">
        No critical or major incidents
      </div>
    );
  }

  // Duplicate for seamless loop
  const items = [...urgent, ...urgent];

  return (
    <div className="bg-slate-900 rounded-lg overflow-hidden">
      <div className="overflow-hidden relative h-10">
        <div
          className="flex gap-6 items-center absolute h-full whitespace-nowrap animate-ticker"
          style={{ animationDuration: `${Math.max(10, urgent.length * 5)}s` }}
        >
          {items.map((incident, i) => (
            <Link
              key={`${incident.incidentId}-${i}`}
              to={`/incidents/${incident.incidentId}`}
              className="flex items-center gap-2 shrink-0 hover:opacity-80"
            >
              <SeverityBadge severity={incident.severity} />
              <span className="text-sm text-slate-300 max-w-[200px] truncate">
                {incident.deviceName ?? 'Unknown'}: {incident.summary}
              </span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Verify build**

Run: `cd pwa && npx tsc --noEmit`
Expected: no type errors

- [ ] **Step 6: Commit**

```bash
git add pwa/src/features/dashboard/StatusCard.tsx \
  pwa/src/features/dashboard/IncidentTicker.tsx \
  pwa/src/features/dashboard/useTacticalSummary.ts \
  pwa/tailwind.config.js
git commit -m "feat(pwa): add status cards, incident ticker, and tactical summary hook"
```

---

## Task 9: Dashboard Screen Assembly

**Files:**
- Modify: `pwa/src/features/dashboard/DashboardScreen.tsx`
- Create: `pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx`

- [ ] **Step 1: Write failing dashboard screen tests**

```typescript
// pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DashboardScreen } from '../DashboardScreen';

// Mock useTacticalSummary
vi.mock('../useTacticalSummary', () => ({
  useTacticalSummary: () => ({
    data: {
      hosts: { ok: 10, ack: 1, warn: 2, un: 0, crit: 3 },
      services: { ok: 20, ack: 0, warn: 1, un: 0, crit: 1 },
      thresholds: { ok: 5, ack: 0, warn: 0, un: 0, crit: 0 },
      anomalies: { ok: 2, ack: 0, warn: 1, un: 0, crit: 0 },
    },
    isLoading: false,
    isError: false,
    dataUpdatedAt: Date.now(),
  }),
}));

// Mock useIncidents
vi.mock('../../incidents/useIncidents', () => ({
  useIncidents: () => ({
    data: [
      {
        incidentId: 'inc-1',
        displayId: '#1',
        deviceName: 'Router-1',
        deviceIp: '10.0.0.1',
        summary: 'Link down',
        severity: 'critical',
        status: 'active',
        incidentState: 'OPEN',
        startTime: new Date(),
        acknowledgedBy: null,
      },
    ],
    isLoading: false,
    dataUpdatedAt: Date.now(),
  }),
}));

function renderDashboard() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <DashboardScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DashboardScreen', () => {
  it('renders all four status cards', () => {
    renderDashboard();
    expect(screen.getByText('Hosts')).toBeInTheDocument();
    expect(screen.getByText('Services')).toBeInTheDocument();
    expect(screen.getByText('Thresholds')).toBeInTheDocument();
    expect(screen.getByText('Anomalies')).toBeInTheDocument();
  });

  it('renders drill-down links', () => {
    renderDashboard();
    expect(screen.getByText('Categories')).toBeInTheDocument();
    expect(screen.getByText('Sites')).toBeInTheDocument();
    expect(screen.getByText('Business Workflows')).toBeInTheDocument();
  });

  it('renders incident ticker with critical incidents', () => {
    renderDashboard();
    expect(screen.getByText(/Router-1/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/features/dashboard/__tests__/DashboardScreen.test.tsx`
Expected: FAIL — DashboardScreen is still a stub

- [ ] **Step 3: Implement full DashboardScreen**

Replace `pwa/src/features/dashboard/DashboardScreen.tsx`:

```typescript
// pwa/src/features/dashboard/DashboardScreen.tsx
import { Link } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { StatusCard } from './StatusCard';
import { IncidentTicker } from './IncidentTicker';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const config = useConfig();
  const { data: summary, isLoading, isError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents } = useIncidents();

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Dashboard</h1>
          {config.serverName && (
            <p className="text-xs text-slate-500">{config.serverName}</p>
          )}
        </div>
        <div className="flex items-center gap-3">
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
          <Link
            to="/settings"
            className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
          >
            Settings
          </Link>
        </div>
      </header>

      {!config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — add a server in Settings.</span>
          <Link to="/settings" className="px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
            Configure
          </Link>
        </div>
      )}

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching status from BHNM." />
      )}

      {isError && (
        <EmptyState
          title="Could not load dashboard"
          description={(error as Error).message}
        />
      )}

      {summary && (
        <div className="p-4 space-y-4">
          {/* Status Cards */}
          <div className="grid grid-cols-2 gap-3">
            <StatusCard label="Hosts" counts={summary.hosts} />
            <StatusCard label="Services" counts={summary.services} />
            <StatusCard label="Thresholds" counts={summary.thresholds} />
            <StatusCard label="Anomalies" counts={summary.anomalies} />
          </div>

          {/* Incident Ticker */}
          <div>
            <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Active Incidents
            </div>
            <IncidentTicker incidents={incidents ?? []} />
          </div>

          {/* Drill-Down Links */}
          <div>
            <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Tactical Overview
            </div>
            <div className="grid grid-cols-3 gap-2">
              <Link
                to="/tactical/category"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Categories
              </Link>
              <Link
                to="/tactical/site"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Sites
              </Link>
              <Link
                to="/tactical/bw"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Business Workflows
              </Link>
            </div>
            <p className="text-xs text-slate-600 mt-1 px-1">Available in v0.4.0</p>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/dashboard/__tests__/DashboardScreen.test.tsx`
Expected: all 3 tests PASS

- [ ] **Step 5: Run full test suite**

Run: `cd pwa && npx vitest run`
Expected: all tests PASS. Fix any import issues from the routing restructure.

- [ ] **Step 6: Commit**

```bash
git add pwa/src/features/dashboard/DashboardScreen.tsx \
  pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx
git commit -m "feat(pwa): implement dashboard screen with status cards, ticker, and drill-downs"
```

---

## Task 10: Settings Redesign — Server List Section

**Files:**
- Create: `pwa/src/features/settings/ServerListSection.tsx`
- Modify: `pwa/src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Create ServerListSection component**

```typescript
// pwa/src/features/settings/ServerListSection.tsx
import { useState } from 'react';
import {
  loadServers,
  setActiveServer,
  removeServer,
  type ServerConfig,
} from '../../lib/serverStorage';
import { notifyConfigChanged } from '../../lib/config';

interface Props {
  servers: ServerConfig[];
  onServersChanged: () => void;
  onEditServer: (server: ServerConfig) => void;
  onAddServer: () => void;
}

export function ServerListSection({
  servers,
  onServersChanged,
  onEditServer,
  onAddServer,
}: Props) {
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);

  const handleSwitch = (id: string) => {
    setActiveServer(id);
    notifyConfigChanged();
    onServersChanged();
  };

  const handleDelete = (id: string) => {
    if (confirmDeleteId === id) {
      removeServer(id);
      notifyConfigChanged();
      onServersChanged();
      setConfirmDeleteId(null);
    } else {
      setConfirmDeleteId(id);
    }
  };

  return (
    <div>
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        Servers
      </div>
      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {servers.length === 0 && (
          <div className="p-3 text-sm text-slate-500">No servers configured.</div>
        )}
        {servers.map((server) => (
          <div key={server.id} className="p-3 flex items-center gap-3">
            {/* Active indicator */}
            <button
              type="button"
              onClick={() => handleSwitch(server.id)}
              className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 ${
                server.isActive
                  ? 'border-sky-500 bg-sky-500'
                  : 'border-slate-600 hover:border-slate-400'
              }`}
              aria-label={server.isActive ? `${server.name} (active)` : `Switch to ${server.name}`}
            >
              {server.isActive && (
                <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24"
                  stroke="currentColor" strokeWidth="3">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              )}
            </button>

            {/* Server info */}
            <button
              type="button"
              onClick={() => onEditServer(server)}
              className="flex-1 text-left"
            >
              <div className="text-sm font-medium text-slate-200">{server.name}</div>
              <div className="text-xs text-slate-500">{server.baseUrl}</div>
            </button>

            {/* Delete */}
            <button
              type="button"
              onClick={() => handleDelete(server.id)}
              className={`text-xs px-2 py-1 rounded ${
                confirmDeleteId === server.id
                  ? 'bg-red-600 text-white'
                  : 'text-slate-500 hover:text-red-400'
              }`}
            >
              {confirmDeleteId === server.id ? 'Confirm' : 'Delete'}
            </button>
          </div>
        ))}
      </div>
      <button
        type="button"
        onClick={onAddServer}
        className="mt-3 w-full py-2 rounded bg-slate-900 border border-slate-700 text-sm text-slate-300 hover:bg-slate-800"
      >
        + Add Server
      </button>
    </div>
  );
}
```

- [ ] **Step 2: Verify build**

Run: `cd pwa && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/settings/ServerListSection.tsx
git commit -m "feat(pwa): add server list section for settings"
```

---

## Task 11: Server Add/Edit Form

**Files:**
- Create: `pwa/src/features/settings/ServerForm.tsx`
- Create: `pwa/src/features/settings/__tests__/ServerForm.test.tsx`

- [ ] **Step 1: Write failing form tests**

```typescript
// pwa/src/features/settings/__tests__/ServerForm.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ServerForm } from '../ServerForm';

describe('ServerForm', () => {
  it('renders empty form for new server', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByLabelText(/server name/i)).toHaveValue('');
    expect(screen.getByLabelText(/base url/i)).toHaveValue('/bhnm');
    expect(screen.getByLabelText(/api key/i)).toHaveValue('');
  });

  it('renders pre-filled form for editing', () => {
    const server = {
      id: 'abc',
      name: 'Test',
      baseUrl: '/test',
      apiKey: 'key123',
      pin: 'pin1',
      pushEnabled: false,
      isActive: true,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByLabelText(/server name/i)).toHaveValue('Test');
    expect(screen.getByLabelText(/base url/i)).toHaveValue('/test');
    expect(screen.getByLabelText(/api key/i)).toHaveValue('key123');
  });

  it('calls onSave with form values', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(<ServerForm onSave={onSave} onCancel={vi.fn()} />);

    await user.type(screen.getByLabelText(/server name/i), 'My Server');
    await user.clear(screen.getByLabelText(/base url/i));
    await user.type(screen.getByLabelText(/base url/i), '/myserver');
    await user.type(screen.getByLabelText(/api key/i), 'mykey');
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'My Server',
        baseUrl: '/myserver',
        apiKey: 'mykey',
      }),
    );
  });

  it('calls onCancel when cancel clicked', async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<ServerForm onSave={vi.fn()} onCancel={onCancel} />);
    await user.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/features/settings/__tests__/ServerForm.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Implement ServerForm**

```typescript
// pwa/src/features/settings/ServerForm.tsx
import { useState, type FormEvent } from 'react';
import type { ServerConfig, NewServerInput } from '../../lib/serverStorage';
import { testConnection } from '../../lib/api/ha-status';
import type { HaStatusResult } from '../../lib/api/ha-status';
import { formatHaRole, formatHaStatus } from '../../lib/api/ha-status';

interface Props {
  server?: Partial<ServerConfig>;
  onSave: (input: NewServerInput) => void;
  onCancel: () => void;
}

type TestState = 'idle' | 'testing' | 'success' | 'failed';

export function ServerForm({ server, onSave, onCancel }: Props) {
  const [name, setName] = useState(server?.name ?? '');
  const [baseUrl, setBaseUrl] = useState(server?.baseUrl ?? '/bhnm');
  const [apiKey, setApiKey] = useState(server?.apiKey ?? '');
  const [pin, setPin] = useState(server?.pin ?? '');
  const [showKey, setShowKey] = useState(false);
  const [webhookSecret, setWebhookSecret] = useState(server?.pushWebhookSecret ?? '');
  const [middlewareUrl, setMiddlewareUrl] = useState(server?.pushMiddlewareUrl ?? '');
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<HaStatusResult | null>(null);
  const [testError, setTestError] = useState('');

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    onSave({
      name: name.trim() || 'BHNM Server',
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      pin: pin.trim() || undefined,
      pushWebhookSecret: webhookSecret.trim() || undefined,
      pushMiddlewareUrl: middlewareUrl.trim() || undefined,
    });
  };

  const handleTestConnection = async () => {
    setTestState('testing');
    setTestResult(null);
    setTestError('');
    try {
      const result = await testConnection({
        serverId: '',
        serverName: '',
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        pin: pin.trim() || undefined,
        isConfigured: apiKey.trim().length > 0,
      });
      setTestResult(result);
      setTestState('success');
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        {server?.id ? 'Edit Server' : 'Add Server'}
      </div>

      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {/* Server Name */}
        <div className="p-3">
          <label htmlFor="server-name" className="block text-xs text-slate-400 mb-1.5">
            Server Name
          </label>
          <input
            id="server-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Production BHNM"
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* Base URL */}
        <div className="p-3">
          <label htmlFor="base-url" className="block text-xs text-slate-400 mb-1.5">
            Base URL
          </label>
          <input
            id="base-url"
            type="text"
            value={baseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            placeholder="/bhnm"
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* API Key */}
        <div className="p-3">
          <label htmlFor="server-api-key" className="block text-xs text-slate-400 mb-1.5">
            API Key
          </label>
          <div className="flex items-center gap-2">
            <input
              id="server-api-key"
              type={showKey ? 'text' : 'password'}
              autoComplete="off"
              spellCheck={false}
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              className="flex-1 rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
            <button
              type="button"
              onClick={() => setShowKey(!showKey)}
              className="px-2 py-2 rounded border border-slate-700 text-slate-400 hover:text-white text-xs"
              aria-label={showKey ? 'Hide key' : 'Show key'}
            >
              {showKey ? 'Hide' : 'Show'}
            </button>
          </div>
        </div>

        {/* PIN */}
        <div className="p-3">
          <label htmlFor="server-pin" className="block text-xs text-slate-400 mb-1.5">
            PIN / License ID <span className="text-slate-600">(SaaS only)</span>
          </label>
          <input
            id="server-pin"
            type="text"
            autoComplete="off"
            spellCheck={false}
            placeholder="Optional"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* Webhook Secret */}
        <div className="p-3">
          <label htmlFor="server-webhook-secret" className="block text-xs text-slate-400 mb-1.5">
            Webhook Secret <span className="text-slate-600">(for push notifications)</span>
          </label>
          <input
            id="server-webhook-secret"
            type="password"
            autoComplete="off"
            spellCheck={false}
            placeholder="Same secret as in BHNM webhook URL"
            value={webhookSecret}
            onChange={(e) => setWebhookSecret(e.target.value)}
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* Push Middleware URL (optional override) */}
        <div className="p-3">
          <label htmlFor="server-middleware-url" className="block text-xs text-slate-400 mb-1.5">
            Push Middleware URL <span className="text-slate-600">(optional, defaults to Base URL)</span>
          </label>
          <input
            id="server-middleware-url"
            type="text"
            placeholder="Leave empty to use Base URL"
            value={middlewareUrl}
            onChange={(e) => setMiddlewareUrl(e.target.value)}
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>
      </div>

      {/* Test Connection */}
      <button
        type="button"
        onClick={handleTestConnection}
        disabled={testState === 'testing' || apiKey.trim().length === 0}
        className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-3 text-sm hover:bg-slate-800 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {testState === 'testing' ? 'Testing...' : 'Test Connection'}
      </button>

      {testState === 'success' && testResult && (
        <div className="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-3">
          <div className="flex items-center gap-2">
            <span className="text-emerald-400 text-sm font-semibold">Connected</span>
          </div>
          <div className="text-xs text-slate-400 mt-1">
            {formatHaRole(testResult.role)}
            {formatHaStatus(testResult.role, testResult.status) && (
              <> — {formatHaStatus(testResult.role, testResult.status)}</>
            )}
          </div>
        </div>
      )}

      {testState === 'failed' && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-3">
          <span className="text-red-400 text-sm font-semibold">Failed</span>
          <p className="text-xs text-slate-400 mt-1">{testError}</p>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={apiKey.trim().length === 0}
          className="flex-1 px-3 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm font-semibold disabled:opacity-50"
        >
          Save
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 px-3 py-2 rounded bg-slate-900 border border-slate-700 hover:bg-slate-800 text-sm"
        >
          Cancel
        </button>
      </div>

      <p className="text-xs text-slate-500 px-1">
        Stored in your browser only.
      </p>
    </form>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/settings/__tests__/ServerForm.test.tsx`
Expected: all 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/settings/ServerForm.tsx \
  pwa/src/features/settings/__tests__/ServerForm.test.tsx
git commit -m "feat(pwa): add server add/edit form component"
```

---

## Task 12: Settings Screen Redesign

**Files:**
- Modify: `pwa/src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Rewrite SettingsScreen with server management**

Replace `pwa/src/features/settings/SettingsScreen.tsx`:

```typescript
// pwa/src/features/settings/SettingsScreen.tsx
import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import {
  loadServers,
  addServer,
  updateServer,
  type ServerConfig,
  type NewServerInput,
} from '../../lib/serverStorage';
import { subscribeToPush, unsubscribeFromPush, getPushState, type PushState } from '../../lib/pushRegistration';
import { ServerListSection } from './ServerListSection';
import { ServerForm } from './ServerForm';

type View = 'list' | 'add' | 'edit';

export function SettingsScreen() {
  const config = useConfig();
  const queryClient = useQueryClient();
  const [servers, setServers] = useState(loadServers);
  const [view, setView] = useState<View>('list');
  const [editingServer, setEditingServer] = useState<ServerConfig | null>(null);
  const [pushState, setPushState] = useState<PushState>(getPushState);
  const [pushLoading, setPushLoading] = useState(false);

  const refreshServers = useCallback(() => {
    setServers(loadServers());
  }, []);

  const handleAddServer = (input: NewServerInput) => {
    addServer(input);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    // Invalidate all queries to re-fetch with potentially new active server
    queryClient.invalidateQueries();
  };

  const handleEditServer = (input: NewServerInput) => {
    if (!editingServer) return;
    updateServer(editingServer.id, input);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    setEditingServer(null);
    queryClient.invalidateQueries();
  };

  const handleEditClick = (server: ServerConfig) => {
    setEditingServer(server);
    setView('edit');
  };

  const handleTogglePush = async () => {
    if (pushLoading) return;
    const activeServer = servers.find((s) => s.isActive);
    if (!activeServer) return;

    const webhookSecret = activeServer.pushWebhookSecret;
    const middlewareUrl = activeServer.pushMiddlewareUrl ?? activeServer.baseUrl;

    setPushLoading(true);
    try {
      if (activeServer.pushEnabled) {
        await unsubscribeFromPush();
        updateServer(activeServer.id, { pushEnabled: false });
        notifyConfigChanged();
        refreshServers();
        setPushState({ status: 'unregistered' });
      } else {
        if (!webhookSecret) {
          setPushState({ status: 'error', message: 'Webhook secret is required' });
          setPushLoading(false);
          return;
        }
        const endpoint = await subscribeToPush(middlewareUrl, webhookSecret);
        updateServer(activeServer.id, { pushEnabled: true });
        notifyConfigChanged();
        refreshServers();
        setPushState({ status: 'registered', endpoint });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Push registration failed';
      setPushState({ status: 'error', message: msg });
    } finally {
      setPushLoading(false);
    }
  };

  const activeServer = servers.find((s) => s.isActive);

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-300 hover:text-white" aria-label="Back to dashboard">
          ← Back
        </Link>
        <h1 className="text-lg font-semibold">Settings</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      <div className="p-4 space-y-6 max-w-md">
        {view === 'list' && (
          <>
            <ServerListSection
              servers={servers}
              onServersChanged={() => {
                refreshServers();
                queryClient.invalidateQueries();
              }}
              onEditServer={handleEditClick}
              onAddServer={() => setView('add')}
            />

            {/* Push Notifications — for active server */}
            {activeServer && (
              <div>
                <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
                  Push Notifications
                </div>
                <div className="bg-slate-900 rounded-lg overflow-hidden">
                  <div className="p-3 flex items-center justify-between">
                    <div>
                      <div className="text-sm font-medium">Push Notifications</div>
                      <div className="text-xs text-slate-500 mt-0.5">
                        {pushState.status === 'unsupported' && 'Not supported in this browser'}
                        {pushState.status === 'denied' && 'Permission denied — enable in browser settings'}
                        {pushState.status === 'unregistered' && 'Not registered'}
                        {pushState.status === 'registered' && 'Registered and active'}
                        {pushState.status === 'error' && pushState.message}
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={handleTogglePush}
                      disabled={pushLoading || pushState.status === 'unsupported' || pushState.status === 'denied'}
                      className={`relative w-11 h-6 rounded-full transition-colors ${
                        activeServer.pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
                      } disabled:opacity-50 disabled:cursor-not-allowed`}
                      role="switch"
                      aria-checked={activeServer.pushEnabled}
                    >
                      <span
                        className="block w-5 h-5 rounded-full bg-white shadow transition-transform"
                        style={{ transform: activeServer.pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
                      />
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* About */}
            <div className="border-t border-slate-800 pt-6">
              <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">About</div>
              <div className="bg-slate-900 rounded-lg p-3">
                <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
                  <dt className="text-slate-500">Version</dt>
                  <dd>0.3.0</dd>
                  <dt className="text-slate-500">Platform</dt>
                  <dd>PWA (Web Push)</dd>
                </dl>
              </div>
            </div>
          </>
        )}

        {view === 'add' && (
          <ServerForm
            onSave={handleAddServer}
            onCancel={() => setView('list')}
          />
        )}

        {view === 'edit' && editingServer && (
          <ServerForm
            server={editingServer}
            onSave={handleEditServer}
            onCancel={() => { setView('list'); setEditingServer(null); }}
          />
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Verify build**

Run: `cd pwa && npx tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Run full test suite**

Run: `cd pwa && npx vitest run`
Expected: All tests pass. Settings tests that depend on the old single-key API may need updating — the old `settingsStorage.test.ts` tests can be kept as-is since those functions still exist for backward compat, but the `SettingsScreen.test.tsx` will need to be updated to use the new component structure. Update mocks and assertions as needed.

- [ ] **Step 4: Commit**

```bash
git add pwa/src/features/settings/SettingsScreen.tsx
git commit -m "feat(pwa): redesign settings screen with multi-server management"
```

---

## Task 13: Server Switching — Data Re-fetch and Push Re-registration

**Files:**
- Modify: `pwa/src/features/settings/ServerListSection.tsx`
- Modify: `pwa/src/lib/pushRegistration.ts`

- [ ] **Step 1: Add push re-registration on server switch**

In `pwa/src/features/settings/ServerListSection.tsx`, update `handleSwitch` to also trigger push re-registration. Import and use `useQueryClient`:

Update the `handleSwitch` function to accept and call a callback:

The `onServersChanged` callback already triggers `queryClient.invalidateQueries()` from the parent `SettingsScreen`. The query invalidation causes React Query to re-fetch all queries with the new active server's config. No additional wiring needed — the `useConfig()` hook will return the new server's config, and query keys include `serverId`, so queries automatically refetch.

For push re-registration: when switching servers, the middleware subscription belongs to the old server. The new server may use a different middleware. Push re-registration is handled by the user toggling push off/on in the push section (which now reads from the active server's config). This is the simplest approach and avoids automatic side effects.

- [ ] **Step 2: Verify server switching works end-to-end**

Run: `cd pwa && npx vite build`
Expected: Build succeeds

- [ ] **Step 3: Commit (if any changes were made)**

```bash
git add -u pwa/
git commit -m "feat(pwa): ensure data re-fetch on server switch via query invalidation"
```

---

## Task 14: Version Bump and Final Cleanup

**Files:**
- Modify: `pwa/package.json`
- Modify: `shared/feature-spec.md` (if it exists)

- [ ] **Step 1: Bump version to 0.3.0**

In `pwa/package.json`, update:

```json
"version": "0.3.0"
```

- [ ] **Step 2: Update feature spec**

In `shared/feature-spec.md`, mark M2 features as implemented:
- Bottom tab bar navigation
- Dashboard with H/S/T/A status cards
- Incident ticker
- Auto-refresh countdown
- Multi-server management
- Settings redesign

- [ ] **Step 3: Run full test suite one final time**

Run: `cd pwa && npx vitest run`
Expected: all tests PASS

- [ ] **Step 4: Verify production build**

Run: `cd pwa && npx vite build`
Expected: Build succeeds with no warnings

- [ ] **Step 5: Commit**

```bash
git add pwa/package.json shared/feature-spec.md
git commit -m "chore(pwa): bump version to 0.3.0 for M2 release"
```
