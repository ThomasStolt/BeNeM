import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { ConnectionBadge, type ConnectionStatus } from '../../components/ConnectionBadge';
import { RefreshRing } from '../../components/RefreshRing';
import { SummaryCards } from './SummaryCards';
import { IncidentTicker } from './IncidentTicker';
import { StatusCard } from './StatusCard';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const config = useConfig();
  const queryClient = useQueryClient();
  const { data: summary, isLoading: summaryLoading, isError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents, isLoading: incidentsLoading } = useIncidents();
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>(
    config.isConfigured ? 'unknown' : 'disconnected',
  );

  const isLoading = summaryLoading || incidentsLoading;
  const derivedStatus: ConnectionStatus = isLoading
    ? 'checking'
    : isError
      ? 'disconnected'
      : summary
        ? 'connected'
        : connectionStatus;

  const handleRefresh = useCallback(() => {
    setConnectionStatus('checking');
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
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <ConnectionBadge status={derivedStatus} onRetry={handleRefresh} />
        <div className="text-center">
          <div className="flex items-center justify-center gap-1.5">
            <div className="w-6 h-6 bg-blue-600 rounded-md flex items-center justify-center text-[12px] font-bold text-white">
              B
            </div>
            <h1 className="text-lg font-bold">Home</h1>
          </div>
          {config.serverName && (
            <p className="text-[11px] text-slate-500">{config.serverName}</p>
          )}
        </div>
        {dataUpdatedAt > 0 ? (
          <RefreshRing
            lastUpdatedAt={dataUpdatedAt}
            intervalMs={120_000}
            isLoading={isLoading}
            onRefresh={handleRefresh}
          />
        ) : (
          <div className="w-7" />
        )}
      </header>

      {!config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — add a server in Settings.</span>
          <Link to="/settings" className="px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
            Configure
          </Link>
        </div>
      )}

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
          {/* 1. Summary Cards */}
          <SummaryCards activeIncidents={activeIncidents} totalDevices={totalDevices} />

          {/* 2. Incident Ticker */}
          <IncidentTicker incidents={incidents ?? []} />

          {/* 3. Heat Map 2x2 */}
          <div className="grid grid-cols-2 gap-2">
            <StatusCard label="Hosts" counts={summary.hosts} />
            <StatusCard label="Services" counts={summary.services} />
            <StatusCard label="Thresholds" counts={summary.thresholds} />
            <StatusCard label="Anomalies" counts={summary.anomalies} />
          </div>

          {/* 4. Drill Down */}
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
