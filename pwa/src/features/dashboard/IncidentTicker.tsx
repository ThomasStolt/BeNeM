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
    <>
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
    </>
  );
}

// Slide phases: 'idle' → 'sliding' → 'idle'
// idle: show current card at translateX(0)
// sliding: current slides to -110%, next slides from +110% to 0
// When sliding ends: currentIndex advances, phase resets to idle

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  const [displayIndex, setDisplayIndex] = useState(0);
  const [phase, setPhase] = useState<'idle' | 'sliding'>('idle');
  const timerRef = useRef<ReturnType<typeof setInterval>>();
  const transitionRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    setDisplayIndex(0);
    setPhase('idle');
  }, [urgent.length]);

  useEffect(() => {
    if (urgent.length <= 1) return;

    timerRef.current = setInterval(() => {
      setPhase('sliding');
      transitionRef.current = setTimeout(() => {
        setDisplayIndex((prev) => (prev + 1) % urgent.length);
        setPhase('idle');
      }, 500);
    }, 4_000);

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      if (transitionRef.current) clearTimeout(transitionRef.current);
    };
  }, [urgent.length]);

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-3 text-sm text-slate-500 border border-slate-700/50">
        No critical or major incidents
      </div>
    );
  }

  const current = urgent[displayIndex] ?? urgent[0];
  const nextIndex = (displayIndex + 1) % urgent.length;
  const next = urgent[nextIndex] ?? urgent[0];
  const dotIndex = phase === 'sliding' ? nextIndex : displayIndex;

  return (
    <Link
      to={`/incidents/${current.incidentId}`}
      className="block bg-slate-800 rounded-xl border border-slate-700/50 overflow-hidden relative"
      style={{ minHeight: '76px' }}
    >
      {/* Slot A: shows displayIndex, always rendered at translateX(0) when idle */}
      <div
        className="p-3 px-3.5"
        style={{
          transform: phase === 'sliding' ? 'translateX(-110%)' : 'translateX(0)',
          opacity: phase === 'sliding' ? 0 : 1,
          transition: phase === 'sliding' ? 'transform 500ms ease-in-out, opacity 500ms ease-in-out' : 'none',
        }}
      >
        <TickerCard incident={current} />
      </div>

      {/* Slot B: shows next incident, slides in from right during 'sliding' phase */}
      {urgent.length > 1 && (
        <div
          className="absolute inset-0 p-3 px-3.5"
          style={{
            transform: phase === 'sliding' ? 'translateX(0)' : 'translateX(110%)',
            opacity: phase === 'sliding' ? 1 : 0,
            transition: phase === 'sliding' ? 'transform 500ms ease-in-out, opacity 500ms ease-in-out' : 'none',
          }}
        >
          <TickerCard incident={next} />
        </div>
      )}

      {/* Page dots */}
      {urgent.length > 1 && (
        <div className="absolute bottom-3 right-3.5 flex gap-1">
          {urgent.map((_, i) => (
            <span
              key={i}
              className={`w-1.5 h-1.5 rounded-full ${
                i === dotIndex ? 'bg-sky-400' : 'bg-slate-600'
              }`}
            />
          ))}
        </div>
      )}
    </Link>
  );
}
