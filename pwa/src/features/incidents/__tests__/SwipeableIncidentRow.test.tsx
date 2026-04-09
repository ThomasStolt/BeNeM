import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SwipeableIncidentRow } from '../SwipeableIncidentRow';
import type { Incident } from '../../../lib/api/types';

const activeIncident: Incident = {
  incidentId: '100',
  displayId: '#100',
  deviceName: 'test-device',
  deviceIp: '10.0.0.1',
  summary: 'Test alert',
  severity: 'critical',
  status: 'active',
  incidentState: 'OPEN',
  startTime: new Date(),
  acknowledgedBy: null,
  alarmCounts: null,
};

const ackedIncident: Incident = {
  ...activeIncident,
  incidentId: '200',
  displayId: '#200',
  status: 'acknowledged',
  incidentState: 'ACKNOWLEDGED',
  acknowledgedBy: 'Thomas',
};

function renderRow(incident: Incident) {
  const client = new QueryClient();
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <SwipeableIncidentRow incident={incident} />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('SwipeableIncidentRow', () => {
  it('renders the incident row content', () => {
    renderRow(activeIncident);
    expect(screen.getByText('test-device')).toBeInTheDocument();
  });

  it('shows ACK action background for active incidents', () => {
    renderRow(activeIncident);
    expect(screen.getByText(/ACK/)).toBeInTheDocument();
  });

  it('shows UnACK action background for acknowledged incidents', () => {
    renderRow(ackedIncident);
    expect(screen.getByText(/UnACK/)).toBeInTheDocument();
  });
});
