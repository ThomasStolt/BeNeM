import { PILLS, type Pill, type PillCounts } from './pills';

/** The selected pill takes its own state colour; the rest stay outlined.
 * Same vocabulary as the row badges and as BHNM itself — red open, blue
 * acknowledged, green cleared, grey closed — so the filter row and the rows
 * beneath it are not two colour languages for one set of facts. */
const SELECTED: Record<Pill, string> = {
  // **The app icon's own purple, MEASURED rather than chosen.** Read 2026-09-22
  // from ios/BeNeM/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png by
  // quantising the 1024x1024 icon to eight colours: the largest cluster is
  // #1B0F33, 799,841 of 1,048,576 pixels (76.3%) — the icon's background field.
  // The same string is asserted on iOS (IncidentPill.totalHex) and here, so a
  // change on one platform fails on that platform rather than drifting silently.
  // Not grey (a grey selected pill reads as
  // disabled, and TOTAL is the default tab) and no longer the 0.19.x gold.
  // White text: #1B0F33 sits at 18.1:1 against white, so the gold era's
  // dark-text exception is gone rather than inverted.
  //
  // Written as an arbitrary-value class with the hex INLINE and not via a
  // Tailwind theme token, because Tailwind's JIT only emits what it can see as
  // a literal string in the source — a template literal here would compile to
  // no class at all and the pill would render transparent.
  TOTAL: 'bg-[#1B0F33] text-white border-[#1B0F33]',
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

/** The filter row: five pills, **count on top, label beneath**.
 *
 * The count moved above the label on 2026-09-22 because side by side stopped
 * fitting. `TOTAL` is a letter longer than the four-letter labels beside it,
 * and at 390 px — five pills sharing the width, so ~72 px each, minus padding
 * and the label's own ~45 px — a single-line `TOTAL 99999` had room for about
 * one digit. Stacking gives the number the full pill width instead of the
 * remainder.
 *
 * `tabular-nums` on the count so the five columns do not jitter as the numbers
 * change; `leading-none` so two lines cost barely more height than one did.
 */
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
            aria-label={`${pill}, ${counts[pill]}`}
            data-pill={pill}
            data-selected={isSelected ? 'true' : 'false'}
            onClick={() => onSelect(pill)}
            className={`flex flex-1 min-w-0 flex-col items-center gap-0.5 rounded-lg border px-1 py-1 transition-colors ${
              isSelected ? SELECTED[pill] : UNSELECTED
            }`}
          >
            <span className="tabular-nums text-base font-bold leading-none">{counts[pill]}</span>
            <span className="text-[9px] font-semibold uppercase tracking-wider leading-none">
              {pill}
            </span>
          </button>
        );
      })}
    </div>
  );
}
