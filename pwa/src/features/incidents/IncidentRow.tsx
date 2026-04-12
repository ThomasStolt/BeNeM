import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { StatusBadge } from './StatusBadge';
import { AlarmBadges } from './AlarmBadges';
import { OverflowMarquee } from '../../components/OverflowMarquee';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

function formatDuration(d: Date): string {
  const diffMs = Date.now() - d.getTime();
  const totalMin = diffMs / 60_000;
  if (totalMin < 1) return 'now';
  if (totalMin < 60) return `${Math.round(totalMin)}m`;
  const totalHr = totalMin / 60;
  if (totalHr < 24) return `${Math.round(totalHr)}h`;
  return `${Math.round(totalHr / 24)}d`;
}

export function IncidentRow({ incident }: { incident: Incident }) {
  return (
    <Link
      to={`/incidents/${encodeURIComponent(incident.incidentId)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      {/* Row 1: display ID + scrolling summary */}
      <div className="flex items-baseline gap-2 mb-1.5">
        <span className="shrink-0 text-xs font-semibold text-slate-500">
          {incident.displayId}
        </span>
        <OverflowMarquee
          text={incident.summary}
          className="flex-1 min-w-0 text-sm font-semibold text-slate-100"
        />
      </div>

      {/* Row 2: status badge · scrolling device name · duration · alarm dots */}
      <div className="flex items-center gap-1.5">
        <StatusBadge status={incident.status} incidentState={incident.incidentState} />
        <OverflowMarquee
          text={incident.deviceName ?? incident.deviceIp ?? 'Unknown'}
          className="flex-1 min-w-0 text-[11px] text-slate-400"
        />
        <span className="shrink-0 text-[11px] text-slate-500">
          {formatDuration(incident.startTime)}
        </span>
        <AlarmBadges counts={incident.alarmCounts ?? EMPTY_COUNTS} />
      </div>
    </Link>
  );
}
