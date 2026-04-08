import { useState, useEffect, useRef } from 'react';
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

  const [displayIndex, setDisplayIndex] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval>>();

  useEffect(() => {
    setDisplayIndex(0);
  }, [urgent.length]);

  useEffect(() => {
    if (urgent.length <= 1) return;
    timerRef.current = setInterval(() => {
      setDisplayIndex((prev) => (prev + 1) % urgent.length);
    }, 4_000);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [urgent.length]);

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-3 text-sm text-slate-500 border border-slate-700/50">
        No critical or major incidents
      </div>
    );
  }

  const incident = urgent[displayIndex] ?? urgent[0];

  return (
    <Link
      to={`/incidents/${incident.incidentId}`}
      className="block bg-slate-800 rounded-xl border border-slate-700/50 overflow-hidden relative"
      style={{ minHeight: '76px' }}
    >
      {/* Key forces React to remount this div on index change, triggering the CSS animation */}
      <div
        key={displayIndex}
        className="p-3 px-3.5 animate-[slideInFromRight_0.5s_ease-out]"
      >
        <div className="flex items-center gap-1.5 mb-1.5">
          <SeverityBadge severity={incident.severity} />
          <span className="text-[11px] text-slate-500">
            {buildDisplayId(incident.incidentId)}
          </span>
        </div>
        <div className="text-[13px] text-slate-100 mb-1 truncate">
          {incident.summary}
        </div>
        <div className="text-xs text-slate-400">
          {incident.deviceName ?? 'Unknown'}
        </div>
      </div>

      {/* Page dots */}
      {urgent.length > 1 && (
        <div className="absolute bottom-3 right-3.5 flex gap-1">
          {urgent.map((_, i) => (
            <span
              key={i}
              className={`w-1.5 h-1.5 rounded-full ${
                i === displayIndex ? 'bg-sky-400' : 'bg-slate-600'
              }`}
            />
          ))}
        </div>
      )}
    </Link>
  );
}
