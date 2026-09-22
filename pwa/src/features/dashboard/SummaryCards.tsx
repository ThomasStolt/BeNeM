import { Link } from 'react-router-dom';

interface Props {
  /** The TOTAL pill count — everything NOT CLOSED.
   *
   * Ruled 2026-09-21 (Thomas), superseding the note's Q5 "the tile is the OPEN
   * count". **TOTAL is BHNM's own Active List View**, so "Active Incidents" is
   * the right label for it — and, decisively, the number does not drop the
   * moment somebody acknowledges. With disjoint pills an OPEN count would have
   * done exactly that, which is the 2026-09-19 defect by another route.
   */
  activeIncidents: number;
  totalDevices: number;
}

function Card({
  icon,
  count,
  label,
  color,
  borderColor,
  shadowColor,
  to,
}: {
  icon: string;
  count: number;
  label: string;
  color: string;
  borderColor: string;
  shadowColor: string;
  to?: string;
}) {
  const content = (
    <div
      className="h-full px-4 py-3 rounded-[14px] bg-slate-950 text-center"
      style={{
        border: `1.5px solid ${borderColor}`,
        boxShadow: `0 3px 6px ${shadowColor}`,
      }}
    >
      <div className="flex items-center justify-center gap-2">
        <span className="text-xl">{icon}</span>
        <span className="text-2xl font-bold" style={{ color }}>{count}</span>
      </div>
      <div className="text-xs text-slate-400 mt-1 flex items-center justify-center gap-1">
        {label}
        {/* The affordance: a card that navigates has to look like it does. */}
        {to && <span aria-hidden="true">›</span>}
      </div>
    </div>
  );

  if (to) {
    // Link, not an onClick div — the whole card is the target, it keeps
    // middle-click and open-in-new-tab, and it is reachable by keyboard.
    return (
      <Link
        to={to}
        aria-label={`${label}, ${count}`}
        className="flex-1 block rounded-[14px] focus:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
      >
        {content}
      </Link>
    );
  }
  return <div className="flex-1">{content}</div>;
}

export function SummaryCards({ activeIncidents, totalDevices }: Props) {
  const incidentColor = activeIncidents > 0 ? '#f87171' : '#4ade80';
  const incidentBorder = activeIncidents > 0 ? 'rgba(239,68,68,0.25)' : 'rgba(74,222,128,0.25)';
  const incidentShadow = activeIncidents > 0 ? 'rgba(239,68,68,0.12)' : 'rgba(74,222,128,0.12)';

  return (
    <div className="flex gap-3">
      <Card
        icon="⚠"
        count={activeIncidents}
        label="Active Incidents"
        color={incidentColor}
        borderColor={incidentBorder}
        shadowColor={incidentShadow}
        // The tile's set is exactly one pill, so it says which one it lands on
        // rather than relying on the list's default happening to agree.
        to="/incidents?pill=TOTAL"
      />
      <Card
        icon="🖥"
        count={totalDevices}
        label="Total Devices"
        color="#60a5fa"
        borderColor="rgba(59,130,246,0.25)"
        shadowColor="rgba(59,130,246,0.12)"
        to="/devices"
      />
    </div>
  );
}
