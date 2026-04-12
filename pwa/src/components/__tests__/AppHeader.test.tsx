// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AppHeader } from '../AppHeader';

vi.mock('../../lib/config', () => ({
  useConfig: vi.fn(() => ({
    serverId: 'srv1',
    serverName: 'AENA PROD',
    baseUrl: 'https://test.example.com',
    apiKey: 'key',
    isConfigured: true,
    ackUser: '',
    bhnmUrl: '',
  })),
}));

import { useConfig } from '../../lib/config';

beforeEach(() => {
  vi.stubGlobal('ResizeObserver', vi.fn(() => ({ observe: vi.fn(), unobserve: vi.fn(), disconnect: vi.fn() })));
});

describe('AppHeader', () => {
  it('renders the title', () => {
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('heading', { name: 'Home' })).toBeInTheDocument();
  });

  it('renders the server name when present', () => {
    render(<AppHeader title="Incidents" />);
    expect(screen.getByText('AENA PROD')).toBeInTheDocument();
  });

  it('omits server name when serverName is empty', () => {
    vi.mocked(useConfig).mockReturnValueOnce({
      serverId: 'srv1', serverName: '', baseUrl: 'https://x', apiKey: 'k',
      isConfigured: true, ackUser: '', bhnmUrl: '',
    });
    render(<AppHeader title="Home" />);
    expect(screen.queryByText('AENA PROD')).not.toBeInTheDocument();
  });

  it('renders connection badge', () => {
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('button', { name: /connection status/i })).toBeInTheDocument();
  });

  it('shows RefreshRing when dataUpdatedAt is positive', () => {
    render(<AppHeader title="Home" dataUpdatedAt={Date.now()} onRefresh={vi.fn()} />);
    expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument();
  });

  it('hides RefreshRing when dataUpdatedAt is 0 (Settings)', () => {
    render(<AppHeader title="Settings" />);
    expect(screen.queryByRole('button', { name: /refresh/i })).not.toBeInTheDocument();
  });

  it('shows disconnected status when not configured', () => {
    vi.mocked(useConfig).mockReturnValueOnce({
      serverId: '', serverName: '', baseUrl: '', apiKey: '',
      isConfigured: false, ackUser: '', bhnmUrl: '',
    });
    render(<AppHeader title="Home" />);
    expect(screen.getByRole('button', { name: /connection status/i }))
      .toHaveAttribute('data-status', 'disconnected');
  });
});
