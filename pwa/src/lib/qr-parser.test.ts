import { describe, it, expect, vi, beforeEach } from 'vitest';
import { parseQRUrl, type ParsedServerConfig } from './qr-parser';

vi.mock('./crypto', () => ({
  decrypt: vi.fn(),
}));
import { decrypt } from './crypto';

describe('parseQRUrl', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('rejects non-benem URLs', async () => {
    await expect(parseQRUrl('https://example.com')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('rejects benem URLs without configure host', async () => {
    await expect(parseQRUrl('benem://other')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('parses compact format with p parameter', async () => {
    const payload = JSON.stringify({
      bhnmURL: 'https://bhnm.example.com',
      middlewareURL: 'https://middleware.example.com',
      apiKey: 'mykey',
      pin: '1234',
      pushSecret: 'webhooksecret',
      name: 'Test Server',
      ackUser: 'admin',
      symbol: 'bolt',
      accentColor: '#ff0000',
    });
    vi.mocked(decrypt).mockResolvedValue(payload);
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result).toEqual({
      name: 'Test Server',
      baseUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      pushMiddlewareUrl: 'https://middleware.example.com',
      pushWebhookSecret: 'webhooksecret',
    });
  });

  it('throws on compact format with missing required fields', async () => {
    vi.mocked(decrypt).mockResolvedValue(JSON.stringify({ name: 'Test' }));
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
      apiKey: 'mykey',
      pin: '1234',
      pushMiddlewareUrl: undefined,
      pushWebhookSecret: undefined,
    });
  });
});
