# PWA Device View Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the PWA device list and device detail views with the iOS app — adding device type icons, status colors, alarm badges, incident tickers, a header card with mini latency chart, alarm summary bar, and collapsible info/issues sections.

**Architecture:** Pure data utilities (`deviceType.ts`, `deviceAlarms.ts`) feed a new shared `DeviceTypeIcon` component and a redesigned `DeviceRow`. `DeviceListScreen` gains `useIncidents()` to build an alarm map passed to each row. `DeviceDetailScreen` is restructured around a new header card and collapsible sections. SVG icons live in `shared/icons/` as the canonical design source; `DeviceTypeIcon.tsx` inlines those paths as JSX.

**Tech Stack:** React 19, TypeScript, Tailwind CSS, Vitest + @testing-library/react, existing `usePerformanceCategories` / `usePerformanceInstances` / `useTimeSeriesBatch` hooks.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `shared/icons/device-linux.svg` | Canonical Tux icon (design source) |
| Create | `shared/icons/device-windows.svg` | Canonical Windows icon (design source) |
| Create | `shared/icons/device-router.svg` | Canonical router icon (design source) |
| Create | `shared/icons/device-switch.svg` | Canonical switch icon (design source) |
| Create | `shared/icons/device-unknown.svg` | Canonical unknown icon (design source) |
| Create | `pwa/src/lib/deviceType.ts` | `classifyDevice()` pure function |
| Create | `pwa/src/lib/deviceType.test.ts` | Unit tests for `classifyDevice()` |
| Create | `pwa/src/lib/deviceAlarms.ts` | `buildDeviceAlarmMap()` pure function |
| Create | `pwa/src/lib/deviceAlarms.test.ts` | Unit tests for `buildDeviceAlarmMap()` |
| Modify | `pwa/src/lib/api/devices.ts` | Add `DeviceStatus` type + `status` to `Device` |
| Modify | `pwa/src/lib/api/devices.test.ts` | Test `status` parsing |
| Create | `pwa/src/components/DeviceTypeIcon.tsx` | Shared icon component (inline SVG paths) |
| Create | `pwa/src/components/__tests__/DeviceTypeIcon.test.tsx` | Tests for icon + status color |
| Create | `pwa/src/features/devices/LatencyMiniChart.tsx` | Mini latency chart for detail header |
| Modify | `pwa/src/features/devices/DeviceRow.tsx` | New 3-col layout: icon + badges + ticker |
| Modify | `pwa/src/features/devices/DeviceListScreen.tsx` | Add `useIncidents`, pass alarm map to rows |
| Modify | `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx` | Update for new Device shape + alarm map |
| Modify | `pwa/src/features/devices/DeviceDetailScreen.tsx` | Header card + alarm bar + collapsibles |
| Modify | `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx` | Update for new structure |
| Modify | `pwa/tailwind.config.js` | Add `marquee` keyframe animation |

---

## Task 1: Shared SVG icon files + Tailwind marquee animation

**Files:**
- Create: `shared/icons/device-linux.svg`
- Create: `shared/icons/device-windows.svg`
- Create: `shared/icons/device-router.svg`
- Create: `shared/icons/device-switch.svg`
- Create: `shared/icons/device-unknown.svg`
- Modify: `pwa/tailwind.config.js`

- [ ] **Step 1: Create `shared/icons/` directory and write the five SVG files**

`shared/icons/device-linux.svg` — Tux penguin silhouette:
```svg
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="currentColor">
  <!-- Body -->
  <ellipse cx="12" cy="16.5" rx="6" ry="5.5"/>
  <!-- Head -->
  <ellipse cx="12" cy="7.5" rx="5" ry="5.5"/>
  <!-- Belly cutout (rendered as bg-colored ellipse in component) -->
  <!-- Eyes: two small circles punched out via mix-blend or rendered separately -->
  <!-- Wings -->
  <ellipse cx="5.5" cy="13" rx="2.5" ry="4" transform="rotate(-10 5.5 13)"/>
  <ellipse cx="18.5" cy="13" rx="2.5" ry="4" transform="rotate(10 18.5 13)"/>
  <!-- Feet -->
  <path d="M9 22 L7.5 24 M9 22 L10 24 M15 22 L13.5 24 M15 22 L16 24"/>
</svg>
```

`shared/icons/device-windows.svg` — four-pane logo:
```svg
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="currentColor">
  <rect x="2" y="2" width="9" height="9" rx="1"/>
  <rect x="13" y="2" width="9" height="9" rx="1"/>
  <rect x="2" y="13" width="9" height="9" rx="1"/>
  <rect x="13" y="13" width="9" height="9" rx="1"/>
</svg>
```

`shared/icons/device-router.svg` — box with four-directional arrows:
```svg
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
  <rect x="4" y="7" width="16" height="10" rx="2.5"/>
  <path d="M12 7V4M12 20v-3M4 12H1M23 12h-3"/>
  <path d="M12 2l-2 2 2 2M12 22l-2-2 2-2M1 12l2-2-2 2M23 12l-2-2 2 2" fill="currentColor" stroke="none"/>
</svg>
```

`shared/icons/device-switch.svg` — bidirectional swap arrows:
```svg
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 9h16M4 9l4-4M4 9l4 4"/>
  <path d="M20 15H4M20 15l-4-4M20 15l-4 4"/>
</svg>
```

`shared/icons/device-unknown.svg` — desktop monitor:
```svg
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
  <rect x="2" y="3" width="20" height="14" rx="2"/>
  <path d="M8 21h8M12 17v4"/>
</svg>
```

- [ ] **Step 2: Add `marquee` keyframe to `pwa/tailwind.config.js`**

```js
// pwa/tailwind.config.js
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
      keyframes: {
        slideInFromRight: {
          '0%': { transform: 'translateX(100%)', opacity: '0' },
          '100%': { transform: 'translateX(0)', opacity: '1' },
        },
        slideOutToLeft: {
          '0%': { transform: 'translateX(0)', opacity: '1' },
          '100%': { transform: 'translateX(-100%)', opacity: '0' },
        },
        marquee: {
          '0%': { transform: 'translateX(0)' },
          '100%': { transform: 'translateX(-50%)' },
        },
      },
      animation: {
        marquee: 'marquee 14s linear infinite',
      },
    },
  },
  plugins: [],
};
```

- [ ] **Step 3: Commit**

```bash
git add shared/icons/ pwa/tailwind.config.js
git commit -m "feat(icons): add shared SVG device type icons and marquee animation"
```

---

## Task 2: `classifyDevice()` utility

**Files:**
- Create: `pwa/src/lib/deviceType.ts`
- Create: `pwa/src/lib/deviceType.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// pwa/src/lib/deviceType.test.ts
import { describe, it, expect } from 'vitest';
import { classifyDevice } from './deviceType';
import type { Device } from './api/devices';

function device(overrides: Partial<Device>): Device {
  return {
    name: 'host', ip: '1.2.3.4', category: '', site: '',
    model: '', serialNumber: '', description: '', deviceIndex: '1',
    status: 'up',
    ...overrides,
  };
}

describe('classifyDevice', () => {
  it('classifies Linux by category', () => {
    expect(classifyDevice(device({ category: 'Linux Servers' }))).toBe('linux');
  });
  it('classifies Linux by description', () => {
    expect(classifyDevice(device({ description: 'Ubuntu linux host' }))).toBe('linux');
  });
  it('classifies Windows by category', () => {
    expect(classifyDevice(device({ category: 'Windows' }))).toBe('windows');
  });
  it('classifies router by description', () => {
    expect(classifyDevice(device({ description: 'Cisco Router' }))).toBe('router');
  });
  it('classifies switch by category', () => {
    expect(classifyDevice(device({ category: 'Network Switch' }))).toBe('switch');
  });
  it('falls back to unknown', () => {
    expect(classifyDevice(device({ category: 'Firewall', description: 'Palo Alto' }))).toBe('unknown');
  });
  it('is case-insensitive', () => {
    expect(classifyDevice(device({ category: 'LINUX' }))).toBe('linux');
    expect(classifyDevice(device({ category: 'WINDOWS Server' }))).toBe('windows');
  });
});
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd pwa && npx vitest run src/lib/deviceType.test.ts
```
Expected: FAIL — `classifyDevice` not found.

- [ ] **Step 3: Write `deviceType.ts`**

```ts
// pwa/src/lib/deviceType.ts
import type { Device } from './api/devices';

export type DeviceTypeClass = 'linux' | 'windows' | 'router' | 'switch' | 'unknown';

export function classifyDevice(device: Device): DeviceTypeClass {
  const haystack = `${device.category} ${device.description}`.toLowerCase();
  if (haystack.includes('linux')) return 'linux';
  if (haystack.includes('windows')) return 'windows';
  if (haystack.includes('router')) return 'router';
  if (haystack.includes('switch')) return 'switch';
  return 'unknown';
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd pwa && npx vitest run src/lib/deviceType.test.ts
```
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/deviceType.ts pwa/src/lib/deviceType.test.ts
git commit -m "feat(pwa): add classifyDevice utility"
```

---

## Task 3: `buildDeviceAlarmMap()` utility

**Files:**
- Create: `pwa/src/lib/deviceAlarms.ts`
- Create: `pwa/src/lib/deviceAlarms.test.ts`

- [ ] **Step 1: Write the failing tests**

```ts
// pwa/src/lib/deviceAlarms.test.ts
import { describe, it, expect } from 'vitest';
import { buildDeviceAlarmMap } from './deviceAlarms';
import type { Incident } from './api/types';

function incident(overrides: Partial<Incident>): Incident {
  return {
    incidentId: '1', displayId: '#1',
    deviceName: 'host-a', deviceIp: '1.2.3.4',
    summary: 'Test incident', severity: 'critical',
    status: 'active', incidentState: 'OPEN',
    startTime: new Date(), acknowledgedBy: null, alarmCounts: null,
    ...overrides,
  };
}

describe('buildDeviceAlarmMap', () => {
  it('returns empty map for empty incidents', () => {
    expect(buildDeviceAlarmMap([]).size).toBe(0);
  });

  it('counts critical active as red', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'critical', status: 'active' })]);
    expect(map.get('host-a')?.counts.red).toBe(1);
  });

  it('counts major/minor active as orange', () => {
    const map = buildDeviceAlarmMap([
      incident({ severity: 'major', status: 'active' }),
      incident({ incidentId: '2', severity: 'minor', status: 'active' }),
    ]);
    expect(map.get('host-a')?.counts.orange).toBe(2);
  });

  it('counts warning active as yellow', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'warning', status: 'active' })]);
    expect(map.get('host-a')?.counts.yellow).toBe(1);
  });

  it('counts acknowledged as blue regardless of severity', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'critical', status: 'acknowledged' })]);
    expect(map.get('host-a')?.counts.blue).toBe(1);
    expect(map.get('host-a')?.counts.red).toBe(0);
  });

  it('counts resolved/closed as green', () => {
    const map = buildDeviceAlarmMap([
      incident({ status: 'resolved' }),
      incident({ incidentId: '2', status: 'closed' }),
    ]);
    expect(map.get('host-a')?.counts.green).toBe(2);
  });

  it('collects activeSummaries only for active incidents, critical first', () => {
    const map = buildDeviceAlarmMap([
      incident({ incidentId: '1', severity: 'warning', status: 'active', summary: 'Warn msg' }),
      incident({ incidentId: '2', severity: 'critical', status: 'active', summary: 'Crit msg' }),
      incident({ incidentId: '3', severity: 'critical', status: 'acknowledged', summary: 'Acked' }),
    ]);
    const summaries = map.get('host-a')?.activeSummaries ?? [];
    expect(summaries[0]).toBe('Crit msg');
    expect(summaries[1]).toBe('Warn msg');
    expect(summaries).not.toContain('Acked');
  });

  it('groups incidents by deviceName', () => {
    const map = buildDeviceAlarmMap([
      incident({ deviceName: 'host-a', severity: 'critical', status: 'active' }),
      incident({ deviceName: 'host-b', severity: 'warning', status: 'active' }),
    ]);
    expect(map.get('host-a')?.counts.red).toBe(1);
    expect(map.get('host-b')?.counts.yellow).toBe(1);
  });

  it('ignores incidents with null deviceName', () => {
    const map = buildDeviceAlarmMap([incident({ deviceName: null })]);
    expect(map.size).toBe(0);
  });
});
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd pwa && npx vitest run src/lib/deviceAlarms.test.ts
```
Expected: FAIL — `buildDeviceAlarmMap` not found.

- [ ] **Step 3: Write `deviceAlarms.ts`**

```ts
// pwa/src/lib/deviceAlarms.ts
import type { Incident, AlarmCounts } from './api/types';

export interface DeviceAlarmSummary {
  counts: AlarmCounts;
  activeSummaries: string[];
}

const SEVERITY_ORDER = ['critical', 'major', 'minor', 'warning', 'informational'];

function emptyCounts(): AlarmCounts {
  return { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
}

export function buildDeviceAlarmMap(
  incidents: Incident[],
): Map<string, DeviceAlarmSummary> {
  const map = new Map<string, DeviceAlarmSummary>();

  for (const inc of incidents) {
    if (!inc.deviceName) continue;

    if (!map.has(inc.deviceName)) {
      map.set(inc.deviceName, { counts: emptyCounts(), activeSummaries: [] });
    }
    const entry = map.get(inc.deviceName)!;

    if (inc.status === 'acknowledged') {
      entry.counts.blue += 1;
    } else if (inc.status === 'active') {
      if (inc.severity === 'critical') entry.counts.red += 1;
      else if (inc.severity === 'major' || inc.severity === 'minor') entry.counts.orange += 1;
      else if (inc.severity === 'warning') entry.counts.yellow += 1;
      entry.activeSummaries.push(inc.summary);
    } else {
      // resolved or closed
      entry.counts.green += 1;
    }
  }

  // Sort active summaries: critical first
  for (const entry of map.values()) {
    const incsByDevice = incidents.filter(
      (i) => i.deviceName === [...map.entries()].find(([, v]) => v === entry)?.[0] &&
              i.status === 'active',
    );
    entry.activeSummaries.sort((a, b) => {
      const ia = incsByDevice.find((i) => i.summary === a);
      const ib = incsByDevice.find((i) => i.summary === b);
      return (SEVERITY_ORDER.indexOf(ia?.severity ?? '') - SEVERITY_ORDER.indexOf(ib?.severity ?? ''));
    });
  }

  return map;
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd pwa && npx vitest run src/lib/deviceAlarms.test.ts
```
Expected: 9 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/lib/deviceAlarms.ts pwa/src/lib/deviceAlarms.test.ts
git commit -m "feat(pwa): add buildDeviceAlarmMap utility"
```

---

## Task 4: Add `status` to `Device` type

**Files:**
- Modify: `pwa/src/lib/api/devices.ts`
- Modify: `pwa/src/lib/api/devices.test.ts`

- [ ] **Step 1: Read `pwa/src/lib/api/devices.test.ts` to understand existing tests**

```bash
cat pwa/src/lib/api/devices.test.ts
```

- [ ] **Step 2: Add `DeviceStatus` type + `status` field to `Device` and update `parseDevice`**

Replace the `Device` interface and `parseDevice` function in `pwa/src/lib/api/devices.ts`:

```ts
// After the imports, add:
export type DeviceStatus = 'up' | 'down' | 'warning' | 'critical' | 'unknown' | 'maintenance';

// Update Device interface — add status field:
export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
  deviceIndex: string;
  status: DeviceStatus;
}

// Add this helper near the top of the file:
const STATUS_MAP: Record<string, DeviceStatus> = {
  up: 'up', UP: 'up',
  down: 'down', DOWN: 'down',
  warning: 'warning', WARNING: 'warning',
  critical: 'critical', CRITICAL: 'critical',
  maintenance: 'maintenance', MAINTENANCE: 'maintenance',
};

function coerceStatus(v: unknown): DeviceStatus {
  if (typeof v === 'string') return STATUS_MAP[v] ?? 'unknown';
  return 'unknown';
}
```

Update `parseDevice` to include `status`:
```ts
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
    deviceIndex: coerceString(entry.dev_index) || coerceString(entry.deviceIndex),
    status: coerceStatus(entry.status),
  };
}
```

- [ ] **Step 3: Add `status` parsing tests to `pwa/src/lib/api/devices.test.ts`**

Open the existing test file and add these cases inside the existing describe block (after the existing tests):

```ts
it('parses status UP to "up"', () => {
  const raw = [{ data: { totalRecords: 1, devices: [
    { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
      serial_number: '', description: '', dev_index: '1', status: 'UP' }
  ]}}];
  const result = parseDevicesResponse(raw);
  expect(result.devices[0].status).toBe('up');
});

it('falls back to "unknown" for unrecognised status', () => {
  const raw = [{ data: { totalRecords: 1, devices: [
    { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
      serial_number: '', description: '', dev_index: '1', status: 'PURPLE' }
  ]}}];
  const result = parseDevicesResponse(raw);
  expect(result.devices[0].status).toBe('unknown');
});

it('defaults to "unknown" when status field is absent', () => {
  const raw = [{ data: { totalRecords: 1, devices: [
    { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
      serial_number: '', description: '', dev_index: '1' }
  ]}}];
  const result = parseDevicesResponse(raw);
  expect(result.devices[0].status).toBe('unknown');
});
```

- [ ] **Step 4: Update mock device objects in test files to include `status: 'up'`**

The existing tests in `DeviceListScreen.test.tsx` and `DeviceDetailScreen.test.tsx` use `mockDevices` without a `status` field. TypeScript will error. Update them:

In `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx`, change `mockDevices`:
```ts
const mockDevices = [
  { name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home',
    model: '', serialNumber: '', description: '', deviceIndex: '1', status: 'up' as const },
  { name: 'core-switch', ip: '10.0.0.1', category: 'Network', site: 'Office',
    model: '', serialNumber: '', description: '', deviceIndex: '2', status: 'up' as const },
];
```

In `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx`, change `mockDevice`:
```ts
const mockDevice = {
  name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home',
  model: 'RPi 4', serialNumber: 'ABC123', description: 'Test Pi',
  deviceIndex: '3', status: 'up' as const,
};
```

- [ ] **Step 5: Run all tests — verify they pass**

```bash
cd pwa && npx vitest run
```
Expected: all 196+ tests PASS (including 3 new status tests).

- [ ] **Step 6: Commit**

```bash
git add pwa/src/lib/api/devices.ts pwa/src/lib/api/devices.test.ts \
  pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx \
  pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
git commit -m "feat(pwa): add DeviceStatus type and status field to Device"
```

---

## Task 5: `DeviceTypeIcon` component

**Files:**
- Create: `pwa/src/components/DeviceTypeIcon.tsx`
- Create: `pwa/src/components/__tests__/DeviceTypeIcon.test.tsx`

- [ ] **Step 1: Write the failing tests**

```tsx
// pwa/src/components/__tests__/DeviceTypeIcon.test.tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { DeviceTypeIcon } from '../DeviceTypeIcon';

describe('DeviceTypeIcon', () => {
  it('renders without crashing for each type', () => {
    const types = ['linux', 'windows', 'router', 'switch', 'unknown'] as const;
    for (const type of types) {
      const { container } = render(<DeviceTypeIcon type={type} status="up" size={40} />);
      expect(container.querySelector('svg')).not.toBeNull();
    }
  });

  it('applies blue background for status "up"', () => {
    const { container } = render(<DeviceTypeIcon type="linux" status="up" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(2, 132, 199)'); // #0284c7
  });

  it('applies red background for status "critical"', () => {
    const { container } = render(<DeviceTypeIcon type="linux" status="critical" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(220, 38, 38)'); // #dc2626
  });

  it('applies amber background for status "warning"', () => {
    const { container } = render(<DeviceTypeIcon type="router" status="warning" size={40} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.backgroundColor).toBe('rgb(217, 119, 6)'); // #d97706
  });

  it('renders at specified size', () => {
    const { container } = render(<DeviceTypeIcon type="switch" status="up" size={52} />);
    const wrapper = container.firstElementChild as HTMLElement;
    expect(wrapper.style.width).toBe('52px');
    expect(wrapper.style.height).toBe('52px');
  });
});
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd pwa && npx vitest run src/components/__tests__/DeviceTypeIcon.test.tsx
```
Expected: FAIL — `DeviceTypeIcon` not found.

- [ ] **Step 3: Write `DeviceTypeIcon.tsx`**

```tsx
// pwa/src/components/DeviceTypeIcon.tsx
import type { DeviceTypeClass } from '../lib/deviceType';
import type { DeviceStatus } from '../lib/api/devices';

const STATUS_COLORS: Record<DeviceStatus, string> = {
  up: '#0284c7',
  down: '#dc2626',
  critical: '#dc2626',
  warning: '#d97706',
  maintenance: '#6b7280',
  unknown: '#374151',
};

function LinuxIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="white" width="60%" height="60%">
      <ellipse cx="12" cy="16.5" rx="6" ry="5.5" />
      <ellipse cx="12" cy="7.5" rx="5" ry="5.5" />
      <ellipse cx="5.5" cy="13" rx="2.5" ry="4" transform="rotate(-10 5.5 13)" />
      <ellipse cx="18.5" cy="13" rx="2.5" ry="4" transform="rotate(10 18.5 13)" />
      <path d="M9 22 L7.5 24 M9 22 L10.5 24 M15 22 L13.5 24 M15 22 L16.5 24"
        stroke="white" strokeWidth="1.2" strokeLinecap="round" fill="none" />
    </svg>
  );
}

function WindowsIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="white" width="60%" height="60%">
      <rect x="2" y="2" width="9" height="9" rx="1" />
      <rect x="13" y="2" width="9" height="9" rx="1" />
      <rect x="2" y="13" width="9" height="9" rx="1" />
      <rect x="13" y="13" width="9" height="9" rx="1" />
    </svg>
  );
}

function RouterIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" width="62%" height="62%">
      <rect x="4" y="7" width="16" height="10" rx="2.5" />
      <line x1="12" y1="7" x2="12" y2="4" />
      <line x1="12" y1="20" x2="12" y2="17" />
      <line x1="4" y1="12" x2="1" y2="12" />
      <line x1="23" y1="12" x2="20" y2="12" />
    </svg>
  );
}

function SwitchIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" width="62%" height="62%">
      <path d="M4 9h16M4 9l4-4M4 9l4 4" />
      <path d="M20 15H4M20 15l-4-4M20 15l-4 4" />
    </svg>
  );
}

function UnknownIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" width="62%" height="62%">
      <rect x="2" y="3" width="20" height="14" rx="2" />
      <line x1="8" y1="21" x2="16" y2="21" />
      <line x1="12" y1="17" x2="12" y2="21" />
    </svg>
  );
}

const ICONS: Record<DeviceTypeClass, () => JSX.Element> = {
  linux: LinuxIcon,
  windows: WindowsIcon,
  router: RouterIcon,
  switch: SwitchIcon,
  unknown: UnknownIcon,
};

interface DeviceTypeIconProps {
  type: DeviceTypeClass;
  status: DeviceStatus;
  size: number;
}

export function DeviceTypeIcon({ type, status, size }: DeviceTypeIconProps) {
  const Icon = ICONS[type];
  return (
    <div
      style={{
        width: `${size}px`,
        height: `${size}px`,
        backgroundColor: STATUS_COLORS[status],
        borderRadius: '10px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0,
      }}
    >
      <Icon />
    </div>
  );
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
cd pwa && npx vitest run src/components/__tests__/DeviceTypeIcon.test.tsx
```
Expected: 5 tests PASS.

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
cd pwa && npx vitest run
```
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add pwa/src/components/DeviceTypeIcon.tsx \
  pwa/src/components/__tests__/DeviceTypeIcon.test.tsx
git commit -m "feat(pwa): add DeviceTypeIcon component"
```

---

## Task 6: `LatencyMiniChart` component

**Files:**
- Create: `pwa/src/features/devices/LatencyMiniChart.tsx`

No unit tests for this component — it is a pure rendering component that wraps async data hooks; it will be covered by integration/visual testing in a browser. Add a smoke test to verify it renders without crashing when data is unavailable.

- [ ] **Step 1: Write `LatencyMiniChart.tsx`**

```tsx
// pwa/src/features/devices/LatencyMiniChart.tsx
import { usePerformanceCategories, usePerformanceInstances, useTimeSeriesBatch } from '../performance/usePerformance';
import type { TimeSeriesDataPoint } from '../../lib/api/types';

interface MiniChartSvgProps {
  points: TimeSeriesDataPoint[];
}

function MiniChartSvg({ points }: MiniChartSvgProps) {
  if (points.length < 2) return null;

  const values = points.map((p) => p.value);
  const maxVal = Math.max(...values);
  const minVal = Math.min(...values, 0);
  const range = maxVal - minVal || 1;

  const W = 120;
  const H = 72;
  const PAD = 4;

  const toX = (i: number) => PAD + (i / (points.length - 1)) * (W - PAD * 2);
  const toY = (v: number) => PAD + (1 - (v - minVal) / range) * (H - PAD * 2);

  const coords = points.map((p, i) => ({ x: toX(i), y: toY(p.value) }));
  const linePath = coords.map((c, i) => `${i === 0 ? 'M' : 'L'}${c.x.toFixed(1)},${c.y.toFixed(1)}`).join(' ');
  const areaPath = `${linePath} L${coords[coords.length - 1].x.toFixed(1)},${H} L${coords[0].x.toFixed(1)},${H} Z`;

  const current = values[values.length - 1];
  const lastCoord = coords[coords.length - 1];

  const formatVal = (v: number) =>
    v >= 1000 ? `${(v / 1000).toFixed(1)}s` : `${Math.round(v)}ms`;

  return (
    <div className="flex flex-col h-full min-w-0">
      <span className="text-[10px] text-slate-500 text-right mb-0.5">Latency</span>
      <div className="flex-1 relative">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="w-full h-full"
        >
          <path d={areaPath} fill="#0ea5e9" fillOpacity="0.15" />
          <path d={linePath} fill="none" stroke="#0ea5e9" strokeWidth="2" />
          <circle cx={lastCoord.x} cy={lastCoord.y} r="3" fill="#0ea5e9" />
          <text x="2" y="10" fill="#6b7280" fontSize="8">{formatVal(maxVal)}</text>
          <text x="2" y={H - 2} fill="#6b7280" fontSize="8">0</text>
        </svg>
      </div>
      <span className="text-[12px] font-bold text-sky-400 text-right mt-0.5">
        {formatVal(current)}
      </span>
    </div>
  );
}

interface LatencyMiniChartProps {
  deviceIndex: string;
  deviceName: string;
}

export function LatencyMiniChart({ deviceIndex, deviceName }: LatencyMiniChartProps) {
  const { data: categories } = usePerformanceCategories(deviceIndex);

  const latencyCategory = categories?.find((c) => c.category === 'Latency');

  const { data: instances } = usePerformanceInstances(
    deviceIndex,
    latencyCategory?.id ?? '',
    latencyCategory?.category ?? '',
    !!latencyCategory,
  );

  const firstInstance = instances?.[0];

  const { data: timeseries } = useTimeSeriesBatch(
    deviceName,
    firstInstance?.statGroup ?? '',
    firstInstance?.unit ?? '',
    firstInstance?.unit === '' ? firstInstance?.title : undefined,
    !!firstInstance,
  );

  const points = timeseries?.[0]?.datapoints ?? [];

  if (points.length < 2) return null;

  return <MiniChartSvg points={points} />;
}
```

- [ ] **Step 2: Verify TypeScript compiles cleanly**

```bash
cd pwa && npx tsc --noEmit
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/devices/LatencyMiniChart.tsx
git commit -m "feat(pwa): add LatencyMiniChart component for device detail header"
```

---

## Task 7: Redesign `DeviceRow`

**Files:**
- Modify: `pwa/src/features/devices/DeviceRow.tsx`

`DeviceRow` now receives `alarmSummary` as an optional prop. When it has `activeSummaries`, it renders the marquee ticker in the bottom-right of the row. The row height stays fixed via a spacer when there are no summaries.

- [ ] **Step 1: Replace `DeviceRow.tsx` entirely**

```tsx
// pwa/src/features/devices/DeviceRow.tsx
import { Link } from 'react-router-dom';
import type { Device } from '../../lib/api/devices';
import type { DeviceAlarmSummary } from '../../lib/deviceAlarms';
import { DeviceTypeIcon } from '../../components/DeviceTypeIcon';
import { AlarmBadges } from '../incidents/AlarmBadges';
import { classifyDevice } from '../../lib/deviceType';

const TICKER_COLOR: Record<string, string> = {
  critical: 'text-red-400',
  major: 'text-orange-400',
  minor: 'text-orange-400',
  warning: 'text-yellow-300',
  informational: 'text-slate-400',
};

function worstSeverityColor(summaries: string[], incidents: { summary: string; severity: string }[]): string {
  const order = ['critical', 'major', 'minor', 'warning', 'informational'];
  for (const sev of order) {
    if (incidents.some((i) => summaries.includes(i.summary) && i.severity === sev)) {
      return TICKER_COLOR[sev];
    }
  }
  return 'text-slate-400';
}

interface DeviceRowProps {
  device: Device;
  alarmSummary?: DeviceAlarmSummary;
}

export function DeviceRow({ device, alarmSummary }: DeviceRowProps) {
  const type = classifyDevice(device);
  const counts = alarmSummary?.counts ?? { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
  const summaries = alarmSummary?.activeSummaries ?? [];
  const hasTicker = summaries.length > 0;
  const tickerText = summaries.join(' · ');

  return (
    <Link
      to={`/devices/${encodeURIComponent(device.name)}`}
      className="flex items-stretch gap-3 px-4 py-2.5 border-b border-slate-800 hover:bg-slate-900"
    >
      {/* Device type icon */}
      <div className="self-center">
        <DeviceTypeIcon type={type} status={device.status} size={40} />
      </div>

      {/* Left info column */}
      <div className="flex-1 min-w-0 flex flex-col justify-center gap-0.5">
        <div className="text-sm font-semibold truncate">{device.name}</div>
        <div className="text-[11px] text-slate-400 font-mono">{device.ip || 'No IP'}</div>
        <div className="text-[11px] text-slate-400 truncate">
          {[device.category, device.site].filter(Boolean).join(' · ')}
        </div>
      </div>

      {/* Right column: badges top, ticker bottom */}
      <div className="flex-1 min-w-0 flex flex-col justify-between items-end gap-1">
        <AlarmBadges counts={counts} />
        {hasTicker ? (
          <div
            className="w-full overflow-hidden"
            style={{
              maskImage: 'linear-gradient(to right, transparent 0%, black 8%, black 92%, transparent 100%)',
              WebkitMaskImage: 'linear-gradient(to right, transparent 0%, black 8%, black 92%, transparent 100%)',
            }}
          >
            <div
              className="flex w-max animate-marquee"
              aria-hidden="true"
            >
              {/* Duplicated for seamless loop */}
              <span className={`text-[10px] whitespace-nowrap pr-8 ${TICKER_COLOR['critical']}`}>
                {tickerText}
              </span>
              <span className={`text-[10px] whitespace-nowrap pr-8 ${TICKER_COLOR['critical']}`}>
                {tickerText}
              </span>
            </div>
          </div>
        ) : (
          <div className="h-[14px]" />
        )}
      </div>
    </Link>
  );
}
```

Note: the ticker color simplification uses `TICKER_COLOR['critical']` as a constant — for a proper implementation replace with `worstSeverityColor(summaries, deviceIncidents)` once the incidents are passed down. In Phase 1 we use `text-red-400` for any active ticker since it implies something is wrong. Update this if you want severity-aware colors.

- [ ] **Step 2: Verify TypeScript compiles cleanly**

```bash
cd pwa && npx tsc --noEmit
```
Expected: no errors.

- [ ] **Step 3: Run existing tests — they may need updating if DeviceRow is tested directly**

```bash
cd pwa && npx vitest run
```
Fix any breakage. The `DeviceListScreen` test renders rows via the screen — if it checks for the category badge it will no longer find it in its old form.

- [ ] **Step 4: Commit**

```bash
git add pwa/src/features/devices/DeviceRow.tsx
git commit -m "feat(pwa): redesign DeviceRow with icon, alarm badges, and incident ticker"
```

---

## Task 8: Update `DeviceListScreen` to wire alarm map

**Files:**
- Modify: `pwa/src/features/devices/DeviceListScreen.tsx`
- Modify: `pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx`

- [ ] **Step 1: Add `useIncidents` and `buildDeviceAlarmMap` to `DeviceListScreen`**

Add imports at the top of `DeviceListScreen.tsx`:
```ts
import { useIncidents } from '../incidents/useIncidents';
import { buildDeviceAlarmMap } from '../../lib/deviceAlarms';
```

Inside the `DeviceListScreen` function body, after the existing hooks:
```ts
const { data: allIncidents } = useIncidents();
const deviceAlarmMap = buildDeviceAlarmMap(allIncidents ?? []);
```

Update the `DeviceRow` render to pass `alarmSummary`:
```tsx
{displayDevices.map((device) => (
  <DeviceRow
    key={device.name}
    device={device}
    alarmSummary={deviceAlarmMap.get(device.name)}
  />
))}
```

- [ ] **Step 2: Update `DeviceListScreen.test.tsx` to mock `useIncidents`**

Add this mock near the top of the test file (alongside the other `vi.mock` calls):
```ts
vi.mock('../../incidents/useIncidents', () => ({
  useIncidents: vi.fn(),
}));
```

Add the import:
```ts
import { useIncidents } from '../../incidents/useIncidents';
```

In `beforeEach`, add a default mock return:
```ts
vi.mocked(useIncidents).mockReturnValue({
  data: [],
} as unknown as ReturnType<typeof useIncidents>);
```

- [ ] **Step 3: Run tests — verify they pass**

```bash
cd pwa && npx vitest run src/features/devices/__tests__/DeviceListScreen.test.tsx
```
Expected: all tests PASS.

- [ ] **Step 4: Run full suite**

```bash
cd pwa && npx vitest run
```
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/devices/DeviceListScreen.tsx \
  pwa/src/features/devices/__tests__/DeviceListScreen.test.tsx
git commit -m "feat(pwa): wire incident alarm map into device list rows"
```

---

## Task 9: Overhaul `DeviceDetailScreen`

**Files:**
- Modify: `pwa/src/features/devices/DeviceDetailScreen.tsx`
- Modify: `pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx`

- [ ] **Step 1: Replace `DeviceDetailScreen.tsx` entirely**

```tsx
// pwa/src/features/devices/DeviceDetailScreen.tsx
import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { useDeviceSearch } from './useDeviceSearch';
import { useIncidents } from '../incidents/useIncidents';
import { SeverityBadge } from '../incidents/SeverityBadge';
import { EmptyState } from '../../components/EmptyState';
import { PerformanceSection } from '../performance/PerformanceSection';
import { MaintenanceDialog } from './MaintenanceDialog';
import { LatencyMiniChart } from './LatencyMiniChart';
import { DeviceTypeIcon } from '../../components/DeviceTypeIcon';
import { createMaintenanceWindow } from '../../lib/api/maintenance';
import { useConfig } from '../../lib/config';
import { classifyDevice } from '../../lib/deviceType';
import { buildDeviceAlarmMap } from '../../lib/deviceAlarms';
import type { Incident } from '../../lib/api/types';

// ── Status helpers ────────────────────────────────────────────────
const STATUS_LABELS: Record<string, string> = {
  up: 'UP', down: 'DOWN', warning: 'WARNING',
  critical: 'CRITICAL', maintenance: 'MAINTENANCE', unknown: 'UNKNOWN',
};
const STATUS_COLORS: Record<string, string> = {
  up: 'text-green-400', down: 'text-red-400', warning: 'text-amber-400',
  critical: 'text-red-400', maintenance: 'text-slate-400', unknown: 'text-slate-500',
};

// ── Duration helper ───────────────────────────────────────────────
function duration(start: Date): string {
  const ms = Date.now() - start.getTime();
  const m = Math.floor(ms / 60_000);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ${m % 60}m`;
  return `${Math.floor(h / 24)}d ${h % 24}h`;
}

// ── Collapsible section wrapper ───────────────────────────────────
function CollapsibleSection({
  title,
  badge,
  defaultOpen = false,
  children,
}: {
  title: string;
  badge?: number;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="bg-slate-800 rounded-xl overflow-hidden">
      <button
        className="w-full flex items-center justify-between px-4 py-3 text-left"
        onClick={() => setOpen((v) => !v)}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-slate-100">{title}</span>
          {badge !== undefined && badge > 0 && (
            <span className="bg-red-600 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">
              {badge}
            </span>
          )}
        </div>
        <svg
          viewBox="0 0 20 20"
          fill="currentColor"
          className={`w-4 h-4 text-slate-400 transition-transform duration-200 ${open ? 'rotate-180' : ''}`}
        >
          <path fillRule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clipRule="evenodd" />
        </svg>
      </button>
      {open && <div className="border-t border-slate-700">{children}</div>}
    </div>
  );
}

// ── InfoRow (kept from original) ──────────────────────────────────
function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex justify-between items-start gap-4 text-sm px-4 py-2">
      <span className="text-slate-500 shrink-0">{label}</span>
      <span className={`text-slate-200 text-right break-all ${mono ? 'font-mono' : ''}`}>{value}</span>
    </div>
  );
}

// ── Incident table row ────────────────────────────────────────────
function IssueRow({ incident }: { incident: Incident }) {
  return (
    <div className="grid px-4 py-2.5 border-b border-slate-700 last:border-0"
      style={{ gridTemplateColumns: '80px 1fr 56px', gap: '8px', alignItems: 'start' }}>
      <SeverityBadge severity={incident.severity} />
      <p className="text-xs text-slate-200 line-clamp-2">{incident.summary}</p>
      <p className="text-[11px] text-slate-500 text-right">{duration(incident.startTime)}</p>
    </div>
  );
}

// ── Main screen ───────────────────────────────────────────────────
export function DeviceDetailScreen() {
  const { name } = useParams<{ name: string }>();
  const decodedName = name ? decodeURIComponent(name) : '';

  const config = useConfig();
  const [showMaintenance, setShowMaintenance] = useState(false);

  const { data: searchResults, isLoading, isError } = useDeviceSearch(decodedName);
  const { data: allIncidents } = useIncidents();

  const device = searchResults?.[0];
  const deviceIncidents = (allIncidents ?? []).filter(
    (inc) => inc.deviceName === decodedName,
  );

  const alarmMap = buildDeviceAlarmMap(allIncidents ?? []);
  const alarmSummary = alarmMap.get(decodedName);
  const counts = alarmSummary?.counts ?? { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

  return (
    <div className="min-h-full">
      {isLoading && <EmptyState title="Loading..." description="Fetching device details." />}
      {isError && <EmptyState title="Could not load device" description="Failed to fetch device details." />}

      {device && (
        <div className="p-4 space-y-3">

          {/* ── Header card ── */}
          <div className="bg-slate-800 rounded-xl p-3.5 flex items-stretch gap-3">
            {/* Icon */}
            <div className="self-start pt-0.5">
              <DeviceTypeIcon type={classifyDevice(device)} status={device.status} size={52} />
            </div>

            {/* Info column */}
            <div className="flex flex-col justify-center gap-1 min-w-0" style={{ flex: '0 0 38%' }}>
              <p className="text-[15px] font-bold text-slate-100 truncate">{device.name}</p>
              <p className="text-[11px] text-slate-400 font-mono">{device.ip}</p>
              {device.category && (
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <svg viewBox="0 0 24 24" className="w-3 h-3 shrink-0" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
                  </svg>
                  {device.category}
                </p>
              )}
              {device.site && (
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <svg viewBox="0 0 24 24" className="w-3 h-3 shrink-0" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                  </svg>
                  {device.site}
                </p>
              )}
              <p className={`text-[10px] font-semibold flex items-center gap-1 ${STATUS_COLORS[device.status] ?? 'text-slate-500'}`}>
                <span className="w-2 h-2 rounded-full bg-current inline-block" />
                {STATUS_LABELS[device.status] ?? device.status.toUpperCase()}
              </p>
            </div>

            {/* Latency mini chart */}
            <div className="flex-1 min-w-0">
              <LatencyMiniChart deviceIndex={device.deviceIndex} deviceName={device.name} />
            </div>
          </div>

          {/* ── Alarm summary bar ── */}
          <div className="grid grid-cols-4">
            {([
              { label: 'HEALTHY', value: counts.green, color: 'text-green-500' },
              { label: 'ACK', value: counts.blue, color: 'text-blue-400' },
              { label: 'WARNING', value: counts.yellow + counts.orange, color: 'text-yellow-300' },
              { label: 'CRITICAL', value: counts.red, color: 'text-red-400' },
            ] as const).map((col, i) => (
              <div
                key={col.label}
                className={`text-center ${i > 0 ? 'border-l border-slate-700' : ''}`}
              >
                <p className={`text-[26px] font-bold leading-none ${col.color}`}>{col.value}</p>
                <p className={`text-[9px] font-semibold tracking-widest mt-0.5 ${col.color}`}>{col.label}</p>
              </div>
            ))}
          </div>

          {/* ── Maintenance Window card ── */}
          <button
            onClick={() => setShowMaintenance(true)}
            className="w-full bg-slate-800 rounded-xl py-3.5 text-sm font-medium text-sky-400 hover:bg-slate-700 transition-colors"
          >
            + Create Maintenance Window
          </button>

          <MaintenanceDialog
            deviceName={decodedName}
            username={config.ackUser}
            isOpen={showMaintenance}
            onClose={() => setShowMaintenance(false)}
            onSubmit={(duration, comment) =>
              createMaintenanceWindow(config, decodedName, duration, comment)
            }
          />

          {/* ── Host Information (collapsed) ── */}
          <CollapsibleSection title="Host Information" defaultOpen={false}>
            <InfoRow label="Current State" value={STATUS_LABELS[device.status] ?? device.status} />
            {device.description && <InfoRow label="Type" value={device.description} />}
            {device.category && <InfoRow label="Category" value={device.category} />}
            {device.site && <InfoRow label="Site" value={device.site} />}
            {device.model && <InfoRow label="Model" value={device.model} />}
            {device.serialNumber && <InfoRow label="Serial Number" value={device.serialNumber} />}
            <InfoRow label="UID" value={device.deviceIndex} mono />
          </CollapsibleSection>

          {/* ── Current Issues (expanded) ── */}
          <CollapsibleSection
            title="Current Issues"
            badge={deviceIncidents.length}
            defaultOpen={true}
          >
            {deviceIncidents.length === 0 ? (
              <div className="px-4 py-5 flex items-center justify-center gap-2 text-slate-400 text-sm">
                <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M20 6L9 17l-5-5" />
                </svg>
                No current issues
              </div>
            ) : (
              <div>
                {deviceIncidents.map((inc) => (
                  <IssueRow key={inc.incidentId} incident={inc} />
                ))}
              </div>
            )}
          </CollapsibleSection>

          {/* ── Performance ── */}
          <PerformanceSection
            deviceIndex={device.deviceIndex}
            deviceName={device.name}
          />
        </div>
      )}

      {!isLoading && !device && !isError && (
        <EmptyState title="Device not found" description={`No device named '${decodedName}'.`} />
      )}
    </div>
  );
}
```

- [ ] **Step 2: Update `DeviceDetailScreen.test.tsx` for new structure**

The test currently checks for `'raspi-054'`, `'192.168.1.54'`, `'RPi 4'`, `'ABC123'`. The new screen renders these inside `InfoRow` inside the `CollapsibleSection` for "Host Information" (collapsed by default) and inside the header card. Adjust tests:

```tsx
// pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceDetailScreen } from '../DeviceDetailScreen';

vi.mock('../useDeviceSearch', () => ({ useDeviceSearch: vi.fn() }));
vi.mock('../../incidents/useIncidents', () => ({ useIncidents: vi.fn() }));
vi.mock('../LatencyMiniChart', () => ({ LatencyMiniChart: () => null }));
vi.mock('../../performance/PerformanceSection', () => ({
  PerformanceSection: () => <div data-testid="perf-section">Performance</div>,
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test', serverName: 'Test', baseUrl: '/bhnm',
    apiKey: 'key', isConfigured: true, ackUser: 'tester',
  }),
}));

import { useDeviceSearch } from '../useDeviceSearch';
import { useIncidents } from '../../incidents/useIncidents';

const mockDevice = {
  name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home',
  model: 'RPi 4', serialNumber: 'ABC123', description: 'Test Pi',
  deviceIndex: '3', status: 'up' as const,
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
  beforeEach(() => {
    vi.mocked(useIncidents).mockReturnValue({ data: [] } as unknown as ReturnType<typeof useIncidents>);
  });

  it('shows device name and IP in header', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice], isLoading: false, isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('192.168.1.54')).toBeInTheDocument();
  });

  it('shows model and serial inside Host Information when expanded', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice], isLoading: false, isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    await userEvent.click(screen.getByText('Host Information'));
    expect(screen.getByText('RPi 4')).toBeInTheDocument();
    expect(screen.getByText('ABC123')).toBeInTheDocument();
  });

  it('shows "No current issues" when no incidents', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice], isLoading: false, isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('No current issues')).toBeInTheDocument();
  });

  it('shows matching incidents in Current Issues table', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice], isLoading: false, isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [
        {
          incidentId: '1', displayId: '#1', deviceName: 'raspi-054', deviceIp: '192.168.1.54',
          summary: 'High CPU', severity: 'critical' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null, alarmCounts: null,
        },
        {
          incidentId: '2', displayId: '#2', deviceName: 'other-host', deviceIp: '10.0.0.1',
          summary: 'Disk full', severity: 'major' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null, alarmCounts: null,
        },
      ],
    } as unknown as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('High CPU')).toBeInTheDocument();
    expect(screen.queryByText('Disk full')).not.toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined, isLoading: true, isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('shows alarm bar with HEALTHY / ACK / WARNING / CRITICAL labels', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice], isLoading: false, isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('HEALTHY')).toBeInTheDocument();
    expect(screen.getByText('ACK')).toBeInTheDocument();
    expect(screen.getByText('WARNING')).toBeInTheDocument();
    expect(screen.getByText('CRITICAL')).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: Run the detail tests**

```bash
cd pwa && npx vitest run src/features/devices/__tests__/DeviceDetailScreen.test.tsx
```
Expected: 6 tests PASS.

- [ ] **Step 4: Run full test suite**

```bash
cd pwa && npx vitest run
```
Expected: all tests PASS. Fix any TypeScript errors with `npx tsc --noEmit`.

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/devices/DeviceDetailScreen.tsx \
  pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
git commit -m "feat(pwa): overhaul DeviceDetailScreen with iOS-aligned header, alarm bar, and collapsible sections"
```

---

## Spec Coverage Checklist

| Spec requirement | Task |
|---|---|
| `shared/icons/` SVG files for all 5 device types | Task 1 |
| Tailwind marquee animation | Task 1 |
| `classifyDevice()` utility | Task 2 |
| `buildDeviceAlarmMap()` utility | Task 3 |
| `DeviceStatus` type + `status` on `Device` | Task 4 |
| `DeviceTypeIcon` component (status-colored, sized) | Task 5 |
| `LatencyMiniChart` (eager fetch, SVG area+line) | Task 6 |
| `DeviceRow` — icon + alarm badges + ticker | Task 7 |
| `DeviceListScreen` — alarm map wired | Task 8 |
| Header card (icon + info + latency chart) | Task 9 |
| Alarm summary bar (HEALTHY/ACK/WARNING/CRITICAL) | Task 9 |
| Maintenance Window card | Task 9 |
| Host Information collapsible (closed by default) | Task 9 |
| Current Issues collapsible (open, table format) | Task 9 |
