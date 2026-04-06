import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { TacticalGroupListScreen } from '../TacticalGroupListScreen';
import type { TacticalGroup } from '../../../lib/api/tactical-overview';

vi.mock('../useTacticalGroups', () => ({
  useTacticalGroups: vi.fn(),
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

import { useTacticalGroups } from '../useTacticalGroups';

const zero = { ok: 0, ack: 0, warn: 0, un: 0, crit: 0 };
const healthy: TacticalGroup = {
  name: 'Linux',
  hosts: { ok: 5, ack: 0, warn: 0, un: 0, crit: 0 },
  services: { ...zero, ok: 10 },
  thresholds: zero,
  anomalies: zero,
};
const unhealthy: TacticalGroup = {
  name: 'Network',
  hosts: { ok: 3, ack: 0, warn: 1, un: 0, crit: 2 },
  services: { ...zero, ok: 5 },
  thresholds: zero,
  anomalies: zero,
};

function renderScreen(routeType: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/tactical/${routeType}`]}>
        <Routes>
          <Route path="/tactical/:type" element={<TacticalGroupListScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('TacticalGroupListScreen', () => {
  beforeEach(() => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: [healthy, unhealthy],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useTacticalGroups>);
  });

  it('renders the correct title for category route', () => {
    renderScreen('category');
    expect(screen.getByText('Categories')).toBeInTheDocument();
  });

  it('renders the correct title for site route', () => {
    renderScreen('site');
    expect(screen.getByText('Sites')).toBeInTheDocument();
  });

  it('renders the correct title for bw route', () => {
    renderScreen('bw');
    expect(screen.getByText('Business Workflows')).toBeInTheDocument();
  });

  it('renders all groups by default', () => {
    renderScreen('category');
    expect(screen.getByText('Linux')).toBeInTheDocument();
    expect(screen.getByText('Network')).toBeInTheDocument();
  });

  it('filter toggle hides healthy groups', async () => {
    renderScreen('category');
    const filterBtn = screen.getByLabelText('Filter unhealthy');
    await userEvent.click(filterBtn);
    expect(screen.queryByText('Linux')).not.toBeInTheDocument();
    expect(screen.getByText('Network')).toBeInTheDocument();
  });

  it('shows "All groups are healthy" when filter hides everything', async () => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: [healthy],
      isLoading: false,
      isError: false,
      dataUpdatedAt: Date.now(),
    } as ReturnType<typeof useTacticalGroups>);
    renderScreen('category');
    const filterBtn = screen.getByLabelText('Filter unhealthy');
    await userEvent.click(filterBtn);
    expect(screen.getByText('All groups are healthy')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    vi.mocked(useTacticalGroups).mockReturnValue({
      data: undefined,
      isLoading: true,
      isError: false,
      dataUpdatedAt: 0,
    } as ReturnType<typeof useTacticalGroups>);
    renderScreen('category');
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });
});
