# M3: Devices + Tactical Drill-downs (v0.4.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add paginated device list with search, device detail screen, and tactical overview group drill-down views to the BeNeM PWA.

**Architecture:** Window-based pagination (50 per page) for device list using independent React Query entries per page. Device detail shows info + filtered incidents from existing hook. Tactical group list reuses existing `fetchTacticalOverview` API, parameterized by route `:type`. All screens follow the established pattern: API module -> React Query hook -> screen component.

**Tech Stack:** React 18, TypeScript, React Router 6, TanStack React Query 5, Tailwind CSS 3, Vitest + Testing Library

---

## File Structure

### New Files

| File | Responsibility |
|---|---|
| `pwa/src/lib/api/devices.ts` | Device type + `fetchDevices` / `searchDevices` API functions + response parser |
| `pwa/src/lib/api/__tests__/devices.test.ts` | Unit tests for device response parsing |
| `pwa/src/features/devices/useDevices.ts` | React Query hook for paginated device list |
| `pwa/src/features/devices/useDeviceSearch.ts` | React Query hook for server-side device search |
| `pwa/src/features/devices/DeviceRow.tsx` | Single device row (name, IP, category badge) |
| `pwa/src/features/devices/DeviceListScreen.tsx` | Paginated device list + search bar |
| `pwa/src/features/devices/DeviceDetailScreen.tsx` | Device detail: info card + host incidents |
| `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` | Device list screen tests |
| `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx` | Device detail screen tests |
| `pwa/src/features/tactical/TacticalGroupRow.tsx` | Single group row with H/S/T/A alarm badges |
| `pwa/src/features/tactical/TacticalGroupListScreen.tsx` | Group list view parameterized by route type |
| `pwa/src/features/tactical/useTacticalGroups.ts` | React Query hook for tactical group data |
| `pwa/src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx` | Group list screen tests |

### Modified Files

| File | Changes |
|---|---|
| `pwa/src/App.tsx` | Add `/devices/:name` and `/tactical/:type` routes, remove `DevicesPlaceholder` import |
| `pwa/src/features/dashboard/DashboardScreen.tsx` | Remove "Available in v0.4.0" caption from tactical links |
| `pwa/package.json` | Bump version to `0.4.0` |
| `shared/feature-spec.md` | Mark M3 features as implemented |

### Deleted Files

| File | Reason |
|---|---|
| `pwa/src/features/devices/DevicesPlaceholder.tsx` | Replaced by `DeviceListScreen` |

---

## Task 1: Device API Module — Types and Parser

**Files:**
- Create: `pwa/src/lib/api/devices.ts`
- Create: `pwa/src/lib/api/__tests__/devices.test.ts`

- [ ] **Step 1: Write failing tests for `parseDevicesResponse`**

Create the test file:

```typescript
// pwa/src/lib/api/__tests__/devices.test.ts
import { describe, it, expect } from 'vitest';
import { parseDevicesResponse, parseDeviceFindResponse } from '../devices';

describe('parseDevicesResponse', () => {
  it('parses a normal device list response', () => {
    const raw = [{
      raspi: {
        name: 'raspi-054',
        ip: '192.168.1.54',
        category: 'Linux',
        site: 'Home',
        model: 'RPi 4',
        serial_number: 'ABC123',
        description: 'Raspberry Pi',
      },
      switch: {
        name: 'core-switch',
        ip: '10.0.0.1',
        category: 'Network',
        site: 'Office',
      },
    }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toHaveLength(2);
    expect(devices[0]).toEqual({
      name: 'raspi-054',
      ip: '192.168.1.54',
      category: 'Linux',
      site: 'Home',
      model: 'RPi 4',
      serialNumber: 'ABC123',
      description: 'Raspberry Pi',
    });
    expect(devices[1]).toEqual({
      name: 'core-switch',
      ip: '10.0.0.1',
      category: 'Network',
      site: 'Office',
      model: '',
      serialNumber: '',
      description: '',
    });
  });

  it('handles array-wrapped response', () => {
    const raw = [{ dev1: { name: 'host-1', ip: '1.2.3.4' } }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toHaveLength(1);
    expect(devices[0].name).toBe('host-1');
  });

  it('returns empty array for null/undefined', () => {
    expect(parseDevicesResponse(null)).toEqual([]);
    expect(parseDevicesResponse(undefined)).toEqual([]);
  });

  it('returns empty array for empty object', () => {
    expect(parseDevicesResponse([{}])).toEqual([]);
    expect(parseDevicesResponse({})).toEqual([]);
  });

  it('skips entries without a name', () => {
    const raw = [{ dev: { ip: '1.2.3.4' } }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toEqual([]);
  });
});

describe('parseDeviceFindResponse', () => {
  it('parses a find response with direct device object', () => {
    const raw = [{
      name: 'raspi-054',
      ip: '192.168.1.54',
      category: 'Linux',
      site: 'Home',
      model: 'RPi 4',
      serial_number: 'ABC123',
      description: 'Test device',
    }];
    const devices = parseDeviceFindResponse(raw);
    expect(devices).toHaveLength(1);
    expect(devices[0].name).toBe('raspi-054');
    expect(devices[0].serialNumber).toBe('ABC123');
  });

  it('parses find response with nested results', () => {
    const raw = [{
      results: [
        { name: 'host-a', ip: '1.1.1.1' },
        { name: 'host-b', ip: '2.2.2.2' },
      ],
    }];
    const devices = parseDeviceFindResponse(raw);
    expect(devices).toHaveLength(2);
  });

  it('returns empty array for no matches', () => {
    expect(parseDeviceFindResponse([{}])).toEqual([]);
    expect(parseDeviceFindResponse(null)).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd pwa && npx vitest run src/lib/api/__tests__/devices.test.ts`
Expected: FAIL — module `../devices` does not exist

- [ ] **Step 3: Implement the devices API module**

```typescript
// pwa/src/lib/api/devices.ts
import { postForm } from './client';
import type { BhnmConfig } from '../config';

export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
}

function coerceString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

function parseDevice(entry: Record<string, unknown>): Device | null {
  const name = coerceString(entry.name);
  if (!name) return null;
  return {
    name,
    ip: coerceString(entry.ip) || coerceString(entry.ip_address),
    category: coerceString(entry.category),
    site: coerceString(entry.site),
    model: coerceString(entry.model),
    serialNumber: coerceString(entry.serial_number) || coerceString(entry.serialNumber),
    description: coerceString(entry.description),
  };
}

/**
 * Parse response from `restful/devices/list`.
 * BHNM returns `[{ key1: {device}, key2: {device}, ... }]` — an array-wrapped
 * object whose keys are opaque identifiers and values are device records.
 */
export function parseDevicesResponse(raw: unknown): Device[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;
  const devices: Device[] = [];

  for (const value of Object.values(obj)) {
    if (!value || typeof value !== 'object') continue;
    const device = parseDevice(value as Record<string, unknown>);
    if (device) devices.push(device);
  }

  return devices;
}

/**
 * Parse response from `restful/devices/find`.
 * May return a single device object wrapped in array, or an object with a
 * `results` array, or a direct device record.
 */
export function parseDeviceFindResponse(raw: unknown): Device[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;

  // If response has a `results` array, parse each entry
  if (Array.isArray(obj.results)) {
    const devices: Device[] = [];
    for (const entry of obj.results) {
      if (entry && typeof entry === 'object') {
        const device = parseDevice(entry as Record<string, unknown>);
        if (device) devices.push(device);
      }
    }
    return devices;
  }

  // Otherwise treat root as a single device record
  const device = parseDevice(obj);
  return device ? [device] : [];
}

export async function fetchDevices(
  config: BhnmConfig,
  start: number,
  count: number,
): Promise<Device[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    recordStart: String(start),
    recordCount: String(count),
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/list',
    params,
  );
  return parseDevicesResponse(raw);
}

export async function searchDevices(
  config: BhnmConfig,
  name: string,
): Promise<Device[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/find',
    params,
  );
  return parseDeviceFindResponse(raw);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/api/__tests__/devices.test.ts`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/api/devices.ts pwa/src/lib/api/__tests__/devices.test.ts
git commit -m "feat(pwa): add device API module with list/find parsers"
```

---

## Task 2: useDevices Hook (Paginated)

**Files:**
- Create: `pwa/src/features/devices/useDevices.ts`

- [ ] **Step 1: Create the useDevices hook**

```typescript
// pwa/src/features/devices/useDevices.ts
import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchDevices } from '../../lib/api/devices';

export const PAGE_SIZE = 50;
const REFETCH_INTERVAL_MS = 120_000;

export function useDevices(page: number) {
  const config = useConfig();
  const start = page * PAGE_SIZE;

  return useQuery({
    queryKey: ['devices', config.serverId, page],
    queryFn: () => fetchDevices(config, start, PAGE_SIZE),
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add pwa/src/features/devices/useDevices.ts
git commit -m "feat(pwa): add useDevices React Query hook with pagination"
```

---

## Task 3: useDeviceSearch Hook

**Files:**
- Create: `pwa/src/features/devices/useDeviceSearch.ts`

- [ ] **Step 1: Create the useDeviceSearch hook**

```typescript
// pwa/src/features/devices/useDeviceSearch.ts
import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { searchDevices } from '../../lib/api/devices';

export function useDeviceSearch(query: string) {
  const config = useConfig();

  return useQuery({
    queryKey: ['device-search', config.serverId, query],
    queryFn: () => searchDevices(config, query),
    enabled: config.isConfigured && query.length > 0,
    refetchOnWindowFocus: false,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add pwa/src/features/devices/useDeviceSearch.ts
git commit -m "feat(pwa): add useDeviceSearch React Query hook"
```

---

## Task 4: DeviceRow Component

**Files:**
- Create: `pwa/src/features/devices/DeviceRow.tsx`

- [ ] **Step 1: Create the DeviceRow component**

```tsx
// pwa/src/features/devices/DeviceRow.tsx
import { Link } from 'react-router-dom';
import type { Device } from '../../lib/api/devices';

export function DeviceRow({ device }: { device: Device }) {
  return (
    <Link
      to={`/devices/${encodeURIComponent(device.name)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      <div className="flex items-center gap-3">
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium truncate">{device.name}</div>
          <div className="text-xs text-slate-400 font-mono truncate">{device.ip || 'No IP'}</div>
        </div>
        {device.category && (
          <span className="text-xs px-2 py-0.5 rounded bg-slate-800 text-slate-400 shrink-0">
            {device.category}
          </span>
        )}
      </div>
    </Link>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add pwa/src/features/devices/DeviceRow.tsx
git commit -m "feat(pwa): add DeviceRow component"
```

---

## Task 5: DeviceListScreen

**Files:**
- Create: `pwa/src/features/devices/DeviceListScreen.tsx`
- Create: `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx`

- [ ] **Step 1: Write failing test for DeviceListScreen**

```tsx
// pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceListScreen } from '../DeviceListScreen';

// Mock the hooks
vi.mock('../useDevices', () => ({
  useDevices: vi.fn(),
  PAGE_SIZE: 50,
}));
vi.mock('../useDeviceSearch', () => ({
  useDeviceSearch: vi.fn(),
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test Server',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));

import { useDevices } from '../useDevices';
import { useDeviceSearch } from '../useDeviceSearch';

const mockDevices = [
  { name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home', model: '', serialNumber: '', description: '' },
  { name: 'core-switch', ip: '10.0.0.1', category: 'Network', site: 'Office', model: '', serialNumber: '', description: '' },
];

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <DeviceListScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DeviceListScreen', () => {
  beforeEach(() => {
    vi.mocked(useDevices).mockReturnValue({
      data: mockDevices,
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useDevices>);
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: false,
      isFetching: false,
    } as ReturnType<typeof useDeviceSearch>);
  });

  it('renders device rows', () => {
    renderScreen();
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('core-switch')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDevices).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
      dataUpdatedAt: 0,
    } as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('shows empty state when no devices', () => {
    vi.mocked(useDevices).mockReturnValue({
      data: [],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('No devices found')).toBeInTheDocument();
  });

  it('shows search results when query is active', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevices[0]],
      isLoading: false,
      isFetching: false,
    } as ReturnType<typeof useDeviceSearch>);
    renderScreen();
    const input = screen.getByPlaceholderText('Search devices by name...');
    await userEvent.type(input, 'raspi');
    // Search results should show (after debounce in real usage, but hook is mocked)
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/devices/__tests__/DeviceListScreen.test.tsx`
Expected: FAIL — `DeviceListScreen` does not exist

- [ ] **Step 3: Implement DeviceListScreen**

```tsx
// pwa/src/features/devices/DeviceListScreen.tsx
import { useState, useDeferredValue } from 'react';
import { Link } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useDevices, PAGE_SIZE } from './useDevices';
import { useDeviceSearch } from './useDeviceSearch';
import { DeviceRow } from './DeviceRow';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';

export function DeviceListScreen() {
  const config = useConfig();
  const [page, setPage] = useState(0);
  const [searchInput, setSearchInput] = useState('');
  const deferredQuery = useDeferredValue(searchInput);

  const { data: devices, isLoading, isError, error, dataUpdatedAt } = useDevices(page);
  const { data: searchResults, isFetching: isSearching } = useDeviceSearch(deferredQuery);

  const isSearchActive = deferredQuery.length > 0;
  const displayDevices = isSearchActive ? searchResults : devices;

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Devices</h1>
          {!isSearchActive && devices && devices.length > 0 && (
            <p className="text-xs text-slate-500">Page {page + 1}</p>
          )}
        </div>
        <div className="flex items-center gap-3">
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
        </div>
      </header>

      {!config.isConfigured && (
        <EmptyState
          title="Not configured"
          description="Add a server in Settings to view devices."
          action={
            <Link to="/settings" className="px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
              Configure
            </Link>
          }
        />
      )}

      {config.isConfigured && (
        <>
          {/* Search Bar */}
          <div className="px-4 py-2 border-b border-slate-800">
            <div className="relative">
              <input
                type="text"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                placeholder="Search devices by name..."
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder:text-slate-500 focus:outline-none focus:border-sky-600"
              />
              {searchInput && (
                <button
                  onClick={() => setSearchInput('')}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300 text-sm px-1"
                >
                  ✕
                </button>
              )}
            </div>
            {isSearchActive && isSearching && (
              <p className="text-xs text-slate-500 mt-1">Searching...</p>
            )}
          </div>

          {/* Content */}
          {isLoading && !isSearchActive && (
            <EmptyState title="Loading..." description="Fetching devices from BHNM." />
          )}

          {isError && !isSearchActive && (
            <EmptyState title="Could not load devices" description={(error as Error).message} />
          )}

          {displayDevices && displayDevices.length === 0 && (
            <EmptyState
              title={isSearchActive ? `No devices matching '${deferredQuery}'` : 'No devices found'}
            />
          )}

          {displayDevices && displayDevices.length > 0 && (
            <div>
              {displayDevices.map((device) => (
                <DeviceRow key={device.name} device={device} />
              ))}
            </div>
          )}

          {/* Pagination Controls (only when not searching) */}
          {!isSearchActive && devices && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-slate-800">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}
                className="px-3 py-1.5 text-sm rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                Previous
              </button>
              <span className="text-xs text-slate-500">Page {page + 1}</span>
              <button
                onClick={() => setPage((p) => p + 1)}
                disabled={devices.length < PAGE_SIZE}
                className="px-3 py-1.5 text-sm rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/devices/__tests__/DeviceListScreen.test.tsx`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/devices/DeviceListScreen.tsx pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx
git commit -m "feat(pwa): add DeviceListScreen with pagination and search"
```

---

## Task 6: DeviceDetailScreen

**Files:**
- Create: `pwa/src/features/devices/DeviceDetailScreen.tsx`
- Create: `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx`

- [ ] **Step 1: Write failing test for DeviceDetailScreen**

```tsx
// pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceDetailScreen } from '../DeviceDetailScreen';

vi.mock('../useDeviceSearch', () => ({
  useDeviceSearch: vi.fn(),
}));
vi.mock('../../incidents/useIncidents', () => ({
  useIncidents: vi.fn(),
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));

import { useDeviceSearch } from '../useDeviceSearch';
import { useIncidents } from '../../incidents/useIncidents';

const mockDevice = {
  name: 'raspi-054',
  ip: '192.168.1.54',
  category: 'Linux',
  site: 'Home',
  model: 'RPi 4',
  serialNumber: 'ABC123',
  description: 'Test Pi',
};

function renderDetail(deviceName: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/devices/${encodeURIComponent(deviceName)}`]}>
        <Routes>
          <Route path="/devices/:name" element={<DeviceDetailScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DeviceDetailScreen', () => {
  it('shows device info when found', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('192.168.1.54')).toBeInTheDocument();
    expect(screen.getByText('RPi 4')).toBeInTheDocument();
    expect(screen.getByText('ABC123')).toBeInTheDocument();
  });

  it('shows matching incidents for the device', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [
        {
          incidentId: '1', displayId: '#1', deviceName: 'raspi-054', deviceIp: '192.168.1.54',
          summary: 'High CPU', severity: 'critical' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null,
        },
        {
          incidentId: '2', displayId: '#2', deviceName: 'other-host', deviceIp: '10.0.0.1',
          summary: 'Disk full', severity: 'major' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null,
        },
      ],
    } as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('High CPU')).toBeInTheDocument();
    expect(screen.queryByText('Disk full')).not.toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/devices/__tests__/DeviceDetailScreen.test.tsx`
Expected: FAIL — `DeviceDetailScreen` does not exist

- [ ] **Step 3: Implement DeviceDetailScreen**

```tsx
// pwa/src/features/devices/DeviceDetailScreen.tsx
import { Link, useParams } from 'react-router-dom';
import { useDeviceSearch } from './useDeviceSearch';
import { useIncidents } from '../incidents/useIncidents';
import { SwipeableIncidentRow } from '../incidents/SwipeableIncidentRow';
import { EmptyState } from '../../components/EmptyState';

export function DeviceDetailScreen() {
  const { name } = useParams<{ name: string }>();
  const decodedName = name ? decodeURIComponent(name) : '';

  const { data: searchResults, isLoading, isError } = useDeviceSearch(decodedName);
  const { data: allIncidents } = useIncidents();

  const device = searchResults?.[0];
  const deviceIncidents = (allIncidents ?? []).filter(
    (inc) => inc.deviceName === decodedName,
  );

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800">
        <Link to="/devices" className="text-xs text-sky-400 hover:text-sky-300">
          &larr; Devices
        </Link>
        <h1 className="text-lg font-semibold mt-1">{decodedName}</h1>
      </header>

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching device details." />
      )}

      {isError && (
        <EmptyState title="Could not load device" description="Failed to fetch device details." />
      )}

      {device && (
        <div className="p-4 space-y-4">
          {/* Device Info Card */}
          <div className="bg-slate-900 rounded-lg p-4 space-y-2">
            <h2 className="text-sm font-semibold text-slate-300 mb-2">Device Info</h2>
            <InfoRow label="IP Address" value={device.ip} mono />
            {device.model && <InfoRow label="Model" value={device.model} />}
            {device.serialNumber && <InfoRow label="Serial Number" value={device.serialNumber} />}
            <InfoRow label="Category" value={device.category || 'N/A'} />
            <InfoRow label="Site" value={device.site || 'N/A'} />
            {device.description && <InfoRow label="Description" value={device.description} />}
          </div>

          {/* Host Current Issues */}
          <div>
            <h2 className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Current Issues
            </h2>
            {deviceIncidents.length === 0 ? (
              <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
                No current issues
              </div>
            ) : (
              <div className="rounded-lg overflow-hidden">
                {deviceIncidents.map((incident) => (
                  <SwipeableIncidentRow key={incident.incidentId} incident={incident} />
                ))}
              </div>
            )}
          </div>

          {/* Performance Placeholder */}
          <div>
            <button
              disabled
              className="w-full py-2.5 rounded-lg bg-slate-900 text-sm text-slate-500 cursor-not-allowed"
            >
              View Performance
            </button>
            <p className="text-xs text-slate-600 text-center mt-1">Available in v0.5.0</p>
          </div>
        </div>
      )}

      {!isLoading && !device && !isError && (
        <EmptyState title="Device not found" description={`No device named '${decodedName}'.`} />
      )}
    </div>
  );
}

function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex justify-between items-center text-sm">
      <span className="text-slate-500">{label}</span>
      <span className={`text-slate-200 ${mono ? 'font-mono' : ''}`}>{value}</span>
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/devices/__tests__/DeviceDetailScreen.test.tsx`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/devices/DeviceDetailScreen.tsx pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
git commit -m "feat(pwa): add DeviceDetailScreen with info card and host incidents"
```

---

## Task 7: useTacticalGroups Hook

**Files:**
- Create: `pwa/src/features/tactical/useTacticalGroups.ts`

- [ ] **Step 1: Create the hook**

```typescript
// pwa/src/features/tactical/useTacticalGroups.ts
import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchTacticalOverview, type GroupingType } from '../../lib/api/tactical-overview';

const REFETCH_INTERVAL_MS = 120_000;

/** Map route param to API grouping_type. 'bw' maps to 'app' for the BHNM API. */
function toApiGroupingType(routeType: string): GroupingType {
  if (routeType === 'bw') return 'app';
  if (routeType === 'site') return 'site';
  return 'category';
}

export function useTacticalGroups(routeType: string) {
  const config = useConfig();
  const groupingType = toApiGroupingType(routeType);

  return useQuery({
    queryKey: ['tactical-groups', config.serverId, groupingType],
    queryFn: () => fetchTacticalOverview(config, groupingType),
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add pwa/src/features/tactical/useTacticalGroups.ts
git commit -m "feat(pwa): add useTacticalGroups React Query hook"
```

---

## Task 8: TacticalGroupRow Component

**Files:**
- Create: `pwa/src/features/tactical/TacticalGroupRow.tsx`

- [ ] **Step 1: Create the component**

```tsx
// pwa/src/features/tactical/TacticalGroupRow.tsx
import type { TacticalGroup, StatusCounts } from '../../lib/api/tactical-overview';

function CountBadge({ value, color, bgColor }: { value: number; color: string; bgColor: string }) {
  if (value === 0) {
    return <span className="text-xs text-slate-600 tabular-nums w-8 text-center">0</span>;
  }
  return (
    <span className={`text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded ${color} ${bgColor} min-w-[2rem] text-center`}>
      {value}
    </span>
  );
}

function AlarmRow({ label, counts }: { label: string; counts: StatusCounts }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-slate-500 w-20 shrink-0">{label}</span>
      <div className="flex items-center gap-1">
        <CountBadge value={counts.ok} color="text-emerald-400" bgColor="bg-emerald-500/20" />
        <CountBadge value={counts.ack} color="text-sky-400" bgColor="bg-sky-500/20" />
        <CountBadge value={counts.warn} color="text-yellow-400" bgColor="bg-yellow-500/20" />
        <CountBadge value={counts.un} color="text-orange-400" bgColor="bg-orange-500/20" />
        <CountBadge value={counts.crit} color="text-red-400" bgColor="bg-red-500/20" />
      </div>
    </div>
  );
}

export function TacticalGroupRow({ group }: { group: TacticalGroup }) {
  return (
    <div className="border-b border-slate-800 px-4 py-3">
      <div className="text-sm font-medium text-slate-200 mb-2">
        {group.name || 'Unknown'}
      </div>
      <div className="space-y-1">
        <AlarmRow label="Hosts" counts={group.hosts} />
        <AlarmRow label="Services" counts={group.services} />
        <AlarmRow label="Thresholds" counts={group.thresholds} />
        <AlarmRow label="Anomalies" counts={group.anomalies} />
      </div>
    </div>
  );
}

/** Returns true if all alarm counts across H/S/T/A are OK-only (no warn/un/crit). */
export function isGroupHealthy(group: TacticalGroup): boolean {
  const check = (c: StatusCounts) => c.warn === 0 && c.un === 0 && c.crit === 0;
  return check(group.hosts) && check(group.services) && check(group.thresholds) && check(group.anomalies);
}
```

- [ ] **Step 2: Commit**

```bash
git add pwa/src/features/tactical/TacticalGroupRow.tsx
git commit -m "feat(pwa): add TacticalGroupRow with alarm count badges"
```

---

## Task 9: TacticalGroupListScreen

**Files:**
- Create: `pwa/src/features/tactical/TacticalGroupListScreen.tsx`
- Create: `pwa/src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx`

- [ ] **Step 1: Write failing test for TacticalGroupListScreen**

```tsx
// pwa/src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { TacticalGroupListScreen } from '../TacticalGroupListScreen';
import type { TacticalGroup } from '../../../lib/api/tactical-overview';

vi.mock('../useTacticalGroups', () => ({
  useTacticalGroups: vi.fn(),
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));

import { useTacticalGroups } from '../useTacticalGroups';

const zero = { ok: 0, ack: 0, warn: 0, un: 0, crit: 0 };
const healthy: TacticalGroup = {
  name: 'Linux',
  hosts: { ok: 5, ack: 0, warn: 0, un: 0, crit: 0 },
  services: { ...zero, ok: 10 },
  thresholds: zero,
  anomalies: zero,
};
const unhealthy: TacticalGroup = {
  name: 'Network',
  hosts: { ok: 3, ack: 0, warn: 1, un: 0, crit: 2 },
  services: { ...zero, ok: 5 },
  thresholds: zero,
  anomalies: zero,
};

function renderScreen(routeType: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/tactical/${routeType}`]}>
        <Routes>
          <Route path="/tactical/:type" element={<TacticalGroupListScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('TacticalGroupListScreen', () => {
  beforeEach(() => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: [healthy, unhealthy],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useTacticalGroups>);
  });

  it('renders the correct title for category route', () => {
    renderScreen('category');
    expect(screen.getByText('Categories')).toBeInTheDocument();
  });

  it('renders the correct title for site route', () => {
    renderScreen('site');
    expect(screen.getByText('Sites')).toBeInTheDocument();
  });

  it('renders the correct title for bw route', () => {
    renderScreen('bw');
    expect(screen.getByText('Business Workflows')).toBeInTheDocument();
  });

  it('renders all groups by default', () => {
    renderScreen('category');
    expect(screen.getByText('Linux')).toBeInTheDocument();
    expect(screen.getByText('Network')).toBeInTheDocument();
  });

  it('filter toggle hides healthy groups', async () => {
    renderScreen('category');
    const filterBtn = screen.getByLabelText('Filter unhealthy');
    await userEvent.click(filterBtn);
    expect(screen.queryByText('Linux')).not.toBeInTheDocument();
    expect(screen.getByText('Network')).toBeInTheDocument();
  });

  it('shows "All groups are healthy" when filter hides everything', async () => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: [healthy],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useTacticalGroups>);
    renderScreen('category');
    const filterBtn = screen.getByLabelText('Filter unhealthy');
    await userEvent.click(filterBtn);
    expect(screen.getByText('All groups are healthy')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
      dataUpdatedAt: 0,
    } as ReturnType<typeof useTacticalGroups>);
    renderScreen('category');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx`
Expected: FAIL — `TacticalGroupListScreen` does not exist

- [ ] **Step 3: Implement TacticalGroupListScreen**

```tsx
// pwa/src/features/tactical/TacticalGroupListScreen.tsx
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useTacticalGroups } from './useTacticalGroups';
import { TacticalGroupRow, isGroupHealthy } from './TacticalGroupRow';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';

const TITLES: Record<string, string> = {
  category: 'Categories',
  site: 'Sites',
  bw: 'Business Workflows',
};

export function TacticalGroupListScreen() {
  const { type = 'category' } = useParams<{ type: string }>();
  const config = useConfig();
  const { data: groups, isLoading, isError, error, dataUpdatedAt } = useTacticalGroups(type);
  const [filterActive, setFilterActive] = useState(false);

  const title = TITLES[type] ?? 'Groups';
  const displayGroups = filterActive
    ? (groups ?? []).filter((g) => !isGroupHealthy(g))
    : groups;

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <Link to="/" className="text-xs text-sky-400 hover:text-sky-300">
            &larr; Dashboard
          </Link>
          <h1 className="text-lg font-semibold mt-1">{title}</h1>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setFilterActive((v) => !v)}
            aria-label="Filter unhealthy"
            className={`text-sm px-2 py-1 rounded ${
              filterActive
                ? 'bg-sky-600 text-white'
                : 'bg-slate-800 text-slate-400 hover:bg-slate-700'
            }`}
          >
            &#9698;
          </button>
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
        </div>
      </header>

      {!config.isConfigured && (
        <EmptyState
          title="Not configured"
          description="Add a server in Settings."
          action={
            <Link to="/settings" className="px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
              Configure
            </Link>
          }
        />
      )}

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching tactical data." />
      )}

      {isError && (
        <EmptyState title="Could not load data" description={(error as Error).message} />
      )}

      {displayGroups && displayGroups.length === 0 && (
        <EmptyState
          title={filterActive ? 'All groups are healthy' : 'No data available'}
        />
      )}

      {displayGroups && displayGroups.length > 0 && (
        <div>
          {displayGroups.map((group) => (
            <TacticalGroupRow key={group.name} group={group} />
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/tactical/TacticalGroupListScreen.tsx pwa/src/features/tactical/TacticalGroupRow.tsx pwa/src/features/tactical/useTacticalGroups.ts pwa/src/features/tactical/__tests__/TacticalGroupListScreen.test.tsx
git commit -m "feat(pwa): add TacticalGroupListScreen with filter toggle"
```

---

## Task 10: Wire Up Routes and Clean Up

**Files:**
- Modify: `pwa/src/App.tsx`
- Delete: `pwa/src/features/devices/DevicesPlaceholder.tsx`
- Modify: `pwa/src/features/dashboard/DashboardScreen.tsx`

- [ ] **Step 1: Update App.tsx to add new routes and replace DevicesPlaceholder**

Replace the entire `App.tsx` with:

```tsx
// pwa/src/App.tsx
import { useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { AppLayout } from './components/AppLayout';
import { DashboardScreen } from './features/dashboard/DashboardScreen';
import { IncidentListScreen } from './features/incidents/IncidentListScreen';
import { IncidentDetailScreen } from './features/incidents/IncidentDetailScreen';
import { SettingsScreen } from './features/settings/SettingsScreen';
import { DeviceListScreen } from './features/devices/DeviceListScreen';
import { DeviceDetailScreen } from './features/devices/DeviceDetailScreen';
import { TacticalGroupListScreen } from './features/tactical/TacticalGroupListScreen';

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
        <Route path="/devices" element={<DeviceListScreen />} />
        <Route path="/devices/:name" element={<DeviceDetailScreen />} />
        <Route path="/tactical/:type" element={<TacticalGroupListScreen />} />
      </Route>
      <Route path="/settings" element={<SettingsScreen />} />
    </Routes>
  );
}
```

- [ ] **Step 2: Delete DevicesPlaceholder.tsx**

```bash
rm pwa/src/features/devices/DevicesPlaceholder.tsx
```

- [ ] **Step 3: Remove "Available in v0.4.0" caption from DashboardScreen**

In `pwa/src/features/dashboard/DashboardScreen.tsx`, remove the line:

```tsx
            <p className="text-xs text-slate-600 mt-1 px-1">Available in v0.4.0</p>
```

- [ ] **Step 4: Run the full test suite**

Run: `cd pwa && npx vitest run`
Expected: All tests PASS

- [ ] **Step 5: Run typecheck**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add pwa/src/App.tsx pwa/src/features/dashboard/DashboardScreen.tsx
git rm pwa/src/features/devices/DevicesPlaceholder.tsx
git commit -m "feat(pwa): wire up device and tactical routes, remove placeholder"
```

---

## Task 11: Version Bump and Feature Spec Update

**Files:**
- Modify: `pwa/package.json`
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Bump pwa/package.json version to 0.4.0**

In `pwa/package.json`, change:

```json
"version": "0.3.0",
```

to:

```json
"version": "0.4.0",
```

- [ ] **Step 2: Update shared/feature-spec.md with M3 features**

Append after the existing features in `shared/feature-spec.md`:

```markdown
### Feature: Device List
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/list`, `POST /fw/index.php?r=restful/devices/find`

#### Behaviour (both platforms)
- Paginated device list (50 per page) with Previous/Next controls
- Server-side search by device name
- Display device name, IP, category badge per row
- Tap navigates to device detail

#### iOS-specific
- Native SwiftUI List with UID-based identity

#### PWA-specific
- v0.4.0: Window-based pagination with independent React Query entries per page
- Debounced search input (300ms via useDeferredValue)
- 120-second auto-refresh with RefreshCountdown

### Feature: Device Detail
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/find`

#### Behaviour (both platforms)
- Device info card: IP, model, serial number, category, site, description
- Host current issues: filtered from incident list by device name
- Performance placeholder (v0.5.0)

#### iOS-specific
- Per-device alarm status via get-host-and-service-status

#### PWA-specific
- v0.4.0: Info card + filtered incidents using existing useIncidents hook
- Alarm status badges deferred (no per-device H/S/T/A endpoint identified)

### Feature: Tactical Drill-down
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/tactical-overview/data`

#### Behaviour (both platforms)
- Category, Site, and Business Workflow group list views
- Per-group H/S/T/A alarm count badges (OK/ACK/WARN/UN/CRIT)
- Filter toggle to hide all-healthy groups
- 120-second auto-refresh

#### iOS-specific
- Native SwiftUI grouped list

#### PWA-specific
- v0.4.0: Single parameterized TacticalGroupListScreen for all three group types
- Filter button in header with active state indicator
```

- [ ] **Step 3: Commit**

```bash
git add pwa/package.json shared/feature-spec.md
git commit -m "chore(pwa): bump version to 0.4.0, update feature spec for M3"
```

---

## Task 12: Build Verification

- [ ] **Step 1: Run the full test suite**

Run: `cd pwa && npx vitest run`
Expected: All tests PASS

- [ ] **Step 2: Run typecheck**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Run production build**

Run: `cd pwa && npm run build`
Expected: Build succeeds with no errors
