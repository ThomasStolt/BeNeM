import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { SettingsScreen } from '../SettingsScreen';
import { saveApiKey, loadApiKey, loadPin, savePin } from '../settingsStorage';

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
    expect(screen.getByLabelText(/API Key/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /clear/i })).toBeInTheDocument();
  });

  it('renders the PIN input', () => {
    renderScreen();
    expect(screen.getByLabelText(/PIN/i)).toBeInTheDocument();
  });

  it('renders the Test Connection button', () => {
    renderScreen();
    expect(screen.getByRole('button', { name: /test connection/i })).toBeInTheDocument();
  });

  it('renders the About section with version', () => {
    renderScreen();
    expect(screen.getByText(/0\.1\.1/)).toBeInTheDocument();
  });

  it('pre-populates API key from localStorage on mount', () => {
    saveApiKey('preloaded-key');
    renderScreen();
    expect(screen.getByLabelText(/API Key/i)).toHaveValue('preloaded-key');
  });

  it('pre-populates PIN from localStorage on mount', () => {
    savePin('preloaded-pin');
    renderScreen();
    expect(screen.getByLabelText(/PIN/i)).toHaveValue('preloaded-pin');
  });

  it('saves API key and PIN to localStorage', async () => {
    const user = userEvent.setup();
    renderScreen();
    await user.type(screen.getByLabelText(/API Key/i), 'new-key');
    await user.type(screen.getByLabelText(/PIN/i), 'new-pin');
    await user.click(screen.getByRole('button', { name: /save/i }));
    expect(loadApiKey()).toBe('new-key');
    expect(loadPin()).toBe('new-pin');
  });

  it('clears both API key and PIN', async () => {
    const user = userEvent.setup();
    saveApiKey('key');
    savePin('pin');
    renderScreen();
    await user.click(screen.getByRole('button', { name: /clear/i }));
    expect(loadApiKey()).toBeNull();
    expect(loadPin()).toBeNull();
  });
});
