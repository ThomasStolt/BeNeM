import type { Incident } from '../../lib/api/types';

/** The row chip, using the same four labels and colours as the filter pills.
 *
 * Reads `state` and `acknowledged` — never `incident_state`. Before middleware
 * 2.20.0 this resolved CLOSED and ALARMS CLEARED to the SAME green CLRD chip,
 * because `status === 'closed'` and the literal 'ALARMS CLEARED' shared a
 * branch. They are different facts and now look different: a closed incident
 * is grey and finished, a cleared one is green and still in the list.
 */
type Props = Pick<Incident, 'state' | 'acknowledged'>;

function resolve({ state, acknowledged }: Props) {
  if (state === 'CLOSED') return { label: 'CLSD', className: 'bg-slate-500 text-white' } as const;
  if (state === 'ALARMS CLEARED') return { label: 'CLRD', className: 'bg-emerald-600 text-white' } as const;
  if (acknowledged) return { label: 'ACKD', className: 'bg-blue-600 text-white' } as const;
  return { label: 'OPEN', className: 'bg-red-600 text-white' } as const;
}

export function StatusBadge(props: Props) {
  const { label, className } = resolve(props);
  return (
    <span
      className={`inline-block shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold tracking-wide ${className}`}
    >
      {label}
    </span>
  );
}
