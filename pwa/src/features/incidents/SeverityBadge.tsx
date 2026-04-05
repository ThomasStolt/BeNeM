import type { Severity } from '../../lib/api/types';

const LABELS: Record<Severity, string> = {
  critical: 'CRIT',
  major: 'MAJ',
  minor: 'MIN',
  warning: 'WARN',
  informational: 'INFO',
};

const CLASSES: Record<Severity, string> = {
  critical: 'bg-severity-critical text-white',
  major: 'bg-severity-major text-white',
  minor: 'bg-severity-minor text-slate-900',
  warning: 'bg-severity-warning text-slate-900',
  informational: 'bg-severity-informational text-white',
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  return (
    <span
      className={`inline-block rounded px-2 py-0.5 text-xs font-semibold tracking-wide ${CLASSES[severity]}`}
      aria-label={`Severity: ${severity}`}
    >
      {LABELS[severity]}
    </span>
  );
}
