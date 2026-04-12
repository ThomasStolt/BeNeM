import { useState, useCallback } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useIncidents } from './useIncidents';
import { useIncidentDetail } from './useIncidentDetail';
import { useConfig } from '../../lib/config';
import { acknowledgeIncident, unacknowledgeIncident } from '../../lib/api/incidents';
import { StatusBadge } from './StatusBadge';
import { StateBadge } from './StateBadge';
import { AlarmBadges } from './AlarmBadges';
import { Toast, type ToastMessage } from '../../components/Toast';
import type { IncidentAlarm, IncidentLogEntry } from '../../lib/api/types';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

function formatTimestamp(d: Date): string {
  return (
    d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) +
    ' · ' +
    d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false })
  );
}

function formatDuration(start: Date): string {
  const s = Math.max(0, Math.floor((Date.now() - start.getTime()) / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (d > 0) return `${d}d ${h}h ${m}m ${sec}s`;
  if (h > 0) return `${h}h ${m}m ${sec}s`;
  return `${m}m ${sec}s`;
}

function AlarmRow({ alarm }: { alarm: IncidentAlarm }) {
  return (
    <div className="py-2 border-b border-slate-950 last:border-0">
      <div className="flex items-center gap-1.5 mb-1">
        <StateBadge state={alarm.state} />
        <span className="text-[11px] text-slate-500">{alarm.type}</span>
      </div>
      {alarm.output && (
        <p className="text-[11px] text-slate-400 leading-snug">{alarm.output}</p>
      )}
      {alarm.time && (
        <p className="text-[10px] text-slate-600 mt-1">{formatTimestamp(alarm.time)}</p>
      )}
    </div>
  );
}

function LogRow({ entry }: { entry: IncidentLogEntry }) {
  return (
    <div className="py-2 border-b border-slate-950 last:border-0">
      <div className="flex items-center justify-between mb-1">
        <StateBadge state={entry.state} />
        {entry.time && (
          <span className="text-[10px] text-slate-600">{formatTimestamp(entry.time)}</span>
        )}
      </div>
      {entry.username && (
        <p className="text-[11px] text-slate-500">{entry.username}</p>
      )}
      {entry.comment && (
        <p className="text-[11px] text-slate-400">{entry.comment}</p>
      )}
    </div>
  );
}

export function IncidentDetailScreen() {
  const { id } = useParams();
  const { data: incidents, isLoading, isFetching } = useIncidents();
  const {
    data: detail,
    isLoading: isDetailLoading,
    isError: isDetailError,
    refetch: refetchDetail,
  } = useIncidentDetail(id ?? '');
  const config = useConfig();
  const queryClient = useQueryClient();
  const [isAcking, setIsAcking] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const dismissToast = useCallback(() => setToast(null), []);

  const incident = incidents?.find((i) => i.incidentId === id);

  if ((isLoading || isFetching) && !incident) {
    return (
      <div className="p-6">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <p className="mt-4 text-slate-400">Loading...</p>
      </div>
    );
  }

  if (!incident) {
    return (
      <div className="p-6">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <p className="mt-4 text-slate-400">Incident not found.</p>
      </div>
    );
  }

  const isAlarmsCleared = incident.incidentState.toUpperCase() === 'ALARMS CLEARED';
  const isAcked = incident.status === 'acknowledged';
  const alarmCounts = detail?.alarmCounts ?? incident.alarmCounts ?? EMPTY_COUNTS;

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
      await queryClient.invalidateQueries({ queryKey: ['incidentDetail', id] });
    } catch (err) {
      setToast({ text: err instanceof Error ? err.message : 'ACK failed', type: 'error' });
    } finally {
      setIsAcking(false);
    }
  };

  const infoRows: [string, string][] = [
    ['Incident ID', incident.incidentId],
    ...(detail ? ([
      ['Title', detail.title],
      ['Device', detail.deviceName],
      ...(detail.deviceIp ? [['IP', detail.deviceIp]] : []),
      ...(detail.alertType ? [['Alert Type', detail.alertType]] : []),
      ...(detail.openTime ? [
        ['Created', formatTimestamp(detail.openTime)],
        ['Duration', formatDuration(detail.openTime)],
      ] : []),
      ...(detail.acknowledged && detail.ackTime ? [['ACK Time', formatTimestamp(detail.ackTime)]] : []),
      ...(detail.acknowledged && detail.ackUser ? [['ACK User', detail.ackUser]] : []),
      ...(detail.acknowledged && detail.ackComment ? [['ACK Comment', detail.ackComment]] : []),
    ] as [string, string][]) : ([
      ['Device', incident.deviceName ?? 'Unknown'],
      ...(incident.deviceIp ? [['IP', incident.deviceIp]] : []),
    ] as [string, string][])),
  ];

  return (
    <div className="min-h-full">
      {/* Header */}
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between sticky top-0 bg-slate-950 z-10">
        <Link to="/incidents" className="text-sm text-slate-400 hover:text-slate-200">
          ← Back
        </Link>
        <h1 className="text-base font-semibold">Incident Detail</h1>
        <span
          className={`text-xs text-sky-400 ${isDetailLoading ? 'animate-spin' : 'invisible'}`}
          aria-hidden="true"
        >
          ↻
        </span>
      </header>

      <div className="p-3 space-y-2.5">
        {/* Status section */}
        <div className="bg-slate-900 rounded-xl p-3 flex items-center justify-between gap-3">
          {isAlarmsCleared ? (
            <div className="w-9 h-9 rounded-full bg-slate-700 flex items-center justify-center text-slate-400 text-lg flex-shrink-0">
              ✓
            </div>
          ) : isAcking ? (
            <div className="w-9 h-9 flex items-center justify-center flex-shrink-0">
              <span className="text-sky-400 animate-spin text-lg" aria-hidden="true">↻</span>
            </div>
          ) : (
            <button
              type="button"
              onClick={handleToggleAck}
              className="w-9 h-9 rounded-full bg-sky-500 hover:bg-sky-400 flex items-center justify-center text-white text-lg flex-shrink-0 transition-colors"
              aria-label={isAcked ? 'Unacknowledge' : 'Acknowledge'}
            >
              {isAcked ? '↩' : '✓'}
            </button>
          )}

          <div className="flex flex-col items-center gap-1">
            <span className="text-[10px] text-slate-500">Status</span>
            <StatusBadge status={incident.status} incidentState={incident.incidentState} />
          </div>

          <AlarmBadges counts={alarmCounts} />
        </div>

        {/* Detail loading skeleton */}
        {isDetailLoading && !detail && (
          <div className="bg-slate-900 rounded-xl p-3 animate-pulse h-48" />
        )}

        {/* Detail error */}
        {isDetailError && !detail && (
          <div className="bg-slate-900 rounded-xl p-3 text-center">
            <p className="text-sm text-slate-400 mb-2">Failed to load incident details</p>
            <button
              type="button"
              onClick={() => refetchDetail()}
              className="text-xs text-sky-400 hover:text-sky-300"
            >
              Retry
            </button>
          </div>
        )}

        {/* Incident Info */}
        <div className="bg-slate-900 rounded-xl overflow-hidden">
          <div className="px-3 py-2 border-b border-slate-800">
            <div className="text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Incident Info
            </div>
          </div>
          <div className="px-3">
            {infoRows.map(([label, value], idx) => (
              <div
                key={idx}
                className="flex justify-between items-baseline gap-2 py-1.5 border-b border-slate-800/40 last:border-0 text-sm"
              >
                <span className="text-slate-500 flex-shrink-0">{label}</span>
                <span className="text-slate-200 text-right text-xs">{value}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Primary Alarms */}
        {detail && detail.primaryAlarms.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Primary Alarms ({detail.primaryAlarms.length})
            </div>
            <div className="px-3">
              {detail.primaryAlarms.map((alarm, i) => (
                <AlarmRow key={i} alarm={alarm} />
              ))}
            </div>
          </div>
        )}

        {/* Related Alarms */}
        {detail && detail.relatedAlarms.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Related Alarms ({detail.relatedAlarms.length})
            </div>
            <div className="px-3">
              {detail.relatedAlarms.map((alarm, i) => (
                <AlarmRow key={i} alarm={alarm} />
              ))}
            </div>
          </div>
        )}

        {/* Incident State Log */}
        {detail && detail.incidentLog.length > 0 && (
          <div className="bg-slate-900 rounded-xl overflow-hidden">
            <div className="px-3 py-2 border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-500">
              Incident State Log
            </div>
            <div className="px-3">
              {detail.incidentLog.map((entry, i) => (
                <LogRow key={i} entry={entry} />
              ))}
            </div>
          </div>
        )}
      </div>

      <Toast message={toast} onDismiss={dismissToast} />
    </div>
  );
}
