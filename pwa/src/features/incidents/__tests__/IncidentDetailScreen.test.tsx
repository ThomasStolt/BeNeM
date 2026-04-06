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
      },
    ],
    isLoading: false,
    isError: false,
    error: null,
    refetch: vi.fn(),
  }),
}));

function renderDetail(incidentId: string) {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={[`/incident/${incidentId}`]}>
        <Routes>
          <Route path="/incident/:id" element={<IncidentDetailScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('IncidentDetailScreen', () => {
  it('displays incident metadata for an active incident', () => {
    renderDetail('58431');
    expect(screen.getByText('#58431')).toBeInTheDocument();
    expect(screen.getByText('core-switch-01')).toBeInTheDocument();
    expect(screen.getByText('10.0.0.1')).toBeInTheDocument();
    expect(screen.getByText(/CPU utilization high/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /acknowledge/i })).toBeInTheDocument();
  });

  it('shows Unacknowledge button and ack info for acknowledged incident', () => {
    renderDetail('58432');
    expect(screen.getByText('#58432')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /unacknowledge/i })).toBeInTheDocument();
    expect(screen.getByText('oncall@example.com')).toBeInTheDocument();
  });

  it('shows not-found message for unknown incident', () => {
    renderDetail('99999');
    expect(screen.getByText(/not found/i)).toBeInTheDocument();
  });
});
