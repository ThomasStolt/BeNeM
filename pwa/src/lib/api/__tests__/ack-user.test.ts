import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { BhnmConfig } from '../../config';

const postForm = vi.fn();
vi.mock('../client', () => ({
  postForm: (...args: unknown[]) => postForm(...args),
}));

import { acknowledgeIncident, unacknowledgeIncident } from '../incidents';

/**
 * The acknowledging user must be the **Username** typed into the admin portal's
 * QR generator — required there for exactly this reason, carried in the QR
 * payload as `user`, stored as `ackUser`.
 *
 * 0.17.2 replaced it with a constant, on the reasoning that values like
 * "Thomas Android PWA" looked like device names. The admin link log shows they
 * are the usernames someone typed. These tests exist so that mistake cannot be
 * repeated silently: they fail the moment a constant displaces the QR username.
 */
function config(ackUser: string): BhnmConfig {
  return {
    serverId: 's', serverName: 'S', baseUrl: '/bhnm', apiKey: 'k',
    isConfigured: true, ackUser, bhnmUrl: '',
  } as BhnmConfig;
}

function sentUser(): string {
  // postForm(baseUrl, path, params, apiKey)
  return (postForm.mock.calls.at(-1)?.[2] as Record<string, string>).user;
}

describe('ack attribution', () => {
  beforeEach(() => {
    postForm.mockReset();
    postForm.mockResolvedValue([{ result: 'completed' }]);
  });

  it('sends the QR username on acknowledge', async () => {
    await acknowledgeIncident(config('Thomas Android PWA'), '42');
    expect(sentUser()).toBe('Thomas Android PWA');
  });

  it('sends the QR username on unacknowledge', async () => {
    await unacknowledgeIncident(config('Thomas Android PWA'), '42');
    expect(sentUser()).toBe('Thomas Android PWA');
  });

  it('never substitutes a constant while a username exists', async () => {
    await acknowledgeIncident(config('Luiz'), '42');
    expect(sentUser()).toBe('Luiz');
    expect(sentUser()).not.toBe('BHNM Mobile');
  });

  it('falls back only when the username is genuinely empty', async () => {
    // REACHABLE, and not only as a guard. `ServerForm` requires the field, but QR
    // import bypasses the form entirely, and the admin portal's Username is
    // required in JavaScript ONLY — `main.py` declares `user: str = Form("")`. A
    // link generated without JS carries `"user": ""`, which qr-parser turns into
    // undefined (`'' || undefined`) and storage into ''. So this path fires on a
    // real QR, and without it BHNM would record the ack as nobody.
    await acknowledgeIncident(config(''), '42');
    expect(sentUser()).toBe('BHNM Mobile');
  });
});
