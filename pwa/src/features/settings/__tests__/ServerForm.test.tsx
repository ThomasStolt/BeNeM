import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ServerForm } from '../ServerForm';

// Helper to get form fields by their specific label id
function getField(id: string) {
  return document.getElementById(id) as HTMLInputElement;
}

describe('ServerForm', () => {
  it('renders empty form for new server', () => {
    render(<ServerForm onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('');
    expect(getField('base-url')).toHaveValue('/bhnm');
    expect(getField('server-api-key')).toHaveValue('');
  });

  it('renders pre-filled form for editing', () => {
    const server = {
      id: 'abc',
      name: 'Test',
      baseUrl: '/test',
      apiKey: 'key123',
      pin: 'pin1',
      pushEnabled: false,
      isActive: true,
    };
    render(<ServerForm server={server} onSave={vi.fn()} onCancel={vi.fn()} />);
    expect(getField('server-name')).toHaveValue('Test');
    expect(getField('base-url')).toHaveValue('/test');
    expect(getField('server-api-key')).toHaveValue('key123');
  });

  it('calls onSave with form values', async () => {
    const user = userEvent.setup();
    const onSave = vi.fn();
    render(<ServerForm onSave={onSave} onCancel={vi.fn()} />);

    await user.type(getField('server-name'), 'My Server');
    await user.clear(getField('base-url'));
    await user.type(getField('base-url'), '/myserver');
    await user.type(getField('server-api-key'), 'mykey');
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'My Server',
        baseUrl: '/myserver',
        apiKey: 'mykey',
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
