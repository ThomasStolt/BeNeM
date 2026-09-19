import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ServerForm, maskSecret } from '../ServerForm';

vi.mock('../../../lib/api/ha-status', () => ({
  testConnection: vi.fn().mockResolvedValue({ role: 'standalone', status: '1' }),
  formatHaRole: vi.fn().mockReturnValue('Standalone'),
  formatHaStatus: vi.fn().mockReturnValue(null),
}));

function getField(id: string) {
  return document.getElementById(id) as HTMLInputElement;
}

describe('ServerForm', () => {
  // The form must not leave on its own. Both result panels were unreachable until
  // 0.17.2 because onSave navigated in the same tick that set the verdict.
  it('shows "Connection verified" and stays until OK is pressed', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    const onDone = vi.fn();
    render(<ServerForm onDone={onDone} onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-api-key'), 'k');
    await user.click(screen.getByRole('button', { name: /^save$/i }));

    expect(await screen.findByText(/connection verified/i)).toBeInTheDocument();
    expect(onSave).toHaveBeenCalledTimes(1);   // persisted immediately, as on iOS
    expect(onDone).not.toHaveBeenCalled();     // but has NOT navigated away

    await user.click(screen.getByRole('button', { name: /^ok$/i }));
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it('renders empty form for new server', () => {
    render(<ServerForm onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('');
    expect(getField('server-bhnm-url')).toHaveValue('');
    expect(getField('server-middleware-url')).toHaveValue('');
    expect(getField('server-api-key')).toHaveValue('');
    expect(getField('server-ack-user')).toHaveValue('');
  });

  it('renders pre-filled form for editing', () => {
    const server = {
      id: 'abc',
      name: 'Test',
      baseUrl: '/bhnm',
      bhnmUrl: 'https://bhnm.test.com',
      pushMiddlewareUrl: 'https://middleware.test.com',
      apiKey: 'key123',
      pin: 'pin1',
      ackUser: 'thomas',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: false,
    };
    render(<ServerForm server={server} onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('Test');
    expect(getField('server-bhnm-url')).toHaveValue('https://bhnm.test.com');
    expect(getField('server-middleware-url')).toHaveValue('https://middleware.test.com');
    expect(getField('server-api-key')).toHaveValue('key123');
    expect(getField('server-ack-user')).toHaveValue('thomas');
  });

  it('leaves QR-provisioned fields EDITABLE, and keeps the provenance note', () => {
    // Inverted 2026-09-18. The lock protected nothing — the user holds the
    // credentials either way — and it trapped anyone whose QR-imported middleware
    // URL had gone stale: the only way out was delete and re-add. iOS never locked
    // these fields, so the asymmetry was the bug.
    const server = {
      id: 'abc',
      name: 'QR Server',
      baseUrl: '/bhnm',
      bhnmUrl: 'https://bhnm.example.com',
      pushMiddlewareUrl: 'https://middleware.example.com',
      apiKey: 'secret-key',
      ackUser: 'admin',
      pushEnabled: false,
      isActive: true,
      isQrProvisioned: true,
    };
    render(<ServerForm server={server} onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    for (const id of ['server-name', 'server-bhnm-url', 'server-middleware-url',
                      'server-api-key', 'server-ack-user']) {
      expect(getField(id)).not.toBeDisabled();
    }
    expect(getField('server-bhnm-url')).toHaveValue('https://bhnm.example.com');
    expect(getField('server-middleware-url')).toHaveValue('https://middleware.example.com');
    // The provenance stays as information; the instruction that is no longer true is gone.
    expect(screen.getByText(/configured via qr code/i)).toBeInTheDocument();
    expect(screen.queryByText(/scan again to update/i)).not.toBeInTheDocument();
  });

  it('never reveals more than a quarter of a secret', () => {
    // 10 characters: below the 16-character threshold, so dots only. The last 4 of
    // a short key leaves too little to guess — see the rule in ServerForm.tsx.
    expect(maskSecret('short-key0')).toBe('••••••••');
    expect(maskSecret('')).toBe('not set');
    // 16+ characters: the last 4, never more, and never the whole value.
    // Non-hex fixtures on purpose: tests/test_no_credentials_in_repo.py flags long
    // hex runs in tracked files, and it is right to — a digest and a leaked key are
    // the same shape to a scanner. Fix the fixture, never the guard.
    expect(maskSecret('not-a-real-secret')).toBe('••••••••cret');
    expect(maskSecret('not-a-real-secret-wxyz')).toBe('••••••••wxyz');
    expect(maskSecret('not-a-real-secret')).not.toContain('not-a');
  });

  it('shows the stored secret tail so one key can be told from another', () => {
    const server = {
      id: 'abc', name: 'S', baseUrl: '/bhnm', apiKey: 'not-a-real-secret',
      ackUser: 'a', isQrProvisioned: false,
    };
    render(<ServerForm server={server} onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByText(/Stored: ••••••••cret/)).toBeInTheDocument();
    // and the input itself never exposes it
    expect(getField('server-api-key')).toHaveAttribute('type', 'password');
  });

  it('leaves every secret untouched when an unrelated field is edited', async () => {
    // THE DATA-LOSS TEST. Unlocking the QR fields made the secrets editable and the
    // mask shows them as dots, which together are the classic way to destroy a
    // stored credential: pre-fill with dots instead of the value, and the first save
    // writes the dots. This asserts the inputs carry the REAL stored values, so a
    // save that touches nothing else round-trips them unchanged.
    const user = userEvent.setup();
    const onSave = vi.fn();
    const server = {
      id: 'abc',
      name: 'Original',
      baseUrl: '/bhnm',
      bhnmUrl: 'https://bhnm.example.com',
      pushMiddlewareUrl: 'https://mw.example.com',
      apiKey: 'not-a-real-secret',
      pin: 'pin-1234',
      ackUser: 'thomas',
      pushEnabled: true,
      pushWebhookSecret: 'not-a-real-webhook-secret',
      isActive: true,
      isQrProvisioned: true,
    };
    render(<ServerForm server={server} onDone={vi.fn()} onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-name'), '-renamed');
    await user.click(screen.getByRole('button', { name: /save/i }));
    await vi.waitFor(() => expect(onSave).toHaveBeenCalled());

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Original-renamed',
        apiKey: 'not-a-real-secret',
        pin: 'pin-1234',
        pushWebhookSecret: 'not-a-real-webhook-secret',
        pushEnabled: true,
      }),
    );
  });

  it('does not lock the user out of an existing connection that has push on and no secret', () => {
    // A new validation rule must never trap data that already exists. This state is
    // reachable today — a QR payload with notifications on and no push_secret — and
    // if Save is disabled the user cannot even fix the middleware URL.
    const server = {
      id: 'abc', name: 'S', baseUrl: '/bhnm', apiKey: 'k', ackUser: 'a',
      pushEnabled: true, pushWebhookSecret: undefined, isQrProvisioned: true,
    };
    render(<ServerForm server={server} onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByRole('button', { name: /save/i })).not.toBeDisabled();
  });

  it('shows delete button only in edit mode', () => {
    render(<ServerForm onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.queryByRole('button', { name: /delete/i })).not.toBeInTheDocument();

    const server = { id: 'abc', name: 'Test', baseUrl: '/test', apiKey: 'k', isQrProvisioned: false };
    const { unmount } = render(<ServerForm server={server} onDone={vi.fn()} onSave={vi.fn()} onCancel={vi.fn()} onDelete={vi.fn()} />);
    expect(screen.getByRole('button', { name: /delete/i })).toBeInTheDocument();
    unmount();
  });

  it('calls onSave with all fields including new ones', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(<ServerForm onDone={vi.fn()} onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-name'), 'My Server');
    await user.type(getField('server-bhnm-url'), 'https://bhnm.test');
    await user.type(getField('server-middleware-url'), 'https://mw.test');
    await user.type(getField('server-api-key'), 'mykey');
    await user.type(getField('server-ack-user'), 'admin');
    await user.click(screen.getByRole('button', { name: /save/i }));

    await vi.waitFor(() => expect(onSave).toHaveBeenCalled());

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'My Server',
        bhnmUrl: 'https://bhnm.test',
        pushMiddlewareUrl: 'https://mw.test',
        apiKey: 'mykey',
        ackUser: 'admin',
      }),
    );
  });

  it('calls onCancel when cancel clicked', async () => {
    const user = userEvent.setup();
    const onCancel = vi.fn();
    render(<ServerForm onDone={vi.fn()} onSave={vi.fn()} onCancel={onCancel} />);
    await user.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onCancel).toHaveBeenCalled();
  });
});
