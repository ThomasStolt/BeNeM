# PWA Settings — iOS Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the PWA settings screen with the iOS app — QR-provisioned servers lock fields to read-only, add User Name/BHNM URL fields, single save-with-test button, server switch confirmation.

**Architecture:** Extend the existing storage model with 3 new fields (`ackUser`, `bhnmUrl`, `isQrProvisioned`). Update QR parser field mapping. Enhance `ServerForm` with conditional read-only mode. Add switch confirmation dialog to `ServerListSection`.

**Tech Stack:** React 19, TypeScript, Vitest, @testing-library/react

**Spec:** `docs/superpowers/specs/2026-04-07-pwa-settings-ios-parity-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `pwa/src/lib/serverStorage.ts` | Modify | Add `ackUser`, `bhnmUrl`, `isQrProvisioned` to interfaces and `createServerConfig` |
| `pwa/src/lib/__tests__/serverStorage.test.ts` | Modify | Add tests for new fields |
| `pwa/src/lib/config.ts` | Modify | Add `ackUser`, `bhnmUrl` to `BhnmConfig` and `buildSnapshot()` |
| `pwa/src/lib/config.test.ts` | Modify | Add test for new config fields |
| `pwa/src/lib/qr-parser.ts` | Modify | New field mapping: `bhnm_url`→`bhnmUrl`, `middleware_url`→`baseUrl`, `user`→`ackUser` |
| `pwa/src/lib/qr-parser.test.ts` | Modify | Update expected results, add ackUser/bhnmUrl assertions |
| `pwa/src/lib/api/incidents.ts` | Modify | Use `config.ackUser` in ACK/UnACK |
| `pwa/src/features/settings/ServerForm.tsx` | Modify | Read-only mode, new fields, single save-with-test button, delete button |
| `pwa/src/features/settings/__tests__/ServerForm.test.tsx` | Modify | Tests for read-only mode, new fields, save-with-test |
| `pwa/src/features/settings/ServerListSection.tsx` | Modify | Add switch confirmation dialog |
| `pwa/src/features/scanner/QRConfirmScreen.tsx` | Modify | Show new fields, pass `isQrProvisioned` |
| `pwa/src/features/scanner/QRConfirmScreen.test.tsx` | Modify | Update mock config, test new fields |
| `pwa/src/features/settings/SettingsScreen.tsx` | Modify | Pass new fields through QR confirm flow |

---

### Task 1: Storage Model — Add New Fields

**Files:**
- Modify: `pwa/src/lib/serverStorage.ts:12-32`
- Modify: `pwa/src/lib/serverStorage.ts:164-176`
- Test: `pwa/src/lib/__tests__/serverStorage.test.ts`

- [ ] **Step 1: Write failing tests for new fields**

Add to `pwa/src/lib/__tests__/serverStorage.test.ts`, inside the `describe('addServer')` block, after the existing "adds a second server as inactive" test:

```typescript
    it('stores ackUser, bhnmUrl, and isQrProvisioned', () => {
      const server = addServer({
        name: 'QR Server',
        baseUrl: '/middleware',
        apiKey: 'k1',
        ackUser: 'thomas',
        bhnmUrl: 'https://bhnm.example.com',
        isQrProvisioned: true,
      });
      const servers = loadServers();
      expect(servers[0].ackUser).toBe('thomas');
      expect(servers[0].bhnmUrl).toBe('https://bhnm.example.com');
      expect(servers[0].isQrProvisioned).toBe(true);
      expect(servers[0].id).toBe(server.id);
    });

    it('defaults new fields when not provided', () => {
      addServer({ name: 'Manual', baseUrl: '/bhnm', apiKey: 'k1' });
      const servers = loadServers();
      expect(servers[0].ackUser).toBe('');
      expect(servers[0].bhnmUrl).toBe('');
      expect(servers[0].isQrProvisioned).toBe(false);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: FAIL — `ackUser`, `bhnmUrl`, `isQrProvisioned` not in types

- [ ] **Step 3: Add fields to ServerConfig and NewServerInput**

In `pwa/src/lib/serverStorage.ts`, update the `ServerConfig` interface (lines 12-22):

```typescript
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
  ackUser: string;
  bhnmUrl: string;
  isQrProvisioned: boolean;
}
```

Update `NewServerInput` (lines 24-32):

```typescript
export interface NewServerInput {
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushEnabled?: boolean;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
  ackUser?: string;
  bhnmUrl?: string;
  isQrProvisioned?: boolean;
}
```

Update `createServerConfig` (lines 164-176) to include the new fields:

```typescript
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
    ackUser: input.ackUser ?? '',
    bhnmUrl: input.bhnmUrl ?? '',
    isQrProvisioned: input.isQrProvisioned ?? false,
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/__tests__/serverStorage.test.ts`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/serverStorage.ts pwa/src/lib/__tests__/serverStorage.test.ts
git commit -m "feat(pwa): add ackUser, bhnmUrl, isQrProvisioned to storage model"
```

---

### Task 2: Config Snapshot — Expose New Fields

**Files:**
- Modify: `pwa/src/lib/config.ts:4-13,34-57`
- Test: `pwa/src/lib/config.test.ts`

- [ ] **Step 1: Write failing test**

Add to `pwa/src/lib/config.test.ts`, after the existing "includes webhook fields" test:

```typescript
  it('includes ackUser and bhnmUrl from active server', () => {
    addServer({
      name: 'ACK Test',
      baseUrl: '/bhnm',
      apiKey: 'k',
      ackUser: 'thomas',
      bhnmUrl: 'https://bhnm.test.com',
    });
    const config = getSnapshotForTest();
    expect(config.ackUser).toBe('thomas');
    expect(config.bhnmUrl).toBe('https://bhnm.test.com');
  });

  it('defaults ackUser and bhnmUrl to empty string', () => {
    addServer({ name: 'Basic', baseUrl: '/bhnm', apiKey: 'k' });
    const config = getSnapshotForTest();
    expect(config.ackUser).toBe('');
    expect(config.bhnmUrl).toBe('');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/config.test.ts`
Expected: FAIL — `ackUser` and `bhnmUrl` not in BhnmConfig

- [ ] **Step 3: Add fields to BhnmConfig and buildSnapshot**

In `pwa/src/lib/config.ts`, update the `BhnmConfig` interface:

```typescript
export interface BhnmConfig {
  serverId: string;
  serverName: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  webhookSecret?: string;
  pushMiddlewareUrl?: string;
  isConfigured: boolean;
  ackUser: string;
  bhnmUrl: string;
}
```

Update `buildSnapshot()` — in the `if (!server)` fallback, add defaults:

```typescript
function buildSnapshot(): BhnmConfig {
  const server = getActiveServer();
  if (!server) {
    const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
    return {
      serverId: '',
      serverName: '',
      baseUrl: '/bhnm',
      apiKey: envKey,
      isConfigured: envKey.length > 0,
      ackUser: '',
      bhnmUrl: '',
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
    ackUser: server.ackUser,
    bhnmUrl: server.bhnmUrl,
  };
}
```

Also update `getServerSnapshot()` to include the new fields:

```typescript
function getServerSnapshot(): BhnmConfig {
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  return {
    serverId: '',
    serverName: '',
    baseUrl: '/bhnm',
    apiKey: envKey,
    isConfigured: envKey.length > 0,
    ackUser: '',
    bhnmUrl: '',
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/config.test.ts`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/config.ts pwa/src/lib/config.test.ts
git commit -m "feat(pwa): expose ackUser and bhnmUrl in BhnmConfig"
```

---

### Task 3: QR Parser — New Field Mapping

**Files:**
- Modify: `pwa/src/lib/qr-parser.ts:8-15,58-82,104-112`
- Test: `pwa/src/lib/qr-parser.test.ts`

- [ ] **Step 1: Update test expectations for compact format**

In `pwa/src/lib/qr-parser.test.ts`, update the "parses compact format with snake_case field names" test (line 30-52):

```typescript
  it('parses compact format with snake_case field names (middleware format)', async () => {
    const payload = JSON.stringify({
      bhnm_url: 'https://bhnm.example.com',
      middleware_url: 'https://middleware.example.com',
      api_key: 'mykey',
      pin: '1234',
      push_secret: 'webhooksecret',
      name: 'Test Server',
      user: 'admin',
      symbol: 'server.rack',
      color: '#0A84FF',
    });
    vi.mocked(decryptCompressed).mockResolvedValue(payload);
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result).toEqual({
      name: 'Test Server',
      baseUrl: 'https://middleware.example.com',
      bhnmUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      ackUser: 'admin',
      pushWebhookSecret: 'webhooksecret',
    });
  });
```

Update the "handles base64url encoded p parameter" test (line 93-103):

```typescript
  it('handles base64url encoded p parameter', async () => {
    vi.mocked(decryptCompressed).mockResolvedValue(
      JSON.stringify({ bhnm_url: 'https://bhnm.test', api_key: 'k', name: 'S' }),
    );
    const result = await parseQRUrl('benem://configure?p=abc-def_ghi');
    expect(result.baseUrl).toBe('https://bhnm.test');
    expect(result.bhnmUrl).toBe('https://bhnm.test');
    expect(result.ackUser).toBeUndefined();
    expect(decryptCompressed).toHaveBeenCalled();
    expect(decrypt).not.toHaveBeenCalled();
  });
```

Update the legacy format test (line 67-84):

```typescript
  it('parses legacy format with individual encrypted parameters', async () => {
    vi.mocked(decrypt)
      .mockResolvedValueOnce('https://bhnm.example.com')
      .mockResolvedValueOnce('mykey')
      .mockResolvedValueOnce('1234')
      .mockResolvedValueOnce('Legacy Server');
    const fakeB64 = btoa('encrypted');
    const url = `benem://configure?server=${fakeB64}&api_key=${fakeB64}&pin=${fakeB64}&name=${fakeB64}`;
    const result = await parseQRUrl(url);
    expect(result).toEqual({
      name: 'Legacy Server',
      baseUrl: 'https://bhnm.example.com',
      bhnmUrl: '',
      apiKey: 'mykey',
      pin: '1234',
      ackUser: undefined,
      pushWebhookSecret: undefined,
    });
  });
```

Add a new test for middleware_url fallback:

```typescript
  it('falls back to bhnm_url as baseUrl when middleware_url is absent', async () => {
    const payload = JSON.stringify({
      bhnm_url: 'https://bhnm.example.com',
      api_key: 'mykey',
      name: 'No Middleware',
    });
    vi.mocked(decryptCompressed).mockResolvedValue(payload);
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result.baseUrl).toBe('https://bhnm.example.com');
    expect(result.bhnmUrl).toBe('https://bhnm.example.com');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/qr-parser.test.ts`
Expected: FAIL — old field names in expected results don't match

- [ ] **Step 3: Update ParsedServerConfig and parsing logic**

In `pwa/src/lib/qr-parser.ts`, update the interface (lines 8-15):

```typescript
export interface ParsedServerConfig {
  name: string;
  baseUrl: string;
  bhnmUrl: string;
  apiKey: string;
  pin?: string;
  ackUser?: string;
  pushWebhookSecret?: string;
}
```

Update the compact format return block (lines 75-82):

```typescript
    const middlewareUrl = data.middleware_url || data.middlewareURL || '';
    const ackUser = data.user || data.ackUser || undefined;

    return {
      name: data.name ?? 'BHNM Server',
      baseUrl: middlewareUrl || bhnmUrl,
      bhnmUrl,
      apiKey,
      pin: data.pin || undefined,
      ackUser,
      pushWebhookSecret: data.push_secret || data.pushSecret || undefined,
    };
```

Update the legacy format return block (lines 104-112):

```typescript
  return {
    name,
    baseUrl: server,
    bhnmUrl: '',
    apiKey,
    pin: pin || undefined,
    ackUser: undefined,
    pushWebhookSecret: undefined,
  };
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/qr-parser.test.ts`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/qr-parser.ts pwa/src/lib/qr-parser.test.ts
git commit -m "feat(pwa): update QR parser — bhnmUrl, ackUser, middleware_url→baseUrl"
```

---

### Task 4: ACK/UnACK — Use config.ackUser

**Files:**
- Modify: `pwa/src/lib/api/incidents.ts:150-176`

- [ ] **Step 1: Update acknowledgeIncident**

In `pwa/src/lib/api/incidents.ts`, change line 157 from:

```typescript
    user: 'BeNeM PWA',
```

to:

```typescript
    user: config.ackUser || 'BeNeM PWA',
```

- [ ] **Step 2: Update unacknowledgeIncident**

In the same file, change line 170 from:

```typescript
    user: 'BeNeM PWA',
```

to:

```typescript
    user: config.ackUser || 'BeNeM PWA',
```

- [ ] **Step 3: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS (no test changes needed — existing tests don't assert on the user field)

- [ ] **Step 4: Commit**

```bash
git add pwa/src/lib/api/incidents.ts
git commit -m "feat(pwa): use config.ackUser for incident ACK/UnACK"
```

---

### Task 5: ServerForm — New Fields, Read-Only Mode, Save-with-Test

**Files:**
- Modify: `pwa/src/features/settings/ServerForm.tsx`
- Test: `pwa/src/features/settings/__tests__/ServerForm.test.tsx`

- [ ] **Step 1: Write failing tests for new behavior**

Replace the entire contents of `pwa/src/features/settings/__tests__/ServerForm.test.tsx`:

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ServerForm } from '../ServerForm';

function getField(id: string) {
  return document.getElementById(id) as HTMLInputElement;
}

describe('ServerForm', () => {
  it('renders empty form for new server', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('');
    expect(getField('server-bhnm-url')).toHaveValue('');
    expect(getField('server-middleware-url')).toHaveValue('/bhnm');
    expect(getField('server-api-key')).toHaveValue('');
    expect(getField('server-ack-user')).toHaveValue('');
  });

  it('renders pre-filled form for editing', () => {
    const server = {
      id: 'abc',
      name: 'Test',
      baseUrl: '/test',
      bhnmUrl: 'https://bhnm.test.com',
      apiKey: 'key123',
      pin: 'pin1',
      ackUser: 'thomas',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: false,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('Test');
    expect(getField('server-bhnm-url')).toHaveValue('https://bhnm.test.com');
    expect(getField('server-middleware-url')).toHaveValue('/test');
    expect(getField('server-api-key')).toHaveValue('key123');
    expect(getField('server-ack-user')).toHaveValue('thomas');
  });

  it('makes fields read-only when QR-provisioned', () => {
    const server = {
      id: 'abc',
      name: 'QR Server',
      baseUrl: '/middleware',
      bhnmUrl: 'https://bhnm.example.com',
      apiKey: 'secret-key',
      ackUser: 'admin',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: true,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    // Name should still be editable
    expect(getField('server-name')).not.toBeDisabled();
    // QR fields should not be editable inputs — check that text is displayed instead
    expect(screen.getByText('https://bhnm.example.com')).toBeInTheDocument();
    expect(screen.getByText(/middleware/i)).toBeInTheDocument();
    // API key should be masked
    expect(screen.getByText('••••••••')).toBeInTheDocument();
    // Footer should indicate QR provisioning
    expect(screen.getByText(/configured via qr code/i)).toBeInTheDocument();
  });

  it('shows delete button only in edit mode', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.queryByRole('button', { name: /delete/i })).not.toBeInTheDocument();

    const server = { id: 'abc', name: 'Test', baseUrl: '/test', apiKey: 'k', isQrProvisioned: false };
    const { unmount } = render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByRole('button', { name: /delete/i })).toBeInTheDocument();
    unmount();
  });

  it('calls onSave with all fields including new ones', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(<ServerForm onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-name'), 'My Server');
    await user.type(getField('server-bhnm-url'), 'https://bhnm.test');
    await user.clear(getField('server-middleware-url'));
    await user.type(getField('server-middleware-url'), '/myserver');
    await user.type(getField('server-api-key'), 'mykey');
    await user.type(getField('server-ack-user'), 'admin');
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'My Server',
        baseUrl: '/myserver',
        bhnmUrl: 'https://bhnm.test',
        apiKey: 'mykey',
        ackUser: 'admin',
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
Expected: FAIL — new field IDs and read-only behavior don't exist yet

- [ ] **Step 3: Rewrite ServerForm with new fields and read-only mode**

Replace the entire contents of `pwa/src/features/settings/ServerForm.tsx`:

```typescript
import { useState, type FormEvent } from 'react';
import type { ServerConfig, NewServerInput } from '../../lib/serverStorage';
import { testConnection } from '../../lib/api/ha-status';
import type { HaStatusResult } from '../../lib/api/ha-status';
import { formatHaRole, formatHaStatus } from '../../lib/api/ha-status';

interface Props {
  server?: Partial<ServerConfig>;
  onSave: (input: NewServerInput) => void;
  onCancel: () => void;
  onDelete?: () => void;
}

type TestState = 'idle' | 'testing' | 'success' | 'failed';

function maskSecret(value: string): string {
  if (!value) return '';
  return '••••••••';
}

function ReadOnlyField({ label, value, masked }: { label: string; value: string; masked?: boolean }) {
  return (
    <div className="p-3">
      <div className="block text-xs text-slate-400 mb-1.5">{label}</div>
      <div className="text-sm text-slate-500 font-mono">{masked ? maskSecret(value) : value}</div>
    </div>
  );
}

export function ServerForm({ server, onSave, onCancel, onDelete }: Props) {
  const isEditing = !!server?.id;
  const isQr = server?.isQrProvisioned ?? false;

  const [name, setName] = useState(server?.name ?? '');
  const [bhnmUrl, setBhnmUrl] = useState(server?.bhnmUrl ?? '');
  const [baseUrl, setBaseUrl] = useState(server?.baseUrl ?? '/bhnm');
  const [apiKey, setApiKey] = useState(server?.apiKey ?? '');
  const [pin, setPin] = useState(server?.pin ?? '');
  const [ackUser, setAckUser] = useState(server?.ackUser ?? '');
  const [showKey, setShowKey] = useState(false);
  const [webhookSecret, setWebhookSecret] = useState(server?.pushWebhookSecret ?? '');
  const [pushEnabled, setPushEnabled] = useState(server?.pushEnabled ?? false);
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<HaStatusResult | null>(null);
  const [testError, setTestError] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    // Test connection first
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
        ackUser: '',
        bhnmUrl: '',
      });
      setTestResult(result);
      setTestState('success');
      // Test passed — save
      onSave({
        name: name.trim() || 'BHNM Server',
        baseUrl: baseUrl.trim(),
        bhnmUrl: bhnmUrl.trim(),
        apiKey: apiKey.trim(),
        pin: pin.trim() || undefined,
        ackUser: ackUser.trim(),
        pushEnabled,
        pushWebhookSecret: webhookSecret.trim() || undefined,
        pushMiddlewareUrl: undefined, // no longer used separately
        isQrProvisioned: isQr,
      });
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }
  };

  const saveDisabled =
    testState === 'testing' ||
    apiKey.trim().length === 0 ||
    (!isQr && pushEnabled && !webhookSecret.trim());

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        {isEditing ? 'Edit Server' : 'Add Server'}
      </div>

      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {/* Server Name — always editable */}
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

        {/* BHNM URL */}
        {isQr ? (
          <ReadOnlyField label="BHNM URL" value={bhnmUrl} />
        ) : (
          <div className="p-3">
            <label htmlFor="server-bhnm-url" className="block text-xs text-slate-400 mb-1.5">
              BHNM URL
            </label>
            <input
              id="server-bhnm-url"
              type="text"
              value={bhnmUrl}
              onChange={(e) => setBhnmUrl(e.target.value)}
              placeholder="https://bhnm.example.com"
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* Middleware URL (was Base URL) */}
        {isQr ? (
          <ReadOnlyField label="Middleware URL" value={baseUrl} />
        ) : (
          <div className="p-3">
            <label htmlFor="server-middleware-url" className="block text-xs text-slate-400 mb-1.5">
              Middleware URL
            </label>
            <input
              id="server-middleware-url"
              type="text"
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="/bhnm"
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* API Token */}
        {isQr ? (
          <ReadOnlyField label="API Token" value={apiKey} masked />
        ) : (
          <div className="p-3">
            <label htmlFor="server-api-key" className="block text-xs text-slate-400 mb-1.5">
              API Token
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
        )}

        {/* PIN / License ID */}
        {isQr ? (
          pin ? <ReadOnlyField label="PIN / License ID" value={pin} masked /> : null
        ) : (
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
        )}

        {/* User Name */}
        {isQr ? (
          ackUser ? <ReadOnlyField label="User Name" value={ackUser} /> : null
        ) : (
          <div className="p-3">
            <label htmlFor="server-ack-user" className="block text-xs text-slate-400 mb-1.5">
              User Name <span className="text-slate-600">(for incident ACK/UnACK)</span>
            </label>
            <input
              id="server-ack-user"
              type="text"
              placeholder="e.g. your.name"
              value={ackUser}
              onChange={(e) => setAckUser(e.target.value)}
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* Push Toggle */}
        <div className="p-3 flex items-center justify-between">
          <div className="text-xs text-slate-400">Enable Push Notifications</div>
          <button
            type="button"
            onClick={() => setPushEnabled(!pushEnabled)}
            className={`relative w-11 h-6 rounded-full transition-colors ${
              pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
            }`}
            role="switch"
            aria-checked={pushEnabled}
            aria-label="Enable Push Notifications"
          >
            <span
              className="block w-5 h-5 rounded-full bg-white shadow transition-transform"
              style={{ transform: pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
            />
          </button>
        </div>

        {/* Webhook Secret */}
        {isQr ? (
          webhookSecret ? <ReadOnlyField label="Webhook Secret" value={webhookSecret} masked /> : null
        ) : (
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
        )}
      </div>

      {/* Test result feedback */}
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
          <span className="text-red-400 text-sm font-semibold">Connection Failed</span>
          <p className="text-xs text-slate-400 mt-1">{testError}</p>
        </div>
      )}

      {/* Save button */}
      <button
        type="submit"
        disabled={saveDisabled}
        className="w-full px-4 py-3 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-sm font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {testState === 'testing' ? 'Testing connection...' : 'Save'}
      </button>

      {/* Delete button — edit mode only */}
      {isEditing && onDelete && (
        showDeleteConfirm ? (
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onDelete}
              className="flex-1 px-3 py-2.5 rounded-lg bg-red-600 hover:bg-red-500 text-sm font-semibold"
            >
              Confirm Delete
            </button>
            <button
              type="button"
              onClick={() => setShowDeleteConfirm(false)}
              className="flex-1 px-3 py-2.5 rounded-lg bg-slate-800 border border-slate-700 text-sm"
            >
              Cancel
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setShowDeleteConfirm(true)}
            className="w-full px-4 py-3 rounded-lg border border-red-500/50 text-red-400 text-sm font-semibold hover:bg-red-500/10"
            aria-label="Delete server"
          >
            Delete Server
          </button>
        )
      )}

      {/* Cancel */}
      <button
        type="button"
        onClick={onCancel}
        className="w-full px-4 py-2.5 rounded-lg bg-slate-900 border border-slate-700 hover:bg-slate-800 text-sm text-slate-400"
      >
        Cancel
      </button>

      <p className="text-xs text-slate-500 px-1 text-center">
        {isQr ? 'Configured via QR code. Scan again to update.' : 'Stored in your browser only.'}
      </p>
    </form>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/settings/__tests__/ServerForm.test.tsx`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/settings/ServerForm.tsx pwa/src/features/settings/__tests__/ServerForm.test.tsx
git commit -m "feat(pwa): ServerForm read-only mode, new fields, save-with-test"
```

---

### Task 6: Server Switch Confirmation Dialog

**Files:**
- Modify: `pwa/src/features/settings/ServerListSection.tsx`

- [ ] **Step 1: Add confirmation state and dialog**

Replace the entire contents of `pwa/src/features/settings/ServerListSection.tsx`:

```typescript
import { useState } from 'react';
import {
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
  const [switchTarget, setSwitchTarget] = useState<ServerConfig | null>(null);

  const handleSwitch = (server: ServerConfig) => {
    if (server.isActive) {
      onEditServer(server);
      return;
    }
    setSwitchTarget(server);
  };

  const confirmSwitch = () => {
    if (!switchTarget) return;
    setActiveServer(switchTarget.id);
    notifyConfigChanged();
    onServersChanged();
    setSwitchTarget(null);
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
              onClick={() => handleSwitch(server)}
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
              <div className="text-xs text-slate-500">{server.bhnmUrl || server.baseUrl}</div>
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

      {/* Switch confirmation dialog */}
      {switchTarget && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center">
          <div className="bg-slate-900 border border-slate-700 rounded-xl p-5 mx-4 max-w-sm w-full shadow-2xl">
            <h3 className="text-lg font-semibold text-white text-center">{switchTarget.name}</h3>
            <p className="text-sm text-slate-400 text-center mt-2">Switch to this server?</p>
            <div className="flex gap-3 mt-5">
              <button
                type="button"
                onClick={() => setSwitchTarget(null)}
                className="flex-1 py-2.5 rounded-lg bg-slate-800 border border-slate-700 text-sm text-slate-300 hover:bg-slate-700"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmSwitch}
                className="flex-1 py-2.5 rounded-lg bg-sky-600 text-sm text-white font-semibold hover:bg-sky-500"
              >
                Switch
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/settings/ServerListSection.tsx
git commit -m "feat(pwa): add server switch confirmation dialog"
```

---

### Task 7: QRConfirmScreen — Show New Fields

**Files:**
- Modify: `pwa/src/features/scanner/QRConfirmScreen.tsx`
- Test: `pwa/src/features/scanner/QRConfirmScreen.test.tsx`

- [ ] **Step 1: Update test mock and expectations**

Replace the entire contents of `pwa/src/features/scanner/QRConfirmScreen.test.tsx`:

```typescript
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QRConfirmScreen } from './QRConfirmScreen';
import type { ParsedServerConfig } from '../../lib/qr-parser';

const mockConfig: ParsedServerConfig = {
  name: 'Test Server',
  baseUrl: 'https://middleware.example.com',
  bhnmUrl: 'https://bhnm.example.com',
  apiKey: 'secret-api-key-12345',
  pin: '1234',
  ackUser: 'admin',
  pushWebhookSecret: 'webhooksecret',
};

describe('QRConfirmScreen', () => {
  it('displays parsed server information including new fields', () => {
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={vi.fn()} onCancel={vi.fn()} />,
    );
    expect(screen.getByText('Test Server')).toBeInTheDocument();
    expect(screen.getByText('https://bhnm.example.com')).toBeInTheDocument();
    expect(screen.getByText('https://middleware.example.com')).toBeInTheDocument();
    expect(screen.getByText('admin')).toBeInTheDocument();
    expect(screen.getByText(/\*\*\*/)).toBeInTheDocument(); // masked API key
  });

  it('calls onConfirm when Add Server is clicked', () => {
    const onConfirm = vi.fn();
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={onConfirm} onCancel={vi.fn()} />,
    );
    fireEvent.click(screen.getByRole('button', { name: /add server/i }));
    expect(onConfirm).toHaveBeenCalled();
  });

  it('calls onCancel when Cancel is clicked', () => {
    const onCancel = vi.fn();
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={vi.fn()} onCancel={onCancel} />,
    );
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });

  it('shows Update button when existing server matches', () => {
    render(
      <QRConfirmScreen
        config={mockConfig}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
        existingServerId="abc123"
      />,
    );
    expect(screen.getByRole('button', { name: /update server/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Update QRConfirmScreen to show new fields**

Replace the entire contents of `pwa/src/features/scanner/QRConfirmScreen.tsx`:

```typescript
import type { ParsedServerConfig } from '../../lib/qr-parser';

interface QRConfirmScreenProps {
  config: ParsedServerConfig;
  onConfirm: () => void;
  onCancel: () => void;
  existingServerId?: string;
}

function maskKey(key: string): string {
  if (key.length <= 6) return '***';
  return key.slice(0, 3) + '***' + key.slice(-3);
}

export function QRConfirmScreen({
  config,
  onConfirm,
  onCancel,
  existingServerId,
}: QRConfirmScreenProps) {
  const isUpdate = !!existingServerId;

  return (
    <div className="p-4 space-y-4 max-w-md">
      <h2 className="text-lg font-semibold text-white">
        {isUpdate ? 'Update Server' : 'Add Server'}
      </h2>
      <p className="text-sm text-slate-400">
        {isUpdate
          ? 'A server with this URL already exists. Update its configuration?'
          : 'Add this server to your configuration?'}
      </p>
      <div className="bg-slate-900 rounded-lg p-4 space-y-2">
        <InfoRow label="Name" value={config.name} />
        {config.bhnmUrl && <InfoRow label="BHNM URL" value={config.bhnmUrl} />}
        <InfoRow label="Middleware URL" value={config.baseUrl} />
        <InfoRow label="API Key" value={maskKey(config.apiKey)} />
        {config.pin && <InfoRow label="PIN" value="••••" />}
        {config.ackUser && <InfoRow label="User Name" value={config.ackUser} />}
        {config.pushWebhookSecret && <InfoRow label="Push Secret" value="[set]" />}
      </div>
      <div className="flex gap-3">
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 py-2.5 rounded-lg bg-slate-800 text-sm text-white hover:bg-slate-700"
          aria-label="Cancel"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onConfirm}
          className="flex-1 py-2.5 rounded-lg bg-sky-600 text-sm text-white hover:bg-sky-500"
          aria-label={isUpdate ? 'Update Server' : 'Add Server'}
        >
          {isUpdate ? 'Update Server' : 'Add Server'}
        </button>
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-center text-sm">
      <span className="text-slate-500">{label}</span>
      <span className="text-slate-200 font-mono text-xs break-all text-right max-w-[60%]">{value}</span>
    </div>
  );
}
```

- [ ] **Step 3: Run tests**

Run: `cd pwa && npx vitest run src/features/scanner/QRConfirmScreen.test.tsx`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add pwa/src/features/scanner/QRConfirmScreen.tsx pwa/src/features/scanner/QRConfirmScreen.test.tsx
git commit -m "feat(pwa): QRConfirmScreen shows BHNM URL, Middleware URL, User Name"
```

---

### Task 8: SettingsScreen — Wire Up New Fields and Delete

**Files:**
- Modify: `pwa/src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Update QR scan confirm to pass new fields**

In `pwa/src/features/settings/SettingsScreen.tsx`, update the `handleScanResult` function (line 98-109). Change the duplicate detection to match by `bhnmUrl`:

```typescript
  const handleScanResult = async (decodedText: string) => {
    setShowScanner(false);
    try {
      const config = await parseQRUrl(decodedText);
      const existing = loadServers().find((s) =>
        (config.bhnmUrl && s.bhnmUrl === config.bhnmUrl) || s.baseUrl === config.baseUrl,
      );
      setExistingServerId(existing?.id);
      setScannedConfig(config);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Could not read QR code';
      setScanError(msg);
    }
  };
```

Update `handleScanConfirm` (line 111-136) to pass new fields and set `isQrProvisioned`:

```typescript
  const handleScanConfirm = () => {
    if (!scannedConfig) return;
    if (existingServerId) {
      updateServer(existingServerId, {
        name: scannedConfig.name,
        baseUrl: scannedConfig.baseUrl,
        bhnmUrl: scannedConfig.bhnmUrl,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        ackUser: scannedConfig.ackUser ?? '',
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
        isQrProvisioned: true,
      });
    } else {
      addServer({
        name: scannedConfig.name,
        baseUrl: scannedConfig.baseUrl,
        bhnmUrl: scannedConfig.bhnmUrl,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        ackUser: scannedConfig.ackUser ?? '',
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
        isQrProvisioned: true,
      });
    }
    notifyConfigChanged();
    refreshServers();
    setScannedConfig(null);
    setExistingServerId(undefined);
    queryClient.invalidateQueries();
  };
```

- [ ] **Step 2: Add delete handler and pass onDelete to ServerForm**

Add a `handleDeleteServer` function after `handleEditServer`:

```typescript
  const handleDeleteServer = () => {
    if (!editingServer) return;
    removeServer(editingServer.id);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    setEditingServer(null);
    queryClient.invalidateQueries();
  };
```

Add `removeServer` to the imports from `serverStorage`:

```typescript
import {
  loadServers,
  addServer,
  updateServer,
  removeServer,
  type ServerConfig,
  type NewServerInput,
} from '../../lib/serverStorage';
```

Update both `<ServerForm>` render calls to pass `onDelete`:

For the edit view (around line 255-260):

```typescript
        {view === 'edit' && editingServer && (
          <ServerForm
            server={editingServer}
            onSave={handleEditServer}
            onCancel={() => { setView('list'); setEditingServer(null); }}
            onDelete={handleDeleteServer}
          />
        )}
```

- [ ] **Step 3: Remove the Push Notifications section from the list view**

The push toggle is now inside the ServerForm, so remove the push notifications section from the list view (lines 195-231 in the original). Delete the entire `{/* Push Notifications — for active server */}` block and the `pushState`, `pushLoading`, and `handleTogglePush` state/handler that are no longer needed in SettingsScreen.

Actually — keep the push toggle in SettingsScreen for now as a quick-access toggle for the active server. The ServerForm toggle controls the per-server setting. Both can coexist. Skip this sub-step.

- [ ] **Step 4: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/settings/SettingsScreen.tsx
git commit -m "feat(pwa): wire up new fields, isQrProvisioned, delete in SettingsScreen"
```

---

### Task 9: Full Test Suite and Type Check

- [ ] **Step 1: Run type checker**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 2: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS

- [ ] **Step 3: Fix any type errors or test failures**

If `tsc` reports errors, they'll likely be in files that consume `BhnmConfig` or `ServerConfig` without the new required fields. Fix by adding defaults.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A pwa/src
git commit -m "fix(pwa): resolve type errors from settings parity changes"
```
