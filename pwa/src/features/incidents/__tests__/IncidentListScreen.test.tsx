import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { IncidentListScreen } from '../IncidentListScreen';

beforeEach(() => {
  vi.stubGlobal(
    'ResizeObserver',
    vi.fn(() => ({ observe: vi.fn(), disconnect: vi.fn() })),
  );
});

vi.mock('../useIncidents', () => ({
  useIncidents: () => ({
    data: [
      {
        incidentId: '58431',
        displayId: '#58431',
        deviceName: 'core-switch-01',
        deviceIp: '10.0.0.1',
        summary: 'CPU utilization high',
        severity: 'critical',
        status: 'active',
        incidentState: 'OPEN',
        startTime: new Date(Date.now() - 5 * 60_000),
        acknowledgedBy: null, alarmCounts: null,
      },
      {
        incidentId: '58432',
        displayId: '#58432',
        deviceName: 'edge-router-02',
        deviceIp: '10.0.0.2',
        summary: 'Interface down',
        severity: 'major',
        status: 'acknowledged',
        incidentState: 'ACKNOWLEDGED',
        startTime: new Date(Date.now() - 60 * 60_000),
        acknowledgedBy: 'oncall@example.com',
      },
    ],
    isLoading: false,
    isError: false,
    error: null,
    refetch: vi.fn(),
  }),
}));

function renderScreen() {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <IncidentListScreen />
      </MemoryRouter>
    </QueryClientProvider>
  );
}

describe('IncidentListScreen', () => {
  it('renders a row for each incident', async () => {
    renderScreen();
    await waitFor(() => {
      expect(screen.getAllByText(/core-switch-01/).length).toBeGreaterThan(0);
      expect(screen.getAllByText(/edge-router-02/).length).toBeGreaterThan(0);
    });
    const list = screen.getByTestId('incident-list');
    expect(list.querySelectorAll('li')).toHaveLength(2);
  });

  it('renders status badges', async () => {
    renderScreen();
    await waitFor(() => {
      expect(screen.getByText('OPEN')).toBeInTheDocument();
      expect(screen.getByText('ACKD')).toBeInTheDocument();
    });
  });
});
