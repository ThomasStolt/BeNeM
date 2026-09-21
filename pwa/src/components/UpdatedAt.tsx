interface Props {
  updatedAt: number;
  isLoading: boolean;
  onRefresh: () => void;
}

function hhmm(ts: number): string {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/** `Updated HH:MM` plus a refresh control — what replaced the countdown ring.
 *
 * Removing the countdown is a truthfulness fix, not a cosmetic one. A countdown
 * is a promise that something happens at zero. Under webhook mode nothing does:
 * the next scheduled reconciliation is 24 hours away, so the ring was counting
 * down to nothing — a green affordance asserting a claim nobody had checked.
 * `Updated HH:MM` states a fact the app can date.
 */
export function UpdatedAt({ updatedAt, isLoading, onRefresh }: Props) {
  return (
    <button
      type="button"
      onClick={onRefresh}
      disabled={isLoading}
      className="flex items-center gap-1 text-[11px] text-slate-500 hover:text-slate-300 disabled:opacity-60"
      aria-label="Refresh"
    >
      <span className="tabular-nums">
        {isLoading ? 'Updating…' : `Updated ${hhmm(updatedAt)}`}
      </span>
      <span className={isLoading ? 'animate-spin' : ''} aria-hidden="true">↻</span>
    </button>
  );
}
