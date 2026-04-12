import { useState, useEffect } from 'react';

export type ConnectionStatus = 'unknown' | 'checking' | 'connected' | 'disconnected';

const STATUS_COLORS: Record<ConnectionStatus, string> = {
  unknown: '#6b7280',
  checking: '#f97316',
  connected: '#22863a',
  disconnected: '#ef4444',
};

interface Props {
  status: ConnectionStatus;
  onRetry: () => void;
}

export function ConnectionBadge({ status, onRetry }: Props) {
  const [blinkOn, setBlinkOn] = useState(true);
  const shouldBlink = status === 'checking' || status === 'disconnected';
  const broken = status === 'disconnected';
  const color = STATUS_COLORS[status];

  useEffect(() => {
    if (!shouldBlink) {
      setBlinkOn(true);
      return;
    }
    const timer = setInterval(() => setBlinkOn((v) => !v), 700);
    return () => clearInterval(timer);
  }, [shouldBlink]);

  const opacity = shouldBlink ? (blinkOn ? 1 : 0.15) : 1;

  return (
    <button
      type="button"
      onClick={onRetry}
      className="p-1"
      aria-label="Connection status — tap to retry"
      data-status={status}
    >
      <svg
        width="26"
        height="22"
        viewBox="0 0 26 22"
        fill="none"
        style={{ opacity, transition: 'opacity 0.3s' }}
      >
        <rect
          x={broken ? 0 : 3}
          y="2"
          width="8"
          height="13"
          rx="3"
          stroke={color}
          strokeWidth="2.5"
          fill="none"
          transform={`rotate(45, ${broken ? 4 : 7}, 8.5)`}
        />
        <rect
          x={broken ? 18 : 15}
          y="2"
          width="8"
          height="13"
          rx="3"
          stroke={color}
          strokeWidth="2.5"
          fill="none"
          transform={`rotate(45, ${broken ? 22 : 19}, 8.5)`}
        />
      </svg>
    </button>
  );
}
