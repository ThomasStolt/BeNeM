// @vitest-environment jsdom
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
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
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
