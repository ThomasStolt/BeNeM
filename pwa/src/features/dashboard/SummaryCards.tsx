import { Link } from 'react-router-dom';

interface Props {
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
      className="flex-1 px-4 py-3 rounded-[14px] bg-slate-950 text-center"
      style={{
        border: `1.5px solid ${borderColor}`,
        boxShadow: `0 3px 6px ${shadowColor}`,
      }}
    >
      <div className="flex items-center justify-center gap-2">
        <span className="text-xl">{icon}</span>
        <span className="text-2xl font-bold" style={{ color }}>{count}</span>
      </div>
      <div className="text-xs text-slate-400 mt-1">{label}</div>
    </div>
  );

  if (to) {
    return <Link to={to} className="flex-1">{content}</Link>;
  }
  return content;
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
        to="/incidents"
      />
      <Card
        icon="🖥"
        count={totalDevices}
        label="Total Devices"
        color="#60a5fa"
        borderColor="rgba(59,130,246,0.25)"
        shadowColor="rgba(59,130,246,0.12)"
      />
    </div>
  );
}
