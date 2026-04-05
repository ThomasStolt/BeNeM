import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { IncidentRow } from './IncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { useConfig } from '../../lib/config';

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
            <button
              type="button"
              onClick={onRefresh}
              className="px-3 py-1 rounded bg-slate-800 hover:bg-slate-700 text-sm"
            >
              Retry
            </button>
          }
        />
      )}

      {!isLoading && !isError && data && data.length === 0 && (
        <EmptyState title="No open incidents" description="All clear." />
      )}

      {!isLoading && !isError && !config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30">
          Not configured — showing mock data. Set <code>VITE_BHNM_API_KEY</code> in <code>.env.local</code>.
        </div>
      )}

      <ul role="list" data-testid="incident-list">
        {data?.map((incident) => (
          <li key={incident.incidentId}>
            <IncidentRow incident={incident} />
          </li>
        ))}
      </ul>
    </PullToRefresh>
  );
}
