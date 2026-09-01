import { describe, it, expect } from 'vitest';
import { parseDiagnostics } from './diagnostics';

const FULL_PAYLOAD = {
  middleware: { version: '2.7.0', registered_devices: 5, server_time: 1788285788 },
  server: {
    name: "Thomas' Lab Server",
    host: 'bhnm-b.tstolt.com',
    cache_enabled: true,
    bhnm: {
      reachable: true,
      source: 'monitor',
      latency_ms: 180,
      last_success_age_seconds: 11,
      last_error: null,
      last_error_age_seconds: null,
      consecutive_failures: 0,
    },
    feeds: {
      incidents: { cached: true, age_seconds: 15, count: 10, consecutive_failures: 0, last_error: null },
      tactical: { cached: true, age_seconds: 20, count: 4, consecutive_failures: 0, last_error: null },
      thresholds: { cached: true, age_seconds: 30, count: 38, consecutive_failures: 0, last_error: null },
    },
  },
};

describe('parseDiagnostics', () => {
  it('parses a full healthy payload', () => {
    const d = parseDiagnostics(FULL_PAYLOAD);
    expect(d.middleware.version).toBe('2.7.0');
    expect(d.middleware.registered_devices).toBe(5);
    expect(d.server.host).toBe('bhnm-b.tstolt.com');
    expect(d.server.bhnm.reachable).toBe(true);
    expect(d.server.bhnm.source).toBe('monitor');
    expect(d.server.bhnm.latency_ms).toBe(180);
    expect(d.server.feeds.incidents.count).toBe(10);
    expect(d.server.feeds.tactical.cached).toBe(true);
  });

  it('keeps reachable:null as null (startup window — never coerced to false)', () => {
    const raw = structuredClone(FULL_PAYLOAD);
    raw.server.bhnm = {
      reachable: null, source: 'none', latency_ms: null,
      last_success_age_seconds: null, last_error: null,
      last_error_age_seconds: null, consecutive_failures: 0,
    } as never;
    const d = parseDiagnostics(raw);
    expect(d.server.bhnm.reachable).toBeNull();
    expect(d.server.bhnm.source).toBe('none');
  });

  it('parses a BHNM-down payload with error fields', () => {
    const raw = structuredClone(FULL_PAYLOAD);
    raw.server.bhnm = {
      reachable: false, source: 'monitor', latency_ms: null,
      last_success_age_seconds: null, last_error: 'HTTP 502',
      last_error_age_seconds: 4, consecutive_failures: 2,
    } as never;
    const d = parseDiagnostics(raw);
    expect(d.server.bhnm.reachable).toBe(false);
    expect(d.server.bhnm.last_error).toBe('HTTP 502');
    expect(d.server.bhnm.consecutive_failures).toBe(2);
  });

  it('tolerates missing feeds and middleware fields (degraded payload)', () => {
    const d = parseDiagnostics({ middleware: {}, server: { bhnm: {}, feeds: {} } });
    expect(d.middleware.version).toBeNull();
    expect(d.server.bhnm.reachable).toBeNull();
    expect(d.server.feeds).toEqual({});
    expect(d.server.name).toBe('');
  });

  it('throws on a non-object payload', () => {
    expect(() => parseDiagnostics(null)).toThrow();
    expect(() => parseDiagnostics('nope')).toThrow();
  });
});
