import { useState, useEffect } from 'react';

interface Props {
  lastUpdatedAt: number; // timestamp ms
  intervalMs: number;    // e.g. 120_000
}

export function RefreshCountdown({ lastUpdatedAt, intervalMs }: Props) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(timer);
  }, []);

  // Reset "now" baseline when data refreshes
  useEffect(() => {
    setNow(Date.now());
  }, [lastUpdatedAt]);

  const elapsed = now - lastUpdatedAt;
  const remaining = Math.max(0, Math.ceil((intervalMs - elapsed) / 1_000));
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  const display = `${minutes}:${String(seconds).padStart(2, '0')}`;

  const fraction = Math.min(1, elapsed / intervalMs);

  return (
    <div className="flex items-center gap-1.5 text-xs text-slate-500" title="Time until next refresh">
      <div className="w-16 h-1.5 bg-slate-800 rounded-full overflow-hidden">
        <div
          className="h-full bg-sky-600 rounded-full transition-all duration-1000"
          style={{ width: `${(1 - fraction) * 100}%` }}
        />
      </div>
      <span className="tabular-nums w-8">{display}</span>
    </div>
  );
}
