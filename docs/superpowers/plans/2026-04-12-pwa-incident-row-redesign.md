# PWA Incident Row Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `IncidentRow` to a 2-row iOS-parity layout — incident ID + scrolling title on row 1; status badge (OPEN/ACKD/CLRD) + scrolling device name + compact duration + 5-colour alarm dots on row 2.

**Architecture:** A new generic `OverflowMarquee` component uses `ResizeObserver` to detect when text overflows its container, then switches from static truncation to a continuous dual-copy CSS animation (reusing the existing `marquee` keyframe from `tailwind.config.js`). A new `StatusBadge` component maps incident status + state to OPEN/ACKD/CLRD. `IncidentRow` is fully rewritten to compose these two new components.

**Tech Stack:** React 19, TypeScript, Tailwind CSS (existing `marquee` keyframe), Vitest + Testing Library

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src/components/OverflowMarquee.tsx` | Generic overflow-detecting continuous marquee |
| Create | `src/components/OverflowMarquee.test.tsx` | Unit tests for marquee behaviour |
| Create | `src/features/incidents/StatusBadge.tsx` | OPEN / ACKD / CLRD badge pill |
| Create | `src/features/incidents/StatusBadge.test.tsx` | Unit tests for badge mapping |
| Modify | `src/features/incidents/IncidentRow.tsx` | 2-row layout using new components |
| Create | `src/features/incidents/__tests__/IncidentRow.test.tsx` | Row integration tests |
| Modify | `src/features/incidents/__tests__/IncidentListScreen.test.tsx` | Update stale severity-badge assertion |

---

## Task 1: `OverflowMarquee` component

**Files:**
- Create: `src/components/OverflowMarquee.tsx`
- Create: `src/components/OverflowMarquee.test.tsx`

- [ ] **Step 1.1 — Write the failing tests**

Create `src/components/OverflowMarquee.test.tsx`:

```tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { OverflowMarquee } from './OverflowMarquee';

// jsdom has no ResizeObserver — capture the callback so we can invoke it manually
let roCallback: ResizeObserverCallback;
const mockObserve = vi.fn();
const mockDisconnect = vi.fn();

beforeEach(() => {
  vi.stubGlobal(
    'ResizeObserver',
    vi.fn((cb: ResizeObserverCallback) => {
      roCallback = cb;
      return { observe: mockObserve, disconnect: mockDisconnect };
    }),
  );
});

describe('OverflowMarquee', () => {
  it('renders text in static mode when dimensions are equal (no overflow)', () => {
    const { container } = render(<OverflowMarquee text="Short text" />);
    // In jsdom scrollWidth = clientWidth = 0 → no overflow → no animate-marquee
    expect(container.querySelector('.animate-marquee')).not.toBeInTheDocument();
    expect(screen.getAllByText('Short text').length).toBeGreaterThan(0);
  });

  it('activates continuous marquee when measure span overflows clip container', () => {
    const { container } = render(<OverflowMarquee text="A very long incident title that overflows" />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    Object.defineProperty(measureEl, 'scrollWidth', { value: 400, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 150, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    expect(container.querySelector('.animate-marquee')).toBeInTheDocument();
  });

  it('renders two text copies in overflow mode (for seamless loop)', () => {
    const { container } = render(<OverflowMarquee text="Long title" />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    Object.defineProperty(measureEl, 'scrollWidth', { value: 300, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 100, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    expect(screen.getAllByText('Long title')).toHaveLength(2);
  });

  it('sets animationDuration on the track from text width and speed', () => {
    const { container } = render(<OverflowMarquee text="Long" speed={50} />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    // textWidth=200, gap=48 → duration = (200+48)/50 = 4.96s
    Object.defineProperty(measureEl, 'scrollWidth', { value: 200, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 100, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    const track = container.querySelector('.animate-marquee') as HTMLElement;
    expect(track.style.animationDuration).toBe('4.96s');
  });

  it('disconnects the ResizeObserver on unmount', () => {
    const { unmount } = render(<OverflowMarquee text="Test" />);
    unmount();
    expect(mockDisconnect).toHaveBeenCalled();
  });
});
```

- [ ] **Step 1.2 — Run tests to verify they fail**

```bash
cd pwa && npx vitest run src/components/OverflowMarquee.test.tsx
```

Expected: `FAIL` — `Cannot find module './OverflowMarquee'`

- [ ] **Step 1.3 — Implement the component**

Create `src/components/OverflowMarquee.tsx`:

```tsx
import { useEffect, useRef, useState } from 'react';

const GAP_PX = 48; // px gap between the two text copies
const FADE_MASK =
  'linear-gradient(to right, transparent 0%, black 4%, black 96%, transparent 100%)';

interface Props {
  text: string;
  /** Applied to the outer clip div — include flex layout + text style classes here. */
  className?: string;
  /** Scroll speed in px/s. Default 40. */
  speed?: number;
}

export function OverflowMarquee({ text, className = '', speed = 40 }: Props) {
  const clipRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const [overflows, setOverflows] = useState(false);
  const [animDuration, setAnimDuration] = useState('8s');

  useEffect(() => {
    function measure() {
      const clip = clipRef.current;
      const measureEl = measureRef.current;
      if (!clip || !measureEl) return;
      const textWidth = measureEl.scrollWidth;
      const containerWidth = clip.clientWidth;
      const doesOverflow = textWidth > containerWidth;
      setOverflows(doesOverflow);
      if (doesOverflow) {
        setAnimDuration(`${(textWidth + GAP_PX) / speed}s`);
      }
    }

    measure();
    const ro = new ResizeObserver(measure);
    if (clipRef.current) ro.observe(clipRef.current);
    return () => ro.disconnect();
  }, [text, speed]);

  return (
    <div
      ref={clipRef}
      className={`overflow-hidden ${className}`}
      style={
        overflows
          ? { maskImage: FADE_MASK, WebkitMaskImage: FADE_MASK }
          : undefined
      }
    >
      {/* Hidden measurement span — always in DOM, out of flow, never animated */}
      <span
        ref={measureRef}
        data-testid="marquee-measure"
        className="invisible absolute whitespace-nowrap pointer-events-none"
        aria-hidden="true"
      >
        {text}
      </span>

      {overflows ? (
        // Dual-copy track — animates from 0 to -50% (= one full copy width + gap)
        <div
          className="flex w-max animate-marquee motion-reduce:animate-none"
          style={{ animationDuration: animDuration }}
        >
          <span className="whitespace-nowrap" style={{ paddingRight: `${GAP_PX}px` }}>
            {text}
          </span>
          <span
            className="whitespace-nowrap"
            style={{ paddingRight: `${GAP_PX}px` }}
            aria-hidden="true"
          >
            {text}
          </span>
        </div>
      ) : (
        <span className="whitespace-nowrap block truncate">{text}</span>
      )}
    </div>
  );
}
```

- [ ] **Step 1.4 — Run tests to verify they pass**

```bash
cd pwa && npx vitest run src/components/OverflowMarquee.test.tsx
```

Expected: `PASS` — 5 tests passing

- [ ] **Step 1.5 — Commit**

```bash
cd pwa && git add src/components/OverflowMarquee.tsx src/components/OverflowMarquee.test.tsx
git commit -m "feat(pwa): add OverflowMarquee component — continuous scroll on overflow"
```

---

## Task 2: `StatusBadge` component

**Files:**
- Create: `src/features/incidents/StatusBadge.tsx`
- Create: `src/features/incidents/StatusBadge.test.tsx`

- [ ] **Step 2.1 — Write the failing tests**

Create `src/features/incidents/StatusBadge.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusBadge } from '../StatusBadge';

describe('StatusBadge', () => {
  it('shows OPEN in red for active incidents', () => {
    const { container } = render(
      <StatusBadge status="active" incidentState="OPEN" />,
    );
    expect(screen.getByText('OPEN')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-red-600');
  });

  it('shows ACKD in blue for acknowledged incidents', () => {
    const { container } = render(
      <StatusBadge status="acknowledged" incidentState="ACKNOWLEDGED" />,
    );
    expect(screen.getByText('ACKD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-blue-600');
  });

  it('shows CLRD in green for resolved incidents', () => {
    const { container } = render(
      <StatusBadge status="resolved" incidentState="RESOLVED" />,
    );
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });

  it('shows CLRD in green for closed incidents', () => {
    render(<StatusBadge status="closed" incidentState="CLOSED" />);
    expect(screen.getByText('CLRD')).toBeInTheDocument();
  });

  it('shows CLRD in green when incidentState is ALARMS CLEARED', () => {
    const { container } = render(
      <StatusBadge status="active" incidentState="ALARMS CLEARED" />,
    );
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });
});
```

- [ ] **Step 2.2 — Run tests to verify they fail**

```bash
cd pwa && npx vitest run src/features/incidents/StatusBadge.test.tsx
```

Expected: `FAIL` — `Cannot find module '../StatusBadge'`

- [ ] **Step 2.3 — Implement the component**

Create `src/features/incidents/StatusBadge.tsx`:

```tsx
import type { IncidentStatus } from '../../lib/api/types';

interface Props {
  status: IncidentStatus;
  incidentState: string;
}

function resolve(status: IncidentStatus, incidentState: string) {
  if (
    status === 'resolved' ||
    status === 'closed' ||
    incidentState === 'ALARMS CLEARED'
  ) {
    return { label: 'CLRD', className: 'bg-emerald-600 text-white' } as const;
  }
  if (status === 'acknowledged') {
    return { label: 'ACKD', className: 'bg-blue-600 text-white' } as const;
  }
  return { label: 'OPEN', className: 'bg-red-600 text-white' } as const;
}

export function StatusBadge({ status, incidentState }: Props) {
  const { label, className } = resolve(status, incidentState);
  return (
    <span
      className={`inline-block shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold tracking-wide ${className}`}
    >
      {label}
    </span>
  );
}
```

- [ ] **Step 2.4 — Run tests to verify they pass**

```bash
cd pwa && npx vitest run src/features/incidents/StatusBadge.test.tsx
```

Expected: `PASS` — 5 tests passing

- [ ] **Step 2.5 — Commit**

```bash
cd pwa && git add src/features/incidents/StatusBadge.tsx src/features/incidents/StatusBadge.test.tsx
git commit -m "feat(pwa): add StatusBadge — OPEN/ACKD/CLRD incident status pill"
```

---

## Task 3: Redesign `IncidentRow`

**Files:**
- Modify: `src/features/incidents/IncidentRow.tsx`
- Create: `src/features/incidents/__tests__/IncidentRow.test.tsx`
- Modify: `src/features/incidents/__tests__/IncidentListScreen.test.tsx`

- [ ] **Step 3.1 — Write the failing IncidentRow tests**

Create `src/features/incidents/__tests__/IncidentRow.test.tsx`:

```tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { IncidentRow } from '../IncidentRow';
import type { Incident } from '../../../lib/api/types';

// ResizeObserver not in jsdom
beforeEach(() => {
  vi.stubGlobal(
    'ResizeObserver',
    vi.fn(() => ({ observe: vi.fn(), disconnect: vi.fn() })),
  );
});

const base: Incident = {
  incidentId: 'Demo-58431',
  displayId: '#58431',
  deviceName: 'core-router-01',
  deviceIp: '10.0.0.1',
  summary: 'Host unreachable',
  severity: 'critical',
  status: 'active',
  incidentState: 'OPEN',
  startTime: new Date(Date.now() - 3 * 3_600_000),
  acknowledgedBy: null,
  alarmCounts: { red: 2, orange: 0, yellow: 1, green: 3, blue: 0 },
};

function renderRow(inc: Incident) {
  return render(
    <MemoryRouter>
      <IncidentRow incident={inc} />
    </MemoryRouter>,
  );
}

describe('IncidentRow', () => {
  it('renders the display ID', () => {
    renderRow(base);
    expect(screen.getByText('#58431')).toBeInTheDocument();
  });

  it('renders the incident summary', () => {
    renderRow(base);
    expect(screen.getAllByText('Host unreachable').length).toBeGreaterThan(0);
  });

  it('renders OPEN badge for active incident', () => {
    renderRow(base);
    expect(screen.getByText('OPEN')).toBeInTheDocument();
  });

  it('renders ACKD badge for acknowledged incident', () => {
    renderRow({ ...base, status: 'acknowledged', incidentState: 'ACKNOWLEDGED' });
    expect(screen.getByText('ACKD')).toBeInTheDocument();
  });

  it('renders CLRD badge for resolved incident', () => {
    renderRow({ ...base, status: 'resolved', incidentState: 'RESOLVED' });
    expect(screen.getByText('CLRD')).toBeInTheDocument();
  });

  it('renders the device name', () => {
    renderRow(base);
    expect(screen.getAllByText('core-router-01').length).toBeGreaterThan(0);
  });

  it('renders compact duration without "ago" suffix', () => {
    renderRow(base);
    expect(screen.getByText('3h')).toBeInTheDocument();
    expect(screen.queryByText(/ago/)).not.toBeInTheDocument();
  });

  it('renders alarm count badges', () => {
    renderRow(base);
    expect(screen.getByText('2')).toBeInTheDocument(); // red
    expect(screen.getByText('1')).toBeInTheDocument(); // yellow
    expect(screen.getByText('3')).toBeInTheDocument(); // green
  });

  it('links to the incident detail route', () => {
    renderRow(base);
    expect(screen.getByRole('link')).toHaveAttribute(
      'href',
      '/incidents/Demo-58431',
    );
  });

  it('shows duration "now" for a brand-new incident', () => {
    renderRow({ ...base, startTime: new Date() });
    expect(screen.getByText('now')).toBeInTheDocument();
  });

  it('falls back to deviceIp when deviceName is null', () => {
    renderRow({ ...base, deviceName: null });
    expect(screen.getAllByText('10.0.0.1').length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 3.2 — Run the new tests to verify they fail**

```bash
cd pwa && npx vitest run src/features/incidents/__tests__/IncidentRow.test.tsx
```

Expected: `FAIL` — tests can't find `OPEN`, `ACKD`, `3h`, etc. because the row hasn't been redesigned yet.

- [ ] **Step 3.3 — Rewrite `IncidentRow.tsx`**

Replace the entire contents of `src/features/incidents/IncidentRow.tsx`:

```tsx
import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { StatusBadge } from './StatusBadge';
import { AlarmBadges } from './AlarmBadges';
import { OverflowMarquee } from '../../components/OverflowMarquee';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

function formatDuration(d: Date): string {
  const diffMs = Date.now() - d.getTime();
  const min = Math.round(diffMs / 60_000);
  if (min < 1) return 'now';
  if (min < 60) return `${min}m`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h`;
  return `${Math.round(hr / 24)}d`;
}

export function IncidentRow({ incident }: { incident: Incident }) {
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
        <AlarmBadges counts={incident.alarmCounts ?? EMPTY_COUNTS} />
      </div>
    </Link>
  );
}
```

- [ ] **Step 3.4 — Run IncidentRow tests to verify they pass**

```bash
cd pwa && npx vitest run src/features/incidents/__tests__/IncidentRow.test.tsx
```

Expected: `PASS` — 11 tests passing

- [ ] **Step 3.5 — Update the stale IncidentListScreen test**

In `src/features/incidents/__tests__/IncidentListScreen.test.tsx`, the test `'renders severity badges'` checks for the old `SeverityBadge` aria-labels (`'Severity: critical'`, `'Severity: major'`). Replace that test with one that checks for the new status badges:

Find this block:
```tsx
  it('renders severity badges', () => {
    renderScreen();
    expect(screen.getByLabelText('Severity: critical')).toBeInTheDocument();
    expect(screen.getByLabelText('Severity: major')).toBeInTheDocument();
  });
```

Replace it with:
```tsx
  it('renders status badges', async () => {
    renderScreen();
    await waitFor(() => {
      expect(screen.getByText('OPEN')).toBeInTheDocument();  // active incident
      expect(screen.getByText('ACKD')).toBeInTheDocument(); // acknowledged incident
    });
  });
```

Also add `ResizeObserver` stub at the top of the file (after imports):
```tsx
beforeEach(() => {
  vi.stubGlobal(
    'ResizeObserver',
    vi.fn(() => ({ observe: vi.fn(), disconnect: vi.fn() })),
  );
});
```

And add `beforeEach` to the imports:
```tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
```

- [ ] **Step 3.6 — Run full incident test suite to verify everything passes**

```bash
cd pwa && npx vitest run src/features/incidents
```

Expected: `PASS` — all tests in the incidents feature passing

- [ ] **Step 3.7 — Run full test suite to catch regressions**

```bash
cd pwa && npx vitest run
```

Expected: all tests passing

- [ ] **Step 3.8 — Commit**

```bash
cd pwa && git add src/features/incidents/IncidentRow.tsx \
  src/features/incidents/__tests__/IncidentRow.test.tsx \
  src/features/incidents/__tests__/IncidentListScreen.test.tsx
git commit -m "feat(pwa): redesign IncidentRow — 2-row layout with scrolling title, StatusBadge, compact duration"
```
