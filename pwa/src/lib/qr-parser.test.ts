import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { parseQRUrl } from './qr-parser';

vi.mock('./crypto', () => ({
  decrypt: vi.fn(),
  decryptCompressed: vi.fn(),
}));
import { decrypt, decryptCompressed } from './crypto';

const FAKE_KEY = 'aa'.repeat(32); // 64 hex chars = 32 bytes

describe('parseQRUrl', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv('VITE_QR_ENCRYPTION_KEY', FAKE_KEY);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('rejects non-benem URLs', async () => {
    await expect(parseQRUrl('https://example.com')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('rejects benem URLs without configure host', async () => {
    await expect(parseQRUrl('benem://other')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('parses compact format with snake_case field names (middleware format)', async () => {
    const payload = JSON.stringify({
      bhnm_url: 'https://bhnm.example.com',
      middleware_url: 'https://middleware.example.com',
      api_key: 'mykey',
      pin: '1234',
      push_secret: 'webhooksecret',
      name: 'Test Server',
      user: 'admin',
      symbol: 'server.rack',
      color: '#0A84FF',
    });
    vi.mocked(decryptCompressed).mockResolvedValue(payload);
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result).toEqual({
      name: 'Test Server',
      baseUrl: 'https://middleware.example.com',
      bhnmUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      ackUser: 'admin',
      pushWebhookSecret: 'webhooksecret',
    });
  });

  it('throws on compact format with missing required fields', async () => {
    vi.mocked(decryptCompressed).mockResolvedValue(JSON.stringify({ name: 'Test' }));
    const fakeB64 = btoa('fakeciphertext');
    await expect(parseQRUrl(`benem://configure?p=${fakeB64}`))
      .rejects.toThrow('Missing required fields');
  });

  it('throws when no p parameter and no legacy parameters', async () => {
    await expect(parseQRUrl('benem://configure'))
      .rejects.toThrow('No configuration data');
  });

  it('parses legacy format with individual encrypted parameters', async () => {
    vi.mocked(decrypt)
      .mockResolvedValueOnce('https://bhnm.example.com')
      .mockResolvedValueOnce('mykey')
      .mockResolvedValueOnce('1234')
      .mockResolvedValueOnce('Legacy Server');
    const fakeB64 = btoa('encrypted');
    const url = `benem://configure?server=${fakeB64}&api_key=${fakeB64}&pin=${fakeB64}&name=${fakeB64}`;
    const result = await parseQRUrl(url);
    expect(result).toEqual({
      name: 'Legacy Server',
      baseUrl: 'https://bhnm.example.com',
      bhnmUrl: '',
      apiKey: 'mykey',
      pin: '1234',
      ackUser: undefined,
      pushWebhookSecret: undefined,
    });
  });

  it('throws when QR encryption key is not configured', async () => {
    vi.stubEnv('VITE_QR_ENCRYPTION_KEY', '');
    const fakeB64 = btoa('fakeciphertext');
    await expect(parseQRUrl(`benem://configure?p=${fakeB64}`))
      .rejects.toThrow('QR encryption key is not configured');
  });

  it('handles base64url encoded p parameter', async () => {
    vi.mocked(decryptCompressed).mockResolvedValue(
      JSON.stringify({ bhnm_url: 'https://bhnm.test', api_key: 'k', name: 'S' }),
    );
    const result = await parseQRUrl('benem://configure?p=abc-def_ghi');
    expect(result.baseUrl).toBe('https://bhnm.test');
    expect(result.bhnmUrl).toBe('https://bhnm.test');
    expect(result.ackUser).toBeUndefined();
    expect(decryptCompressed).toHaveBeenCalled();
    expect(decrypt).not.toHaveBeenCalled();
  });

  it('falls back to bhnm_url as baseUrl when middleware_url is absent', async () => {
    const payload = JSON.stringify({
      bhnm_url: 'https://bhnm.example.com',
      api_key: 'mykey',
      name: 'No Middleware',
    });
    vi.mocked(decryptCompressed).mockResolvedValue(payload);
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result.baseUrl).toBe('https://bhnm.example.com');
    expect(result.bhnmUrl).toBe('https://bhnm.example.com');
  });
});
