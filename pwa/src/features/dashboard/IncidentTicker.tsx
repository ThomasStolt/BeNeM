import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { SeverityBadge } from '../incidents/SeverityBadge';
import { buildDisplayId } from '../../lib/api/incidents';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  const [currentIndex, setCurrentIndex] = useState(0);

  useEffect(() => {
    if (urgent.length <= 1) return;
    const timer = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % urgent.length);
    }, 4_000);
    return () => clearInterval(timer);
  }, [urgent.length]);

  useEffect(() => {
    setCurrentIndex(0);
  }, [urgent.length]);

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-3 text-sm text-slate-500 border border-slate-700/50">
        No critical or major incidents
      </div>
    );
  }

  const incident = urgent[currentIndex] ?? urgent[0];

  return (
    <Link
      to={`/incidents/${incident.incidentId}`}
      className="block bg-slate-800 rounded-xl p-3 px-3.5 border border-slate-700/50 hover:bg-slate-750 transition-colors"
    >
      {/* Line 1: severity + ID + page dots */}
      <div className="flex items-center justify-between mb-1.5">
        <div className="flex items-center gap-1.5">
          <SeverityBadge severity={incident.severity} />
          <span className="text-[11px] text-slate-500">
            {buildDisplayId(incident.incidentId)}
          </span>
        </div>
        {urgent.length > 1 && (
          <div className="flex gap-1">
            {urgent.map((_, i) => (
              <span
                key={i}
                className={`w-1.5 h-1.5 rounded-full ${
                  i === currentIndex ? 'bg-sky-400' : 'bg-slate-600'
                }`}
              />
            ))}
          </div>
        )}
      </div>

      {/* Line 2: summary */}
      <div className="text-[13px] text-slate-100 mb-1 truncate">
        {incident.summary}
      </div>

      {/* Line 3: device name */}
      <div className="text-xs text-slate-400">
        {incident.deviceName ?? 'Unknown'}
      </div>
    </Link>
  );
}
