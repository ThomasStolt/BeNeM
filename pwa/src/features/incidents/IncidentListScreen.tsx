import { useCallback, useDeferredValue, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  useIncidents,
  usePollWhileVisible,
  useRefreshIncidents,
  useRefreshOnForeground,
  useReloadIncidents,
  useReloadOnPush,
} from './useIncidents';
import { SwipeableIncidentRow } from './SwipeableIncidentRow';
import { IncidentPills } from './IncidentPills';
import { DEFAULT_PILL, isPill, pillCounts, selectIncidents, type Pill } from './pills';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { AppHeader } from '../../components/AppHeader';

function ConfigureLink() {
  return (
    <Link
      to="/settings"
      className="inline-block px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm"
    >
      Configure API key
    </Link>
  );
}

const EMPTY_FOR_PILL: Record<Pill, { title: string; description: string }> = {
  TOTAL: { title: 'No incidents', description: 'Nothing open or cleared. All clear.' },
  OPEN: { title: 'Nothing unacknowledged', description: 'Every open incident has been picked up.' },
  ACKD: { title: 'None acknowledged', description: 'Nobody has picked up an incident.' },
  CLRD: { title: 'None cleared', description: 'No incident is waiting with its alarms cleared.' },
  // The window is stated in words rather than implied. A closed incident older
  // than 24 hours is dropped by the middleware, and nothing on screen can tell
  // that apart from one that never existed — so the tab says what it covers.
  CLOSED: { title: 'Nothing closed recently', description: 'Closed incidents are shown for 24 hours.' },
};

export function IncidentListScreen() {
  const { data, isLoading, isError, error, dataUpdatedAt } = useIncidents();
  const { refresh, isRefreshing } = useRefreshIncidents();
  useRefreshOnForeground(refresh);

  // Two cache-only update paths beside the deliberate one above. `reload` is a
  // plain GET of the middleware's cache; `refresh` POSTs and makes the
  // middleware call BHNM. A user action earns the second; these do not.
  const reload = useReloadIncidents();
  useReloadOnPush(reload);
  usePollWhileVisible(reload);

  // The Home tile arrives with ?pill=TOTAL. Anything unrecognised falls back to
  // the default rather than showing an empty list nobody asked for.
  const [searchParams, setSearchParams] = useSearchParams();
  const fromUrl = searchParams.get('pill');
  const [pill, setPillState] = useState<Pill>(isPill(fromUrl) ? fromUrl : DEFAULT_PILL);
  const setPill = useCallback((next: Pill) => {
    setPillState(next);
    setSearchParams((prev) => {
      const params = new URLSearchParams(prev);
      params.set('pill', next);
      return params;
    }, { replace: true });
  }, [setSearchParams]);

  const [searchInput, setSearchInput] = useState('');
  const query = useDeferredValue(searchInput);

  const onRefresh = useCallback(async () => { await refresh(); }, [refresh]);

  const counts = useMemo(() => pillCounts(data ?? []), [data]);
  const rows = useMemo(() => selectIncidents(data ?? [], pill, query), [data, pill, query]);

  return (
    <PullToRefresh onRefresh={onRefresh}>
      <AppHeader
        title="Incidents"
        isLoading={isLoading || isRefreshing}
        isError={isError}
        dataUpdatedAt={dataUpdatedAt}
        onRefresh={onRefresh}
      />

      {data && (
        <div className="px-4 py-2 border-b border-slate-800 space-y-2">
          <IncidentPills selected={pill} counts={counts} onSelect={setPill} />
          <div className="relative">
            <input
              type="search"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search incidents…"
              aria-label="Search incidents"
              className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder:text-slate-500 focus:outline-none focus:border-sky-600"
            />
            {searchInput && (
              <button
                type="button"
                onClick={() => setSearchInput('')}
                aria-label="Clear search"
                className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300 text-sm px-1"
              >
                ✕
              </button>
            )}
          </div>
        </div>
      )}

      {isLoading && !data && (
        <EmptyState title="Loading…" description="Fetching incidents from BHNM." />
      )}

      {isError && !data && (
        <EmptyState
          title="Could not reach BHNM"
          description={(error as Error).message}
          action={
            <div className="flex gap-2">
              <button
                type="button"
                onClick={onRefresh}
                className="px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-sm"
              >
                Retry
              </button>
              <ConfigureLink />
            </div>
          }
        />
      )}

      {data && rows.length === 0 && (
        query.trim()
          ? <EmptyState title="No matches" description={`Nothing in ${pill} matches “${query.trim()}”.`} />
          : <EmptyState {...EMPTY_FOR_PILL[pill]} />
      )}

      {rows.length > 0 && (
        <ul role="list" data-testid="incident-list">
          {rows.map((incident) => (
            <li key={incident.incidentId}>
              <SwipeableIncidentRow incident={incident} />
            </li>
          ))}
        </ul>
      )}
    </PullToRefresh>
  );
}
