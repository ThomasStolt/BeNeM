import { describe, it, expect, afterEach, vi } from 'vitest';
import { QueryClient, onlineManager } from '@tanstack/react-query';
import { fetchJson } from '../client';

/**
 * What state does a failing incidents query actually end up in?
 *
 * Measured in the browser on 2026-09-15 (evidence file Part 7): with a refused
 * credential the incidents query sat at `status: 'pending'`, `fetchStatus:
 * 'paused'`, `error: null`, so `isError` was false and IncidentListScreen's
 * `isError && !data` branch never rendered — the user got a blank screen with no
 * message. The hypothesis was that a failing first attempt with `retry: 1` leaves
 * the query pending with the retry paused, i.e. the error branch is unreachable
 * rather than missing.
 *
 * These tests settle which conditions produce that triple. They are about React
 * Query's own behaviour, not about the deployment, which is why they belong here
 * rather than in another browser sitting.
 */

// main.tsx's defaults, reproduced exactly.
const APP_DEFAULTS = { retry: 1, staleTime: 30_000, refetchOnWindowFocus: true };

const CONFIG = { baseUrl: '/bhnm', apiKey: 'test-key' };

function incidentsQuery(client: QueryClient) {
  return client.fetchQuery({
    queryKey: ['incidents', 'test'],
    queryFn: () => fetchJson(CONFIG.baseUrl, '/api/v1/incidents', { 'X-Proxy-Token': CONFIG.apiKey }),
  });
}

function stateOf(client: QueryClient) {
  const q = client.getQueryCache().getAll().find((x) => x.queryKey[0] === 'incidents')!;
  return { status: q.state.status, fetchStatus: q.state.fetchStatus, error: q.state.error };
}

afterEach(() => {
  onlineManager.setOnline(true);
  vi.unstubAllGlobals();
});

describe('a failing incidents query, with the app’s own defaults', () => {
  it('reaches status=error when the network rejects and the browser is online', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    const client = new QueryClient({ defaultOptions: { queries: APP_DEFAULTS } });

    await expect(incidentsQuery(client)).rejects.toThrow();

    const s = stateOf(client);
    expect(s.status).toBe('error');
    expect(s.fetchStatus).toBe('idle');
    expect(s.error).not.toBeNull();
  });

  it('reaches status=error on a 401 when the browser is online', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response('{"detail":"Invalid proxy token"}', { status: 401 })),
    );
    const client = new QueryClient({ defaultOptions: { queries: APP_DEFAULTS } });

    await expect(incidentsQuery(client)).rejects.toThrow();

    const s = stateOf(client);
    expect(s.status).toBe('error');
    expect(s.fetchStatus).toBe('idle');
    expect(s.error).not.toBeNull();
  });

  it('sits at pending/paused/error=null when React Query believes it is offline', async () => {
    // The signature observed in the browser. Reproduced here by the one condition
    // that produces it, so the signature is attributable rather than mysterious.
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    const client = new QueryClient({ defaultOptions: { queries: APP_DEFAULTS } });
    onlineManager.setOnline(false);

    incidentsQuery(client).catch(() => undefined); // never settles while paused
    await new Promise((r) => setTimeout(r, 50));

    const s = stateOf(client);
    expect(s.status).toBe('pending');
    expect(s.fetchStatus).toBe('paused');
    expect(s.error).toBeNull();

    // And this is what IncidentListScreen reads: isError is false, so its
    // `isError && !data` branch cannot render. Blank screen, no message.
    expect(s.status === 'error').toBe(false);
  });
});
