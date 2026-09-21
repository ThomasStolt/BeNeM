import { PILLS, type Pill, type PillCounts } from './pills';

/** The selected pill takes its own state colour; the rest stay outlined.
 * Same vocabulary as the row badges and as BHNM itself — red open, blue
 * acknowledged, green cleared, grey closed — so the filter row and the rows
 * beneath it are not two colour languages for one set of facts. */
const SELECTED: Record<Pill, string> = {
  // Gold. Not grey — a grey selected pill reads as disabled, and TOTL is the
  // default tab. The exact hex is shared with iOS (IncidentPill.color), and is
  // deliberately darker than the alarm chips' yellow-400 and less red than
  // their orange-500, so the filter row cannot be mistaken for a severity.
  // Dark text on it for the same reason the yellow alarm chip uses text-slate-900.
  TOTL: 'bg-[#c9a227] text-slate-900 border-[#c9a227]',
  OPEN: 'bg-red-600 text-white border-red-600',
  ACKD: 'bg-blue-600 text-white border-blue-600',
  CLRD: 'bg-emerald-600 text-white border-emerald-600',
  CLSD: 'bg-slate-500 text-white border-slate-500',
};

const UNSELECTED = 'bg-transparent text-slate-400 border-slate-700 hover:bg-slate-800';

interface Props {
  selected: Pill;
  counts: PillCounts;
  onSelect: (pill: Pill) => void;
}

export function IncidentPills({ selected, counts, onSelect }: Props) {
  return (
    <div role="tablist" aria-label="Filter incidents" className="flex gap-1.5">
      {PILLS.map((pill) => {
        const isSelected = pill === selected;
        return (
          <button
            key={pill}
            type="button"
            role="tab"
            aria-selected={isSelected}
            data-pill={pill}
            data-selected={isSelected ? 'true' : 'false'}
            onClick={() => onSelect(pill)}
            className={`flex-1 rounded-full border px-2 py-1 text-[11px] font-bold tracking-wide transition-colors ${
              isSelected ? SELECTED[pill] : UNSELECTED
            }`}
          >
            {pill}
            <span className="ml-1 tabular-nums font-semibold opacity-80">{counts[pill]}</span>
          </button>
        );
      })}
    </div>
  );
}
