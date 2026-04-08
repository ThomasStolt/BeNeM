import type { StatusCounts } from '../../lib/api/tactical-overview';

interface Props {
  label: string;
  counts: StatusCounts;
}

const BADGE_COLORS = [
  { bg: '#22c55e', text: '#fff' },    // green (ok)
  { bg: '#3b82f6', text: '#fff' },    // blue (ack)
  { bg: '#eab308', text: '#000' },    // yellow (warn)
  { bg: '#f97316', text: '#fff' },    // orange (un)
  { bg: '#ef4444', text: '#fff' },    // red (crit)
];

export function StatusCard({ label, counts }: Props) {
  const values = [counts.ok, counts.ack, counts.warn, counts.un, counts.crit];
  const total = values.reduce((a, b) => a + b, 0);

  return (
    <div className="bg-slate-800 rounded-[13px] py-2 px-[10px] text-center border border-slate-700/50">
      <div className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">
        {label}
      </div>
      <div className="text-lg font-semibold my-0.5 tabular-nums">
        {total}
      </div>
      <div className="flex gap-[3px]">
        {values.map((n, i) => (
          <span
            key={i}
            className="flex-1 text-[9px] font-semibold py-[3px] rounded-lg text-center tabular-nums"
            style={
              n > 0
                ? { background: BADGE_COLORS[i].bg, color: BADGE_COLORS[i].text }
                : { color: '#4b5563', border: '0.5px solid #374151' }
            }
          >
            {n}
          </span>
        ))}
      </div>
    </div>
  );
}
