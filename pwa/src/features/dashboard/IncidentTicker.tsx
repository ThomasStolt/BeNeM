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
      {/* Line 1: severity + ID */}
      <div className="flex items-center gap-1.5 mb-1.5">
        <SeverityBadge severity={incident.severity} />
        <span className="text-[11px] text-slate-500">
          {buildDisplayId(incident.incidentId)}
        </span>
      </div>
      {/* Line 2: summary */}
      <div className="text-[13px] text-slate-100 mb-1 truncate">
        {incident.summary}
      </div>
      {/* Line 3: device name */}
      <div className="text-xs text-slate-400">
        {incident.deviceName ?? 'Unknown'}
      </div>
    </>
  );
}

export function IncidentTicker({ incidents }: Props) {
  const urgent = incidents.filter(
    (i) => i.severity === 'critical' || i.severity === 'major',
  );

  const [currentIndex, setCurrentIndex] = useState(0);
  const [sliding, setSliding] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    setCurrentIndex(0);
    setSliding(false);
  }, [urgent.length]);

  useEffect(() => {
    if (urgent.length <= 1) return;
    const timer = setInterval(() => {
      setSliding(true);
      // After the slide-out animation completes, swap the index and reset
      timeoutRef.current = setTimeout(() => {
        setCurrentIndex((prev) => (prev + 1) % urgent.length);
        setSliding(false);
      }, 500); // matches CSS transition duration
    }, 4_000);
    return () => {
      clearInterval(timer);
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, [urgent.length]);

  if (urgent.length === 0) {
    return (
      <div className="bg-slate-800 rounded-xl p-3 text-sm text-slate-500 border border-slate-700/50">
        No critical or major incidents
      </div>
    );
  }

  const incident = urgent[currentIndex] ?? urgent[0];
  const nextIndex = (currentIndex + 1) % urgent.length;
  const nextIncident = urgent[nextIndex] ?? urgent[0];

  return (
    <Link
      to={`/incidents/${incident.incidentId}`}
      className="block bg-slate-800 rounded-xl p-3 px-3.5 border border-slate-700/50 overflow-hidden relative"
      style={{ minHeight: '76px' }}
    >
      {/* Current card — slides out to the left */}
      <div
        className="transition-all duration-500 ease-in-out"
        style={{
          transform: sliding ? 'translateX(-110%)' : 'translateX(0)',
          opacity: sliding ? 0 : 1,
        }}
      >
        <TickerCard incident={incident} />
      </div>

      {/* Next card — slides in from the right */}
      {urgent.length > 1 && (
        <div
          className="absolute inset-0 p-3 px-3.5 transition-all duration-500 ease-in-out"
          style={{
            transform: sliding ? 'translateX(0)' : 'translateX(110%)',
            opacity: sliding ? 1 : 0,
          }}
        >
          <TickerCard incident={nextIncident} />
        </div>
      )}

      {/* Page dots — always visible at bottom right */}
      {urgent.length > 1 && (
        <div className="absolute bottom-3 right-3.5 flex gap-1">
          {urgent.map((_, i) => (
            <span
              key={i}
              className={`w-1.5 h-1.5 rounded-full ${
                i === (sliding ? nextIndex : currentIndex) ? 'bg-sky-400' : 'bg-slate-600'
              }`}
            />
          ))}
        </div>
      )}
    </Link>
  );
}
