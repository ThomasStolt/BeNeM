import { useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { AppHeader } from '../../components/AppHeader';
import { SummaryCards } from './SummaryCards';
import { IncidentTicker } from './IncidentTicker';
import { StatusCard } from './StatusCard';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const queryClient = useQueryClient();
  const { data: summary, isLoading: summaryLoading, isError: summaryError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents, isLoading: incidentsLoading, isError: incidentsError } = useIncidents();

  const isLoading = summaryLoading || incidentsLoading;
  const isError = summaryError || incidentsError;

  const handleRefresh = useCallback(() => {
    queryClient.invalidateQueries();
  }, [queryClient]);

  const activeIncidents = incidents?.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  ).length ?? 0;

  const totalDevices = summary
    ? summary.hosts.ok + summary.hosts.ack + summary.hosts.warn + summary.hosts.un + summary.hosts.crit
    : 0;

  return (
    <div className="min-h-full">
      <AppHeader
        title="Home"
        isLoading={isLoading}
        isError={isError}
        dataUpdatedAt={dataUpdatedAt}
        onRefresh={handleRefresh}
      />

      {isLoading && !summary && (
        <EmptyState title="Loading..." description="Fetching status from BHNM." />
      )}

      {isError && !summary && (
        <EmptyState
          title="Could not load dashboard"
          description={(error as Error).message}
        />
      )}

      {summary && (
        <div className="p-4 space-y-4">
          <SummaryCards activeIncidents={activeIncidents} totalDevices={totalDevices} />
          <IncidentTicker incidents={incidents ?? []} />
          <div className="grid grid-cols-2 gap-2">
            <StatusCard label="Hosts" counts={summary.hosts} />
            <StatusCard label="Services" counts={summary.services} />
            <StatusCard label="Thresholds" counts={summary.thresholds} />
            <StatusCard label="Anomalies" counts={summary.anomalies} />
          </div>
          <div>
            <div className="text-base font-semibold mb-3">Drill Down</div>
            <div className="flex flex-col gap-2.5">
              <Link
                to="/tactical/category"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-purple-400 text-lg">🏷</span>
                <span className="text-[15px] font-semibold flex-1">Categories</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
              <Link
                to="/tactical/site"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-blue-400 text-lg">📍</span>
                <span className="text-[15px] font-semibold flex-1">Sites</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
              <Link
                to="/tactical/bw"
                className="flex items-center gap-3 p-3.5 bg-slate-800 rounded-[10px] border border-slate-700/50 hover:bg-slate-750"
              >
                <span className="text-green-400 text-lg">🔄</span>
                <span className="text-[15px] font-semibold flex-1">Business Workflows</span>
                <span className="text-slate-500 text-sm">›</span>
              </Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
