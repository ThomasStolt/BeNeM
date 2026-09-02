import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MaintenanceCard, maintenanceButtonState } from '../MaintenanceCard';
import { parseMaintenanceStatus } from '../../../lib/api/maintenance';

vi.mock('../../../lib/config', () => ({
  useConfig: () => ({
    serverId: 'test',
    baseUrl: '/bhnm',
    apiKey: 'key',
    isConfigured: true,
    ackUser: 'tester',
  }),
}));

vi.mock('../useMaintenanceStatus', () => ({ useMaintenanceStatus: vi.fn() }));

vi.mock('../../../lib/api/maintenance', async (importOriginal) => {
  const original = await importOriginal<typeof import('../../../lib/api/maintenance')>();
  return {
    ...original,
    createMaintenanceWindow: vi.fn(),
    closeMaintenanceWindow: vi.fn(),
  };
});

import { useMaintenanceStatus } from '../useMaintenanceStatus';
import { createMaintenanceWindow, closeMaintenanceWindow } from '../../../lib/api/maintenance';

const NOW = new Date('2026-09-02T10:00:00Z');
const IN_MAINTENANCE = parseMaintenanceStatus({
  inMaintenance: true,
  windows: [{ start_time: 1756800000, end_time: 1756816200, comment: 'Created by tom: swap' }],
});
const NOT_IN_MAINTENANCE = parseMaintenanceStatus({ inMaintenance: false, windows: [] });

// ── maintenanceButtonState (pure) ───────────────────────────────────────────

describe('maintenanceButtonState', () => {
  it('is normal with no data (older BHNM / failed read — version gate)', () => {
    expect(maintenanceButtonState(null, null, null, NOW).kind).toBe('normal');
    expect(maintenanceButtonState(undefined, null, null, NOW).kind).toBe('normal');
  });

  it('is normal when not in maintenance even with non-empty windows (bool is the truth)', () => {
    const disagree = parseMaintenanceStatus({
      inMaintenance: false,
      windows: [{ start_time: 1, end_time: 2, comment: 'x' }],
    });
    expect(maintenanceButtonState(disagree, null, null, NOW).kind).toBe('normal');
  });

  it('is active when inMaintenance is true, with the latest end', () => {
    const s = maintenanceButtonState(IN_MAINTENANCE, null, null, NOW);
    expect(s.kind).toBe('active');
    if (s.kind === 'active') expect(s.endsAt?.getTime()).toBe(1756816200_000);
  });

  it('active wins over a live pending start (precedence)', () => {
    const pending = new Date(NOW.getTime() + 5 * 60_000);
    expect(maintenanceButtonState(IN_MAINTENANCE, pending, null, NOW).kind).toBe('active');
  });

  it('is starting while a pending start is alive', () => {
    const pending = new Date(NOW.getTime() + 5 * 60_000);
    const s = maintenanceButtonState(NOT_IN_MAINTENANCE, pending, null, NOW);
    expect(s.kind).toBe('starting');
  });

  it('pending start expires ~3 min past the start', () => {
    const pending = new Date(NOW.getTime() - 4 * 60_000);
    expect(maintenanceButtonState(NOT_IN_MAINTENANCE, pending, null, NOW).kind).toBe('normal');
  });

  it('a recent local close suppresses the (lagging) active state', () => {
    const closedAt = new Date(NOW.getTime() - 30_000);
    expect(maintenanceButtonState(IN_MAINTENANCE, null, closedAt, NOW).kind).toBe('normal');
  });

  it('close suppression expires after ~3 min (honest if BHNM still claims true)', () => {
    const closedAt = new Date(NOW.getTime() - 4 * 60_000);
    expect(maintenanceButtonState(IN_MAINTENANCE, null, closedAt, NOW).kind).toBe('active');
  });
});

// ── MaintenanceCard (component) ─────────────────────────────────────────────

function renderCard() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MaintenanceCard deviceName="core-router-01" username="tester" />
    </QueryClientProvider>,
  );
}

function mockStatus(data: unknown) {
  vi.mocked(useMaintenanceStatus).mockReturnValue({
    data,
  } as unknown as ReturnType<typeof useMaintenanceStatus>);
}

describe('MaintenanceCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows the create button when the read failed (null)', () => {
    mockStatus(null);
    renderCard();
    expect(screen.getByText('+ Create Maintenance Window')).toBeInTheDocument();
  });

  it('shows the create button when not in maintenance', () => {
    mockStatus(NOT_IN_MAINTENANCE);
    renderCard();
    expect(screen.getByText('+ Create Maintenance Window')).toBeInTheDocument();
  });

  it('shows the inverted In Maintenance button with the end time', () => {
    mockStatus(IN_MAINTENANCE);
    renderCard();
    expect(screen.getByText(/In Maintenance · ends/)).toBeInTheDocument();
  });

  it('tap on active → end-maintenance dialog; confirm calls close and clears to create', async () => {
    mockStatus(IN_MAINTENANCE);
    vi.mocked(closeMaintenanceWindow).mockResolvedValue(undefined);
    renderCard();

    await userEvent.click(screen.getByText(/In Maintenance · ends/));
    expect(screen.getByText(/End maintenance for core-router-01 now\?/)).toBeInTheDocument();
    expect(screen.getByText(/Alerting for this device will resume\./)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'End Maintenance' }));
    expect(closeMaintenanceWindow).toHaveBeenCalledOnce();
    expect(await screen.findByText('+ Create Maintenance Window')).toBeInTheDocument();
  });

  it('cancel in the end dialog makes no call', async () => {
    mockStatus(IN_MAINTENANCE);
    renderCard();
    await userEvent.click(screen.getByText(/In Maintenance · ends/));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(closeMaintenanceWindow).not.toHaveBeenCalled();
    expect(screen.getByText(/In Maintenance · ends/)).toBeInTheDocument();
  });

  it('close failure leaves the active state and shows the error', async () => {
    mockStatus(IN_MAINTENANCE);
    vi.mocked(closeMaintenanceWindow).mockRejectedValue(new Error('Device not found'));
    renderCard();
    await userEvent.click(screen.getByText(/In Maintenance · ends/));
    await userEvent.click(screen.getByRole('button', { name: 'End Maintenance' }));
    expect(await screen.findByText(/Device not found/)).toBeInTheDocument();
    expect(screen.getByText(/In Maintenance · ends/)).toBeInTheDocument();
  });

  it('successful create shows the interim Starts at state from the echoed start', async () => {
    mockStatus(NOT_IN_MAINTENANCE);
    vi.mocked(createMaintenanceWindow).mockResolvedValue(new Date(Date.now() + 5 * 60_000));
    renderCard();

    await userEvent.click(screen.getByText('+ Create Maintenance Window'));
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    expect(createMaintenanceWindow).toHaveBeenCalledOnce();
    expect(await screen.findByText(/Starts at/)).toBeInTheDocument();
  });

  it('tap on starting → cancel-scheduled dialog; confirm calls close and clears', async () => {
    mockStatus(NOT_IN_MAINTENANCE);
    vi.mocked(createMaintenanceWindow).mockResolvedValue(new Date(Date.now() + 5 * 60_000));
    vi.mocked(closeMaintenanceWindow).mockResolvedValue(undefined);
    renderCard();

    await userEvent.click(screen.getByText('+ Create Maintenance Window'));
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));
    await userEvent.click(await screen.findByText(/Starts at/));

    expect(screen.getByText(/Cancel scheduled maintenance for core-router-01\?/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Cancel Maintenance' }));
    expect(closeMaintenanceWindow).toHaveBeenCalledOnce();
    expect(await screen.findByText('+ Create Maintenance Window')).toBeInTheDocument();
  });

  it('Keep in the cancel-scheduled dialog keeps the pending window', async () => {
    mockStatus(NOT_IN_MAINTENANCE);
    vi.mocked(createMaintenanceWindow).mockResolvedValue(new Date(Date.now() + 5 * 60_000));
    renderCard();

    await userEvent.click(screen.getByText('+ Create Maintenance Window'));
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));
    await userEvent.click(await screen.findByText(/Starts at/));
    await userEvent.click(screen.getByRole('button', { name: 'Keep' }));

    expect(closeMaintenanceWindow).not.toHaveBeenCalled();
    expect(screen.getByText(/Starts at/)).toBeInTheDocument();
  });
});
