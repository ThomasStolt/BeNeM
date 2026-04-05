import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { SettingsScreen } from '../SettingsScreen';
import { saveApiKey, loadApiKey } from '../settingsStorage';

function renderScreen() {
  return render(
    <MemoryRouter>
      <SettingsScreen />
    </MemoryRouter>,
  );
}

describe('SettingsScreen', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('renders the API key input and Save button', () => {
    renderScreen();
    expect(screen.getByLabelText(/BHNM API key/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /clear/i })).toBeInTheDocument();
  });

  it('pre-populates the field from localStorage on mount', () => {
    saveApiKey('preloaded-key');
    renderScreen();
    expect(screen.getByLabelText(/BHNM API key/i)).toHaveValue('preloaded-key');
    expect(screen.getByText(/configured/i)).toBeInTheDocument();
  });

  it('saves a new key to localStorage and shows confirmation', async () => {
    const user = userEvent.setup();
    renderScreen();
    await user.type(screen.getByLabelText(/BHNM API key/i), 'new-key');
    await user.click(screen.getByRole('button', { name: /save/i }));
    expect(loadApiKey()).toBe('new-key');
    expect(screen.getByRole('status')).toHaveTextContent(/saved/i);
  });

  it('clears the stored key', async () => {
    const user = userEvent.setup();
    saveApiKey('initial');
    renderScreen();
    await user.click(screen.getByRole('button', { name: /clear/i }));
    expect(loadApiKey()).toBeNull();
    expect(screen.getByLabelText(/BHNM API key/i)).toHaveValue('');
  });
});
