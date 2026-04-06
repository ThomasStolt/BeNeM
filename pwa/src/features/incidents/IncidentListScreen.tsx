import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { SwipeableIncidentRow } from './SwipeableIncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PullToRefresh } from '../../components/PullToRefresh';
import { useConfig } from '../../lib/config';

function GearIcon() {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="w-5 h-5"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h0a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51h0a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v0a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

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
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onRefresh}
            className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
            aria-label="Refresh"
          >
            Refresh
          </button>
          <Link
            to="/settings"
            aria-label="Settings"
            className="p-1 rounded hover:bg-slate-800 text-slate-300 hover:text-white"
          >
            <GearIcon />
          </Link>
        </div>
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
