import { describe, it, expect, vi } from 'vitest';
import { parseHaStatusResponse, formatHaRole, formatHaStatus } from './ha-status';

describe('parseHaStatusResponse', () => {
  it('parses array-wrapped response', () => {
    const result = parseHaStatusResponse([{ role: 'master', status: '1' }]);
    expect(result).toEqual({ role: 'master', status: '1' });
  });

  it('parses plain object response', () => {
    const result = parseHaStatusResponse({ role: 'standalone', status: '1' });
    expect(result).toEqual({ role: 'standalone', status: '1' });
  });

  it('throws on empty array', () => {
    expect(() => parseHaStatusResponse([])).toThrow();
  });

  it('throws on null', () => {
    expect(() => parseHaStatusResponse(null)).toThrow();
  });
});

describe('formatHaRole', () => {
  it('maps master to Primary', () => {
    expect(formatHaRole('master')).toBe('Primary');
  });
  it('maps primary to Primary', () => {
    expect(formatHaRole('primary')).toBe('Primary');
  });
  it('maps slave to Replica', () => {
    expect(formatHaRole('slave')).toBe('Replica');
  });
  it('maps standalone to Standalone', () => {
    expect(formatHaRole('standalone')).toBe('Standalone');
  });
  it('returns raw value for unknown roles', () => {
    expect(formatHaRole('unknown')).toBe('unknown');
  });
});

describe('formatHaStatus', () => {
  it('returns Active for primary status 1', () => {
    expect(formatHaStatus('primary', '1')).toBe('Active');
  });
  it('returns Inactive for primary status 2', () => {
    expect(formatHaStatus('primary', '2')).toBe('Inactive');
  });
  it('returns Takeover for slave status 2', () => {
    expect(formatHaStatus('slave', '2')).toBe('Takeover');
  });
  it('returns null for standalone', () => {
    expect(formatHaStatus('standalone', '1')).toBeNull();
  });
});

// The connection check: BHNM answers 200 for everything, so the body carries the
// verdict. The regression guarded here is the one that was removed on 2026-09-18 —
// a non-JSON 200 used to be reported as a working connection, which BHNM returns
// BEFORE it looks at the credential, so it verified nothing.
vi.mock('./client', () => ({ postForm: vi.fn() }));
const { postForm } = await import('./client');
const { testConnection } = await import('./ha-status');

const CONFIG = {
  serverId: '', serverName: '', baseUrl: 'https://mw.example.com',
  apiKey: 'k', isConfigured: true, ackUser: '', bhnmUrl: '',
} as Parameters<typeof testConnection>[0];

describe('testConnection', () => {
  it('accepts any BHNM reply that is not a password error', async () => {
    vi.mocked(postForm).mockResolvedValue({ result: 'error', detail: 'Method not supported.' });
    await expect(testConnection(CONFIG)).resolves.toEqual({ detail: 'Method not supported.' });
  });

  it('rejects a password failure', async () => {
    vi.mocked(postForm).mockResolvedValue({ result: 'error', detail: 'Password failed.' });
    await expect(testConnection(CONFIG)).rejects.toMatchObject({ error: { kind: 'auth' } });
  });

  it('rejects a 200 that is not a BHNM API response', async () => {
    // What ha_status_api.php actually returns on a TLS-terminated deployment:
    // PHP-serialized text, HTTP 200. This used to be reported as success.
    vi.mocked(postForm).mockResolvedValue('a:1:{s:5:"Error";s:29:"API require HTTPS connection.";}');
    await expect(testConnection(CONFIG)).rejects.toMatchObject({ error: { kind: 'parse' } });
  });
});
