import type { StatusCounts } from '../../lib/api/tactical-overview';

interface Props {
  label: string;
  counts: StatusCounts;
}

interface BadgeProps {
  value: number;
  color: string;
  bgColor: string;
}

function Badge({ value, color, bgColor }: BadgeProps) {
  if (value === 0) {
    return <span className="text-xs text-slate-600 tabular-nums w-8 text-center">0</span>;
  }
  return (
    <span className={`text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded ${color} ${bgColor} min-w-[2rem] text-center`}>
      {value}
    </span>
  );
}

export function StatusCard({ label, counts }: Props) {
  const total = counts.ok + counts.ack + counts.warn + counts.un + counts.crit;

  return (
    <div className="bg-slate-900 rounded-lg p-3">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-medium text-slate-300">{label}</span>
        <span className="text-xs text-slate-500 tabular-nums">{total}</span>
      </div>
      <div className="flex items-center gap-1">
        <Badge value={counts.ok} color="text-emerald-400" bgColor="bg-emerald-500/20" />
        <Badge value={counts.ack} color="text-sky-400" bgColor="bg-sky-500/20" />
        <Badge value={counts.warn} color="text-yellow-400" bgColor="bg-yellow-500/20" />
        <Badge value={counts.un} color="text-orange-400" bgColor="bg-orange-500/20" />
        <Badge value={counts.crit} color="text-red-400" bgColor="bg-red-500/20" />
      </div>
    </div>
  );
}
