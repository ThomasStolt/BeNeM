import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ServerForm } from '../ServerForm';

vi.mock('../../../lib/api/ha-status', () => ({
  testConnection: vi.fn().mockResolvedValue({ role: 'standalone', status: '1' }),
  formatHaRole: vi.fn().mockReturnValue('Standalone'),
  formatHaStatus: vi.fn().mockReturnValue(null),
}));

function getField(id: string) {
  return document.getElementById(id) as HTMLInputElement;
}

describe('ServerForm', () => {
  it('renders empty form for new server', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('');
    expect(getField('server-bhnm-url')).toHaveValue('');
    expect(getField('server-middleware-url')).toHaveValue('/bhnm');
    expect(getField('server-api-key')).toHaveValue('');
    expect(getField('server-ack-user')).toHaveValue('');
  });

  it('renders pre-filled form for editing', () => {
    const server = {
      id: 'abc',
      name: 'Test',
      baseUrl: '/test',
      bhnmUrl: 'https://bhnm.test.com',
      apiKey: 'key123',
      pin: 'pin1',
      ackUser: 'thomas',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: false,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('Test');
    expect(getField('server-bhnm-url')).toHaveValue('https://bhnm.test.com');
    expect(getField('server-middleware-url')).toHaveValue('/test');
    expect(getField('server-api-key')).toHaveValue('key123');
    expect(getField('server-ack-user')).toHaveValue('thomas');
  });

  it('makes fields read-only when QR-provisioned', () => {
    const server = {
      id: 'abc',
      name: 'QR Server',
      baseUrl: '/middleware',
      bhnmUrl: 'https://bhnm.example.com',
      apiKey: 'secret-key',
      ackUser: 'admin',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: true,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    // Name should still be editable
    expect(getField('server-name')).not.toBeDisabled();
    // QR fields should not be editable inputs — check that text is displayed instead
    expect(screen.getByText('https://bhnm.example.com')).toBeInTheDocument();
    expect(screen.getByText('/middleware')).toBeInTheDocument();
    // API key should be masked
    expect(screen.getByText('••••••••')).toBeInTheDocument();
    // Footer should indicate QR provisioning
    expect(screen.getByText(/configured via qr code/i)).toBeInTheDocument();
  });

  it('shows delete button only in edit mode', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.queryByRole('button', { name: /delete/i })).not.toBeInTheDocument();

    const server = { id: 'abc', name: 'Test', baseUrl: '/test', apiKey: 'k', isQrProvisioned: false };
    const { unmount } = render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} onDelete={vi.fn()} />);
    expect(screen.getByRole('button', { name: /delete/i })).toBeInTheDocument();
    unmount();
  });

  it('calls onSave with all fields including new ones', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(<ServerForm onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-name'), 'My Server');
    await user.type(getField('server-bhnm-url'), 'https://bhnm.test');
    await user.clear(getField('server-middleware-url'));
    await user.type(getField('server-middleware-url'), '/myserver');
    await user.type(getField('server-api-key'), 'mykey');
    await user.type(getField('server-ack-user'), 'admin');
    await user.click(screen.getByRole('button', { name: /save/i }));

    await vi.waitFor(() => expect(onSave).toHaveBeenCalled());

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'My Server',
        baseUrl: '/myserver',
        bhnmUrl: 'https://bhnm.test',
        apiKey: 'mykey',
        ackUser: 'admin',
      }),
    );
  });

  it('calls onCancel when cancel clicked', async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<ServerForm onSave={vi.fn()} onCancel={onCancel} />);
    await user.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });
});
