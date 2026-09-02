// pwa/src/features/devices/__tests__/DeviceDetailScreen.test.tsx
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceDetailScreen } from '../DeviceDetailScreen';

vi.mock('../useDeviceSearch', () => ({ useDeviceSearch: vi.fn() }));
vi.mock('../useMaintenanceStatus', () => ({ useMaintenanceStatus: vi.fn() }));
vi.mock('../../incidents/useIncidents', () => ({ useIncidents: vi.fn() }));
vi.mock('../LatencyMiniChart', () => ({ LatencyMiniChart: () => null }));
vi.mock('../../performance/PerformanceSection', () => ({
  PerformanceSection: () => <div data-testid="perf-section">Performance</div>,
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
    ackUser: 'tester',
  }),
}));

import { useDeviceSearch } from '../useDeviceSearch';
import { useIncidents } from '../../incidents/useIncidents';
import { useMaintenanceStatus } from '../useMaintenanceStatus';
import { parseMaintenanceStatus } from '../../../lib/api/maintenance';

const mockDevice = {
  name: 'raspi-054',
  ip: '192.168.1.54',
  category: 'Linux',
  site: 'Home',
  model: 'RPi 4',
  serialNumber: 'ABC123',
  description: 'Test Pi',
  deviceIndex: '3',
  status: 'up' as const,
};

function renderDetail(deviceName: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/devices/${encodeURIComponent(deviceName)}`]}>
        <Routes>
          <Route path="/devices/:name" element={<DeviceDetailScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DeviceDetailScreen', () => {
  beforeEach(() => {
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as unknown as ReturnType<typeof useIncidents>);
    vi.mocked(useMaintenanceStatus).mockReturnValue({
      data: null,
    } as unknown as ReturnType<typeof useMaintenanceStatus>);
  });

  it('header status flips to blue MAINTENANCE when inMaintenance is true', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useMaintenanceStatus).mockReturnValue({
      data: parseMaintenanceStatus({
        inMaintenance: true,
        windows: [{ start_time: 1, end_time: 2, comment: 'x' }],
      }),
    } as unknown as ReturnType<typeof useMaintenanceStatus>);

    renderDetail('raspi-054');
    const label = screen.getByText('MAINTENANCE');
    expect(label.closest('p')).toHaveClass('text-sky-400');
    // The in-maintenance button replaces the create button
    expect(screen.getByText(/In Maintenance · ends/)).toBeInTheDocument();
    expect(screen.queryByText('+ Create Maintenance Window')).not.toBeInTheDocument();
  });

  it('header status stays the device status when the maintenance read fails', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('UP')).toBeInTheDocument();
    expect(screen.queryByText('MAINTENANCE')).not.toBeInTheDocument();
    expect(screen.getByText('+ Create Maintenance Window')).toBeInTheDocument();
  });

  it('shows device name and IP in header', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('192.168.1.54')).toBeInTheDocument();
  });

  it('shows model and serial inside Host Information when expanded', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    await userEvent.click(screen.getByText('Host Information'));
    expect(screen.getByText('RPi 4')).toBeInTheDocument();
    expect(screen.getByText('ABC123')).toBeInTheDocument();
  });

  it('shows "No current issues" when no incidents', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    await userEvent.click(screen.getByText('Current Issues'));
    expect(screen.getByText('No current issues')).toBeInTheDocument();
  });

  it('shows matching incidents in Current Issues table', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [
        {
          incidentId: '1',
          displayId: '#1',
          deviceName: 'raspi-054',
          deviceIp: '192.168.1.54',
          summary: 'High CPU',
          severity: 'critical' as const,
          status: 'active' as const,
          incidentState: 'OPEN',
          startTime: new Date(),
          acknowledgedBy: null,
          alarmCounts: null,
        },
        {
          incidentId: '2',
          displayId: '#2',
          deviceName: 'other-host',
          deviceIp: '10.0.0.1',
          summary: 'Disk full',
          severity: 'major' as const,
          status: 'active' as const,
          incidentState: 'OPEN',
          startTime: new Date(),
          acknowledgedBy: null,
          alarmCounts: null,
        },
      ],
    } as unknown as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    await userEvent.click(screen.getByText('Current Issues'));
    expect(screen.getByText('High CPU')).toBeInTheDocument();
    expect(screen.queryByText('Disk full')).not.toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('shows alarm bar with HEALTHY / ACK / WARNING / CRITICAL labels', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);

    renderDetail('raspi-054');
    expect(screen.getByText('HEALTHY')).toBeInTheDocument();
    expect(screen.getByText('ACK')).toBeInTheDocument();
    expect(screen.getByText('WARNING')).toBeInTheDocument();
    expect(screen.getByText('CRITICAL')).toBeInTheDocument();
  });

  it('shows device not found state', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [],
      isLoading: false,
      isError: false,
    } as unknown as ReturnType<typeof useDeviceSearch>);

    renderDetail('nonexistent-host');
    expect(screen.getByText('Device not found')).toBeInTheDocument();
  });
});
