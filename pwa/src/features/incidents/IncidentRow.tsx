import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { SeverityBadge } from './SeverityBadge';
import { AlarmBadges } from './AlarmBadges';

function relativeTime(d: Date): string {
  const diffMs = Date.now() - d.getTime();
  const min = Math.round(diffMs / 60_000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const days = Math.round(hr / 24);
  return `${days}d ago`;
}

export function IncidentRow({ incident }: { incident: Incident }) {
  const ackPrefix = incident.status === 'acknowledged' ? '✓ ' : '';
  return (
    <Link
      to={`/incident/${encodeURIComponent(incident.incidentId)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      <div className="flex items-center gap-3">
        <SeverityBadge severity={incident.severity} />
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium truncate">
            {ackPrefix}
            {incident.deviceName ?? incident.deviceIp ?? 'Unknown device'}
          </div>
          <div className="text-xs text-slate-400 truncate">{incident.summary}</div>
        </div>
        <div className="flex flex-col items-end gap-1 shrink-0">
          <span className="text-xs text-slate-500">{relativeTime(incident.startTime)}</span>
          {incident.alarmCounts && <AlarmBadges counts={incident.alarmCounts} />}
        </div>
      </div>
    </Link>
  );
}
