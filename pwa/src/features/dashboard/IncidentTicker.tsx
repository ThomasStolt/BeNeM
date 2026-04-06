import { Link } from 'react-router-dom';
import { SeverityBadge } from '../incidents/SeverityBadge';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

export function IncidentTicker({ incidents }: Props) {
  // Only show critical and major incidents
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-900 rounded-lg p-3 text-sm text-slate-500">
        No critical or major incidents
      </div>
    );
  }

  // Duplicate for seamless loop
  const items = [...urgent, ...urgent];

  return (
    <div className="bg-slate-900 rounded-lg overflow-hidden">
      <div className="overflow-hidden relative h-10">
        <div
          className="flex gap-6 items-center absolute h-full whitespace-nowrap animate-ticker"
          style={{ animationDuration: `${Math.max(10, urgent.length * 5)}s` }}
        >
          {items.map((incident, i) => (
            <Link
              key={`${incident.incidentId}-${i}`}
              to={`/incidents/${incident.incidentId}`}
              className="flex items-center gap-2 shrink-0 hover:opacity-80"
            >
              <SeverityBadge severity={incident.severity} />
              <span className="text-sm text-slate-300 max-w-[200px] truncate">
                {incident.deviceName ?? 'Unknown'}: {incident.summary}
              </span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
