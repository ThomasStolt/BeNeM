import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceDetailScreen } from '../DeviceDetailScreen';

vi.mock('../useDeviceSearch', () => ({
  useDeviceSearch: vi.fn(),
}));
vi.mock('../../incidents/useIncidents', () => ({
  useIncidents: vi.fn(),
}));
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
  }),
}));

import { useDeviceSearch } from '../useDeviceSearch';
import { useIncidents } from '../../incidents/useIncidents';

const mockDevice = {
  name: 'raspi-054',
  ip: '192.168.1.54',
  category: 'Linux',
  site: 'Home',
  model: 'RPi 4',
  serialNumber: 'ABC123',
  description: 'Test Pi',
  deviceIndex: '3',
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
  it('shows device info when found', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as unknown as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('192.168.1.54')).toBeInTheDocument();
    expect(screen.getByText('RPi 4')).toBeInTheDocument();
    expect(screen.getByText('ABC123')).toBeInTheDocument();
  });

  it('shows matching incidents for the device', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevice],
      isLoading: false,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [
        {
          incidentId: '1', displayId: '#1', deviceName: 'raspi-054', deviceIp: '192.168.1.54',
          summary: 'High CPU', severity: 'critical' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null,
        },
        {
          incidentId: '2', displayId: '#2', deviceName: 'other-host', deviceIp: '10.0.0.1',
          summary: 'Disk full', severity: 'major' as const, status: 'active' as const,
          incidentState: 'OPEN', startTime: new Date(), acknowledgedBy: null,
        },
      ],
    } as unknown as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('High CPU')).toBeInTheDocument();
    expect(screen.queryByText('Disk full')).not.toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
    } as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as unknown as ReturnType<typeof useIncidents>);

    renderDetail('raspi-054');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });
});
