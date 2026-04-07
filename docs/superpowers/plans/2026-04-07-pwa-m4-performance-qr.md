# PWA M4: Performance Charts + QR Scanning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline performance charts to device detail and QR-based server onboarding to settings, bringing the PWA to feature parity with iOS M4.

**Architecture:** Two independent feature modules (`features/performance/` and `features/scanner/`) sharing only types and serverStorage. Performance data flows through three BHNM API calls (categories → instances → timeseries) into React Query hooks, rendered as expandable Recharts cards. QR scanning uses html5-qrcode for camera + Web Crypto API for AES-256-GCM decryption of `benem://` URLs.

**Tech Stack:** React 18, TypeScript, Recharts (charts), html5-qrcode (camera QR), Web Crypto API (AES-256-GCM), TanStack React Query, Tailwind CSS, Vitest + React Testing Library.

---

## File Structure

### New Files

```
src/lib/api/performance.ts              — 3 API functions: categories, instances, timeseries batch
src/lib/api/performance.test.ts         — Unit tests for API parsing + filtering
src/lib/crypto.ts                       — AES-256-GCM decryption via Web Crypto
src/lib/crypto.test.ts                  — Round-trip encryption/decryption test
src/lib/qr-parser.ts                    — benem:// URL parsing (compact + legacy)
src/lib/qr-parser.test.ts              — URL parsing tests (valid, invalid, malformed)

src/features/performance/
  usePerformance.ts                     — React Query hooks for perf data
  PerformanceSection.tsx                — Category list container
  PerformanceSection.test.tsx           — Component tests
  MetricCard.tsx                        — Expandable category card
  MetricChart.tsx                       — Recharts LineChart wrapper

src/features/scanner/
  QRScannerOverlay.tsx                  — Full-screen camera overlay
  QRConfirmScreen.tsx                   — Parsed server confirmation
  QRScannerOverlay.test.tsx             — Overlay lifecycle tests
  QRConfirmScreen.test.tsx              — Confirmation display tests
```

### Modified Files

```
src/lib/api/types.ts                         — Add performance types
src/lib/api/devices.ts                       — Add deviceIndex to Device, parse dev_index from find
src/lib/api/devices.test.ts                  — Update tests for deviceIndex
src/features/devices/DeviceDetailScreen.tsx   — Replace placeholder with PerformanceSection
src/features/devices/__tests__/DeviceDetailScreen.test.tsx — Update for PerformanceSection mock
src/features/settings/SettingsScreen.tsx      — Add Scan QR Code button, version bump to 0.5.0
src/features/settings/__tests__/SettingsScreen.test.tsx    — Update for QR button
package.json                                 — Add recharts, html5-qrcode, bump to 0.5.0
```

---

## Task 1: Add Performance Types

**Files:**
- Modify: `pwa/src/lib/api/types.ts`

- [ ] **Step 1: Add performance types to types.ts**

Add after the `ApiException` class (line 28):

```typescript
export interface PerformanceCategory {
  id: string;
  category: string;
}

export interface PerformanceInstance {
  key: string;
  title: string;
  unit: string;
  statGroup: string;
  valueKey: 'value1' | 'value2';
}

export interface TimeSeriesDataPoint {
  timestamp: number;
  value: number;
}

export interface TimeSeriesResult {
  instanceDescr: string;
  metricId: string;
  datapoints: TimeSeriesDataPoint[];
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd pwa && git add src/lib/api/types.ts && git commit -m "feat(pwa): add performance metric types"
```

---

## Task 2: Add deviceIndex to Device Interface and Parser

The performance-category API requires `device_id` set to `deviceIndex` (NOT the `id` from `devices/find`). The `devices/find` response includes a `dev_index` field. We need to parse it.

**Files:**
- Modify: `pwa/src/lib/api/devices.ts`
- Create: `pwa/src/lib/api/devices.test.ts`

- [ ] **Step 1: Write test for deviceIndex parsing**

Create `pwa/src/lib/api/devices.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { parseDeviceFindResponse } from './devices';

describe('parseDeviceFindResponse', () => {
  it('parses dev_index from find response', () => {
    const raw = [
      {
        results: [
          {
            name: 'raspi-054',
            ip: '192.168.1.54',
            category: 'Linux',
            site: 'Home',
            model: 'RPi 4',
            serial_number: 'ABC',
            description: 'Test',
            dev_index: '3',
          },
        ],
      },
    ];
    const devices = parseDeviceFindResponse(raw);
    expect(devices[0].deviceIndex).toBe('3');
  });

  it('defaults deviceIndex to empty string when missing', () => {
    const raw = [
      {
        results: [
          { name: 'switch-01', ip: '10.0.0.1' },
        ],
      },
    ];
    const devices = parseDeviceFindResponse(raw);
    expect(devices[0].deviceIndex).toBe('');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/lib/api/devices.test.ts`
Expected: FAIL — `deviceIndex` property doesn't exist on Device

- [ ] **Step 3: Add deviceIndex to Device and parseDevice**

In `pwa/src/lib/api/devices.ts`, add `deviceIndex` to the `Device` interface (after `description`):

```typescript
export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
  deviceIndex: string;
}
```

In `parseDevice`, add the field:

```typescript
function parseDevice(entry: Record<string, unknown>): Device | null {
  const name = coerceString(v: unknown): string {
  // ... existing logic unchanged ...
  return {
    name,
    ip: coerceString(entry.ip) || coerceString(entry.ip_address),
    category: coerceString(entry.category),
    site: coerceString(entry.site),
    model: coerceString(entry.model),
    serialNumber: coerceString(entry.serial_number) || coerceString(entry.serialNumber),
    description: coerceString(entry.description),
    deviceIndex: coerceString(entry.dev_index) || coerceString(entry.deviceIndex),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/lib/api/devices.test.ts`
Expected: PASS

- [ ] **Step 5: Run all tests to ensure no regressions**

Run: `cd pwa && npx vitest run`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
cd pwa && git add src/lib/api/devices.ts src/lib/api/devices.test.ts && git commit -m "feat(pwa): parse deviceIndex from devices/find response"
```

---

## Task 3: Install Dependencies

**Files:**
- Modify: `pwa/package.json`

- [ ] **Step 1: Install recharts and html5-qrcode**

Run: `cd pwa && npm install recharts html5-qrcode`

- [ ] **Step 2: Verify install succeeded**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd pwa && git add package.json package-lock.json && git commit -m "chore(pwa): add recharts and html5-qrcode dependencies"
```

---

## Task 4: Performance API Module

**Files:**
- Create: `pwa/src/lib/api/performance.ts`
- Create: `pwa/src/lib/api/performance.test.ts`

- [ ] **Step 1: Write failing tests for category parsing**

Create `pwa/src/lib/api/performance.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  parsePerformanceCategories,
  parsePerformanceInstances,
  parseTimeSeriesResponse,
} from './performance';

describe('parsePerformanceCategories', () => {
  it('parses categories from BHNM response', () => {
    const raw = [
      { id: 1, category: 'CPU' },
      { id: 9, category: 'Disk' },
      { id: 'interfaces', cat: 'Network' },
    ];
    const result = parsePerformanceCategories(raw);
    expect(result).toEqual([
      { id: '1', category: 'CPU' },
      { id: '9', category: 'Disk' },
      { id: 'interfaces', category: 'Network' },
    ]);
  });

  it('normalizes Network category from "cat" to "category"', () => {
    const raw = [{ id: 'interfaces', cat: 'Network' }];
    const result = parsePerformanceCategories(raw);
    expect(result[0].category).toBe('Network');
  });

  it('handles array-wrapped response', () => {
    const raw = [[{ id: 1, category: 'CPU' }]];
    const result = parsePerformanceCategories(raw);
    expect(result).toEqual([{ id: '1', category: 'CPU' }]);
  });

  it('returns empty array for invalid input', () => {
    expect(parsePerformanceCategories(null)).toEqual([]);
    expect(parsePerformanceCategories({})).toEqual([]);
  });
});

describe('parsePerformanceInstances', () => {
  it('parses standard metric instances', () => {
    const raw = [
      { key: '1', title: 'CPU Utilization', unit: '%', type: 'oid', description: 'CPU Utilization' },
    ];
    const result = parsePerformanceInstances(raw, 'CPU');
    expect(result).toEqual([
      { key: '1', title: 'CPU Utilization', unit: '%', statGroup: 'CPU', valueKey: 'value1' },
    ]);
  });

  it('filters out per-process metrics', () => {
    const raw = [
      { key: '1', title: 'CPU Utilization', unit: '%', type: 'oid' },
      { key: '2', title: 'Utilization by Process', unit: '%', type: 'oid_pertable' },
    ];
    const result = parsePerformanceInstances(raw, 'CPU');
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('CPU Utilization');
  });

  it('filters out swap metrics', () => {
    const raw = [
      { key: '1', title: 'Memory Utilization', unit: '%', type: 'oid' },
      { key: '2', title: 'Swap Utilization', unit: '%', type: 'oid' },
    ];
    const result = parsePerformanceInstances(raw, 'Memory');
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('Memory Utilization');
  });

  it('filters out raw-byte metrics', () => {
    const raw = [
      { key: '1', title: 'Disk Utilization', unit: '%', type: 'oid' },
      { key: '2', title: 'Hard Drive Usage', unit: 'B', type: 'oid' },
    ];
    const result = parsePerformanceInstances(raw, 'Disks');
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('Disk Utilization');
  });

  it('creates in/out pairs for interface entries', () => {
    const raw = [
      {
        key: 'eth0',
        type: 'interface',
        description: 'eth0',
        bandwidth: { unit: 'Mbps' },
      },
    ];
    const result = parsePerformanceInstances(raw, 'Network');
    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({
      key: 'eth0-in',
      title: 'eth0 — In',
      unit: 'Mbps',
      statGroup: 'Network',
      valueKey: 'value1',
    });
    expect(result[1]).toEqual({
      key: 'eth0-out',
      title: 'eth0 — Out',
      unit: 'Mbps',
      statGroup: 'Network',
      valueKey: 'value2',
    });
  });
});

describe('parseTimeSeriesResponse', () => {
  it('parses datapoints[0] object with string keys and values', () => {
    const raw = {
      metrics: [
        {
          instanceDescr: 'CPU Utilization for raspi-054 (CPU Utilization)',
          metricId: 'instance_772',
          datapoints: [
            {
              '1775209800': '2.25',
              '1775210100': '3.50',
            },
          ],
        },
      ],
    };
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(1);
    expect(result[0].instanceDescr).toBe('CPU Utilization for raspi-054 (CPU Utilization)');
    expect(result[0].metricId).toBe('instance_772');
    expect(result[0].datapoints).toEqual([
      { timestamp: 1775209800, value: 2.25 },
      { timestamp: 1775210100, value: 3.5 },
    ]);
  });

  it('handles multiple metrics in one response', () => {
    const raw = {
      metrics: [
        {
          instanceDescr: 'CPU Utilization',
          metricId: 'a',
          datapoints: [{ '100': '1.0' }],
        },
        {
          instanceDescr: 'CPU Cores',
          metricId: 'b',
          datapoints: [{ '100': '2.0' }],
        },
      ],
    };
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(2);
  });

  it('returns empty array for missing metrics', () => {
    expect(parseTimeSeriesResponse({})).toEqual([]);
    expect(parseTimeSeriesResponse(null)).toEqual([]);
  });

  it('handles array-wrapped response', () => {
    const raw = [
      {
        metrics: [
          {
            instanceDescr: 'Test',
            metricId: 'x',
            datapoints: [{ '100': '5.0' }],
          },
        ],
      },
    ];
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/lib/api/performance.test.ts`
Expected: FAIL — module `./performance` not found

- [ ] **Step 3: Implement performance API module**

Create `pwa/src/lib/api/performance.ts`:

```typescript
import type { BhnmConfig } from '../config';
import { postForm } from './client';
import type { PerformanceCategory, PerformanceInstance, TimeSeriesResult, TimeSeriesDataPoint } from './types';
import { ApiException } from './types';

// --- Parsers (exported for testing) ---

export function parsePerformanceCategories(raw: unknown): PerformanceCategory[] {
  let arr: unknown[];
  if (Array.isArray(raw)) {
    arr = Array.isArray(raw[0]) ? raw[0] : raw;
  } else {
    return [];
  }

  const categories: PerformanceCategory[] = [];
  for (const entry of arr) {
    if (!entry || typeof entry !== 'object') continue;
    const obj = entry as Record<string, unknown>;
    const rawId = obj.id;
    if (rawId === undefined || rawId === null) continue;
    const id = String(rawId);
    const category = (typeof obj.category === 'string' ? obj.category : null)
      ?? (typeof obj.cat === 'string' ? obj.cat : null)
      ?? '';
    if (!category) continue;
    categories.push({ id, category });
  }
  return categories;
}

const FILTERED_TITLE_PATTERNS = ['by process', 'swap'];

export function parsePerformanceInstances(
  raw: unknown,
  statGroup: string,
): PerformanceInstance[] {
  if (!Array.isArray(raw)) return [];

  const instances: PerformanceInstance[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== 'object') continue;
    const obj = entry as Record<string, unknown>;
    const rawKey = typeof obj.key === 'string' ? obj.key
      : typeof obj.key === 'number' ? String(obj.key)
      : '';
    const type = typeof obj.type === 'string' ? obj.type : '';
    const title = typeof obj.title === 'string' ? obj.title : rawKey;
    const unit = typeof obj.unit === 'string' ? obj.unit : '';

    // Filter per-process, swap, raw-byte duplicates (matching iOS logic)
    const titleLower = title.toLowerCase();
    if (FILTERED_TITLE_PATTERNS.some((p) => titleLower.includes(p))) continue;
    if (unit === 'B') continue;

    if (type === 'interface') {
      const description = typeof obj.description === 'string' ? obj.description : rawKey;
      const bw = obj.bandwidth as Record<string, unknown> | undefined;
      const bwUnit = (bw && typeof bw.unit === 'string') ? bw.unit : '%';
      instances.push({
        key: `${rawKey}-in`,
        title: `${description} — In`,
        unit: bwUnit,
        statGroup,
        valueKey: 'value1',
      });
      instances.push({
        key: `${rawKey}-out`,
        title: `${description} — Out`,
        unit: bwUnit,
        statGroup,
        valueKey: 'value2',
      });
    } else {
      instances.push({
        key: rawKey,
        title,
        unit,
        statGroup,
        valueKey: 'value1',
      });
    }
  }
  return instances;
}

export function parseTimeSeriesResponse(raw: unknown): TimeSeriesResult[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;
  const metrics = obj.metrics;
  if (!Array.isArray(metrics)) return [];

  const results: TimeSeriesResult[] = [];
  for (const metric of metrics) {
    if (!metric || typeof metric !== 'object') continue;
    const m = metric as Record<string, unknown>;
    const instanceDescr = typeof m.instanceDescr === 'string' ? m.instanceDescr : '';
    const metricId = typeof m.metricId === 'string' ? m.metricId : '';
    const dpArr = m.datapoints;
    const datapoints: TimeSeriesDataPoint[] = [];

    if (Array.isArray(dpArr) && dpArr.length > 0 && dpArr[0] && typeof dpArr[0] === 'object') {
      for (const [tsKey, rawValue] of Object.entries(dpArr[0] as Record<string, unknown>)) {
        const timestamp = Number(tsKey);
        if (isNaN(timestamp)) continue;
        const value = typeof rawValue === 'string' ? parseFloat(rawValue)
          : typeof rawValue === 'number' ? rawValue
          : NaN;
        if (isNaN(value)) continue;
        datapoints.push({ timestamp, value });
      }
      datapoints.sort((a, b) => a.timestamp - b.timestamp);
    }

    results.push({ instanceDescr, metricId, datapoints });
  }
  return results;
}

// --- API Functions ---

export async function fetchPerformanceCategories(
  config: BhnmConfig,
  deviceId: string,
): Promise<PerformanceCategory[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    device_id: deviceId,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/performance-category',
    params,
  );
  return parsePerformanceCategories(raw);
}

export async function fetchPerformanceInstances(
  config: BhnmConfig,
  deviceId: string,
  categoryId: string,
  statGroup: string,
): Promise<PerformanceInstance[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    device_id: deviceId,
    id: categoryId,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/performance-instance-per-category',
    params,
  );
  return parsePerformanceInstances(raw, statGroup);
}

const EMPTY_UNIT_OVERRIDES: Record<string, string> = {
  'Running Processes': 'Processes',
};

export async function fetchTimeSeriesBatch(
  config: BhnmConfig,
  deviceName: string,
  statGroup: string,
  units: string,
  metricTitle?: string,
): Promise<TimeSeriesResult[]> {
  // For empty-unit metrics, use the title as metricFilterUnits (with overrides)
  const apiUnits = units === ''
    ? (metricTitle ? (EMPTY_UNIT_OVERRIDES[metricTitle] ?? metricTitle) : statGroup)
    : units;

  // timeseries-metrics requires multipart/form-data
  const boundary = `Boundary-${crypto.randomUUID()}`;
  const fields: [string, string][] = [
    ['password', config.apiKey],
    ['groupFilterBy', 'device'],
    ['groupFilterValue', deviceName],
    ['metricFilterStatGroup', statGroup],
    ['metricFilterUnits', apiUnits],
    ['timeFrameFilterBy', 'time_offset'],
    ['timeFrameFilterValue', 'Last 24 Hours'],
    ['returnFormatFilterBy', 'average'],
  ];
  if (config.pin) fields.push(['pin', config.pin]);

  let body = '';
  for (const [name, value] of fields) {
    body += `--${boundary}\r\n`;
    body += `Content-Disposition: form-data; name="${name}"\r\n\r\n`;
    body += `${value}\r\n`;
  }
  body += `--${boundary}--\r\n`;

  let response: Response;
  try {
    response = await fetch(
      `${config.baseUrl}/fw/index.php?r=restful/devices/timeseries-metrics`,
      {
        method: 'POST',
        headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}` },
        body,
      },
    );
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

  let json: unknown;
  try {
    json = await response.json();
  } catch (err) {
    throw new ApiException({
      kind: 'parse',
      message: err instanceof Error ? err.message : 'JSON parse error',
    });
  }
  return parseTimeSeriesResponse(json);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pwa && npx vitest run src/lib/api/performance.test.ts`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd pwa && git add src/lib/api/performance.ts src/lib/api/performance.test.ts && git commit -m "feat(pwa): add performance API module with category, instance, and timeseries parsing"
```

---

## Task 5: React Query Hooks for Performance Data

**Files:**
- Create: `pwa/src/features/performance/usePerformance.ts`

- [ ] **Step 1: Create performance hooks**

Create `pwa/src/features/performance/usePerformance.ts`:

```typescript
import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import {
  fetchPerformanceCategories,
  fetchPerformanceInstances,
  fetchTimeSeriesBatch,
} from '../../lib/api/performance';

export function usePerformanceCategories(deviceIndex: string) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-categories', config.serverId, deviceIndex],
    queryFn: () => fetchPerformanceCategories(config, deviceIndex),
    enabled: config.isConfigured && deviceIndex !== '',
    staleTime: 5 * 60 * 1000,
  });
}

export function usePerformanceInstances(
  deviceIndex: string,
  categoryId: string,
  statGroup: string,
  enabled: boolean,
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-instances', config.serverId, deviceIndex, categoryId],
    queryFn: () => fetchPerformanceInstances(config, deviceIndex, categoryId, statGroup),
    enabled: config.isConfigured && enabled && deviceIndex !== '',
    staleTime: 5 * 60 * 1000,
  });
}

export function useTimeSeriesBatch(
  deviceName: string,
  statGroup: string,
  units: string,
  metricTitle: string | undefined,
  enabled: boolean,
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-timeseries', config.serverId, deviceName, statGroup, units],
    queryFn: () => fetchTimeSeriesBatch(config, deviceName, statGroup, units, metricTitle),
    enabled: config.isConfigured && enabled,
    staleTime: 60 * 1000,
  });
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd pwa && git add src/features/performance/usePerformance.ts && git commit -m "feat(pwa): add React Query hooks for performance data"
```

---

## Task 6: MetricChart Component

**Files:**
- Create: `pwa/src/features/performance/MetricChart.tsx`

- [ ] **Step 1: Create MetricChart component**

Create `pwa/src/features/performance/MetricChart.tsx`:

```tsx
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart,
  Legend,
} from 'recharts';
import type { TimeSeriesResult } from '../../lib/api/types';

interface MetricChartProps {
  series: TimeSeriesResult[];
  unit: string;
}

const COLORS = ['#38bdf8', '#f472b6', '#a78bfa', '#34d399', '#fbbf24', '#fb923c'];

function formatTime(ts: number): string {
  const d = new Date(ts * 1000);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
}

function formatTooltipTime(ts: number): string {
  const d = new Date(ts * 1000);
  return d.toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

export function MetricChart({ series, unit }: MetricChartProps) {
  if (series.length === 0) return null;

  // Single series: use AreaChart with gradient fill
  if (series.length === 1) {
    const data = series[0].datapoints.map((dp) => ({
      ts: dp.timestamp,
      value: dp.value,
    }));

    return (
      <ResponsiveContainer width="100%" height={200}>
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
          <defs>
            <linearGradient id="areaGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#38bdf8" stopOpacity={0.3} />
              <stop offset="100%" stopColor="#38bdf8" stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis
            dataKey="ts"
            tickFormatter={formatTime}
            tick={{ fill: '#94a3b8', fontSize: 11 }}
            axisLine={{ stroke: '#334155' }}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: '#94a3b8', fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            unit={unit ? ` ${unit}` : ''}
            width={60}
          />
          <Tooltip
            contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #334155', borderRadius: 8 }}
            labelStyle={{ color: '#94a3b8' }}
            itemStyle={{ color: '#e2e8f0' }}
            labelFormatter={(ts) => formatTooltipTime(ts as number)}
            formatter={(value: number) => [`${value.toFixed(2)} ${unit}`, '']}
          />
          <Area
            type="monotone"
            dataKey="value"
            stroke="#38bdf8"
            strokeWidth={2}
            fill="url(#areaGrad)"
          />
        </AreaChart>
      </ResponsiveContainer>
    );
  }

  // Multi-series: use LineChart with legend
  // Build combined data: each point has ts + one key per series
  const allTimestamps = new Set<number>();
  for (const s of series) {
    for (const dp of s.datapoints) {
      allTimestamps.add(dp.timestamp);
    }
  }
  const sortedTs = [...allTimestamps].sort((a, b) => a - b);

  const seriesKeys = series.map((s, i) => {
    // Extract a short label from instanceDescr
    const descr = s.instanceDescr;
    const match = descr.match(/on (.+?) \(/);
    return match ? match[1] : `Series ${i + 1}`;
  });

  const data = sortedTs.map((ts) => {
    const point: Record<string, number> = { ts };
    for (let i = 0; i < series.length; i++) {
      const dp = series[i].datapoints.find((d) => d.timestamp === ts);
      if (dp) point[seriesKeys[i]] = dp.value;
    }
    return point;
  });

  return (
    <ResponsiveContainer width="100%" height={200}>
      <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
        <XAxis
          dataKey="ts"
          tickFormatter={formatTime}
          tick={{ fill: '#94a3b8', fontSize: 11 }}
          axisLine={{ stroke: '#334155' }}
          tickLine={false}
        />
        <YAxis
          tick={{ fill: '#94a3b8', fontSize: 11 }}
          axisLine={false}
          tickLine={false}
          unit={unit ? ` ${unit}` : ''}
          width={60}
        />
        <Tooltip
          contentStyle={{ backgroundColor: '#1e293b', border: '1px solid #334155', borderRadius: 8 }}
          labelStyle={{ color: '#94a3b8' }}
          itemStyle={{ color: '#e2e8f0' }}
          labelFormatter={(ts) => formatTooltipTime(ts as number)}
          formatter={(value: number) => `${value.toFixed(2)} ${unit}`}
        />
        <Legend
          wrapperStyle={{ fontSize: 11, color: '#94a3b8' }}
        />
        {seriesKeys.map((key, i) => (
          <Line
            key={key}
            type="monotone"
            dataKey={key}
            stroke={COLORS[i % COLORS.length]}
            strokeWidth={2}
            dot={false}
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd pwa && git add src/features/performance/MetricChart.tsx && git commit -m "feat(pwa): add MetricChart component with single and multi-series support"
```

---

## Task 7: MetricCard Component

**Files:**
- Create: `pwa/src/features/performance/MetricCard.tsx`

- [ ] **Step 1: Create MetricCard component**

Create `pwa/src/features/performance/MetricCard.tsx`:

```tsx
import { useState } from 'react';
import { usePerformanceInstances, useTimeSeriesBatch } from './usePerformance';
import { MetricChart } from './MetricChart';
import type { PerformanceCategory, PerformanceInstance } from '../../lib/api/types';

interface MetricCardProps {
  category: PerformanceCategory;
  deviceIndex: string;
  deviceName: string;
}

export function MetricCard({ category, deviceIndex, deviceName }: MetricCardProps) {
  const [expanded, setExpanded] = useState(false);

  const {
    data: instances,
    isLoading: instancesLoading,
    isError: instancesError,
    refetch: refetchInstances,
  } = usePerformanceInstances(deviceIndex, category.id, category.category, expanded);

  // Group instances by statGroup+unit for batch fetching
  const groups = groupByStatGroupAndUnit(instances ?? []);
  const firstGroup = groups[0];

  const {
    data: timeseries,
    isLoading: tsLoading,
    isError: tsError,
  } = useTimeSeriesBatch(
    deviceName,
    firstGroup?.statGroup ?? '',
    firstGroup?.unit ?? '',
    firstGroup?.metricTitle,
    expanded && !!firstGroup,
  );

  const isLoading = instancesLoading || tsLoading;
  const isError = instancesError || tsError;

  return (
    <div className="bg-gray-800 rounded-lg overflow-hidden">
      <button
        type="button"
        className="w-full px-4 py-3 flex items-center justify-between text-left"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-slate-200">{category.category}</span>
          {instances && (
            <span className="text-xs bg-slate-700 text-slate-400 px-1.5 py-0.5 rounded">
              {instances.length}
            </span>
          )}
        </div>
        <svg
          className={`w-4 h-4 text-slate-500 transition-transform ${expanded ? 'rotate-180' : ''}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {expanded && (
        <div className="px-4 pb-4 space-y-4">
          {isLoading && (
            <div className="flex items-center justify-center py-6">
              <div className="w-5 h-5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
            </div>
          )}

          {isError && !isLoading && (
            <div className="text-center py-4">
              <p className="text-sm text-slate-400">Failed to load metrics</p>
              <button
                type="button"
                className="mt-2 text-xs text-sky-400 hover:text-sky-300"
                onClick={() => refetchInstances()}
              >
                Retry
              </button>
            </div>
          )}

          {!isLoading && !isError && timeseries && timeseries.length === 0 && (
            <p className="text-sm text-slate-500 text-center py-4">
              No data for the last 24 hours
            </p>
          )}

          {!isLoading && !isError && timeseries && timeseries.length > 0 && (
            <MetricChart
              series={timeseries}
              unit={firstGroup?.unit ?? ''}
            />
          )}
        </div>
      )}
    </div>
  );
}

interface InstanceGroup {
  statGroup: string;
  unit: string;
  metricTitle: string | undefined;
  instances: PerformanceInstance[];
}

function groupByStatGroupAndUnit(instances: PerformanceInstance[]): InstanceGroup[] {
  const map = new Map<string, InstanceGroup>();
  for (const inst of instances) {
    const key = `${inst.statGroup}|${inst.unit}`;
    if (!map.has(key)) {
      map.set(key, {
        statGroup: inst.statGroup,
        unit: inst.unit,
        metricTitle: inst.unit === '' ? inst.title : undefined,
        instances: [],
      });
    }
    map.get(key)!.instances.push(inst);
  }
  return [...map.values()];
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd pwa && git add src/features/performance/MetricCard.tsx && git commit -m "feat(pwa): add expandable MetricCard with loading, error, and empty states"
```

---

## Task 8: PerformanceSection Container + DeviceDetail Integration

**Files:**
- Create: `pwa/src/features/performance/PerformanceSection.tsx`
- Modify: `pwa/src/features/devices/DeviceDetailScreen.tsx`

- [ ] **Step 1: Write test for PerformanceSection rendering**

Create `pwa/src/features/performance/PerformanceSection.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { PerformanceSection } from './PerformanceSection';

vi.mock('./usePerformance', () => ({
  usePerformanceCategories: vi.fn(),
}));
vi.mock('../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));

import { usePerformanceCategories } from './usePerformance';

function renderSection() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <PerformanceSection deviceIndex="3" deviceName="raspi-054" />
    </QueryClientProvider>,
  );
}

describe('PerformanceSection', () => {
  it('renders header text', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: [],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText(/Performance/)).toBeInTheDocument();
    expect(screen.getByText(/Last 24 Hours/)).toBeInTheDocument();
  });

  it('renders category cards when data is loaded', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: [
        { id: '5', category: 'Latency' },
        { id: '1', category: 'CPU' },
      ],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText('Latency')).toBeInTheDocument();
    expect(screen.getByText('CPU')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(usePerformanceCategories).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
    } as ReturnType<typeof usePerformanceCategories>);

    renderSection();
    expect(screen.getByText(/Loading/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/performance/PerformanceSection.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Create PerformanceSection component**

Create `pwa/src/features/performance/PerformanceSection.tsx`:

```tsx
import { usePerformanceCategories } from './usePerformance';
import { MetricCard } from './MetricCard';

interface PerformanceSectionProps {
  deviceIndex: string;
  deviceName: string;
}

// Sort with Latency first (matches iOS behavior)
const PRIORITY_CATEGORIES = ['Latency', 'CPU', 'Memory', 'Disk', 'Network'];

export function PerformanceSection({ deviceIndex, deviceName }: PerformanceSectionProps) {
  const { data: categories, isLoading, isError } = usePerformanceCategories(deviceIndex);

  const sortedCategories = [...(categories ?? [])].sort((a, b) => {
    const ai = PRIORITY_CATEGORIES.indexOf(a.category);
    const bi = PRIORITY_CATEGORIES.indexOf(b.category);
    const ap = ai === -1 ? PRIORITY_CATEGORIES.length : ai;
    const bp = bi === -1 ? PRIORITY_CATEGORIES.length : bi;
    return ap - bp;
  });

  return (
    <div>
      <h2 className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
        Performance · Last 24 Hours
      </h2>

      {isLoading && (
        <div className="bg-slate-900 rounded-lg p-4 flex items-center justify-center">
          <div className="w-5 h-5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
          <span className="ml-2 text-sm text-slate-400">Loading categories...</span>
        </div>
      )}

      {isError && !isLoading && (
        <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
          Could not load performance data
        </div>
      )}

      {!isLoading && !isError && sortedCategories.length === 0 && (
        <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
          No performance categories available
        </div>
      )}

      {sortedCategories.length > 0 && (
        <div className="space-y-2">
          {sortedCategories.map((cat) => (
            <MetricCard
              key={cat.id}
              category={cat}
              deviceIndex={deviceIndex}
              deviceName={deviceName}
            />
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/features/performance/PerformanceSection.test.tsx`
Expected: All PASS

- [ ] **Step 5: Integrate into DeviceDetailScreen**

In `pwa/src/features/devices/DeviceDetailScreen.tsx`:

1. Add import at top (after existing imports):
```typescript
import { PerformanceSection } from '../performance/PerformanceSection';
```

2. Replace the performance placeholder (lines 67-76):
```tsx
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
```

With:
```tsx
          {/* Performance */}
          <PerformanceSection
            deviceIndex={device.deviceIndex}
            deviceName={device.name}
          />
```

- [ ] **Step 6: Update DeviceDetailScreen test**

In `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx`:

Add mock for the performance module (after the existing vi.mock calls):
```typescript
vi.mock('../../performance/PerformanceSection', () => ({
  PerformanceSection: () => <div data-testid="perf-section">Performance</div>,
}));
```

Update the `mockDevice` to include `deviceIndex`:
```typescript
const mockDevice = {
  name: 'raspi-054',
  ip: '192.168.1.54',
  category: 'Linux',
  site: 'Home',
  model: 'RPi 4',
  serialNumber: 'ABC123',
  description: 'Test Pi',
  deviceIndex: '3',
};
```

- [ ] **Step 7: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
cd pwa && git add src/features/performance/PerformanceSection.tsx src/features/performance/PerformanceSection.test.tsx src/features/devices/DeviceDetailScreen.tsx src/features/devices/__tests__/DeviceDetailScreen.test.tsx && git commit -m "feat(pwa): add PerformanceSection and integrate into DeviceDetail, replacing placeholder"
```

---

## Task 9: AES-256-GCM Crypto Module

**Files:**
- Create: `pwa/src/lib/crypto.ts`
- Create: `pwa/src/lib/crypto.test.ts`

- [ ] **Step 1: Write crypto test**

Create `pwa/src/lib/crypto.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { decrypt } from './crypto';

// To test decryption, we need to encrypt first.
// Web Crypto API is available in jsdom via Node.js crypto.
async function encrypt(plaintext: string, hexKey: string): Promise<Uint8Array> {
  const keyBytes = new Uint8Array(hexKey.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
  // Compact format: [12-byte IV | ciphertext + 16-byte auth tag]
  const result = new Uint8Array(12 + ciphertext.byteLength);
  result.set(iv, 0);
  result.set(new Uint8Array(ciphertext), 12);
  return result;
}

const TEST_KEY = 'a'.repeat(64); // 32 bytes of 0xAA

describe('decrypt', () => {
  it('round-trips encryption and decryption', async () => {
    const plaintext = '{"bhnmURL":"https://bhnm.example.com","apiKey":"secret123"}';
    const blob = await encrypt(plaintext, TEST_KEY);
    const result = await decrypt(blob, TEST_KEY);
    expect(result).toBe(plaintext);
  });

  it('throws on wrong key', async () => {
    const blob = await encrypt('test', TEST_KEY);
    const wrongKey = 'b'.repeat(64);
    await expect(decrypt(blob, wrongKey)).rejects.toThrow();
  });

  it('throws on truncated data', async () => {
    const blob = new Uint8Array(10); // too short for IV
    await expect(decrypt(blob, TEST_KEY)).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/lib/crypto.test.ts`
Expected: FAIL — module `./crypto` not found

- [ ] **Step 3: Implement crypto module**

Create `pwa/src/lib/crypto.ts`:

```typescript
export async function decrypt(blob: Uint8Array, hexKey: string): Promise<string> {
  if (blob.length < 12 + 16) {
    throw new Error('Encrypted data too short (need at least IV + auth tag)');
  }

  const keyBytes = new Uint8Array(
    hexKey.match(/.{2}/g)!.map((b) => parseInt(b, 16)),
  );
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    'AES-GCM',
    false,
    ['decrypt'],
  );

  const iv = blob.slice(0, 12);
  const ciphertextWithTag = blob.slice(12);

  const plainBuffer = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertextWithTag,
  );
  return new TextDecoder().decode(plainBuffer);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/lib/crypto.test.ts`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd pwa && git add src/lib/crypto.ts src/lib/crypto.test.ts && git commit -m "feat(pwa): add AES-256-GCM decryption module via Web Crypto API"
```

---

## Task 10: QR URL Parser

**Files:**
- Create: `pwa/src/lib/qr-parser.ts`
- Create: `pwa/src/lib/qr-parser.test.ts`

- [ ] **Step 1: Write QR parser tests**

Create `pwa/src/lib/qr-parser.test.ts`:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { parseQRUrl, type ParsedServerConfig } from './qr-parser';

// Mock the decrypt function
vi.mock('./crypto', () => ({
  decrypt: vi.fn(),
}));
import { decrypt } from './crypto';

describe('parseQRUrl', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('rejects non-benem URLs', async () => {
    await expect(parseQRUrl('https://example.com')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('rejects benem URLs without configure host', async () => {
    await expect(parseQRUrl('benem://other')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('parses compact format with p parameter', async () => {
    const payload = JSON.stringify({
      bhnmURL: 'https://bhnm.example.com',
      middlewareURL: 'https://middleware.example.com',
      apiKey: 'mykey',
      pin: '1234',
      pushSecret: 'webhooksecret',
      name: 'Test Server',
      ackUser: 'admin',
      symbol: 'bolt',
      accentColor: '#ff0000',
    });
    vi.mocked(decrypt).mockResolvedValue(payload);

    // Create a fake base64 blob (the actual decryption is mocked)
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);

    expect(result).toEqual({
      name: 'Test Server',
      baseUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      pushMiddlewareUrl: 'https://middleware.example.com',
      pushWebhookSecret: 'webhooksecret',
    });
  });

  it('throws on compact format with missing required fields', async () => {
    vi.mocked(decrypt).mockResolvedValue(JSON.stringify({ name: 'Test' }));
    const fakeB64 = btoa('fakeciphertext');
    await expect(parseQRUrl(`benem://configure?p=${fakeB64}`))
      .rejects.toThrow('Missing required fields');
  });

  it('throws when no p parameter and no legacy parameters', async () => {
    await expect(parseQRUrl('benem://configure'))
      .rejects.toThrow('No configuration data');
  });

  it('parses legacy format with individual encrypted parameters', async () => {
    vi.mocked(decrypt)
      .mockResolvedValueOnce('https://bhnm.example.com')  // server
      .mockResolvedValueOnce('mykey')                       // api_key
      .mockResolvedValueOnce('1234')                        // pin
      .mockResolvedValueOnce('Legacy Server');               // name

    const fakeB64 = btoa('encrypted');
    const url = `benem://configure?server=${fakeB64}&api_key=${fakeB64}&pin=${fakeB64}&name=${fakeB64}`;
    const result = await parseQRUrl(url);

    expect(result).toEqual({
      name: 'Legacy Server',
      baseUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      pushMiddlewareUrl: undefined,
      pushWebhookSecret: undefined,
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/lib/qr-parser.test.ts`
Expected: FAIL — module `./qr-parser` not found

- [ ] **Step 3: Implement QR parser**

Create `pwa/src/lib/qr-parser.ts`:

```typescript
import { decrypt } from './crypto';

const QR_KEY = import.meta.env.VITE_QR_ENCRYPTION_KEY ?? '';

export interface ParsedServerConfig {
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export async function parseQRUrl(urlString: string): Promise<ParsedServerConfig> {
  let url: URL;
  try {
    url = new URL(urlString);
  } catch {
    throw new Error('Not a BeNeM configuration URL');
  }

  if (url.protocol !== 'benem:' || url.hostname !== 'configure') {
    throw new Error('Not a BeNeM configuration URL');
  }

  const params = url.searchParams;

  // Compact format: single `p` parameter
  const compactParam = params.get('p');
  if (compactParam) {
    const blob = base64ToBytes(compactParam);
    const json = await decrypt(blob, QR_KEY);
    const data = JSON.parse(json);

    if (!data.bhnmURL || !data.apiKey) {
      throw new Error('Missing required fields in QR code');
    }

    return {
      name: data.name ?? 'BHNM Server',
      baseUrl: data.bhnmURL,
      apiKey: data.apiKey,
      pin: data.pin || undefined,
      pushMiddlewareUrl: data.middlewareURL || undefined,
      pushWebhookSecret: data.pushSecret || undefined,
    };
  }

  // Legacy format: individual encrypted parameters
  const serverParam = params.get('server');
  const apiKeyParam = params.get('api_key');
  if (!serverParam || !apiKeyParam) {
    throw new Error('No configuration data in QR code');
  }

  const server = await decrypt(base64ToBytes(serverParam), QR_KEY);
  const apiKey = await decrypt(base64ToBytes(apiKeyParam), QR_KEY);

  const pinParam = params.get('pin');
  const pin = pinParam ? await decrypt(base64ToBytes(pinParam), QR_KEY) : undefined;

  const nameParam = params.get('name');
  const name = nameParam ? await decrypt(base64ToBytes(nameParam), QR_KEY) : 'BHNM Server';

  return {
    name,
    baseUrl: server,
    apiKey,
    pin: pin || undefined,
    pushMiddlewareUrl: undefined,
    pushWebhookSecret: undefined,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/lib/qr-parser.test.ts`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd pwa && git add src/lib/qr-parser.ts src/lib/qr-parser.test.ts && git commit -m "feat(pwa): add QR URL parser with compact and legacy format support"
```

---

## Task 11: QR Scanner Overlay

**Files:**
- Create: `pwa/src/features/scanner/QRScannerOverlay.tsx`
- Create: `pwa/src/features/scanner/QRScannerOverlay.test.tsx`

- [ ] **Step 1: Write scanner overlay test**

Create `pwa/src/features/scanner/QRScannerOverlay.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QRScannerOverlay } from './QRScannerOverlay';

// Mock html5-qrcode — the camera API isn't available in jsdom
vi.mock('html5-qrcode', () => ({
  Html5Qrcode: vi.fn().mockImplementation(() => ({
    start: vi.fn().mockResolvedValue(undefined),
    stop: vi.fn().mockResolvedValue(undefined),
    clear: vi.fn(),
  })),
}));

describe('QRScannerOverlay', () => {
  it('renders overlay with cancel button', () => {
    render(<QRScannerOverlay onScanned={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByText(/Point at a BeNeM QR code/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
  });

  it('calls onCancel when cancel is clicked', () => {
    const onCancel = vi.fn();
    render(<QRScannerOverlay onScanned={vi.fn()} onCancel={onCancel} />);
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/scanner/QRScannerOverlay.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Create QRScannerOverlay component**

Create `pwa/src/features/scanner/QRScannerOverlay.tsx`:

```tsx
import { useEffect, useRef } from 'react';
import { Html5Qrcode } from 'html5-qrcode';

interface QRScannerOverlayProps {
  onScanned: (decodedText: string) => void;
  onCancel: () => void;
  onError?: (error: string) => void;
}

export function QRScannerOverlay({ onScanned, onCancel, onError }: QRScannerOverlayProps) {
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const containerRef = useRef<string>('qr-reader-' + Math.random().toString(36).slice(2));

  useEffect(() => {
    const scanner = new Html5Qrcode(containerRef.current);
    scannerRef.current = scanner;

    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: 250 },
        (decodedText) => {
          scanner.stop().then(() => {
            onScanned(decodedText);
          });
        },
        undefined,
      )
      .catch((err) => {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('Permission') || msg.includes('NotAllowed')) {
          onError?.('Camera permission denied. Enable it in browser settings.');
        } else {
          onError?.(msg);
        }
      });

    return () => {
      scanner.stop().catch(() => {});
      scanner.clear();
    };
  }, [onScanned, onError]);

  return (
    <div className="fixed inset-0 z-50 bg-black flex flex-col items-center justify-center">
      <div className="relative w-full max-w-sm">
        <div id={containerRef.current} className="w-full" />
        <p className="text-center text-sm text-slate-300 mt-4">
          Point at a BeNeM QR code
        </p>
      </div>

      <button
        type="button"
        onClick={onCancel}
        className="mt-8 px-6 py-2.5 rounded-lg bg-slate-800 text-sm text-white hover:bg-slate-700"
        aria-label="Cancel"
      >
        Cancel
      </button>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/features/scanner/QRScannerOverlay.test.tsx`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd pwa && git add src/features/scanner/QRScannerOverlay.tsx src/features/scanner/QRScannerOverlay.test.tsx && git commit -m "feat(pwa): add QR scanner overlay component with camera lifecycle management"
```

---

## Task 12: QR Confirm Screen

**Files:**
- Create: `pwa/src/features/scanner/QRConfirmScreen.tsx`
- Create: `pwa/src/features/scanner/QRConfirmScreen.test.tsx`

- [ ] **Step 1: Write confirm screen test**

Create `pwa/src/features/scanner/QRConfirmScreen.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QRConfirmScreen } from './QRConfirmScreen';
import type { ParsedServerConfig } from '../../lib/qr-parser';

const mockConfig: ParsedServerConfig = {
  name: 'Test Server',
  baseUrl: 'https://bhnm.example.com',
  apiKey: 'secret-api-key-12345',
  pin: '1234',
  pushMiddlewareUrl: 'https://middleware.example.com',
  pushWebhookSecret: 'webhooksecret',
};

describe('QRConfirmScreen', () => {
  it('displays parsed server information', () => {
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={vi.fn()} onCancel={vi.fn()} />,
    );
    expect(screen.getByText('Test Server')).toBeInTheDocument();
    expect(screen.getByText('https://bhnm.example.com')).toBeInTheDocument();
    // API key should be masked
    expect(screen.getByText(/\*\*\*/)).toBeInTheDocument();
    expect(screen.getByText('https://middleware.example.com')).toBeInTheDocument();
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

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/features/scanner/QRConfirmScreen.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Create QRConfirmScreen component**

Create `pwa/src/features/scanner/QRConfirmScreen.tsx`:

```tsx
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
        <InfoRow label="URL" value={config.baseUrl} />
        <InfoRow label="API Key" value={maskKey(config.apiKey)} />
        {config.pin && <InfoRow label="PIN" value="****" />}
        {config.pushMiddlewareUrl && (
          <InfoRow label="Middleware" value={config.pushMiddlewareUrl} />
        )}
        {config.pushWebhookSecret && (
          <InfoRow label="Push Secret" value={maskKey(config.pushWebhookSecret)} />
        )}
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/features/scanner/QRConfirmScreen.test.tsx`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd pwa && git add src/features/scanner/QRConfirmScreen.tsx src/features/scanner/QRConfirmScreen.test.tsx && git commit -m "feat(pwa): add QR confirmation screen with server detail display"
```

---

## Task 13: Settings Integration — QR Scanner Button + Flow

**Files:**
- Modify: `pwa/src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Add QR scanner flow to SettingsScreen**

In `pwa/src/features/settings/SettingsScreen.tsx`:

1. Add imports at top:
```typescript
import { QRScannerOverlay } from '../scanner/QRScannerOverlay';
import { QRConfirmScreen } from '../scanner/QRConfirmScreen';
import { parseQRUrl, type ParsedServerConfig } from '../../lib/qr-parser';
import { loadServers, addServer, updateServer } from '../../lib/serverStorage';
```

Note: `addServer`, `updateServer`, `loadServers` are already imported — only add the scanner/parser imports.

2. Add state variables inside `SettingsScreen` (after existing state):
```typescript
const [showScanner, setShowScanner] = useState(false);
const [scanError, setScanError] = useState<string | null>(null);
const [scannedConfig, setScannedConfig] = useState<ParsedServerConfig | null>(null);
const [existingServerId, setExistingServerId] = useState<string | undefined>(undefined);
const hasCamera = typeof navigator !== 'undefined' && !!navigator.mediaDevices;
```

3. Add handler functions (after `handleTogglePush`):
```typescript
  const handleScanResult = async (decodedText: string) => {
    setShowScanner(false);
    try {
      const config = await parseQRUrl(decodedText);
      // Check for existing server with same URL
      const existing = loadServers().find((s) => s.baseUrl === config.baseUrl);
      setExistingServerId(existing?.id);
      setScannedConfig(config);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Could not read QR code';
      setScanError(msg);
    }
  };

  const handleScanConfirm = () => {
    if (!scannedConfig) return;
    if (existingServerId) {
      updateServer(existingServerId, {
        name: scannedConfig.name,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        pushMiddlewareUrl: scannedConfig.pushMiddlewareUrl,
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
      });
    } else {
      addServer({
        name: scannedConfig.name,
        baseUrl: scannedConfig.baseUrl,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        pushMiddlewareUrl: scannedConfig.pushMiddlewareUrl,
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
      });
    }
    notifyConfigChanged();
    refreshServers();
    setScannedConfig(null);
    setExistingServerId(undefined);
    queryClient.invalidateQueries();
  };
```

4. Add the QR button inside the `view === 'list'` block, right after `<ServerListSection ... />` (after line 113):
```tsx
            {hasCamera && (
              <button
                type="button"
                onClick={() => { setScanError(null); setShowScanner(true); }}
                className="w-full py-2.5 rounded-lg bg-slate-800 text-sm text-sky-400 hover:bg-slate-700 mt-2"
              >
                Scan QR Code
              </button>
            )}

            {scanError && (
              <div className="bg-red-900/30 border border-red-800 rounded-lg p-3 mt-2">
                <p className="text-sm text-red-300">{scanError}</p>
                <div className="flex gap-2 mt-2">
                  <button
                    type="button"
                    onClick={() => { setScanError(null); setShowScanner(true); }}
                    className="text-xs text-sky-400 hover:text-sky-300"
                  >
                    Try Again
                  </button>
                  <button
                    type="button"
                    onClick={() => { setScanError(null); setView('add'); }}
                    className="text-xs text-slate-400 hover:text-slate-300"
                  >
                    Enter Server Manually
                  </button>
                </div>
              </div>
            )}
```

5. Add overlay and confirm screen renders at the bottom of the component, before the final closing `</div>`:
```tsx
      {showScanner && (
        <QRScannerOverlay
          onScanned={handleScanResult}
          onCancel={() => setShowScanner(false)}
          onError={(msg) => { setShowScanner(false); setScanError(msg); }}
        />
      )}

      {scannedConfig && (
        <div className="fixed inset-0 z-50 bg-slate-950/90 flex items-center justify-center">
          <QRConfirmScreen
            config={scannedConfig}
            onConfirm={handleScanConfirm}
            onCancel={() => { setScannedConfig(null); setExistingServerId(undefined); }}
            existingServerId={existingServerId}
          />
        </div>
      )}
```

6. Update the version number in the About section (line 159):
```
0.4.0  →  0.5.0
```

- [ ] **Step 2: Update SettingsScreen test**

In `pwa/src/features/settings/__tests__/SettingsScreen.test.tsx`, add a mock for the scanner modules at the top (with existing mocks):

```typescript
vi.mock('../../scanner/QRScannerOverlay', () => ({
  QRScannerOverlay: () => null,
}));
vi.mock('../../scanner/QRConfirmScreen', () => ({
  QRConfirmScreen: () => null,
}));
vi.mock('../../../lib/qr-parser', () => ({
  parseQRUrl: vi.fn(),
}));
```

- [ ] **Step 3: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
cd pwa && git add src/features/settings/SettingsScreen.tsx src/features/settings/__tests__/SettingsScreen.test.tsx && git commit -m "feat(pwa): add QR scanner flow to settings with error handling and duplicate detection"
```

---

## Task 14: Version Bump + Package JSON

**Files:**
- Modify: `pwa/package.json`

- [ ] **Step 1: Bump version to 0.5.0 in package.json**

Change `"version": "0.4.0"` to `"version": "0.5.0"` in `pwa/package.json`.

- [ ] **Step 2: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: All PASS

- [ ] **Step 3: Verify build**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
cd pwa && git add package.json && git commit -m "chore(pwa): bump version to 0.5.0 for M4 release"
```

---

## Task 15: Update Feature Spec

**Files:**
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Update feature spec with M4 PWA status**

Add performance charts and QR scanning as implemented for PWA in `shared/feature-spec.md`. Mark both features as available on iOS and PWA.

- [ ] **Step 2: Commit**

```bash
git add shared/feature-spec.md && git commit -m "docs: update feature spec with PWA M4 performance charts and QR scanning"
```

---

## Summary

| Task | Feature | Files |
|------|---------|-------|
| 1 | Performance types | `types.ts` |
| 2 | deviceIndex parsing | `devices.ts`, test |
| 3 | Install deps | `package.json` |
| 4 | Performance API | `performance.ts`, test |
| 5 | React Query hooks | `usePerformance.ts` |
| 6 | MetricChart | `MetricChart.tsx` |
| 7 | MetricCard | `MetricCard.tsx` |
| 8 | PerformanceSection + integration | `PerformanceSection.tsx`, `DeviceDetailScreen.tsx`, tests |
| 9 | AES-256-GCM crypto | `crypto.ts`, test |
| 10 | QR URL parser | `qr-parser.ts`, test |
| 11 | QR scanner overlay | `QRScannerOverlay.tsx`, test |
| 12 | QR confirm screen | `QRConfirmScreen.tsx`, test |
| 13 | Settings integration | `SettingsScreen.tsx`, test |
| 14 | Version bump | `package.json` |
| 15 | Feature spec update | `feature-spec.md` |
