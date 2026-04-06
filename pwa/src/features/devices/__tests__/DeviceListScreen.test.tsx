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

import { useDevices } from '../useDevices';
import { useDeviceSearch } from '../useDeviceSearch';

const mockDevices = [
  { name: 'raspi-054', ip: '192.168.1.54', category: 'Linux', site: 'Home', model: '', serialNumber: '', description: '' },
  { name: 'core-switch', ip: '10.0.0.1', category: 'Network', site: 'Office', model: '', serialNumber: '', description: '' },
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
      data: mockDevices,
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useDevices>);
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: undefined,
      isLoading: false,
      isFetching: false,
    } as ReturnType<typeof useDeviceSearch>);
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
    } as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  it('shows empty state when no devices', () => {
    vi.mocked(useDevices).mockReturnValue({
      data: [],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useDevices>);
    renderScreen();
    expect(screen.getByText('No devices found')).toBeInTheDocument();
  });

  it('shows search results when query is active', async () => {
    vi.mocked(useDeviceSearch).mockReturnValue({
      data: [mockDevices[0]],
      isLoading: false,
      isFetching: false,
    } as ReturnType<typeof useDeviceSearch>);
    renderScreen();
    const input = screen.getByPlaceholderText('Search devices by name...');
    await userEvent.type(input, 'raspi');
  });
});
