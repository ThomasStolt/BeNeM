import { Link } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useIncidents } from '../incidents/useIncidents';
import { useTacticalSummary } from './useTacticalSummary';
import { StatusCard } from './StatusCard';
import { IncidentTicker } from './IncidentTicker';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';

export function DashboardScreen() {
  const config = useConfig();
  const { data: summary, isLoading, isError, error, dataUpdatedAt } = useTacticalSummary();
  const { data: incidents } = useIncidents();

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Dashboard</h1>
          {config.serverName && (
            <p className="text-xs text-slate-500">{config.serverName}</p>
          )}
        </div>
        <div className="flex items-center gap-3">
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
          <Link
            to="/settings"
            className="text-xs px-3 py-1 rounded bg-slate-800 hover:bg-slate-700"
          >
            Settings
          </Link>
        </div>
      </header>

      {!config.isConfigured && (
        <div className="px-4 py-2 text-xs bg-amber-500/20 text-amber-200 border-b border-amber-500/30 flex items-center justify-between gap-2">
          <span>Not configured — add a server in Settings.</span>
          <Link to="/settings" className="px-3 py-1 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
            Configure
          </Link>
        </div>
      )}

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching status from BHNM." />
      )}

      {isError && (
        <EmptyState
          title="Could not load dashboard"
          description={(error as Error).message}
        />
      )}

      {summary && (
        <div className="p-4 space-y-4">
          {/* Status Cards */}
          <div className="grid grid-cols-2 gap-3">
            <StatusCard label="Hosts" counts={summary.hosts} />
            <StatusCard label="Services" counts={summary.services} />
            <StatusCard label="Thresholds" counts={summary.thresholds} />
            <StatusCard label="Anomalies" counts={summary.anomalies} />
          </div>

          {/* Incident Ticker */}
          <div>
            <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Active Incidents
            </div>
            <IncidentTicker incidents={incidents ?? []} />
          </div>

          {/* Drill-Down Links */}
          <div>
            <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Tactical Overview
            </div>
            <div className="grid grid-cols-3 gap-2">
              <Link
                to="/tactical/category"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Categories
              </Link>
              <Link
                to="/tactical/site"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Sites
              </Link>
              <Link
                to="/tactical/bw"
                className="bg-slate-900 rounded-lg p-3 text-center text-sm text-slate-300 hover:bg-slate-800"
              >
                Business Workflows
              </Link>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
