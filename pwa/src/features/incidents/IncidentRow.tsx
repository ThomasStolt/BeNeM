import { Link } from 'react-router-dom';
import type { Incident } from '../../lib/api/types';
import { StatusBadge } from './StatusBadge';
import { AlarmBadges } from './AlarmBadges';
import { OverflowMarquee } from '../../components/OverflowMarquee';
import { useIncidentDetail } from './useIncidentDetail';

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

function ShimmerBadges() {
  return (
    <div className="flex gap-1">
      {(['green', 'blue', 'yellow', 'orange', 'red'] as const).map((color) => (
        <span
          key={color}
          data-testid="alarm-shimmer"
          className="inline-block w-5 h-4 rounded bg-slate-700 animate-pulse"
        />
      ))}
    </div>
  );
}

export function IncidentRow({ incident }: { incident: Incident }) {
  // Cold-cache fallback: fetch detail per-row only when the middleware did not
  // supply alarmCounts. Once loaded, results are cached for 60s (staleTime on
  // useIncidentDetail). In production the middleware cache is warm on most
  // refreshes, so this fan-out is rare.
  const needsCounts = incident.alarmCounts === null;
  const { data: detail, isLoading: isDetailLoading, isFetching: isDetailFetching } = useIncidentDetail(
    incident.incidentId,
    { enabled: needsCounts },
  );

  const alarmCounts = incident.alarmCounts ?? detail?.alarmCounts ?? null;
  const isLoadingCounts = needsCounts && (isDetailLoading || isDetailFetching);

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
        {isLoadingCounts ? (
          <ShimmerBadges />
        ) : (
          <AlarmBadges counts={alarmCounts ?? EMPTY_COUNTS} />
        )}
      </div>
    </Link>
  );
}
