import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { parseQRUrl } from './qr-parser';

function mockFetch(payload: unknown, ok = true) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok,
      json: () => Promise.resolve(payload),
    }),
  );
}

describe('parseQRUrl', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('rejects non-benem URLs', async () => {
    await expect(parseQRUrl('https://example.com')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('rejects benem URLs without configure host', async () => {
    await expect(parseQRUrl('benem://other')).rejects.toThrow('Not a BeNeM configuration URL');
  });

  it('parses compact format with snake_case field names (middleware format)', async () => {
    mockFetch({
      bhnm_url: 'https://bhnm.example.com',
      middleware_url: 'https://middleware.example.com',
      api_key: 'mykey',
      pin: '1234',
      push_secret: 'webhooksecret',
      name: 'Test Server',
      user: 'admin',
    });
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result).toEqual({
      name: 'Test Server',
      baseUrl: '/bhnm',
      bhnmUrl: 'https://bhnm.example.com',
      apiKey: 'mykey',
      pin: '1234',
      ackUser: 'admin',
      pushMiddlewareUrl: 'https://middleware.example.com',
      pushWebhookSecret: 'webhooksecret',
    });
  });

  it('throws on compact format with missing required fields', async () => {
    mockFetch({ name: 'Test' });
    const fakeB64 = btoa('fakeciphertext');
    await expect(parseQRUrl(`benem://configure?p=${fakeB64}`))
      .rejects.toThrow('Missing required fields');
  });

  it('throws when server returns an error for compact format', async () => {
    mockFetch(null, false);
    const fakeB64 = btoa('fakeciphertext');
    await expect(parseQRUrl(`benem://configure?p=${fakeB64}`))
      .rejects.toThrow('QR code could not be decrypted');
  });

  it('throws when no p parameter and no legacy parameters', async () => {
    await expect(parseQRUrl('benem://configure'))
      .rejects.toThrow('No configuration data');
  });

  it('sends the blob to /bhnm/api/v1/qr-redeem', async () => {
    mockFetch({ bhnm_url: 'https://bhnm.test', api_key: 'k', name: 'S' });
    await parseQRUrl('benem://configure?p=abc-def_ghi');
    expect(fetch).toHaveBeenCalledWith(
      '/bhnm/api/v1/qr-redeem',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ blob: 'abc-def_ghi' }),
      }),
    );
  });

  it('throws a helpful message for legacy format', async () => {
    const fakeB64 = btoa('encrypted');
    const url = `benem://configure?server=${fakeB64}&api_key=${fakeB64}`;
    await expect(parseQRUrl(url)).rejects.toThrow('older format');
  });

  it('falls back to bhnm_url as baseUrl when middleware_url is absent', async () => {
    mockFetch({ bhnm_url: 'https://bhnm.example.com', api_key: 'mykey', name: 'No Middleware' });
    const fakeB64 = btoa('fakeciphertext');
    const result = await parseQRUrl(`benem://configure?p=${fakeB64}`);
    expect(result.baseUrl).toBe('/bhnm');
    expect(result.bhnmUrl).toBe('https://bhnm.example.com');
    expect(result.pushMiddlewareUrl).toBeUndefined();
  });
});
