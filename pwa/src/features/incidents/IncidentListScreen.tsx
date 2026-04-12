import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { SwipeableIncidentRow } from './SwipeableIncidentRow';
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

export function IncidentListScreen() {
  const { data, isLoading, isError, error, refetch, dataUpdatedAt } = useIncidents();
  const queryClient = useQueryClient();

  const onRefresh = useCallback(async () => {
    await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    await refetch();
  }, [queryClient, refetch]);

  return (
    <PullToRefresh onRefresh={onRefresh}>
      <AppHeader
        title="Incidents"
        isLoading={isLoading}
        isError={isError}
        dataUpdatedAt={dataUpdatedAt}
        onRefresh={onRefresh}
      />

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

      {data && data.length === 0 && (
        <EmptyState title="No incidents" description="All clear." />
      )}

      {data && data.length > 0 && (
        <ul role="list" data-testid="incident-list">
          {[...data].sort((a, b) => Number(b.incidentId) - Number(a.incidentId)).map((incident) => (
            <li key={incident.incidentId}>
              <SwipeableIncidentRow incident={incident} />
            </li>
          ))}
        </ul>
      )}
    </PullToRefresh>
  );
}
