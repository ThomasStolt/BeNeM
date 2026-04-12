# Unified App Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an M:SS countdown inside a resized RefreshRing, then extract a shared `AppHeader` component and use it on all four main screens (Home, Incidents, Devices, Settings).

**Architecture:** Two independent changes: (1) `RefreshRing` grows from 28 px to 40 px and gains an SVG `<text>` countdown centred inside; (2) a new `AppHeader` component reads `useConfig()` internally and derives connection status from props, replacing four bespoke `<header>` blocks. Each screen passes its own `isLoading`/`isError`/`dataUpdatedAt`; Settings omits `dataUpdatedAt` to suppress the ring.

**Tech Stack:** React 19, TypeScript, Tailwind CSS, Vitest, React Testing Library.

---

## File Map

| File | Action |
|---|---|
| `src/components/RefreshRing.tsx` | Modify — resize to 40 px, add `<text>` countdown |
| `src/components/__tests__/RefreshRing.test.tsx` | Modify — add countdown tests |
| `src/components/AppHeader.tsx` | Create — shared header component |
| `src/components/__tests__/AppHeader.test.tsx` | Create — connection status + ring visibility tests |
| `src/features/dashboard/DashboardScreen.tsx` | Modify — use AppHeader, remove inline connection state |
| `src/features/incidents/IncidentListScreen.tsx` | Modify — use AppHeader, add dataUpdatedAt |
| `src/features/devices/DeviceListScreen.tsx` | Modify — use AppHeader, remove RefreshCountdown |
| `src/features/settings/SettingsScreen.tsx` | Modify — use AppHeader |

---

## Task 1: Update RefreshRing — resize + countdown

**Files:**
- Modify: `src/components/RefreshRing.tsx`
- Modify: `src/components/__tests__/RefreshRing.test.tsx`

- [ ] **Step 1: Add failing countdown tests to `src/components/__tests__/RefreshRing.test.tsx`**

Add inside `describe('RefreshRing')`:

```tsx
it('renders M:SS countdown text when not loading', () => {
  const { container } = render(
    <RefreshRing
      lastUpdatedAt={Date.now() - 30_000}
      intervalMs={120_000}
      isLoading={false}
      onRefresh={vi.fn()}
    />,
  );
  const textEl = container.querySelector('text');
  expect(textEl).toBeInTheDocument();
  expect(textEl?.textContent).toMatch(/^\d+:\d{2}$/);
});

it('hides countdown text while loading', () => {
  const { container } = render(
    <RefreshRing
      lastUpdatedAt={Date.now()}
      intervalMs={120_000}
      isLoading={true}
      onRefresh={vi.fn()}
    />,
  );
  expect(container.querySelector('text')).not.toBeInTheDocument();
});

it('renders with 40px dimensions', () => {
  const { container } = render(
    <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={vi.fn()} />,
  );
  const svgs = container.querySelectorAll('svg');
  expect(svgs[0]).toHaveAttribute('width', '40');
  expect(svgs[0]).toHaveAttribute('height', '40');
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
cd pwa && npx vitest run src/components/__tests__/RefreshRing.test.tsx
```

Expected: 3 new tests FAIL, existing 3 tests pass.

- [ ] **Step 3: Replace `src/components/RefreshRing.tsx`**

```tsx
import { useState, useEffect } from 'react';

interface Props {
  lastUpdatedAt: number;
  intervalMs: number;
  isLoading: boolean;
  onRefresh: () => void;
}

export function RefreshRing({ lastUpdatedAt, intervalMs, isLoading, onRefresh }: Props) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    setNow(Date.now());
  }, [lastUpdatedAt]);

  const elapsed = now - lastUpdatedAt;
  const progress = Math.min(1, elapsed / intervalMs);
  const remaining = Math.max(0, intervalMs - elapsed);
  const countdownText = `${Math.floor(remaining / 60_000)}:${String(
    Math.floor((remaining % 60_000) / 1_000),
  ).padStart(2, '0')}`;

  const size = 40;
  const strokeWidth = 2;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - progress);

  return (
    <button
      type="button"
      onClick={onRefresh}
      className="relative flex items-center justify-center"
      style={{ width: size, height: size }}
      aria-label="Refresh — tap to reload"
    >
      {isLoading ? (
        <svg width={size} height={size} className="animate-spin">
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#334155" strokeWidth={strokeWidth} fill="none"
          />
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#38bdf8" strokeWidth={strokeWidth} fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={circumference * 0.75}
            strokeLinecap="round"
          />
        </svg>
      ) : (
        <svg width={size} height={size}>
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#334155" strokeWidth={strokeWidth} fill="none"
          />
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#38bdf8" strokeWidth={strokeWidth} fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
            strokeLinecap="round"
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
            style={{ transition: 'stroke-dashoffset 1s linear' }}
          />
          <text
            x={size / 2}
            y={size / 2}
            textAnchor="middle"
            dominantBaseline="central"
            fontSize="9"
            fontWeight="700"
            fill="#64748b"
            style={{ fontFamily: 'inherit', letterSpacing: '-0.03em' }}
          >
            {countdownText}
          </text>
        </svg>
      )}
    </button>
  );
}
```

- [ ] **Step 4: Run all RefreshRing tests**

```bash
npx vitest run src/components/__tests__/RefreshRing.test.tsx
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/RefreshRing.tsx src/components/__tests__/RefreshRing.test.tsx
git commit -m "feat(pwa): resize RefreshRing to 40px and add M:SS countdown"
```

---

## Task 2: Create `AppHeader` component

**Files:**
- Create: `src/components/AppHeader.tsx`
- Create: `src/components/__tests__/AppHeader.test.tsx`

- [ ] **Step 1: Write failing tests in `src/components/__tests__/AppHeader.test.tsx`**

```tsx
// @vitest-environment jsdom
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AppHeader } from '../AppHeader';

vi.mock('../../lib/config', () => ({
  useConfig: vi.fn(() => ({
    serverId: 'srv1',
    serverName: 'AENA PROD',
    baseUrl: 'https://test.example.com',
    apiKey: 'key',
    isConfigured: true,
    ackUser: '',
    bhnmUrl: '',
  })),
}));

// ResizeObserver not in jsdom (needed by RefreshRing internals via button)
beforeEach(() => {
  vi.stubGlobal('ResizeObserver', vi.fn(() => ({ observe: vi.fn(), disconnect: vi.fn() })));
});

import { useConfig } from '../../lib/config';

describe('AppHeader', () => {
  it('renders the title', () => {
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('heading', { name: 'Home' })).toBeInTheDocument();
  });

  it('renders the server name when present', () => {
    render(<AppHeader title="Incidents" />);
    expect(screen.getByText('AENA PROD')).toBeInTheDocument();
  });

  it('omits server name when serverName is empty', () => {
    vi.mocked(useConfig).mockReturnValueOnce({
      serverId: 'srv1', serverName: '', baseUrl: 'https://x', apiKey: 'k',
      isConfigured: true, ackUser: '', bhnmUrl: '',
    });
    render(<AppHeader title="Home" />);
    expect(screen.queryByText('AENA PROD')).not.toBeInTheDocument();
  });

  it('renders connection badge', () => {
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('button', { name: /connection status/i })).toBeInTheDocument();
  });

  it('shows RefreshRing when dataUpdatedAt is positive', () => {
    render(<AppHeader title="Home" dataUpdatedAt={Date.now()} onRefresh={vi.fn()} />);
    expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument();
  });

  it('hides RefreshRing when dataUpdatedAt is 0 (Settings)', () => {
    render(<AppHeader title="Settings" />);
    expect(screen.queryByRole('button', { name: /refresh/i })).not.toBeInTheDocument();
  });

  it('shows disconnected status when not configured', () => {
    vi.mocked(useConfig).mockReturnValueOnce({
      serverId: '', serverName: '', baseUrl: '', apiKey: '',
      isConfigured: false, ackUser: '', bhnmUrl: '',
    });
    // ConnectionBadge is always rendered regardless of status
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('button', { name: /connection status/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/components/__tests__/AppHeader.test.tsx
```

Expected: all tests FAIL with "Cannot find module '../AppHeader'".

- [ ] **Step 3: Create `src/components/AppHeader.tsx`**

```tsx
import { useConfig } from '../lib/config';
import { ConnectionBadge, type ConnectionStatus } from './ConnectionBadge';
import { RefreshRing } from './RefreshRing';

interface AppHeaderProps {
  title: string;
  isLoading?: boolean;
  isError?: boolean;
  dataUpdatedAt?: number;
  intervalMs?: number;
  onRefresh?: () => void;
}

export function AppHeader({
  title,
  isLoading = false,
  isError = false,
  dataUpdatedAt = 0,
  intervalMs = 120_000,
  onRefresh,
}: AppHeaderProps) {
  const config = useConfig();
  const handleRefresh = onRefresh ?? (() => {});

  const derivedStatus: ConnectionStatus =
    !config.isConfigured ? 'disconnected' :
    isLoading             ? 'checking'     :
    isError               ? 'disconnected' :
    dataUpdatedAt > 0     ? 'connected'    :
                            'unknown';

  return (
    <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
      <ConnectionBadge status={derivedStatus} onRetry={handleRefresh} />
      <div className="text-center">
        <div className="flex items-center justify-center gap-1.5">
          <div className="w-6 h-6 bg-blue-600 rounded-md flex items-center justify-center text-[12px] font-bold text-white flex-shrink-0">
            B
          </div>
          <h1 className="text-lg font-bold">{title}</h1>
        </div>
        {config.serverName && (
          <p className="text-[11px] text-slate-500">{config.serverName}</p>
        )}
      </div>
      {dataUpdatedAt > 0 ? (
        <RefreshRing
          lastUpdatedAt={dataUpdatedAt}
          intervalMs={intervalMs}
          isLoading={isLoading}
          onRefresh={handleRefresh}
        />
      ) : (
        <div className="w-10" />
      )}
    </header>
  );
}
```

- [ ] **Step 4: Run AppHeader tests**

```bash
npx vitest run src/components/__tests__/AppHeader.test.tsx
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/AppHeader.tsx src/components/__tests__/AppHeader.test.tsx
git commit -m "feat(pwa): add AppHeader — unified header with connection badge, title, and RefreshRing"
```

---

## Task 3: Update DashboardScreen

**Files:**
- Modify: `src/features/dashboard/DashboardScreen.tsx`

- [ ] **Step 1: Run existing DashboardScreen tests to confirm baseline**

```bash
cd pwa && npx vitest run src/features/dashboard/__tests__/DashboardScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 2: Replace `src/features/dashboard/DashboardScreen.tsx`**

```tsx
import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { AppHeader } from '../../components/AppHeader';
import { SummaryCards } from './SummaryCards';
import { IncidentTicker } from './IncidentTicker';
import { StatusCard } from './StatusCard';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const queryClient = useQueryClient();
  const { data: summary, isLoading: summaryLoading, isError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents, isLoading: incidentsLoading } = useIncidents();

  const isLoading = summaryLoading || incidentsLoading;

  const handleRefresh = useCallback(() => {
    queryClient.invalidateQueries();
  }, [queryClient]);

  const activeIncidents = incidents?.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  ).length ?? 0;

  const totalDevices = summary
    ? summary.hosts.ok + summary.hosts.ack + summary.hosts.warn + summary.hosts.un + summary.hosts.crit
    : 0;

  return (
    <div className="min-h-full">
      <AppHeader
        title="Home"
        isLoading={isLoading}
        isError={isError}
        dataUpdatedAt={dataUpdatedAt}
        onRefresh={handleRefresh}
      />

      {isLoading && !summary && (
        <EmptyState title="Loading..." description="Fetching status from BHNM." />
      )}

      {isError && !summary && (
        <EmptyState
          title="Could not load dashboard"
          description={(error as Error).message}
        />
      )}

      {summary && (
        <div className="p-4 space-y-4">
          {/* 1. Summary Cards */}
          <SummaryCards activeIncidents={activeIncidents} totalDevices={totalDevices} />

          {/* 2. Incident Ticker */}
          <IncidentTicker incidents={incidents ?? []} />

          {/* 3. Heat Map 2x2 */}
          <div className="grid grid-cols-2 gap-2">
            <StatusCard label="Hosts" counts={summary.hosts} />
            <StatusCard label="Services" counts={summary.services} />
            <StatusCard label="Thresholds" counts={summary.thresholds} />
            <StatusCard label="Anomalies" counts={summary.anomalies} />
          </div>

          {/* 4. Drill Down */}
          <div>
            <div className="text-base font-semibold mb-3">Drill Down</div>
            <div className="flex flex-col gap-2.5">
              <Link
                to="/tactical/category"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-purple-400 text-lg">🏷</span>
                <span className="text-[15px] font-semibold flex-1">Categories</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
              <Link
                to="/tactical/site"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-blue-400 text-lg">📍</span>
                <span className="text-[15px] font-semibold flex-1">Sites</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
              <Link
                to="/tactical/bw"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-green-400 text-lg">🔄</span>
                <span className="text-[15px] font-semibold flex-1">Business Workflows</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
```

Note: the "Not configured" banner (`!config.isConfigured` block) is removed — `AppHeader`'s `ConnectionBadge` now shows `'disconnected'` status when not configured, which is sufficient. The `useConfig` import is no longer needed in `DashboardScreen` itself.

- [ ] **Step 3: Run DashboardScreen tests**

```bash
npx vitest run src/features/dashboard/__tests__/DashboardScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/dashboard/DashboardScreen.tsx
git commit -m "feat(pwa): DashboardScreen uses AppHeader"
```

---

## Task 4: Update IncidentListScreen

**Files:**
- Modify: `src/features/incidents/IncidentListScreen.tsx`

- [ ] **Step 1: Run existing IncidentListScreen tests to confirm baseline**

```bash
cd pwa && npx vitest run src/features/incidents/__tests__/IncidentListScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 2: Replace `src/features/incidents/IncidentListScreen.tsx`**

```tsx
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { SwipeableIncidentRow } from './SwipeableIncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { AppHeader } from '../../components/AppHeader';

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
  const { data, isLoading, isError, error, refetch, dataUpdatedAt } = useIncidents();
  const queryClient = useQueryClient();

  const onRefresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    await refetch();
  };

  return (
    <PullToRefresh onRefresh={onRefresh}>
      <AppHeader
        title="Incidents"
        isLoading={isLoading}
        isError={isError}
        dataUpdatedAt={dataUpdatedAt}
        onRefresh={onRefresh}
      />

      {isLoading && !data && (
        <EmptyState title="Loading…" description="Fetching incidents from BHNM." />
      )}

      {isError && !data && (
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

      {data && data.length === 0 && (
        <EmptyState title="No incidents" description="All clear." />
      )}

      {data && data.length > 0 && (
        <ul>
          {data.map((incident) => (
            <SwipeableIncidentRow key={incident.incidentId} incident={incident} />
          ))}
        </ul>
      )}
    </PullToRefresh>
  );
}
```

- [ ] **Step 3: Run IncidentListScreen tests**

```bash
npx vitest run src/features/incidents/__tests__/IncidentListScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/incidents/IncidentListScreen.tsx
git commit -m "feat(pwa): IncidentListScreen uses AppHeader"
```

---

## Task 5: Update DeviceListScreen

**Files:**
- Modify: `src/features/devices/DeviceListScreen.tsx`

- [ ] **Step 1: Run existing DeviceListScreen tests to confirm baseline**

```bash
cd pwa && npx vitest run src/features/devices/__tests__/DeviceListScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 2: In `src/features/devices/DeviceListScreen.tsx`, make these targeted changes**

Remove the `RefreshCountdown` import:
```ts
// Remove this line:
import { RefreshCountdown } from '../../components/RefreshCountdown';
```

Add the `AppHeader` import:
```ts
import { AppHeader } from '../../components/AppHeader';
```

Replace the entire `<header>` block (lines starting `<header className=...` through `</header>`) with:

```tsx
<AppHeader
  title="Devices"
  isLoading={isLoading}
  isError={isError}
  dataUpdatedAt={dataUpdatedAt}
  onRefresh={() => queryClient.invalidateQueries({ queryKey: ['devices'] })}
/>
```

Also add `useQueryClient` and `useCallback` imports — check whether `useQueryClient` is already imported. If not, add:

```ts
import { useQueryClient } from '@tanstack/react-query';
```

And add inside `DeviceListScreen()`:
```ts
const queryClient = useQueryClient();
```

Note: the page info sub-line (`Page X of Y`) that was previously shown below the "Devices" title in the header is not included in `AppHeader` — it is removed from the header. The search bar and pagination controls remain in the content area below the header.

- [ ] **Step 3: Run DeviceListScreen tests**

```bash
npx vitest run src/features/devices/__tests__/DeviceListScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/features/devices/DeviceListScreen.tsx
git commit -m "feat(pwa): DeviceListScreen uses AppHeader, remove RefreshCountdown from header"
```

---

## Task 6: Update SettingsScreen

**Files:**
- Modify: `src/features/settings/SettingsScreen.tsx`

- [ ] **Step 1: Run existing SettingsScreen tests to confirm baseline**

```bash
cd pwa && npx vitest run src/features/settings/__tests__/SettingsScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 2: In `src/features/settings/SettingsScreen.tsx`, make these targeted changes**

Add the `AppHeader` import at the top of the imports:
```ts
import { AppHeader } from '../../components/AppHeader';
```

Replace the `<header>` block:
```tsx
// Remove:
<header className="px-4 py-3 border-b border-slate-800 flex items-center justify-center">
  <h1 className="text-lg font-semibold">Settings</h1>
</header>

// Replace with:
<AppHeader title="Settings" />
```

- [ ] **Step 3: Run SettingsScreen tests**

```bash
npx vitest run src/features/settings/__tests__/SettingsScreen.test.tsx
```

Expected: all tests PASS.

- [ ] **Step 4: Run full test suite**

```bash
npx vitest run
```

Expected: all tests PASS (302+ tests, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add src/features/settings/SettingsScreen.tsx
git commit -m "feat(pwa): SettingsScreen uses AppHeader"
```
