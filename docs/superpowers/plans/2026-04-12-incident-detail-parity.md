# Incident Detail iOS Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix incident duration display, add lazy alarm-count fallback when middleware cache is cold, and rebuild IncidentDetailScreen to match iOS (Status + alarm badges, Incident Info, Primary Alarms, Related Alarms, Incident State Log).

**Architecture:** All three improvements share a new `getIncidentDetail` / `parseIncidentDetailResponse` API layer in `incidents.ts`. `IncidentRow` calls `useIncidentDetail` with `enabled: alarmCounts === null` so counts load lazily per-row without Intersection Observer. `IncidentDetailScreen` calls the same hook unconditionally on mount.

**Tech Stack:** React 19, TypeScript, Vitest, React Testing Library, @tanstack/react-query, Tailwind CSS.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `src/lib/api/types.ts` | Modify | Add `IncidentAlarm`, `IncidentLogEntry`, `IncidentDetail` types |
| `src/lib/api/incidents.ts` | Modify | Fix `startTime` field lookup; add `parseIncidentDetailResponse`, `getIncidentDetail` |
| `src/lib/api/incidents.test.ts` | Modify | Add tests for `parseIncidentDetailResponse` + `startTime` fix |
| `src/lib/mock/incident-detail.json` | Create | Test fixture for `getincidentdetail` response |
| `src/features/incidents/useIncidentDetail.ts` | Create | React Query hook wrapping `getIncidentDetail` |
| `src/features/incidents/StateBadge.tsx` | Create | Alarm/log state string → coloured pill (distinct from `StatusBadge`) |
| `src/features/incidents/StateBadge.test.tsx` | Create | Tests for `StateBadge` colour mapping |
| `src/features/incidents/IncidentRow.tsx` | Modify | Shimmer fallback + `useIncidentDetail` when `alarmCounts === null` |
| `src/features/incidents/__tests__/IncidentRow.test.tsx` | Modify | Tests for shimmer and loaded fallback states |
| `src/features/incidents/IncidentDetailScreen.tsx` | Modify | Full redesign: Status section, Incident Info, alarms, log |
| `src/features/incidents/__tests__/IncidentDetailScreen.test.tsx` | Modify | Update for new layout + mock `useIncidentDetail` |

---

## Task 1: Fix `startTime` Parsing (Duration Bug)

**Files:**
- Modify: `src/lib/api/incidents.ts`
- Modify: `src/lib/api/incidents.test.ts`

The `parseRow` function currently looks for `row.start_time ?? row.startTime`. When neither field is present (or the middleware cache returns a different field name like `incident_open_time`), `coerceStartTime` falls back to `new Date()`, making all durations show "now". Fix: widen the field lookup to cover more field names.

- [ ] **Step 1: Write failing test for start_time field lookup**

In `src/lib/api/incidents.test.ts`, add inside `describe('parseIncidentsResponse')`:

```ts
it('parses start_time from incident_open_time field when start_time absent', () => {
  const payload = {
    active_incidents: [
      {
        incident_id: 99,
        title: 'test',
        name: 'host',
        incident_state: 'OPEN',
        severity: 'critical',
        incident_open_time: 1712332800,
      },
    ],
  };
  const incidents = parseIncidentsResponse(payload);
  expect(incidents[0].startTime.getTime()).toBe(1712332800 * 1000);
});

it('parses start_time from open_time field when start_time absent', () => {
  const payload = {
    active_incidents: [
      {
        incident_id: 100,
        title: 'test2',
        name: 'host2',
        incident_state: 'OPEN',
        severity: 'major',
        open_time: 1712332800,
      },
    ],
  };
  const incidents = parseIncidentsResponse(payload);
  expect(incidents[0].startTime.getTime()).toBe(1712332800 * 1000);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd pwa && npx vitest run src/lib/api/incidents.test.ts
```

Expected: the two new tests FAIL with `expected 1712332800000, received <current timestamp ms>`.

- [ ] **Step 3: Widen field lookup in `parseRow`**

In `src/lib/api/incidents.ts`, update the `startTime` line inside `parseRow`:

```ts
// Before:
startTime: coerceStartTime(row.start_time ?? row.startTime),

// After:
startTime: coerceStartTime(
  row.start_time ?? row.startTime ?? row.incident_open_time ?? row.open_time
),
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
npx vitest run src/lib/api/incidents.test.ts
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/incidents.ts src/lib/api/incidents.test.ts
git commit -m "fix(pwa): widen startTime field lookup — cover incident_open_time and open_time"
```

---

## Task 2: Add `IncidentDetail` Types + Mock Fixture

**Files:**
- Modify: `src/lib/api/types.ts`
- Create: `src/lib/mock/incident-detail.json`

- [ ] **Step 1: Add types to `src/lib/api/types.ts`**

Append after the existing `Incident` interface:

```ts
export interface IncidentAlarm {
  state: string;    // e.g. "CRITICAL", "MAJOR", "OK"
  type: string;     // e.g. "Host", "Service", "Threshold"
  name: string;
  output: string;   // HTML-stripped alarm output
  time: Date | null;
}

export interface IncidentLogEntry {
  state: string;
  time: Date | null;
  username: string;
  comment: string;
}

export interface IncidentDetail {
  incidentId: string;
  title: string;
  deviceName: string;
  deviceIp: string | null;
  incidentState: string;
  alertType: string | null;
  openTime: Date | null;
  acknowledged: boolean;
  ackTime: Date | null;
  ackUser: string | null;
  ackComment: string | null;
  alarmCounts: AlarmCounts;          // computed from primary + related alarms
  primaryAlarms: IncidentAlarm[];
  relatedAlarms: IncidentAlarm[];
  incidentLog: IncidentLogEntry[];
}
```

- [ ] **Step 2: Create mock fixture `src/lib/mock/incident-detail.json`**

```json
{
  "incident": {
    "incident_id": "58431",
    "title": "CPU utilization high on core-switch-01",
    "name": "core-switch-01",
    "ip": "10.0.0.1",
    "incident_state": "OPEN",
    "primary_alarm_state": "CRITICAL",
    "incident_open_time": "2026-04-12T09:14:02",
    "acknowledged": 0,
    "ack_time": null,
    "ack_user": null,
    "ack_comment": null,
    "alert_type": "Host",
    "detail": {
      "primary_alarm_log": [
        {
          "state": "CRITICAL",
          "type": "Host",
          "name": "core-switch-01",
          "output": "PING CRITICAL <br /> Packet loss = 100%",
          "time": "2026-04-12T09:14:02"
        },
        {
          "state": "MAJOR",
          "type": "Service",
          "name": "BGP-Peer",
          "output": "BGP neighbor 10.0.0.1 is down",
          "time": "2026-04-12T09:14:05"
        }
      ],
      "relatedalarms": [
        {
          "state": "OK",
          "type": "Service",
          "name": "DNS-Check",
          "output": "DNS resolution OK (12ms)",
          "time": "2026-04-12T08:58:00"
        }
      ],
      "incident_log": [
        {
          "state": "OPEN",
          "time": "2026-04-12T09:14:02",
          "username": "System",
          "comment": ""
        },
        {
          "state": "ACK",
          "time": "2026-04-12T09:22:15",
          "username": "thomas.stolt",
          "comment": "Investigating — core switch unreachable"
        }
      ]
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add src/lib/api/types.ts src/lib/mock/incident-detail.json
git commit -m "feat(pwa): add IncidentDetail types and mock fixture"
```

---

## Task 3: Implement `parseIncidentDetailResponse` + `getIncidentDetail`

**Files:**
- Modify: `src/lib/api/incidents.ts`
- Modify: `src/lib/api/incidents.test.ts`

- [ ] **Step 1: Write failing tests**

In `src/lib/api/incidents.test.ts`, update the top-level import line to add `parseIncidentDetailResponse`, and add a new import for the mock fixture (alongside existing imports at the top of the file):

```ts
// Update existing import:
import { parseIncidentsResponse, buildDisplayId, parseAckResponse, parseIncidentDetailResponse } from './incidents';
// Add new import:
import detailMock from '../mock/incident-detail.json';
```

Then add at the bottom of the file:

```ts
describe('parseIncidentDetailResponse', () => {
  it('parses incidentId, title, deviceName and deviceIp', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.incidentId).toBe('58431');
    expect(d.title).toBe('CPU utilization high on core-switch-01');
    expect(d.deviceName).toBe('core-switch-01');
    expect(d.deviceIp).toBe('10.0.0.1');
  });

  it('parses openTime from incident_open_time ISO string', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.openTime).toBeInstanceOf(Date);
    expect(d.openTime!.toISOString()).toMatch(/^2026-04-12/);
  });

  it('parses primaryAlarms with HTML stripped from output', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.primaryAlarms).toHaveLength(2);
    expect(d.primaryAlarms[0].state).toBe('CRITICAL');
    expect(d.primaryAlarms[0].name).toBe('core-switch-01');
    expect(d.primaryAlarms[0].output).not.toMatch(/<br/);
    expect(d.primaryAlarms[0].output).toContain('Packet loss');
  });

  it('parses relatedAlarms', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.relatedAlarms).toHaveLength(1);
    expect(d.relatedAlarms[0].state).toBe('OK');
  });

  it('parses incidentLog entries', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.incidentLog).toHaveLength(2);
    expect(d.incidentLog[1].username).toBe('thomas.stolt');
    expect(d.incidentLog[1].comment).toBe('Investigating — core switch unreachable');
  });

  it('computes alarmCounts from primary + related alarms', () => {
    const d = parseIncidentDetailResponse(detailMock);
    // primary: CRITICAL → red, MAJOR → orange; related: OK → green
    expect(d.alarmCounts.red).toBe(1);
    expect(d.alarmCounts.orange).toBe(1);
    expect(d.alarmCounts.green).toBe(1);
    expect(d.alarmCounts.yellow).toBe(0);
    expect(d.alarmCounts.blue).toBe(0);
  });

  it('returns acknowledged=false when field is 0', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.acknowledged).toBe(false);
  });

  it('returns acknowledged=true when field is 1', () => {
    const acked = { incident: { ...detailMock.incident, acknowledged: 1, ack_user: 'alice', ack_time: '2026-04-12T10:00:00', ack_comment: 'on it' } };
    const d = parseIncidentDetailResponse(acked);
    expect(d.acknowledged).toBe(true);
    expect(d.ackUser).toBe('alice');
    expect(d.ackComment).toBe('on it');
  });

  it('handles array-wrapped response', () => {
    const d = parseIncidentDetailResponse([detailMock]);
    expect(d.incidentId).toBe('58431');
  });

  it('throws ApiException on missing incident key', () => {
    expect(() => parseIncidentDetailResponse({})).toThrow();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/lib/api/incidents.test.ts
```

Expected: all `parseIncidentDetailResponse` tests FAIL with "parseIncidentDetailResponse is not a function".

- [ ] **Step 3: Add helpers + `parseIncidentDetailResponse` + `getIncidentDetail` to `src/lib/api/incidents.ts`**

Add after the existing imports at the top:

```ts
import type { IncidentAlarm, IncidentLogEntry, IncidentDetail } from './types';
```

Add these private helpers before `parseRow` (keep them private — not exported):

```ts
function stripHtml(s: string): string {
  return s
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .trim();
}

function parseDetailDate(raw: unknown): Date | null {
  if (typeof raw !== 'string' || !raw) return null;
  const d = new Date(raw);
  if (!isNaN(d.getTime())) return d;
  // No-timezone ISO string — treat as local time
  const d2 = new Date(raw.replace('T', ' '));
  return isNaN(d2.getTime()) ? null : d2;
}

function alarmStateToColorKey(state: string): keyof AlarmCounts {
  switch (state.toUpperCase()) {
    case 'CRITICAL': case 'DOWN': case 'OPEN': return 'red';
    case 'MAJOR': case 'UNREACHABLE': return 'orange';
    case 'WARNING': case 'MINOR': return 'yellow';
    case 'OK': case 'NORMAL': case 'RECOVERY': case 'CLEARED': case 'UP': return 'green';
    default: return 'blue';
  }
}
```

Add after `parseIncidentsResponse`:

```ts
export function parseIncidentDetailResponse(raw: unknown): IncidentDetail {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') {
    throw new ApiException({ kind: 'parse', message: 'Invalid detail response' });
  }
  const obj = root as Record<string, unknown>;
  const incident = obj.incident as Record<string, unknown> | undefined;
  if (!incident) {
    throw new ApiException({ kind: 'parse', message: 'No incident key in detail response' });
  }
  const detail = (typeof incident.detail === 'object' && incident.detail !== null
    ? incident.detail
    : {}) as Record<string, unknown>;

  function parseAlarms(arr: unknown): IncidentAlarm[] {
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((a): a is Record<string, unknown> => !!a && typeof a === 'object')
      .map((a) => ({
        state: String(a.state ?? ''),
        type: String(a.type ?? ''),
        name: String(a.name ?? ''),
        output: stripHtml(String(a.output ?? '')),
        time: parseDetailDate(a.time),
      }));
  }

  const primaryAlarms = parseAlarms(detail.primary_alarm_log);
  const relatedAlarms = parseAlarms(detail.relatedalarms);

  const incidentLog: IncidentLogEntry[] = Array.isArray(detail.incident_log)
    ? (detail.incident_log as unknown[])
        .filter((e): e is Record<string, unknown> => !!e && typeof e === 'object')
        .map((e) => ({
          state: String(e.state ?? ''),
          time: parseDetailDate(e.time),
          username: String(e.username ?? ''),
          comment: String(e.comment ?? ''),
        }))
    : [];

  const alarmCounts: AlarmCounts = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
  for (const alarm of [...primaryAlarms, ...relatedAlarms]) {
    alarmCounts[alarmStateToColorKey(alarm.state)]++;
  }

  const ackRaw = incident.acknowledged;
  const acknowledged = ackRaw === 1 || ackRaw === '1' || ackRaw === true;

  const deviceIp =
    coerceString(incident.ip) ??
    coerceString(incident.device_ip) ??
    coerceString(incident.ip_address) ??
    coerceString(incident.host_ip);

  return {
    incidentId: String(incident.incident_id ?? ''),
    title: String(incident.title ?? ''),
    deviceName: String(incident.name ?? ''),
    deviceIp,
    incidentState: String(incident.incident_state ?? ''),
    alertType: coerceString(incident.alert_type),
    openTime: parseDetailDate(incident.incident_open_time),
    acknowledged,
    ackTime: acknowledged ? parseDetailDate(incident.ack_time) : null,
    ackUser: acknowledged ? coerceString(incident.ack_user) : null,
    ackComment: acknowledged ? coerceString(incident.ack_comment) : null,
    alarmCounts,
    primaryAlarms,
    relatedAlarms,
    incidentLog,
  };
}

export async function getIncidentDetail(
  config: BhnmConfig,
  incidentId: string,
): Promise<IncidentDetail> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'getincidentdetail',
    incident_id: incidentId,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/api/incident_api.php',
    params,
    config.apiKey,
  );
  return parseIncidentDetailResponse(raw);
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
npx vitest run src/lib/api/incidents.test.ts
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/incidents.ts src/lib/api/incidents.test.ts
git commit -m "feat(pwa): add parseIncidentDetailResponse and getIncidentDetail"
```

---

## Task 4: `useIncidentDetail` Hook

**Files:**
- Create: `src/features/incidents/useIncidentDetail.ts`

No separate test file — this is a thin React Query wrapper; it is exercised via component tests in Tasks 5 and 6.

- [ ] **Step 1: Create `src/features/incidents/useIncidentDetail.ts`**

```ts
import { useQuery } from '@tanstack/react-query';
import { getIncidentDetail } from '../../lib/api/incidents';
import { useConfig } from '../../lib/config';

export function useIncidentDetail(
  incidentId: string,
  options?: { enabled?: boolean },
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['incidentDetail', incidentId],
    queryFn: () => getIncidentDetail(config, incidentId),
    staleTime: 60_000,
    enabled: (options?.enabled ?? true) && Boolean(incidentId),
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add src/features/incidents/useIncidentDetail.ts
git commit -m "feat(pwa): add useIncidentDetail React Query hook"
```

---

## Task 5: `StateBadge` Component

**Files:**
- Create: `src/features/incidents/StateBadge.tsx`
- Create: `src/features/incidents/StateBadge.test.tsx`

`StateBadge` maps arbitrary alarm/log state strings to coloured pills. It is distinct from `StatusBadge`, which is specific to the three-state incident pill on list rows.

- [ ] **Step 1: Write failing tests in `src/features/incidents/StateBadge.test.tsx`**

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StateBadge } from './StateBadge';

describe('StateBadge', () => {
  it('renders the state text', () => {
    render(<StateBadge state="CRITICAL" />);
    expect(screen.getByText('CRITICAL')).toBeInTheDocument();
  });

  it('applies red styling for CRITICAL', () => {
    const { container } = render(<StateBadge state="CRITICAL" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies red styling for DOWN', () => {
    const { container } = render(<StateBadge state="DOWN" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies red styling for OPEN', () => {
    const { container } = render(<StateBadge state="OPEN" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies orange styling for MAJOR', () => {
    const { container } = render(<StateBadge state="MAJOR" />);
    expect(container.firstChild).toHaveClass('bg-orange-700');
  });

  it('applies yellow styling for WARNING', () => {
    const { container } = render(<StateBadge state="WARNING" />);
    expect(container.firstChild).toHaveClass('bg-yellow-800');
  });

  it('applies yellow styling for MINOR', () => {
    const { container } = render(<StateBadge state="MINOR" />);
    expect(container.firstChild).toHaveClass('bg-yellow-800');
  });

  it('applies green styling for OK', () => {
    const { container } = render(<StateBadge state="OK" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies green styling for ALARMS CLEARED', () => {
    const { container } = render(<StateBadge state="ALARMS CLEARED" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies green styling for CLEARED', () => {
    const { container } = render(<StateBadge state="CLEARED" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies blue styling for ACKNOWLEDGED', () => {
    const { container } = render(<StateBadge state="ACKNOWLEDGED" />);
    expect(container.firstChild).toHaveClass('bg-blue-800');
  });

  it('applies blue styling for ACK', () => {
    const { container } = render(<StateBadge state="ACK" />);
    expect(container.firstChild).toHaveClass('bg-blue-800');
  });

  it('applies slate fallback for unknown state', () => {
    const { container } = render(<StateBadge state="SOME_UNKNOWN_STATE" />);
    expect(container.firstChild).toHaveClass('bg-slate-700');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/features/incidents/StateBadge.test.tsx
```

Expected: all tests FAIL with "Cannot find module './StateBadge'".

- [ ] **Step 3: Create `src/features/incidents/StateBadge.tsx`**

```tsx
const STATE_CLASSES: Record<string, string> = {
  CRITICAL:        'bg-red-700 text-red-200',
  DOWN:            'bg-red-700 text-red-200',
  OPEN:            'bg-red-700 text-red-200',
  MAJOR:           'bg-orange-700 text-orange-200',
  UNREACHABLE:     'bg-orange-700 text-orange-200',
  WARNING:         'bg-yellow-800 text-yellow-300',
  MINOR:           'bg-yellow-800 text-yellow-300',
  OK:              'bg-green-800 text-green-300',
  RESOLVED:        'bg-green-800 text-green-300',
  CLOSED:          'bg-green-800 text-green-300',
  UP:              'bg-green-800 text-green-300',
  NORMAL:          'bg-green-800 text-green-300',
  RECOVERY:        'bg-green-800 text-green-300',
  CLEARED:         'bg-green-800 text-green-300',
  'ALARMS CLEARED':'bg-green-800 text-green-300',
  ACKNOWLEDGED:    'bg-blue-800 text-blue-200',
  ACK:             'bg-blue-800 text-blue-200',
};

export function StateBadge({ state }: { state: string }) {
  const cls = STATE_CLASSES[state.toUpperCase()] ?? 'bg-slate-700 text-slate-300';
  return (
    <span
      className={`inline-block rounded text-[9px] font-bold px-1.5 py-0.5 leading-tight uppercase ${cls}`}
    >
      {state}
    </span>
  );
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
npx vitest run src/features/incidents/StateBadge.test.tsx
```

Expected: all 13 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/incidents/StateBadge.tsx src/features/incidents/StateBadge.test.tsx
git commit -m "feat(pwa): add StateBadge — alarm/log state string to coloured pill"
```

---

## Task 6: `IncidentRow` Alarm Badge Fallback

**Files:**
- Modify: `src/features/incidents/IncidentRow.tsx`
- Modify: `src/features/incidents/__tests__/IncidentRow.test.tsx`

When `incident.alarmCounts === null` (middleware cache cold), `IncidentRow` calls `useIncidentDetail` with `enabled: true` and shows animated shimmer placeholders while loading.

- [ ] **Step 1: Add failing tests to `src/features/incidents/__tests__/IncidentRow.test.tsx`**

Add at the top of the file after existing imports:

```tsx
import { vi } from 'vitest';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

vi.mock('../useIncidentDetail', () => ({
  useIncidentDetail: vi.fn(() => ({ data: undefined, isLoading: false })),
}));
```

Add this import after the mock declaration:

```tsx
import { useIncidentDetail } from '../useIncidentDetail';
```

Update the `renderRow` helper to wrap with `QueryClientProvider`:

```tsx
function renderRow(inc: Incident) {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <IncidentRow incident={inc} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}
```

Add inside `describe('IncidentRow')`:

```tsx
describe('alarm badge fallback (cold cache)', () => {
  it('shows shimmer placeholders when alarmCounts is null and detail is loading', () => {
    vi.mocked(useIncidentDetail).mockReturnValueOnce({
      data: undefined,
      isLoading: true,
    } as ReturnType<typeof useIncidentDetail>);
    renderRow({ ...base, alarmCounts: null });
    // No count numbers visible while loading
    expect(screen.queryByText('2')).not.toBeInTheDocument();
    // Five shimmer spans present
    const shimmers = document.querySelectorAll('[data-testid="alarm-shimmer"]');
    expect(shimmers.length).toBe(5);
  });

  it('shows counts from detail when alarmCounts is null and detail loaded', () => {
    vi.mocked(useIncidentDetail).mockReturnValueOnce({
      data: {
        alarmCounts: { red: 3, orange: 1, yellow: 0, green: 2, blue: 0 },
      } as any,
      isLoading: false,
    } as ReturnType<typeof useIncidentDetail>);
    renderRow({ ...base, alarmCounts: null });
    expect(screen.getByText('3')).toBeInTheDocument(); // red
    expect(screen.getByText('1')).toBeInTheDocument(); // orange
    expect(screen.getByText('2')).toBeInTheDocument(); // green
  });

  it('shows empty counts when alarmCounts is null and detail unavailable', () => {
    vi.mocked(useIncidentDetail).mockReturnValueOnce({
      data: undefined,
      isLoading: false,
    } as ReturnType<typeof useIncidentDetail>);
    renderRow({ ...base, alarmCounts: null });
    const zeros = screen.getAllByText('0');
    expect(zeros.length).toBe(5);
  });

  it('does not call useIncidentDetail when alarmCounts is already present', () => {
    vi.mocked(useIncidentDetail).mockClear();
    renderRow(base); // base has alarmCounts: { red:2, orange:0, yellow:1, green:3, blue:0 }
    expect(vi.mocked(useIncidentDetail)).toHaveBeenCalledWith(
      base.incidentId,
      { enabled: false },
    );
  });
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
npx vitest run src/features/incidents/__tests__/IncidentRow.test.tsx
```

Expected: the four new `alarm badge fallback` tests FAIL. Existing tests may also fail due to the missing `QueryClientProvider` in the updated `renderRow` — that is expected and will be fixed in the next step.

- [ ] **Step 3: Update `src/features/incidents/IncidentRow.tsx`**

```tsx
import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { StatusBadge } from './StatusBadge';
import { AlarmBadges } from './AlarmBadges';
import { OverflowMarquee } from '../../components/OverflowMarquee';
import { useIncidentDetail } from './useIncidentDetail';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

function formatDuration(d: Date): string {
  const diffMs = Date.now() - d.getTime();
  const totalMin = diffMs / 60_000;
  if (totalMin < 1) return 'now';
  if (totalMin < 60) return `${Math.round(totalMin)}m`;
  const totalHr = totalMin / 60;
  if (totalHr < 24) return `${Math.round(totalHr)}h`;
  return `${Math.round(totalHr / 24)}d`;
}

function ShimmerBadges() {
  return (
    <div className="flex gap-1">
      {Array.from({ length: 5 }).map((_, i) => (
        <span
          key={i}
          data-testid="alarm-shimmer"
          className="inline-block w-5 h-4 rounded bg-slate-700 animate-pulse"
        />
      ))}
    </div>
  );
}

export function IncidentRow({ incident }: { incident: Incident }) {
  const needsCounts = incident.alarmCounts === null;
  const { data: detail, isLoading: isDetailLoading } = useIncidentDetail(
    incident.incidentId,
    { enabled: needsCounts },
  );

  const alarmCounts = incident.alarmCounts ?? detail?.alarmCounts ?? null;
  const isLoadingCounts = needsCounts && isDetailLoading;

  return (
    <Link
      to={`/incidents/${encodeURIComponent(incident.incidentId)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      {/* Row 1: display ID + scrolling summary */}
      <div className="flex items-baseline gap-2 mb-1.5">
        <span className="shrink-0 text-xs font-semibold text-slate-500">
          {incident.displayId}
        </span>
        <OverflowMarquee
          text={incident.summary}
          className="flex-1 min-w-0 text-sm font-semibold text-slate-100"
        />
      </div>

      {/* Row 2: status badge · scrolling device name · duration · alarm dots */}
      <div className="flex items-center gap-1.5">
        <StatusBadge status={incident.status} incidentState={incident.incidentState} />
        <OverflowMarquee
          text={incident.deviceName ?? incident.deviceIp ?? 'Unknown'}
          className="flex-1 min-w-0 text-[11px] text-slate-400"
        />
        <span className="shrink-0 text-[11px] text-slate-500">
          {formatDuration(incident.startTime)}
        </span>
        {isLoadingCounts ? (
          <ShimmerBadges />
        ) : (
          <AlarmBadges counts={alarmCounts ?? EMPTY_COUNTS} />
        )}
      </div>
    </Link>
  );
}
```

- [ ] **Step 4: Run all IncidentRow tests**

```bash
npx vitest run src/features/incidents/__tests__/IncidentRow.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/incidents/IncidentRow.tsx src/features/incidents/__tests__/IncidentRow.test.tsx
git commit -m "feat(pwa): add shimmer alarm badge fallback to IncidentRow when cache cold"
```

---

## Task 7: Rebuild `IncidentDetailScreen`

**Files:**
- Modify: `src/features/incidents/IncidentDetailScreen.tsx`
- Modify: `src/features/incidents/__tests__/IncidentDetailScreen.test.tsx`

- [ ] **Step 1: Replace tests in `src/features/incidents/__tests__/IncidentDetailScreen.test.tsx`**

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { IncidentDetailScreen } from '../IncidentDetailScreen';

vi.mock('../useIncidents', () => ({
  useIncidents: () => ({
    data: [
      {
        incidentId: '58431',
        displayId: '#58431',
        deviceName: 'core-switch-01',
        deviceIp: '10.0.0.1',
        summary: 'CPU utilization high',
        severity: 'critical' as const,
        status: 'active' as const,
        incidentState: 'OPEN',
        startTime: new Date('2026-04-06T14:23:00Z'),
        acknowledgedBy: null,
        alarmCounts: null,
      },
      {
        incidentId: '58432',
        displayId: '#58432',
        deviceName: 'edge-router-02',
        deviceIp: '10.0.0.2',
        summary: 'Interface down',
        severity: 'major' as const,
        status: 'acknowledged' as const,
        incidentState: 'ACKNOWLEDGED',
        startTime: new Date('2026-04-06T12:00:00Z'),
        acknowledgedBy: 'oncall@example.com',
        alarmCounts: null,
      },
    ],
    isLoading: false,
  }),
}));

vi.mock('../useIncidentDetail', () => ({
  useIncidentDetail: vi.fn((id: string) => ({
    data: id === '58431' ? {
      incidentId: '58431',
      title: 'CPU utilization high on core-switch-01',
      deviceName: 'core-switch-01',
      deviceIp: '10.0.0.1',
      incidentState: 'OPEN',
      alertType: 'Host',
      openTime: new Date('2026-04-06T14:23:00Z'),
      acknowledged: false,
      ackTime: null,
      ackUser: null,
      ackComment: null,
      alarmCounts: { red: 2, orange: 1, yellow: 0, green: 3, blue: 0 },
      primaryAlarms: [
        { state: 'CRITICAL', type: 'Host', name: 'core-switch-01', output: 'Packet loss 100%', time: new Date('2026-04-06T14:23:00Z') },
      ],
      relatedAlarms: [],
      incidentLog: [
        { state: 'OPEN', time: new Date('2026-04-06T14:23:00Z'), username: 'System', comment: '' },
      ],
    } : id === '58432' ? {
      incidentId: '58432',
      title: 'Interface down',
      deviceName: 'edge-router-02',
      deviceIp: '10.0.0.2',
      incidentState: 'ACKNOWLEDGED',
      alertType: 'Service',
      openTime: new Date('2026-04-06T12:00:00Z'),
      acknowledged: true,
      ackTime: new Date('2026-04-06T12:30:00Z'),
      ackUser: 'oncall@example.com',
      ackComment: 'Looking into it',
      alarmCounts: { red: 0, orange: 1, yellow: 0, green: 0, blue: 0 },
      primaryAlarms: [],
      relatedAlarms: [
        { state: 'MAJOR', type: 'Service', name: 'Gi0/1', output: 'Interface down', time: new Date('2026-04-06T12:00:00Z') },
      ],
      incidentLog: [
        { state: 'OPEN', time: new Date('2026-04-06T12:00:00Z'), username: 'System', comment: '' },
        { state: 'ACK', time: new Date('2026-04-06T12:30:00Z'), username: 'oncall@example.com', comment: 'Looking into it' },
      ],
    } : undefined,
    isLoading: false,
    isError: false,
    refetch: vi.fn(),
  })),
}));

function renderDetail(incidentId: string) {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[`/incidents/${incidentId}`]}>
        <Routes>
          <Route path="/incidents/:id" element={<IncidentDetailScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('IncidentDetailScreen', () => {
  it('renders header with "Incident Detail" title', () => {
    renderDetail('58431');
    expect(screen.getByText('Incident Detail')).toBeInTheDocument();
  });

  it('renders back link to /incidents', () => {
    renderDetail('58431');
    expect(screen.getByRole('link', { name: /back/i })).toHaveAttribute('href', '/incidents');
  });

  it('renders acknowledge button for open incident', () => {
    renderDetail('58431');
    expect(screen.getByRole('button', { name: /acknowledge/i })).toBeInTheDocument();
  });

  it('renders OPEN status badge', () => {
    renderDetail('58431');
    expect(screen.getByText('OPEN')).toBeInTheDocument();
  });

  it('renders alarm counts from detail', () => {
    renderDetail('58431');
    expect(screen.getByText('2')).toBeInTheDocument(); // red
    expect(screen.getByText('3')).toBeInTheDocument(); // green
  });

  it('renders Incident Info section with title and device', () => {
    renderDetail('58431');
    expect(screen.getByText('Incident Info')).toBeInTheDocument();
    expect(screen.getByText('CPU utilization high on core-switch-01')).toBeInTheDocument();
    expect(screen.getByText('core-switch-01')).toBeInTheDocument();
  });

  it('renders Primary Alarms section when alarms present', () => {
    renderDetail('58431');
    expect(screen.getByText(/Primary Alarms/)).toBeInTheDocument();
    expect(screen.getByText('Packet loss 100%')).toBeInTheDocument();
  });

  it('does not render Primary Alarms section when empty', () => {
    renderDetail('58432');
    expect(screen.queryByText(/Primary Alarms/)).not.toBeInTheDocument();
  });

  it('renders Related Alarms section when alarms present', () => {
    renderDetail('58432');
    expect(screen.getByText(/Related Alarms/)).toBeInTheDocument();
    expect(screen.getByText('Interface down')).toBeInTheDocument();
  });

  it('renders Incident State Log section', () => {
    renderDetail('58431');
    expect(screen.getByText(/Incident State Log/)).toBeInTheDocument();
  });

  it('renders unacknowledge button for acknowledged incident', () => {
    renderDetail('58432');
    expect(screen.getByRole('button', { name: /unacknowledge/i })).toBeInTheDocument();
  });

  it('renders ACK user in Incident Info for acknowledged incident', () => {
    renderDetail('58432');
    expect(screen.getByText('oncall@example.com')).toBeInTheDocument();
  });

  it('renders ACK comment for acknowledged incident', () => {
    renderDetail('58432');
    expect(screen.getByText('Looking into it')).toBeInTheDocument();
  });

  it('shows not-found message for unknown incident', () => {
    renderDetail('99999');
    expect(screen.getByText(/not found/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/features/incidents/__tests__/IncidentDetailScreen.test.tsx
```

Expected: most tests FAIL because the current screen doesn't have "Incident Detail" title, alarm counts, or alarms/log sections.

- [ ] **Step 3: Replace `src/features/incidents/IncidentDetailScreen.tsx`**

```tsx
import { useState, useCallback } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { useIncidentDetail } from './useIncidentDetail';
import { useConfig } from '../../lib/config';
import { acknowledgeIncident, unacknowledgeIncident } from '../../lib/api/incidents';
import { StatusBadge } from './StatusBadge';
import { StateBadge } from './StateBadge';
import { AlarmBadges } from './AlarmBadges';
import { Toast, type ToastMessage } from '../../components/Toast';
import type { IncidentAlarm, IncidentLogEntry } from '../../lib/api/types';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

function formatTimestamp(d: Date): string {
  return (
    d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) +
    ' · ' +
    d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
  );
}

function formatDuration(start: Date): string {
  const s = Math.max(0, Math.floor((Date.now() - start.getTime()) / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (d > 0) return `${d}d ${h}h ${m}m ${sec}s`;
  if (h > 0) return `${h}h ${m}m ${sec}s`;
  return `${m}m ${sec}s`;
}

function AlarmRow({ alarm }: { alarm: IncidentAlarm }) {
  return (
    <div className="py-2 border-b border-slate-950 last:border-0">
      <div className="flex items-center gap-1.5 mb-1">
        <StateBadge state={alarm.state} />
        <span className="text-[11px] text-slate-500">{alarm.type}</span>
        <span className="ml-auto text-[11px] font-semibold text-slate-300">{alarm.name}</span>
      </div>
      {alarm.output && (
        <p className="text-[11px] text-slate-400 leading-snug">{alarm.output}</p>
      )}
      {alarm.time && (
        <p className="text-[10px] text-slate-600 mt-1">{formatTimestamp(alarm.time)}</p>
      )}
    </div>
  );
}

function LogRow({ entry }: { entry: IncidentLogEntry }) {
  return (
    <div className="py-2 border-b border-slate-950 last:border-0">
      <div className="flex items-center justify-between mb-1">
        <StateBadge state={entry.state} />
        {entry.time && (
          <span className="text-[10px] text-slate-600">{formatTimestamp(entry.time)}</span>
        )}
      </div>
      {entry.username && (
        <p className="text-[11px] text-slate-500">{entry.username}</p>
      )}
      {entry.comment && (
        <p className="text-[11px] text-slate-400">{entry.comment}</p>
      )}
    </div>
  );
}

export function IncidentDetailScreen() {
  const { id } = useParams();
  const { data: incidents, isLoading } = useIncidents();
  const {
    data: detail,
    isLoading: isDetailLoading,
    isError: isDetailError,
    refetch: refetchDetail,
  } = useIncidentDetail(id ?? '');
  const config = useConfig();
  const queryClient = useQueryClient();
  const [isAcking, setIsAcking] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const dismissToast = useCallback(() => setToast(null), []);

  const incident = incidents?.find((i) => i.incidentId === id);

  if (isLoading && !incident) {
    return (
      <div className="p-6">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <p className="mt-4 text-slate-400">Loading...</p>
      </div>
    );
  }

  if (!incident) {
    return (
      <div className="p-6">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <p className="mt-4 text-slate-400">Incident not found.</p>
      </div>
    );
  }

  const isAlarmsCleared = incident.incidentState.toUpperCase() === 'ALARMS CLEARED';
  const isAcked = incident.status === 'acknowledged';
  const alarmCounts = detail?.alarmCounts ?? incident.alarmCounts ?? EMPTY_COUNTS;

  const handleToggleAck = async () => {
    setIsAcking(true);
    setToast(null);
    try {
      if (isAcked) {
        await unacknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Unacknowledged', type: 'success' });
      } else {
        await acknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Acknowledged', type: 'success' });
      }
      await queryClient.invalidateQueries({ queryKey: ['incidents'] });
      await queryClient.invalidateQueries({ queryKey: ['incidentDetail', id] });
    } catch (err) {
      setToast({ text: err instanceof Error ? err.message : 'ACK failed', type: 'error' });
    } finally {
      setIsAcking(false);
    }
  };

  const infoRows: [string, string][] = [
    ['Incident ID', incident.incidentId],
    ...(detail ? [
      ['Title', detail.title] as [string, string],
      ['Device', detail.deviceName] as [string, string],
      ...(detail.deviceIp ? [['IP', detail.deviceIp] as [string, string]] : []),
      ...(detail.alertType ? [['Alert Type', detail.alertType] as [string, string]] : []),
      ...(detail.openTime ? [
        ['Created', formatTimestamp(detail.openTime)] as [string, string],
        ['Duration', formatDuration(detail.openTime)] as [string, string],
      ] : []),
      ...(detail.acknowledged && detail.ackTime ? [['ACK Time', formatTimestamp(detail.ackTime)] as [string, string]] : []),
      ...(detail.acknowledged && detail.ackUser ? [['ACK User', detail.ackUser] as [string, string]] : []),
      ...(detail.acknowledged && detail.ackComment ? [['ACK Comment', detail.ackComment] as [string, string]] : []),
    ] : [
      ['Device', incident.deviceName ?? 'Unknown'] as [string, string],
      ...(incident.deviceIp ? [['IP', incident.deviceIp] as [string, string]] : []),
    ]),
  ];

  return (
    <div className="min-h-full">
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between sticky top-0 bg-slate-950 z-10">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <h1 className="text-base font-semibold">Incident Detail</h1>
        <span
          className={`text-xs text-sky-400 ${isDetailLoading ? 'animate-spin' : 'invisible'}`}
          aria-hidden="true"
        >
          ↻
        </span>
      </header>

      <div className="p-3 space-y-2.5">
        {/* Status section */}
        <div className="bg-slate-900 rounded-xl p-3 flex items-center justify-between gap-3">
          {/* ACK / UnACK button */}
          {isAlarmsCleared ? (
            <div className="w-9 h-9 rounded-full bg-slate-700 flex items-center justify-center text-slate-400 text-lg flex-shrink-0">
              ✓
            </div>
          ) : isAcking ? (
            <div className="w-9 h-9 flex items-center justify-center flex-shrink-0">
              <span className="text-sky-400 animate-spin text-lg">↻</span>
            </div>
          ) : (
            <button
              type="button"
              onClick={handleToggleAck}
              className="w-9 h-9 rounded-full bg-sky-500 hover:bg-sky-400 flex items-center justify-center text-white text-lg flex-shrink-0 transition-colors"
              aria-label={isAcked ? 'Unacknowledge' : 'Acknowledge'}
            >
              {isAcked ? '↩' : '✓'}
            </button>
          )}

          {/* Status badge */}
          <div className="flex flex-col items-center gap-1">
            <span className="text-[10px] text-slate-500">Status</span>
            <StatusBadge status={incident.status} incidentState={incident.incidentState} />
          </div>

          {/* Alarm counts */}
          <AlarmBadges counts={alarmCounts} />
        </div>

        {/* Detail loading skeleton */}
        {isDetailLoading && !detail && (
          <div className="bg-slate-900 rounded-xl p-3 animate-pulse h-48" />
        )}

        {/* Detail error */}
        {isDetailError && !detail && (
          <div className="bg-slate-900 rounded-xl p-3 text-center">
            <p className="text-sm text-slate-400 mb-2">Failed to load incident details</p>
            <button
              type="button"
              onClick={() => refetchDetail()}
              className="text-xs text-sky-400 hover:text-sky-300"
            >
              Retry
            </button>
          </div>
        )}

        {/* Incident Info */}
        <div className="bg-slate-900 rounded-xl overflow-hidden">
          <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
            Incident Info
          </div>
          <div className="px-3">
            {infoRows.map(([label, value]) => (
              <div
                key={label}
                className="flex justify-between items-baseline gap-2 py-1.5 border-b border-slate-800/40 last:border-0 text-sm"
              >
                <span className="text-slate-500 flex-shrink-0">{label}</span>
                <span className="text-slate-200 text-right text-xs">{value}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Primary Alarms */}
        {detail && detail.primaryAlarms.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Primary Alarms ({detail.primaryAlarms.length})
            </div>
            <div className="px-3">
              {detail.primaryAlarms.map((alarm, i) => (
                <AlarmRow key={i} alarm={alarm} />
              ))}
            </div>
          </div>
        )}

        {/* Related Alarms */}
        {detail && detail.relatedAlarms.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Related Alarms ({detail.relatedAlarms.length})
            </div>
            <div className="px-3">
              {detail.relatedAlarms.map((alarm, i) => (
                <AlarmRow key={i} alarm={alarm} />
              ))}
            </div>
          </div>
        )}

        {/* Incident State Log */}
        {detail && detail.incidentLog.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Incident State Log
            </div>
            <div className="px-3">
              {detail.incidentLog.map((entry, i) => (
                <LogRow key={i} entry={entry} />
              ))}
            </div>
          </div>
        )}
      </div>

      <Toast message={toast} onDismiss={dismissToast} />
    </div>
  );
}
```

- [ ] **Step 4: Run all incident tests**

```bash
npx vitest run src/features/incidents/
```

Expected: all tests PASS.

- [ ] **Step 5: Run full test suite**

```bash
npx vitest run
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/features/incidents/IncidentDetailScreen.tsx \
        src/features/incidents/__tests__/IncidentDetailScreen.test.tsx
git commit -m "feat(pwa): rebuild IncidentDetailScreen — iOS parity with alarms, log, status section"
```

---

## Task 8: Update `shared/feature-spec.md`

**Files:**
- Modify: `shared/feature-spec.md`

- [ ] **Step 1: Update the Incident List and Incident Detail entries**

In `shared/feature-spec.md`, under `### Feature: Incident List`, append to `#### PWA-specific`:

```
- v0.9.0: Duration fixed — widens startTime field lookup to cover `incident_open_time` and `open_time`
- v0.9.0: Alarm badge fallback — when middleware cache cold, counts loaded lazily via `getincidentdetail` per row; shimmer placeholders shown while loading
```

Under `### Feature: Incident Detail` (add a new section after Device Detail if one doesn't exist, or update it):

Find the Device Detail section and add/update `#### PWA-specific` for incident detail:

```
- v0.9.0: Full iOS parity — `IncidentDetailScreen` fetches `getincidentdetail` on mount
  - Status section: icon ACK/UnACK button · StatusBadge · AlarmBadges (from detail)
  - Incident Info card: ID, title, device, IP, alert type, created, duration (Xd Xh Xm Xs), ACK fields when acknowledged
  - Primary Alarms card (hidden when empty): state badge · type · name · output · timestamp
  - Related Alarms card (hidden when empty): same structure
  - Incident State Log card (hidden when empty): state badge · timestamp · username · comment
  - New `StateBadge` component for alarm/log state strings (distinct from `StatusBadge`)
```

- [ ] **Step 2: Commit**

```bash
git add shared/feature-spec.md
git commit -m "docs: update feature-spec for v0.9.0 incident detail parity"
```
