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
