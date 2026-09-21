import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { refreshIncidents } from '../incidents';
import type { BhnmConfig } from '../../config';

/** C7 / M2 — the Refresh control and the foreground resume both POST one
 * endpoint, and the answer is the list itself.
 *
 * Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §2 M2.
 */

const config: BhnmConfig = {
  serverId: 'lab',
  serverName: 'Lab',
  baseUrl: 'https://mw.example.com',
  apiKey: 'key-123',
  isConfigured: true,
  ackUser: 'Thomas',
  bhnmUrl: 'https://bhnm-b.example.com',
} as BhnmConfig;

const BODY = {
  cache_age_seconds: 0,
  coalesced: false,
  active_incidents: [
    { incident_id: '30014', title: 'Anomaly on UAP_AC_M', name: 'UAP_AC_M',
      state: 'ALARMS CLEARED', acknowledged: false, ack_user: null, closed_at: null,
      incident_state: 'ALARMS CLEARED' },
  ],
  closed_incidents: [],
};

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn(async () => new Response(JSON.stringify(BODY), {
    status: 200, headers: { 'Content-Type': 'application/json' },
  }));
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => { vi.unstubAllGlobals(); });

describe('refreshIncidents', () => {
  it('POSTs /api/v1/incidents/refresh with the proxy headers', async () => {
    await refreshIncidents(config);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://mw.example.com/api/v1/incidents/refresh');
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({
      'X-Proxy-Token': 'key-123',
      'X-BHNM-Target': 'https://bhnm-b.example.com',
    });
  });

  it('returns the parsed list, so one tap is one round trip', async () => {
    // The endpoint answers with the same shape as GET /api/v1/incidents. The
    // caller re-renders from THIS, rather than firing a second fetch for the
    // list it was just handed.
    const list = await refreshIncidents(config);
    expect(list).toHaveLength(1);
    expect(list[0].incidentId).toBe('30014');
    expect(list[0].state).toBe('ALARMS CLEARED');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('carries ALARMS CLEARED, which is the state only a list call can deliver', async () => {
    // [MEASURED 2026-09-21, BHNM-B] BHNM sends NO webhook for this transition,
    // so without the refresh there is no path for it to reach the client at all
    // under webhook mode.
    const [row] = await refreshIncidents(config);
    expect(row.state).toBe('ALARMS CLEARED');
    expect(row.status).toBe('active');
  });

  it('throws rather than emptying the list when the server refuses', async () => {
    // A failed refresh must not read as "no incidents". The middleware answers
    // 502 when getincidents did not complete; an empty list here would render
    // an outage as all-clear, which is the doctrine failure exactly.
    vi.stubGlobal('fetch', vi.fn(async () => new Response('', { status: 502 })));
    await expect(refreshIncidents(config)).rejects.toThrow();
  });
});
