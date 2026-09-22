import { PILLS, type Pill, type PillCounts } from './pills';

/** **Two colours per pill**: a `base` for the selected fill, and a brighter
 * `tint` for the frame, the unselected text and the unselected glow.
 *
 * Round two of Thomas's mockup, 2026-09-22. Round one gave each pill a single
 * colour used for everything, which left an unselected pill outlined in the
 * same value its selected neighbour was filled with — the two states separated
 * only by fill, which is exactly what failed on TOTAL when `#1B0F33` went on a
 * near-black page. A brighter frame is the difference that survives whatever
 * the fill does.
 *
 * iOS holds the same ten strings in `IncidentPill.palette`, and both suites
 * assert all ten, so the platforms cannot drift on any of them.
 */
const PALETTE: Record<Pill, { base: string; tint: string }> = {
  TOTAL: { base: '#7C3AED', tint: '#A78BFA' },
  OPEN: { base: '#DC2626', tint: '#F87171' },
  ACKD: { base: '#2563EB', tint: '#60A5FA' },
  CLRD: { base: '#16A34A', tint: '#4ADE80' },
  CLOSED: { base: '#F2F2F7', tint: '#FFFFFF' },
};

/** The ground an UNSELECTED pill sits on. **Not transparent** — round one let
 * the page show through, so the row read as four outlines floating on nothing.
 * A near-black plate gives every pill the same footprint whether it is selected
 * or not, which is what stops the row jumping as the selection moves. */
const UNSELECTED_BG = '#1a1a1d';

/** CLOSED's selected text. The one pill whose fill is nearly white, so
 * white-on-white would be the whole label gone. Near-black rather than pure
 * black, to match the ground the row sits on. */
const CLOSED_ON = '#111114';

/** CLOSED is the only pill with no frame and no glow when unselected: white text
 * on the bare plate. It is the one tab you opt into, and a frame in `#FFFFFF`
 * would make it the brightest thing in a row you are not looking at. */
function isFramedWhenUnselected(pill: Pill): boolean {
  return pill !== 'CLOSED';
}

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

/** The glow's colour: **`base` when selected, `tint` when not.**
 *
 * The mockup's summary line says "a brighter tint for the frame, the unselected
 * text and both glows", and its per-state lines say "glow 14px in **base** at
 * 85%" selected and "glow 4px in tint at 55%" unselected. Those disagree about
 * exactly one value. The per-state lines are followed, being the more specific
 * of the two — a selected pill's halo is its own fill bleeding outwards, which
 * is what a filled chip does everywhere else in this app. iOS resolves it the
 * same way, in `IncidentPill.glowColor(selected:)`. */

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
        const { base, tint } = PALETTE[pill];
        const { radius, opacity } = isSelected ? GLOW.selected : GLOW.unselected;
        const framed = isSelected || isFramedWhenUnselected(pill);
        const glow = isSelected ? base : tint;
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
              backgroundColor: isSelected ? base : UNSELECTED_BG,
              borderWidth: '1.5px',
              borderStyle: 'solid',
              // `transparent`, not `none`: the border box has to keep its width
              // or the frameless CLOSED pill would be 3px narrower than the four
              // beside it and the row would not line up.
              borderColor: framed ? tint : 'transparent',
              color: isSelected
                ? (pill === 'CLOSED' ? CLOSED_ON : '#FFFFFF')
                : tint,
              boxShadow: framed ? `0 0 ${radius}px ${withAlpha(glow, opacity)}` : 'none',
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
