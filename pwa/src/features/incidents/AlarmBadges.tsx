import type { AlarmCounts } from '../../lib/api/types';

const COLORS: { key: keyof AlarmCounts; bg: string; text: string }[] = [
  { key: 'green', bg: 'bg-emerald-600', text: 'text-white' },
  { key: 'blue', bg: 'bg-blue-600', text: 'text-white' },
  { key: 'yellow', bg: 'bg-yellow-400', text: 'text-slate-900' },
  { key: 'orange', bg: 'bg-orange-500', text: 'text-white' },
  { key: 'red', bg: 'bg-red-600', text: 'text-white' },
];

export function AlarmBadges({ counts }: { counts: AlarmCounts }) {
  return (
    <div className="flex gap-1">
      {COLORS.map(({ key, bg, text }) => {
        const n = counts[key];
        return (
          <span
            key={key}
            className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-semibold leading-tight ${
              n === 0
                ? 'text-slate-600 border border-slate-700'
                : `${bg} ${text}`
            }`}
          >
            {n}
          </span>
        );
      })}
    </div>
  );
}
