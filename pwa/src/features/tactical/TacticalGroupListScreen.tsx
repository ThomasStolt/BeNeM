import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useTacticalGroups } from './useTacticalGroups';
import { TacticalGroupRow, isGroupHealthy } from './TacticalGroupRow';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';

const TITLES: Record<string, string> = {
  category: 'Categories',
  site: 'Sites',
  bw: 'Business Workflows',
};

export function TacticalGroupListScreen() {
  const { type = 'category' } = useParams<{ type: string }>();
  const config = useConfig();
  const { data: groups, isLoading, isError, error, dataUpdatedAt } = useTacticalGroups(type);
  const [filterActive, setFilterActive] = useState(false);

  const title = TITLES[type] ?? 'Groups';
  const displayGroups = filterActive
    ? (groups ?? []).filter((g) => !isGroupHealthy(g))
    : groups;

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <Link to="/" className="text-xs text-sky-400 hover:text-sky-300">
            &larr; Dashboard
          </Link>
          <h1 className="text-lg font-semibold mt-1">{title}</h1>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={() => setFilterActive((v) => !v)}
            aria-label="Filter unhealthy"
            className={`text-sm px-2 py-1 rounded ${
              filterActive
                ? 'bg-sky-600 text-white'
                : 'bg-slate-800 text-slate-400 hover:bg-slate-700'
            }`}
          >
            &#9698;
          </button>
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
        </div>
      </header>

      {!config.isConfigured && (
        <EmptyState
          title="Not configured"
          description="Add a server in Settings."
          action={
            <Link to="/settings" className="px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
              Configure
            </Link>
          }
        />
      )}

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching tactical data." />
      )}

      {isError && (
        <EmptyState title="Could not load data" description={(error as Error).message} />
      )}

      {displayGroups && displayGroups.length === 0 && (
        <EmptyState
          title={filterActive ? 'All groups are healthy' : 'No data available'}
        />
      )}

      {displayGroups && displayGroups.length > 0 && (
        <div>
          {displayGroups.map((group) => (
            <TacticalGroupRow key={group.name} group={group} />
          ))}
        </div>
      )}
    </div>
  );
}
