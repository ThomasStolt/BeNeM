import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  parseMaintenanceStatus,
  activeEnd,
  activeComment,
  createMaintenanceWindow,
  closeMaintenanceWindow,
  fetchMaintenanceStatus,
} from './maintenance';
import type { BhnmConfig } from '../config';

const config = {
  baseUrl: '/bhnm',
  apiKey: 'key',
  pin: '',
} as BhnmConfig;

describe('parseMaintenanceStatus', () => {
  it('parses the merged middleware shape with epoch→Date conversion', () => {
    const s = parseMaintenanceStatus({
      inMaintenance: true,
      windows: [{ start_time: 1000, end_time: 2000, comment: 'patching' }],
    });
    expect(s.inMaintenance).toBe(true);
    expect(s.windows[0].start.getTime()).toBe(1000_000);
    expect(s.windows[0].end.getTime()).toBe(2000_000);
    expect(s.windows[0].comment).toBe('patching');
  });

  it('treats a missing inMaintenance field as false (version gate)', () => {
    const s = parseMaintenanceStatus({ windows: [] });
    expect(s.inMaintenance).toBe(false);
  });

  it('parses the live host status literal, accepting only UP / DOWN (middleware 2.12.1)', () => {
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [], status: 'DOWN' }).hostStatus).toBe('DOWN');
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [], status: 'UP' }).hostStatus).toBe('UP');
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [] }).hostStatus).toBeNull();
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [], status: 'UNREACHABLE' }).hostStatus).toBeNull();
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [], status: 'down' }).hostStatus).toBeNull();
  });

  it('treats missing windows as empty', () => {
    const s = parseMaintenanceStatus({ inMaintenance: true });
    expect(s.windows).toEqual([]);
  });
});

describe('activeEnd / activeComment', () => {
  const status = parseMaintenanceStatus({
    inMaintenance: true,
    windows: [
      { start_time: 1000, end_time: 5000, comment: 'later window' },
      { start_time: 1000, end_time: 2000, comment: 'earlier window' },
    ],
  });

  it('picks the latest end across windows', () => {
    expect(activeEnd(status)?.getTime()).toBe(5000_000);
  });

  it('picks the comment of the latest-ending window', () => {
    expect(activeComment(status)).toBe('later window');
  });

  it('returns null for empty windows', () => {
    const empty = parseMaintenanceStatus({ inMaintenance: true, windows: [] });
    expect(activeEnd(empty)).toBeNull();
    expect(activeComment(empty)).toBeNull();
  });
});

describe('createMaintenanceWindow', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('returns the snapped start from the X-Maintenance-Start header', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ result: 'completed' }), {
        status: 200,
        headers: { 'X-Maintenance-Start': '1788337500' },
      }),
    ));
    const start = await createMaintenanceWindow(config, 'router-1', 60, 'note');
    expect(start?.getTime()).toBe(1788337500_000);
  });

  it('returns null when the header is absent (older middleware)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ result: 'completed' }), { status: 200 }),
    ));
    const start = await createMaintenanceWindow(config, 'router-1', 60, 'note');
    expect(start).toBeNull();
  });

  it('throws on a BHNM error result', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ result: 'error', detail: 'Start time error' }), { status: 200 }),
    ));
    await expect(createMaintenanceWindow(config, 'router-1', 60, '')).rejects.toThrow('Start time error');
  });
});

describe('closeMaintenanceWindow', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('posts action-free close to the close route with the device name', async () => {
    const fetchMock = vi.fn(async (_url: RequestInfo | URL, _init?: RequestInit) =>
      new Response(JSON.stringify({ result: 'completed', detail: 'All maintenance windows for this device are closed' }), { status: 200 }),
    );
    vi.stubGlobal('fetch', fetchMock);
    await closeMaintenanceWindow(config, 'router-1');
    const [url, init] = fetchMock.mock.calls[0];
    expect(String(url)).toContain('/api/proxy/maintenance/close');
    expect(String(init?.body)).toContain('name=router-1');
  });

  it('throws on a BHNM error result', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ result: 'error', detail: 'Device not found' }), { status: 200 }),
    ));
    await expect(closeMaintenanceWindow(config, 'router-1')).rejects.toThrow('Device not found');
  });
});

describe('fetchMaintenanceStatus', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('returns the parsed status on success', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({
        inMaintenance: true,
        windows: [{ start_time: 1, end_time: 2, comment: 'x' }],
      }), { status: 200 }),
    ));
    const s = await fetchMaintenanceStatus(config, 'router-1');
    expect(s?.inMaintenance).toBe(true);
    expect(s?.windows).toHaveLength(1);
  });

  it('returns null on failure (best-effort read, no throw)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('network down'); }));
    const s = await fetchMaintenanceStatus(config, 'router-1');
    expect(s).toBeNull();
  });
});

describe('fetchMaintenanceMap', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('returns active names and server-scheduled starts', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({
        cache_age_seconds: 42,
        in_maintenance: ['sw-01', 'srv-09'],
        scheduled: [{ name: 'edge-02', start_time: 1788353700, end_time: 1788355500 }],
      }), { status: 200 }),
    ));
    const { fetchMaintenanceMap } = await import('./maintenance');
    const map = await fetchMaintenanceMap(config);
    expect(map.active).toEqual(new Set(['sw-01', 'srv-09']));
    expect(map.scheduled.get('edge-02')?.getTime()).toBe(1788353700_000);
  });

  it('tolerates an older middleware without the scheduled field', async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ cache_age_seconds: 42, in_maintenance: ['sw-01'] }), { status: 200 }),
    ));
    const { fetchMaintenanceMap } = await import('./maintenance');
    const map = await fetchMaintenanceMap(config);
    expect(map.active).toEqual(new Set(['sw-01']));
    expect(map.scheduled.size).toBe(0);
  });

  it('returns empty on failure (best-effort — no state shown)', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('down'); }));
    const { fetchMaintenanceMap } = await import('./maintenance');
    const map = await fetchMaintenanceMap(config);
    expect(map.active).toEqual(new Set());
    expect(map.scheduled.size).toBe(0);
    expect(map.down.size).toBe(0);
  });

  // ── host_down (Wave B, middleware 2.12.0) ──────────────────────────────────

  async function mapFor(body: unknown) {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify(body), { status: 200 })));
    const { fetchMaintenanceMap } = await import('./maintenance');
    return fetchMaintenanceMap(config);
  }

  it('parses host_down names when the cache is fresh, dropping non-strings', async () => {
    const map = await mapFor({ cache_age_seconds: 12, in_maintenance: [], scheduled: [],
      host_down: ['raspi-050', 42, null, 'raspi-054'] });
    expect(map.down).toEqual(new Set(['raspi-050', 'raspi-054']));
  });

  it('host_down absent (older middleware) → empty down set, wrenches unaffected', async () => {
    const map = await mapFor({ cache_age_seconds: 12, in_maintenance: ['sw-01'], scheduled: [] });
    expect(map.down.size).toBe(0);
    expect(map.active).toEqual(new Set(['sw-01']));
  });

  it('cache_age_seconds null (cold / cache-off / unresolved) → host_down ignored', async () => {
    const map = await mapFor({ cache_age_seconds: null, in_maintenance: [], scheduled: [],
      host_down: ['raspi-050'] });
    expect(map.down.size).toBe(0);
  });

  it('age above HOST_DOWN_MAX_AGE_S (stalled loop) → host_down ignored; at the bound → kept', async () => {
    const { HOST_DOWN_MAX_AGE_S } = await import('./maintenance');
    expect(HOST_DOWN_MAX_AGE_S).toBe(300);
    const stale = await mapFor({ cache_age_seconds: 301, in_maintenance: [], scheduled: [], host_down: ['raspi-050'] });
    expect(stale.down.size).toBe(0);
    const fresh = await mapFor({ cache_age_seconds: 299, in_maintenance: [], scheduled: [], host_down: ['raspi-050'] });
    expect(fresh.down).toEqual(new Set(['raspi-050']));
  });

  it('an unknown sibling key never changes the active set (additive-key contract, both directions)', async () => {
    const map = await mapFor({ cache_age_seconds: 5, in_maintenance: ['sw-01'], scheduled: [],
      host_down: ['x'], some_future_key: { nested: true } });
    expect(map.active).toEqual(new Set(['sw-01']));
  });
});

describe('parseMaintenanceStatus scheduled', () => {
  it('parses the middleware-remembered scheduled start', () => {
    const s = parseMaintenanceStatus({
      inMaintenance: false, windows: [],
      scheduled: { start_time: 1788353700, end_time: 1788355500 },
    });
    expect(s.scheduledStart?.getTime()).toBe(1788353700_000);
  });

  it('scheduledStart is null when absent (older middleware / none)', () => {
    expect(parseMaintenanceStatus({ inMaintenance: false, windows: [] }).scheduledStart).toBeNull();
  });
});
