import type { TacticalGroup, StatusCounts } from '../../lib/api/tactical-overview';

function CountBadge({ value, color, bgColor }: { value: number; color: string; bgColor: string }) {
  if (value === 0) {
    return <span className="text-xs text-slate-600 tabular-nums w-8 text-center">0</span>;
  }
  return (
    <span className={`text-xs font-semibold tabular-nums px-1.5 py-0.5 rounded ${color} ${bgColor} min-w-[2rem] text-center`}>
      {value}
    </span>
  );
}

function AlarmRow({ label, counts }: { label: string; counts: StatusCounts }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-slate-500 w-20 shrink-0">{label}</span>
      <div className="flex items-center gap-1">
        <CountBadge value={counts.ok} color="text-emerald-400" bgColor="bg-emerald-500/20" />
        <CountBadge value={counts.ack} color="text-sky-400" bgColor="bg-sky-500/20" />
        <CountBadge value={counts.warn} color="text-yellow-400" bgColor="bg-yellow-500/20" />
        <CountBadge value={counts.un} color="text-orange-400" bgColor="bg-orange-500/20" />
        <CountBadge value={counts.crit} color="text-red-400" bgColor="bg-red-500/20" />
      </div>
    </div>
  );
}

export function TacticalGroupRow({ group }: { group: TacticalGroup }) {
  return (
    <div className="border-b border-slate-800 px-4 py-3">
      <div className="text-sm font-medium text-slate-200 mb-2">
        {group.name || 'Unknown'}
      </div>
      <div className="space-y-1">
        <AlarmRow label="Hosts" counts={group.hosts} />
        <AlarmRow label="Services" counts={group.services} />
        <AlarmRow label="Thresholds" counts={group.thresholds} />
        <AlarmRow label="Anomalies" counts={group.anomalies} />
      </div>
    </div>
  );
}

/** Returns true if all alarm counts across H/S/T/A are OK-only (no warn/un/crit). */
export function isGroupHealthy(group: TacticalGroup): boolean {
  const check = (c: StatusCounts) => c.warn === 0 && c.un === 0 && c.crit === 0;
  return check(group.hosts) && check(group.services) && check(group.thresholds) && check(group.anomalies);
}
