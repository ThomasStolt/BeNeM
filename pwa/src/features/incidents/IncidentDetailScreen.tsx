import { useState, useCallback } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { useConfig } from '../../lib/config';
import { acknowledgeIncident, unacknowledgeIncident } from '../../lib/api/incidents';
import { SeverityBadge } from './SeverityBadge';
import { Toast, type ToastMessage } from '../../components/Toast';

function formatTimestamp(d: Date): string {
  return d.toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  }) + ' · ' + d.toLocaleTimeString('en-US', {
    hour: '2-digit', minute: '2-digit', hour12: false,
  });
}

function formatDuration(start: Date): string {
  const diffMs = Date.now() - start.getTime();
  const min = Math.floor(diffMs / 60_000);
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  const remainMin = min % 60;
  if (hr < 24) return `${hr}h ${remainMin}m`;
  const days = Math.floor(hr / 24);
  return `${days}d ${hr % 24}h`;
}

const STATUS_CLASSES: Record<string, string> = {
  active: 'bg-amber-500/20 text-amber-400',
  acknowledged: 'bg-emerald-500/20 text-emerald-400',
  resolved: 'bg-slate-500/20 text-slate-400',
  closed: 'bg-slate-500/20 text-slate-400',
};

export function IncidentDetailScreen() {
  const { id } = useParams();
  const { data: incidents, isLoading, isFetching } = useIncidents();
  const config = useConfig();
  const queryClient = useQueryClient();
  const [isAcking, setIsAcking] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const dismissToast = useCallback(() => setToast(null), []);

  const incident = incidents?.find((i) => i.incidentId === id);

  // Still loading the incident list (cold start / deep-link)
  if (isLoading || (isFetching && !incident)) {
    return (
      <div className="p-6">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <p className="mt-4 text-slate-400">Loading incident...</p>
      </div>
    );
  }

  if (!incident) {
    return (
      <div className="p-6">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <p className="mt-4 text-slate-400">Incident not found.</p>
      </div>
    );
  }

  const isAcked = incident.status === 'acknowledged';

  const handleToggleAck = async () => {
    setIsAcking(true);
    setToast(null);
    try {
      if (isAcked) {
        await unacknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Unacknowledged', type: 'success' });
      } else {
        await acknowledgeIncident(config, incident.incidentId);
        setToast({ text: 'Acknowledged', type: 'success' });
      }
      await queryClient.invalidateQueries({ queryKey: ['incidents'] });
    } catch (err) {
      setToast({ text: err instanceof Error ? err.message : 'ACK failed', type: 'error' });
    } finally {
      setIsAcking(false);
    }
  };

  return (
    <div className="min-h-full">
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-400 hover:text-slate-200">← Back</Link>
        <h1 className="text-lg font-semibold">{incident.displayId}</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      {/* Status banner */}
      <div className="px-4 py-3 bg-slate-900 border-b border-slate-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SeverityBadge severity={incident.severity} />
          <span className={`text-xs px-2 py-0.5 rounded ${STATUS_CLASSES[incident.status] ?? ''}`}>
            {incident.incidentState}
          </span>
        </div>
        <button
          type="button"
          onClick={handleToggleAck}
          disabled={isAcking}
          className={isAcked
            ? 'px-4 py-2 rounded border border-slate-600 text-sm text-slate-300 hover:bg-slate-800 disabled:opacity-50'
            : 'px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm font-semibold text-white disabled:opacity-50'
          }
        >
          {isAcking ? '...' : isAcked ? 'Unacknowledge' : 'Acknowledge'}
        </button>
      </div>

      <div className="p-4 space-y-3">
        {/* Summary */}
        <div>
          <div className="text-sm font-semibold">{incident.summary}</div>
        </div>

        {/* Device info card */}
        <div className="bg-slate-900 rounded-lg p-3">
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
            <dt className="text-slate-500">Device</dt>
            <dd className="font-medium">{incident.deviceName ?? 'Unknown'}</dd>
            <dt className="text-slate-500">IP</dt>
            <dd className="font-mono">{incident.deviceIp ?? '—'}</dd>
          </dl>
        </div>

        {/* Timing card */}
        <div className="bg-slate-900 rounded-lg p-3">
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
            <dt className="text-slate-500">Created</dt>
            <dd>{formatTimestamp(incident.startTime)}</dd>
            <dt className="text-slate-500">Duration</dt>
            <dd>{formatDuration(incident.startTime)}</dd>
            <dt className="text-slate-500">Incident ID</dt>
            <dd className="font-mono text-xs">{incident.incidentId}</dd>
          </dl>
        </div>

        {/* ACK info card — only when acknowledged */}
        {isAcked && incident.acknowledgedBy && (
          <div className="bg-slate-900 rounded-lg p-3 border-l-2 border-emerald-500">
            <div className="text-xs text-emerald-400 font-semibold mb-2">ACKNOWLEDGED</div>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
              <dt className="text-slate-500">By</dt>
              <dd>{incident.acknowledgedBy}</dd>
            </dl>
          </div>
        )}
      </div>

      <Toast message={toast} onDismiss={dismissToast} />
    </div>
  );
}
