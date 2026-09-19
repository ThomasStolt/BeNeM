// @vitest-environment jsdom
/**
 * Build order step 4 — the incident detail screen's three states, and the
 * unverified alert type.
 *
 * `Incident not found.` was banned on 2026-09-15 and was still rendered on
 * 2026-09-19, because one string was standing in for three different facts:
 * still looking, genuinely gone, and could not ask. Two of those three are not
 * a statement that the incident does not exist.
 *
 * Design: docs/superpowers/specs/2026-09-19-incident-freshness-webhook-first-design.md C2.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { ApiException } from '../../../lib/api/types';
import { isGone } from '../useSingleIncident';

const getSingleIncident = vi.fn();

vi.mock('../../../lib/api/incidents', async () => {
  const actual = await vi.importActual<Record<string, unknown>>('../../../lib/api/incidents');
  return { ...actual, getSingleIncident: (...a: unknown[]) => getSingleIncident(...a) };
});

vi.mock('../useIncidents', () => ({
  useIncidents: () => ({ data: [], isLoading: false, isFetching: false }),
}));

vi.mock('../useIncidentDetail', () => ({
  useIncidentDetail: () => ({
    data: undefined, isLoading: false, isError: false, refetch: vi.fn(),
  }),
}));

vi.mock('../../../lib/config', () => ({
  useConfig: () => ({ baseUrl: 'https://mw.test', apiKey: 'k', bhnmUrl: 'https://b.test', pin: '' }),
}));

import { IncidentDetailScreen, isUnverifiedType } from '../IncidentDetailScreen';

function renderDetail(id: string) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[`/incidents/${id}`]}>
        <Routes>
          <Route path="/incidents/:id" element={<IncidentDetailScreen />} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

beforeEach(() => {
  getSingleIncident.mockReset();
});

describe('the three states, never one string for all of them', () => {
  it('GONE (404) says the incident no longer exists', async () => {
    getSingleIncident.mockRejectedValue(
      new ApiException({ kind: 'server', status: 404, message: 'HTTP 404' }),
    );
    renderDetail('29570');
    await waitFor(() =>
      expect(screen.getByText(/no longer exists/i)).toBeInTheDocument());
    expect(screen.getByText(/removed from BHNM/i)).toBeInTheDocument();
    expect(screen.queryByText(/not found/i)).not.toBeInTheDocument();
  });

  it('UNREACHABLE says it could not load, and explicitly NOT that it is gone', async () => {
    getSingleIncident.mockRejectedValue(
      new ApiException({ kind: 'network', message: 'Request timed out' }),
    );
    renderDetail('29570');
    // Two fixed 1 s retries before the verdict — the bounded wait, exercised.
    await waitFor(
      () => expect(screen.getByText(/could not load this incident/i)).toBeInTheDocument(),
      { timeout: 5_000 },
    );
    // The load-bearing half: a transport failure must not be read as a verdict.
    expect(screen.getByText(/not a statement that it is gone/i)).toBeInTheDocument();
    expect(screen.queryByText(/no longer exists/i)).not.toBeInTheDocument();
  });

  it('FETCHING is shown while the lookup is in flight', () => {
    getSingleIncident.mockReturnValue(new Promise(() => {}));  // never settles
    renderDetail('29570');
    expect(screen.getByText(/fetching incident data/i)).toBeInTheDocument();
  });

  it('a found incident renders the incident, not a message', async () => {
    getSingleIncident.mockResolvedValue({
      incidentId: '29570', displayId: '#29570', deviceName: 'core-switch-01',
      deviceIp: null, summary: 'Host down', severity: 'critical', status: 'active',
      incidentState: 'OPEN', startTime: new Date('2026-09-19T10:00:00Z'),
      acknowledgedBy: null, alarmCounts: null,
    });
    renderDetail('29570');
    await waitFor(() =>
      expect(screen.getByText('Incident Detail')).toBeInTheDocument());
    expect(screen.queryByText(/fetching incident data/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/no longer exists/i)).not.toBeInTheDocument();
  });
});

describe('isGone keeps the terminal fact apart from the retryable one', () => {
  it('is true only for a 404', () => {
    expect(isGone(new ApiException({ kind: 'server', status: 404, message: '' }))).toBe(true);
  });

  it('is false for 502, for a network error and for anything else', () => {
    expect(isGone(new ApiException({ kind: 'server', status: 502, message: '' }))).toBe(false);
    expect(isGone(new ApiException({ kind: 'network', message: '' }))).toBe(false);
    expect(isGone(new Error('boom'))).toBe(false);
    expect(isGone(undefined)).toBe(false);
  });
});

describe('an unverified alert type gets its own appearance', () => {
  // Doctrine: verified good, verified bad, and UNVERIFIED — the third never
  // borrows the appearance of the first. `host` is the one type known to page,
  // so a failed lookup drawn as `host` is the strongest possible coverage claim
  // made on no evidence. The row is also never omitted: a missing row reads as
  // "nothing to say here", and the whole point is that there is.
  it('treats UNKNOWN, empty and missing as the same unverified state', () => {
    expect(isUnverifiedType('UNKNOWN')).toBe(true);
    expect(isUnverifiedType('unknown')).toBe(true);
    expect(isUnverifiedType('')).toBe(true);
    expect(isUnverifiedType('   ')).toBe(true);
    expect(isUnverifiedType(null)).toBe(true);
    expect(isUnverifiedType(undefined)).toBe(true);
  });

  it('does NOT treat a real type as unverified', () => {
    for (const t of ['host', 'Host', 'service', 'threshold', 'anomaly']) {
      expect(isUnverifiedType(t)).toBe(false);
    }
  });
});
