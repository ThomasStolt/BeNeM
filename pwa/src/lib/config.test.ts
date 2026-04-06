import { describe, it, expect, beforeEach } from 'vitest';
import { getSnapshotForTest } from './config';
import { addServer, setActiveServer } from './serverStorage';

beforeEach(() => {
  localStorage.clear();
});

describe('config snapshot', () => {
  it('returns unconfigured when no servers exist', () => {
    const config = getSnapshotForTest();
    expect(config.isConfigured).toBe(false);
    expect(config.apiKey).toBe('');
  });

  it('reads from active server', () => {
    addServer({ name: 'Test', baseUrl: '/bhnm', apiKey: 'test-key', pin: 'pin123' });
    const config = getSnapshotForTest();
    expect(config.isConfigured).toBe(true);
    expect(config.apiKey).toBe('test-key');
    expect(config.pin).toBe('pin123');
    expect(config.baseUrl).toBe('/bhnm');
    expect(config.serverId).toBeTruthy();
    expect(config.serverName).toBe('Test');
  });

  it('reads from second server when it is active', () => {
    addServer({ name: 'First', baseUrl: '/a', apiKey: 'k1' });
    const s2 = addServer({ name: 'Second', baseUrl: '/b', apiKey: 'k2' });
    setActiveServer(s2.id);
    const config = getSnapshotForTest();
    expect(config.apiKey).toBe('k2');
    expect(config.serverName).toBe('Second');
  });

  it('includes webhook fields', () => {
    addServer({
      name: 'Push',
      baseUrl: '/bhnm',
      apiKey: 'k',
      pushWebhookSecret: 'secret',
      pushMiddlewareUrl: '/middleware',
    });
    const config = getSnapshotForTest();
    expect(config.webhookSecret).toBe('secret');
    expect(config.pushMiddlewareUrl).toBe('/middleware');
  });
});
