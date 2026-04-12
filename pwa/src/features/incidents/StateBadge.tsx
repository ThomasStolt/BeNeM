const STATE_CLASSES: Record<string, string> = {
  CRITICAL:          'bg-red-700 text-red-200',
  DOWN:              'bg-red-700 text-red-200',
  OPEN:              'bg-red-700 text-red-200',
  MAJOR:             'bg-orange-700 text-orange-200',
  UNREACHABLE:       'bg-orange-700 text-orange-200',
  WARNING:           'bg-yellow-800 text-yellow-300',
  MINOR:             'bg-yellow-800 text-yellow-300',
  OK:                'bg-green-800 text-green-300',
  RESOLVED:          'bg-green-800 text-green-300',
  CLOSED:            'bg-green-800 text-green-300',
  UP:                'bg-green-800 text-green-300',
  NORMAL:            'bg-green-800 text-green-300',
  RECOVERY:          'bg-green-800 text-green-300',
  CLEARED:           'bg-green-800 text-green-300',
  'ALARMS CLEARED':  'bg-green-800 text-green-300',
  ACKNOWLEDGED:      'bg-blue-800 text-blue-200',
  ACK:               'bg-blue-800 text-blue-200',
};

export function StateBadge({ state }: { state: string }) {
  const cls = STATE_CLASSES[state.toUpperCase()] ?? 'bg-slate-700 text-slate-300';
  return (
    <span
      className={`inline-block rounded text-[9px] font-bold px-1.5 py-0.5 leading-tight uppercase ${cls}`}
    >
      {state.toUpperCase()}
    </span>
  );
}
