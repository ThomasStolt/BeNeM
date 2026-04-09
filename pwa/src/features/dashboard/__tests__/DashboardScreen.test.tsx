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
        acknowledgedBy: null, alarmCounts: null,
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
