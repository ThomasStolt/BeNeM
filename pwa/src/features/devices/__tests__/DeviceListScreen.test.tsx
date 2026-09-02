import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { DeviceListScreen } from '../DeviceListScreen';

vi.mock('../useDevices', () => ({
  useDevices: vi.fn(),
  PAGE_SIZE: 50,
}));
vi.mock('../useDeviceSearch', () => ({
  useDeviceSearch: vi.fn(),
}));
vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    serverName: 'Test Server',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
  }),
}));
vi.mock('../../incidents/useIncidents', () => ({
  useIncidents: vi.fn(),
}));

import { useDevices } from '../useDevices';
import { useDeviceSearch } from '../useDeviceSearch';
import { useIncidents } from '../../incidents/useIncidents';

const mockDevices = [
  { name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home', model: '', serialNumber: '', description: '', deviceIndex: '', status: 'up' as const },
  { name: 'core-switch', ip: '10.0.0.1', category: 'Network', site: 'Office', model: '', serialNumber: '', description: '', deviceIndex: '', status: 'up' as const },
];

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <DeviceListScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('DeviceListScreen', () => {
  beforeEach(() => {
    vi.mocked(useDevices).mockReturnValue({
      data: { devices: mockDevices, totalRecords: 2 },
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as unknown as ReturnType<typeof useDevices>);
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: false,
      isFetching: false,
    } as unknown as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({
      data: [],
    } as unknown as ReturnType<typeof useIncidents>);
  });

  it('renders device rows', () => {
    renderScreen();
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
    expect(screen.getByText('core-switch')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useDevices).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
      dataUpdatedAt: 0,
    } as unknown as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('shows empty state when no devices', () => {
    vi.mocked(useDevices).mockReturnValue({
      data: { devices: [], totalRecords: 0 },
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as unknown as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('No devices found')).toBeInTheDocument();
  });

  it('shows search results when query is active', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevices[0]],
      isLoading: false,
      isFetching: false,
    } as unknown as ReturnType<typeof useDeviceSearch>);
    renderScreen();
    const input = screen.getByPlaceholderText('Search devices by name...');
    await userEvent.type(input, 'raspi');
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
  });
});

// ── maintenance map: wrench + filter chip ────────────────────────────────────

import { useMaintenanceMap } from '../useMaintenanceMap';
vi.mock('../useMaintenanceMap', () => ({
  useMaintenanceMap: vi.fn(() => ({ data: new Set<string>() })),
}));

describe('DeviceListScreen maintenance', () => {
  beforeEach(() => {
    vi.mocked(useDevices).mockReturnValue({
      data: { devices: mockDevices, totalRecords: 2 },
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as unknown as ReturnType<typeof useDevices>);
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined, isLoading: false, isFetching: false,
    } as unknown as ReturnType<typeof useDeviceSearch>);
    vi.mocked(useIncidents).mockReturnValue({ data: [] } as unknown as ReturnType<typeof useIncidents>);
    vi.mocked(useMaintenanceMap).mockReturnValue({
      data: new Set(['core-switch']),
    } as unknown as ReturnType<typeof useMaintenanceMap>);
  });

  it('marks in-maintenance rows with the wrench and leaves others unmarked', () => {
    renderScreen();
    expect(screen.getAllByLabelText('In maintenance')).toHaveLength(1);
  });

  it('shows the filter chip with the on-page count and filters on click', async () => {
    renderScreen();
    const chip = screen.getByRole('button', { name: /In maintenance \(1\)/ });
    await userEvent.click(chip);
    expect(screen.getByText('core-switch')).toBeInTheDocument();
    expect(screen.queryByText('raspi-054')).not.toBeInTheDocument();
    await userEvent.click(chip); // toggle off
    expect(screen.getByText('raspi-054')).toBeInTheDocument();
  });

  it('hides the chip and shows no markers when the map is empty (cold/old BHNM)', () => {
    vi.mocked(useMaintenanceMap).mockReturnValue({
      data: new Set(),
    } as unknown as ReturnType<typeof useMaintenanceMap>);
    renderScreen();
    expect(screen.queryByLabelText('In maintenance')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /In maintenance/ })).not.toBeInTheDocument();
  });

  it('search-result rows carry the wrench too', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevices[1]], isLoading: false, isFetching: false,
    } as unknown as ReturnType<typeof useDeviceSearch>);
    renderScreen();
    await userEvent.type(screen.getByPlaceholderText(/Search devices/), 'core');
    expect(await screen.findByLabelText('In maintenance')).toBeInTheDocument();
  });
});
