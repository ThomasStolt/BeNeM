import { useState, useEffect } from 'react';

interface Props {
  lastUpdatedAt: number;
  intervalMs: number;
  isLoading: boolean;
  onRefresh: () => void;
}

export function RefreshRing({ lastUpdatedAt, intervalMs, isLoading, onRefresh }: Props) {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    setNow(Date.now());
  }, [lastUpdatedAt]);

  const elapsed = now - lastUpdatedAt;
  const progress = Math.min(1, elapsed / intervalMs);
  const remaining = Math.max(0, intervalMs - elapsed);
  const countdownText = `${Math.floor(remaining / 60_000)}:${String(
    Math.floor((remaining % 60_000) / 1_000),
  ).padStart(2, '0')}`;

  const size = 40;
  const strokeWidth = 2;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const dashOffset = circumference * (1 - progress);

  return (
    <button
      type="button"
      onClick={onRefresh}
      className="relative flex items-center justify-center"
      style={{ width: size, height: size }}
      aria-label="Refresh — tap to reload"
    >
      {isLoading ? (
        <svg width={size} height={size} className="animate-spin">
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#334155" strokeWidth={strokeWidth} fill="none"
          />
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#38bdf8" strokeWidth={strokeWidth} fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={circumference * 0.75}
            strokeLinecap="round"
          />
        </svg>
      ) : (
        <svg width={size} height={size}>
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#334155" strokeWidth={strokeWidth} fill="none"
          />
          <circle
            cx={size / 2} cy={size / 2} r={radius}
            stroke="#38bdf8" strokeWidth={strokeWidth} fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={dashOffset}
            strokeLinecap="round"
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
            style={{ transition: 'stroke-dashoffset 1s linear' }}
          />
          <text
            x={size / 2}
            y={size / 2}
            textAnchor="middle"
            dominantBaseline="central"
            fontSize="9"
            fontWeight="700"
            fill="#64748b"
            style={{ fontFamily: 'inherit', letterSpacing: '-0.03em' }}
          >
            {countdownText}
          </text>
        </svg>
      )}
    </button>
  );
}
