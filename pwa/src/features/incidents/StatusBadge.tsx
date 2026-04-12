import type { IncidentStatus } from '../../lib/api/types';

interface Props {
  status: IncidentStatus;
  incidentState: string;
}

function resolve(status: IncidentStatus, incidentState: string) {
  if (
    status === 'resolved' ||
    status === 'closed' ||
    incidentState === 'ALARMS CLEARED'
  ) {
    return { label: 'CLRD', className: 'bg-emerald-600 text-white' } as const;
  }
  if (status === 'acknowledged') {
    return { label: 'ACKD', className: 'bg-blue-600 text-white' } as const;
  }
  return { label: 'OPEN', className: 'bg-red-600 text-white' } as const;
}

export function StatusBadge({ status, incidentState }: Props) {
  const { label, className } = resolve(status, incidentState);
  return (
    <span
      className={`inline-block shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold tracking-wide ${className}`}
    >
      {label}
    </span>
  );
}
