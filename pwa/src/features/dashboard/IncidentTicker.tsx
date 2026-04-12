import { useState, useEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import { AlarmBadges } from '../incidents/AlarmBadges';
import { buildDisplayId } from '../../lib/api/incidents';
import type { Incident } from '../../lib/api/types';

interface Props {
  incidents: Incident[];
}

function TickerCard({
  incident,
  dotCount = 0,
  activeDot = 0,
}: {
  incident: Incident;
  dotCount?: number;
  activeDot?: number;
}) {
  return (
    <div className="p-3 px-3.5">
      {/* Row 1: OPEN tag · incident number · title (truncates) · page dots */}
      <div className="flex items-center gap-1.5 min-w-0 mb-1.5">
        <span className="shrink-0 text-[10px] font-semibold px-1.5 py-0.5 rounded bg-red-600 text-white leading-tight">
          OPEN
        </span>
        <span className="shrink-0 text-[11px] text-slate-500 font-mono">
          {buildDisplayId(incident.incidentId)}
        </span>
        <span className="text-[13px] text-slate-100 truncate flex-1">
          {incident.summary}
        </span>
        {dotCount > 1 && (
          <div className="shrink-0 flex gap-1 ml-0.5">
            {Array.from({ length: dotCount }).map((_, i) => (
              <span
                key={i}
                className={`w-1.5 h-1.5 rounded-full ${
                  i === activeDot ? 'bg-sky-400' : 'bg-slate-600'
                }`}
              />
            ))}
          </div>
        )}
      </div>
      {/* Row 2: device name · alarm badges */}
      <div className="flex items-center gap-2 min-w-0">
        <span className="text-xs text-slate-400 truncate flex-1">
          {incident.deviceName ?? 'Unknown'}
        </span>
        {incident.alarmCounts && (
          <div className="shrink-0">
            <AlarmBadges counts={incident.alarmCounts} />
          </div>
        )}
      </div>
    </div>
  );
}

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents
    .filter((i) => i.status === 'active' && i.incidentState.toUpperCase() !== 'ALARMS CLEARED'
      && (i.severity === 'critical' || i.severity === 'major'))
    .sort((a, b) => Number(b.incidentId) - Number(a.incidentId))
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

      {/* Incoming card — slides in from the right; carries page dots */}
      <div
        key={displayIndex}
        className="animate-[slideInFromRight_0.5s_ease-out]"
      >
        <TickerCard
          incident={incident}
          dotCount={urgent.length}
          activeDot={displayIndex}
        />
      </div>
    </Link>
  );
}
