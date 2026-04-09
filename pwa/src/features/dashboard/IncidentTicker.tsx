import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import { SeverityBadge } from '../incidents/SeverityBadge';
import { buildDisplayId } from '../../lib/api/incidents';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

function TickerCard({ incident }: { incident: Incident }) {
  return (
    <div className="p-3 px-3.5">
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
  );
}

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents
    .filter((i) => i.status === 'active' && i.incidentState.toUpperCase() !== 'ALARMS CLEARED'
      && (i.severity === 'critical' || i.severity === 'major'))
    .slice(0, 3);

  const [displayIndex, setDisplayIndex] = useState(0);
  const [outgoing, setOutgoing] = useState<Incident | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval>>();
  const cleanupRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    setDisplayIndex(0);
    setOutgoing(null);
  }, [urgent.length]);

  useEffect(() => {
    if (urgent.length <= 1) return;
    timerRef.current = setInterval(() => {
      // Capture the current incident as outgoing before advancing
      setOutgoing(urgent[displayIndex] ?? null);
      setDisplayIndex((prev) => (prev + 1) % urgent.length);
      // Clear outgoing after the exit animation finishes
      cleanupRef.current = setTimeout(() => setOutgoing(null), 500);
    }, 4_000);
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      if (cleanupRef.current) clearTimeout(cleanupRef.current);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [urgent.length, displayIndex]);

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
      {/* Outgoing card — slides out to the left */}
      {outgoing && (
        <div
          key={`out-${displayIndex}`}
          className="absolute inset-0 animate-[slideOutToLeft_0.5s_ease-in_forwards]"
        >
          <TickerCard incident={outgoing} />
        </div>
      )}

      {/* Incoming card — slides in from the right */}
      <div
        key={displayIndex}
        className="animate-[slideInFromRight_0.5s_ease-out]"
      >
        <TickerCard incident={incident} />
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
