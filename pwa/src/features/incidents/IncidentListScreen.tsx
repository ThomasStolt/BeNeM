import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { SwipeableIncidentRow } from './SwipeableIncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { useConfig } from '../../lib/config';

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

export function IncidentListScreen() {
  const { data, isLoading, isError, error, refetch } = useIncidents();
  const queryClient = useQueryClient();
  const config = useConfig();

  const onRefresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    await refetch();
  };

  return (
    <PullToRefresh onRefresh={onRefresh}>
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <h1 className="text-lg font-semibold">Incidents</h1>
        <button
          type="button"
          onClick={onRefresh}
          className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
          aria-label="Refresh"
        >
          Refresh
        </button>
      </header>

      {isLoading && (
        <EmptyState title="Loading…" description="Fetching incidents from BHNM." />
      )}

      {isError && (
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

      {!isLoading && !isError && !config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — showing mock data.</span>
          <ConfigureLink />
        </div>
      )}

      {!isLoading && !isError && data && data.length === 0 && (
        <EmptyState title="No open incidents" description="All clear." />
      )}

      <ul role="list" data-testid="incident-list">
        {data?.map((incident) => (
          <li key={incident.incidentId}>
            <SwipeableIncidentRow incident={incident} />
          </li>
        ))}
      </ul>
    </PullToRefresh>
  );
}
