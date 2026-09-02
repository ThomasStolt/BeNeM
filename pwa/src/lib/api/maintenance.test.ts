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
