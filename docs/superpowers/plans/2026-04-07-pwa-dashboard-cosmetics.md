# PWA Dashboard — iOS Cosmetics Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the PWA dashboard to match the iOS app's visual design — no data flow changes, purely cosmetic.

**Architecture:** Incremental refactor of existing dashboard components. Create 3 new components (ConnectionBadge, RefreshRing, SummaryCards), restyle 2 existing (StatusCard, IncidentTicker), update DashboardScreen layout order.

**Tech Stack:** React 19, TypeScript, Tailwind CSS, Vitest, @testing-library/react

**Spec:** `docs/superpowers/specs/2026-04-07-pwa-dashboard-cosmetics-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `pwa/src/components/ConnectionBadge.tsx` | Create | Chain-link SVG icon, color states, blink animation, tappable |
| `pwa/src/components/RefreshRing.tsx` | Create | Circular SVG countdown ring, spinner state, tappable |
| `pwa/src/features/dashboard/SummaryCards.tsx` | Create | Active Incidents + Total Devices row |
| `pwa/src/features/dashboard/StatusCard.tsx` | Modify | Restyle to iOS statBox (centered, solid badges) |
| `pwa/src/features/dashboard/IncidentTicker.tsx` | Rewrite | Step-through with page dots, multi-line card |
| `pwa/src/features/dashboard/DashboardScreen.tsx` | Modify | New layout order, new header |
| `pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx` | Modify | Update assertions for new layout |

---

### Task 1: ConnectionBadge Component

**Files:**
- Create: `pwa/src/components/ConnectionBadge.tsx`
- Create: `pwa/src/components/__tests__/ConnectionBadge.test.tsx`

- [ ] **Step 1: Write the test**

Create `pwa/src/components/__tests__/ConnectionBadge.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConnectionBadge } from '../ConnectionBadge';

describe('ConnectionBadge', () => {
  it('renders as a button', () => {
    render(<ConnectionBadge status="connected" onRetry={vi.fn()} />);
    expect(screen.getByRole('button', { name: /connection/i })).toBeInTheDocument();
  });

  it('calls onRetry when clicked', () => {
    const onRetry = vi.fn();
    render(<ConnectionBadge status="connected" onRetry={onRetry} />);
    fireEvent.click(screen.getByRole('button'));
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('renders SVG chain links', () => {
    const { container } = render(<ConnectionBadge status="connected" onRetry={vi.fn()} />);
    const rects = container.querySelectorAll('rect');
    expect(rects.length).toBe(2); // two chain links
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/components/__tests__/ConnectionBadge.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Implement ConnectionBadge**

Create `pwa/src/components/ConnectionBadge.tsx`:

```tsx
import { useState, useEffect } from 'react';

export type ConnectionStatus = 'unknown' | 'checking' | 'connected' | 'disconnected';

const STATUS_COLORS: Record<ConnectionStatus, string> = {
  unknown: '#6b7280',      // grey
  checking: '#f97316',     // orange
  connected: '#22863a',    // green
  disconnected: '#ef4444', // red
};

interface Props {
  status: ConnectionStatus;
  onRetry: () => void;
}

export function ConnectionBadge({ status, onRetry }: Props) {
  const [blinkOn, setBlinkOn] = useState(true);
  const shouldBlink = status === 'checking' || status === 'disconnected';
  const broken = status === 'disconnected';
  const color = STATUS_COLORS[status];

  useEffect(() => {
    if (!shouldBlink) {
      setBlinkOn(true);
      return;
    }
    const timer = setInterval(() => setBlinkOn((v) => !v), 700);
    return () => clearInterval(timer);
  }, [shouldBlink]);

  const opacity = shouldBlink ? (blinkOn ? 1 : 0.15) : 1;

  return (
    <button
      type="button"
      onClick={onRetry}
      className="p-1"
      aria-label="Connection status — tap to refresh"
    >
      <svg
        width="26"
        height="22"
        viewBox="0 0 26 22"
        fill="none"
        style={{ opacity, transition: 'opacity 0.3s' }}
      >
        {/* Left chain link */}
        <rect
          x={broken ? 0 : 3}
          y="2"
          width="8"
          height="13"
          rx="3"
          stroke={color}
          strokeWidth="2.5"
          fill="none"
          transform={`rotate(45, ${broken ? 4 : 7}, 8.5)`}
        />
        {/* Right chain link */}
        <rect
          x={broken ? 18 : 15}
          y="2"
          width="8"
          height="13"
          rx="3"
          stroke={color}
          strokeWidth="2.5"
          fill="none"
          transform={`rotate(45, ${broken ? 22 : 19}, 8.5)`}
        />
      </svg>
    </button>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/components/__tests__/ConnectionBadge.test.tsx`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/components/ConnectionBadge.tsx pwa/src/components/__tests__/ConnectionBadge.test.tsx
git commit -m "feat(pwa): add ConnectionBadge component (chain-link icon with blink)"
```

---

### Task 2: RefreshRing Component

**Files:**
- Create: `pwa/src/components/RefreshRing.tsx`
- Create: `pwa/src/components/__tests__/RefreshRing.test.tsx`

- [ ] **Step 1: Write the test**

Create `pwa/src/components/__tests__/RefreshRing.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { RefreshRing } from '../RefreshRing';

describe('RefreshRing', () => {
  it('renders as a tappable button', () => {
    render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={vi.fn()} />,
    );
    expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument();
  });

  it('calls onRefresh when clicked', () => {
    const onRefresh = vi.fn();
    render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={onRefresh} />,
    );
    fireEvent.click(screen.getByRole('button'));
    expect(onRefresh).toHaveBeenCalledOnce();
  });

  it('renders SVG circle for countdown', () => {
    const { container } = render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={vi.fn()} />,
    );
    const circles = container.querySelectorAll('circle');
    expect(circles.length).toBeGreaterThanOrEqual(2); // background + progress
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pwa && npx vitest run src/components/__tests__/RefreshRing.test.tsx`
Expected: FAIL — module not found

- [ ] **Step 3: Implement RefreshRing**

Create `pwa/src/components/RefreshRing.tsx`:

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

  // SVG circle math
  const size = 28;
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
          {/* Background ring */}
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#334155" strokeWidth={strokeWidth} fill="none"
          />
          {/* Progress ring */}
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#38bdf8" strokeWidth={strokeWidth} fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
            strokeLinecap="round"
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
            style={{ transition: 'stroke-dashoffset 1s linear' }}
          />
        </svg>
      )}
    </button>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd pwa && npx vitest run src/components/__tests__/RefreshRing.test.tsx`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add pwa/src/components/RefreshRing.tsx pwa/src/components/__tests__/RefreshRing.test.tsx
git commit -m "feat(pwa): add RefreshRing component (circular SVG countdown)"
```

---

### Task 3: SummaryCards Component

**Files:**
- Create: `pwa/src/features/dashboard/SummaryCards.tsx`

- [ ] **Step 1: Create the component**

Create `pwa/src/features/dashboard/SummaryCards.tsx`:

```tsx
import { Link } from 'react-router-dom';

interface Props {
  activeIncidents: number;
  totalDevices: number;
}

function Card({
  icon,
  count,
  label,
  color,
  borderColor,
  shadowColor,
  to,
}: {
  icon: string;
  count: number;
  label: string;
  color: string;
  borderColor: string;
  shadowColor: string;
  to?: string;
}) {
  const content = (
    <div
      className="flex-1 p-4 rounded-[14px] bg-slate-950 text-center"
      style={{
        border: `1.5px solid ${borderColor}`,
        boxShadow: `0 3px 6px ${shadowColor}`,
      }}
    >
      <div className="flex items-center justify-center gap-2">
        <span className="text-xl">{icon}</span>
        <span className="text-2xl font-bold" style={{ color }}>{count}</span>
      </div>
      <div className="text-xs text-slate-400 mt-1">{label}</div>
    </div>
  );

  if (to) {
    return <Link to={to} className="flex-1">{content}</Link>;
  }
  return content;
}

export function SummaryCards({ activeIncidents, totalDevices }: Props) {
  const incidentColor = activeIncidents > 0 ? '#f87171' : '#4ade80';
  const incidentBorder = activeIncidents > 0 ? 'rgba(239,68,68,0.25)' : 'rgba(74,222,128,0.25)';
  const incidentShadow = activeIncidents > 0 ? 'rgba(239,68,68,0.12)' : 'rgba(74,222,128,0.12)';

  return (
    <div className="flex gap-3">
      <Card
        icon="⚠"
        count={activeIncidents}
        label="Active Incidents"
        color={incidentColor}
        borderColor={incidentBorder}
        shadowColor={incidentShadow}
        to="/incidents"
      />
      <Card
        icon="🖥"
        count={totalDevices}
        label="Total Devices"
        color="#60a5fa"
        borderColor="rgba(59,130,246,0.25)"
        shadowColor="rgba(59,130,246,0.12)"
      />
    </div>
  );
}
```

- [ ] **Step 2: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS (no tests broken by adding a new file)

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/dashboard/SummaryCards.tsx
git commit -m "feat(pwa): add SummaryCards component (Active Incidents + Total Devices)"
```

---

### Task 4: Restyle StatusCard to iOS statBox

**Files:**
- Modify: `pwa/src/features/dashboard/StatusCard.tsx`

- [ ] **Step 1: Replace StatusCard with iOS-style design**

Replace the entire contents of `pwa/src/features/dashboard/StatusCard.tsx`:

```tsx
import type { StatusCounts } from '../../lib/api/tactical-overview';

interface Props {
  label: string;
  counts: StatusCounts;
}

const BADGE_COLORS = [
  { bg: '#22c55e', text: '#fff' },    // green (ok)
  { bg: '#3b82f6', text: '#fff' },    // blue (ack)
  { bg: '#eab308', text: '#000' },    // yellow (warn)
  { bg: '#f97316', text: '#fff' },    // orange (un)
  { bg: '#ef4444', text: '#fff' },    // red (crit)
];

export function StatusCard({ label, counts }: Props) {
  const values = [counts.ok, counts.ack, counts.warn, counts.un, counts.crit];
  const total = values.reduce((a, b) => a + b, 0);

  return (
    <div className="bg-slate-800 rounded-[13px] py-[13px] px-[10px] text-center border border-slate-700/50">
      <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">
        {label}
      </div>
      <div className="text-[21px] font-semibold my-1 tabular-nums">
        {total}
      </div>
      <div className="flex gap-[3px]">
        {values.map((n, i) => (
          <span
            key={i}
            className="flex-1 text-[9px] font-semibold py-[3px] rounded-lg text-center tabular-nums"
            style={
              n > 0
                ? { background: BADGE_COLORS[i].bg, color: BADGE_COLORS[i].text }
                : { color: '#4b5563', border: '0.5px solid #374151' }
            }
          >
            {n}
          </span>
        ))}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Run tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS (StatusCard has no dedicated test file; DashboardScreen test checks text content which still works)

- [ ] **Step 3: Commit**

```bash
git add pwa/src/features/dashboard/StatusCard.tsx
git commit -m "feat(pwa): restyle StatusCard to iOS statBox (centered count, solid badges)"
```

---

### Task 5: Rewrite IncidentTicker (step-through with page dots)

**Files:**
- Modify: `pwa/src/features/dashboard/IncidentTicker.tsx`

- [ ] **Step 1: Replace IncidentTicker with step-through design**

Replace the entire contents of `pwa/src/features/dashboard/IncidentTicker.tsx`:

```tsx
import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { SeverityBadge } from '../incidents/SeverityBadge';
import { buildDisplayId } from '../../lib/api/incidents';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  const [currentIndex, setCurrentIndex] = useState(0);

  useEffect(() => {
    if (urgent.length <= 1) return;
    const timer = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % urgent.length);
    }, 4_000);
    return () => clearInterval(timer);
  }, [urgent.length]);

  // Reset index if incidents change
  useEffect(() => {
    setCurrentIndex(0);
  }, [urgent.length]);

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-3 text-sm text-slate-500 border border-slate-700/50">
        No critical or major incidents
      </div>
    );
  }

  const incident = urgent[currentIndex] ?? urgent[0];

  return (
    <Link
      to={`/incidents/${incident.incidentId}`}
      className="block bg-slate-800 rounded-xl p-3 px-3.5 border border-slate-700/50 hover:bg-slate-750 transition-colors"
    >
      {/* Line 1: severity + ID + page dots */}
      <div className="flex items-center justify-between mb-1.5">
        <div className="flex items-center gap-1.5">
          <SeverityBadge severity={incident.severity} />
          <span className="text-[11px] text-slate-500">
            {buildDisplayId(incident.incidentId)}
          </span>
        </div>
        {urgent.length > 1 && (
          <div className="flex gap-1">
            {urgent.map((_, i) => (
              <span
                key={i}
                className={`w-1.5 h-1.5 rounded-full ${
                  i === currentIndex ? 'bg-sky-400' : 'bg-slate-600'
                }`}
              />
            ))}
          </div>
        )}
      </div>

      {/* Line 2: summary */}
      <div className="text-[13px] text-slate-100 mb-1 truncate">
        {incident.summary}
      </div>

      {/* Line 3: device name */}
      <div className="text-xs text-slate-400">
        {incident.deviceName ?? 'Unknown'}
      </div>
    </Link>
  );
}
```

- [ ] **Step 2: Remove the ticker CSS animation**

In `pwa/tailwind.config.js` (or `tailwind.config.ts`), find and remove the `ticker` animation and keyframe if they exist. If the file doesn't have a custom ticker animation, skip this step.

- [ ] **Step 3: Run tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS (DashboardScreen test checks for "Router-1" text which still renders)

- [ ] **Step 4: Commit**

```bash
git add pwa/src/features/dashboard/IncidentTicker.tsx
git commit -m "feat(pwa): rewrite IncidentTicker as step-through card with page dots"
```

---

### Task 6: Update DashboardScreen Layout and Header

**Files:**
- Modify: `pwa/src/features/dashboard/DashboardScreen.tsx`
- Modify: `pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx`

- [ ] **Step 1: Replace DashboardScreen**

Replace the entire contents of `pwa/src/features/dashboard/DashboardScreen.tsx`:

```tsx
import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { ConnectionBadge, type ConnectionStatus } from '../../components/ConnectionBadge';
import { RefreshRing } from '../../components/RefreshRing';
import { SummaryCards } from './SummaryCards';
import { IncidentTicker } from './IncidentTicker';
import { StatusCard } from './StatusCard';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const config = useConfig();
  const queryClient = useQueryClient();
  const { data: summary, isLoading: summaryLoading, isError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents, isLoading: incidentsLoading } = useIncidents();
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>(
    config.isConfigured ? 'unknown' : 'disconnected',
  );

  // Derive connection status from query state
  const isLoading = summaryLoading || incidentsLoading;
  const derivedStatus: ConnectionStatus = isLoading
    ? 'checking'
    : isError
      ? 'disconnected'
      : summary
        ? 'connected'
        : connectionStatus;

  const handleRefresh = useCallback(() => {
    setConnectionStatus('checking');
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
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <ConnectionBadge status={derivedStatus} onRetry={handleRefresh} />
        <div className="text-center">
          <div className="flex items-center justify-center gap-1.5">
            <div className="w-6 h-6 bg-blue-600 rounded-md flex items-center justify-center text-[12px] font-bold text-white">
              B
            </div>
            <h1 className="text-lg font-bold">Home</h1>
          </div>
          {config.serverName && (
            <p className="text-[11px] text-slate-500">{config.serverName}</p>
          )}
        </div>
        {dataUpdatedAt > 0 ? (
          <RefreshRing
            lastUpdatedAt={dataUpdatedAt}
            intervalMs={120_000}
            isLoading={isLoading}
            onRefresh={handleRefresh}
          />
        ) : (
          <div className="w-7" /> // spacer
        )}
      </header>

      {!config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — add a server in Settings.</span>
          <Link to="/settings" className="px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
            Configure
          </Link>
        </div>
      )}

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

- [ ] **Step 2: Update the DashboardScreen test**

Replace the entire contents of `pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DashboardScreen } from '../DashboardScreen';

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
  it('renders heat map cards', () => {
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

  it('renders summary cards', () => {
    renderDashboard();
    expect(screen.getByText('Active Incidents')).toBeInTheDocument();
    expect(screen.getByText('Total Devices')).toBeInTheDocument();
  });

  it('renders incident ticker with critical incidents', () => {
    renderDashboard();
    expect(screen.getByText('Router-1')).toBeInTheDocument();
  });

  it('renders Home title', () => {
    renderDashboard();
    expect(screen.getByText('Home')).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: Run tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS

- [ ] **Step 4: Run type check**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add pwa/src/features/dashboard/DashboardScreen.tsx pwa/src/features/dashboard/__tests__/DashboardScreen.test.tsx
git commit -m "feat(pwa): dashboard iOS-style layout with summary cards, connection badge, refresh ring"
```

---

### Task 7: Full Test Suite and Type Check

- [ ] **Step 1: Run type checker**

Run: `cd pwa && npx tsc --noEmit`
Expected: No errors

- [ ] **Step 2: Run all tests**

Run: `cd pwa && npx vitest run`
Expected: ALL PASS

- [ ] **Step 3: Fix any issues**

If type errors exist, they'll likely be from unused imports in DashboardScreen (old RefreshCountdown import). Fix by removing stale imports.

- [ ] **Step 4: Commit if fixes needed**

```bash
git add -A pwa/src
git commit -m "fix(pwa): resolve type errors from dashboard cosmetics changes"
```
