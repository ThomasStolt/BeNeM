import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SettingsScreen } from '../SettingsScreen';
import { addServer, loadServers } from '../../../lib/serverStorage';

function renderScreen() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <SettingsScreen />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('SettingsScreen', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('renders the server list section', () => {
    renderScreen();
    expect(screen.getByText('No servers configured.')).toBeInTheDocument();
  });

  it('renders the Add Server button', () => {
    renderScreen();
    expect(screen.getByText(/add server/i)).toBeInTheDocument();
  });

  it('renders the About section with version 0.4.0', () => {
    renderScreen();
    expect(screen.getByText(/0\.4\.0/)).toBeInTheDocument();
  });

  it('shows server name when a server exists', () => {
    addServer({ name: 'Test BHNM', baseUrl: '/bhnm', apiKey: 'k1' });
    renderScreen();
    expect(screen.getByText('Test BHNM')).toBeInTheDocument();
  });

  it('shows push notification section when active server exists', () => {
    addServer({ name: 'Test', baseUrl: '/bhnm', apiKey: 'k1' });
    renderScreen();
    expect(screen.getAllByText(/push notifications/i).length).toBeGreaterThan(0);
  });

  it('navigates to add server form', async () => {
    const user = userEvent.setup();
    renderScreen();
    await user.click(screen.getByText(/add server/i));
    expect(screen.getByText(/add server/i)).toBeInTheDocument();
    // Form fields should appear
    expect(document.getElementById('server-name')).toBeInTheDocument();
    expect(document.getElementById('server-api-key')).toBeInTheDocument();
  });

  it('adds a server and returns to list', async () => {
    const user = userEvent.setup();
    renderScreen();
    await user.click(screen.getByText(/add server/i));

    await user.type(document.getElementById('server-name')!, 'New Server');
    await user.type(document.getElementById('server-api-key')!, 'new-key');
    await user.click(screen.getByRole('button', { name: /save/i }));

    // Back to list — should show new server
    expect(screen.getByText('New Server')).toBeInTheDocument();
    expect(loadServers()).toHaveLength(1);
    expect(loadServers()[0].apiKey).toBe('new-key');
  });

  it('renders back link', () => {
    renderScreen();
    expect(screen.getByLabelText(/back/i)).toBeInTheDocument();
  });
});
