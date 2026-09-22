import { PILLS, type Pill, type PillCounts } from './pills';

/** Fill and accent per pill.
 *
 * **`fill`** is the background of a SELECTED pill; an unselected one is
 * transparent. **`accent`** is the border, the glow and the text of an
 * unselected pill — `fill` for four of the five, because a hollow OPEN is the
 * filled OPEN's vocabulary with the middle taken out.
 *
 * **TOTAL is the exception and has to be.** Its fill `#1B0F33` is the app
 * icon's own near-black purple (measured 2026-09-22: quantise
 * `ios/BeNeM/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` to eight
 * colours and the largest cluster is `#1B0F33`, 799,841 of 1,048,576 pixels,
 * 76.3%) — and a near-black border and glow on a slate-950 page is nothing at
 * all, so its accent is `#7C3AED`. **iOS holds the identical two strings**
 * (`IncidentPill.totalHex`, `IncidentPill.totalGlowHex`) and both suites assert
 * them, so the platforms cannot drift on either.
 *
 * The four other fills are the exact hexes the Tailwind classes they replace
 * produced — red-600, blue-600, emerald-600, slate-500 — so this is the same
 * palette written somewhere the glow can also read it.
 */
const PALETTE: Record<Pill, { fill: string; accent: string }> = {
  TOTAL: { fill: '#1B0F33', accent: '#7C3AED' },
  OPEN: { fill: '#DC2626', accent: '#DC2626' },
  ACKD: { fill: '#2563EB', accent: '#2563EB' },
  CLRD: { fill: '#059669', accent: '#059669' },
  CLSD: { fill: '#64748B', accent: '#64748B' },
};

/** The glow, exactly as the mockup specifies it: 4 px at 55% unselected, 14 px
 * at 85% selected. Radius and opacity travel together because they are one
 * decision — a wide glow at low opacity and a tight one at high opacity are
 * different mockups. iOS holds the same four numbers in `IncidentPill.glow`.
 *
 * **`box-shadow`, never `filter: drop-shadow`.** A filter promotes the element
 * to its own compositing layer and blurs everything inside it, text included;
 * a box-shadow is painted from the border box outwards and leaves the digits
 * sharp.
 */
const GLOW = {
  unselected: { radius: 4, opacity: 0.55 },
  selected: { radius: 14, opacity: 0.85 },
} as const;

/** `#RRGGBB` + an alpha byte. Eight-digit hex is the shortest way to put an
 * opacity on a colour inside a `box-shadow` without a second colour space. */
function withAlpha(hex: string, opacity: number): string {
  return hex + Math.round(opacity * 255).toString(16).padStart(2, '0').toUpperCase();
}

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
 *
 * **Colours are inline styles, not Tailwind classes.** Tailwind's JIT only
 * emits an arbitrary value it can see as a literal string in the source, so a
 * per-pill `bg-[${hex}]` would have compiled to no class at all and the pill
 * would have rendered transparent — with no error anywhere. Inline styles have
 * no build step to fall through, and they let the fill, the border and the glow
 * read one palette entry instead of three hand-synchronised class strings.
 *
 * **`motion-reduce:transition-none`** turns off the 150 ms colour transition
 * for a reader who has asked for less movement. That is the only thing here
 * that moves — the glow itself is static, and nothing animates in or out.
 */
export function IncidentPills({ selected, counts, onSelect }: Props) {
  return (
    <div role="tablist" aria-label="Filter incidents" className="flex gap-1.5">
      {PILLS.map((pill) => {
        const isSelected = pill === selected;
        const { fill, accent } = PALETTE[pill];
        const { radius, opacity } = isSelected ? GLOW.selected : GLOW.unselected;
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
            className="flex flex-1 min-w-0 flex-col items-center gap-0.5 rounded-lg px-1 py-1 transition-colors motion-reduce:transition-none"
            style={{
              backgroundColor: isSelected ? fill : 'transparent',
              borderWidth: '1.5px',
              borderStyle: 'solid',
              borderColor: accent,
              color: isSelected ? '#FFFFFF' : accent,
              boxShadow: `0 0 ${radius}px ${withAlpha(accent, opacity)}`,
            }}
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
