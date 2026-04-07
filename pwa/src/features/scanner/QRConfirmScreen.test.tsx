import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { QRConfirmScreen } from './QRConfirmScreen';
import type { ParsedServerConfig } from '../../lib/qr-parser';

const mockConfig: ParsedServerConfig = {
  name: 'Test Server',
  baseUrl: 'https://middleware.example.com',
  bhnmUrl: 'https://bhnm.example.com',
  apiKey: 'secret-api-key-12345',
  pin: '1234',
  ackUser: 'admin',
  pushWebhookSecret: 'webhooksecret',
};

describe('QRConfirmScreen', () => {
  it('displays parsed server information including new fields', () => {
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={vi.fn()} onCancel={vi.fn()} />,
    );
    expect(screen.getByText('Test Server')).toBeInTheDocument();
    expect(screen.getByText('https://bhnm.example.com')).toBeInTheDocument();
    expect(screen.getByText('https://middleware.example.com')).toBeInTheDocument();
    expect(screen.getByText('admin')).toBeInTheDocument();
    expect(screen.getByText(/\*\*\*/)).toBeInTheDocument(); // masked API key
  });

  it('calls onConfirm when Add Server is clicked', () => {
    const onConfirm = vi.fn();
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={onConfirm} onCancel={vi.fn()} />,
    );
    fireEvent.click(screen.getByRole('button', { name: /add server/i }));
    expect(onConfirm).toHaveBeenCalled();
  });

  it('calls onCancel when Cancel is clicked', () => {
    const onCancel = vi.fn();
    render(
      <QRConfirmScreen config={mockConfig} onConfirm={vi.fn()} onCancel={onCancel} />,
    );
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });

  it('shows Update button when existing server matches', () => {
    render(
      <QRConfirmScreen
        config={mockConfig}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
        existingServerId="abc123"
      />,
    );
    expect(screen.getByRole('button', { name: /update server/i })).toBeInTheDocument();
  });
});
