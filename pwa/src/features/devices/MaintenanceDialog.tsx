import { useState } from 'react';

interface MaintenanceDialogProps {
  deviceName: string;
  username: string;
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (durationMinutes: number, comment: string) => Promise<void>;
}

const DURATION_OPTIONS = [
  { label: '1h', minutes: 60 },
  { label: '6h', minutes: 360 },
  { label: '12h', minutes: 720 },
  { label: '24h', minutes: 1440 },
  { label: '7d', minutes: 10080 },
] as const;

function buildPrefix(username: string): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
  return `Created by ${username || 'unknown'} on ${stamp}: `;
}

export function MaintenanceDialog({ deviceName, username, isOpen, onClose, onSubmit }: MaintenanceDialogProps) {
  const [selectedMinutes, setSelectedMinutes] = useState(60);
  const [isCustom, setIsCustom] = useState(false);
  const [customMinutes, setCustomMinutes] = useState('60');
  const [userComment, setUserComment] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const prefix = isOpen ? buildPrefix(username) : '';

  if (!isOpen) return null;

  const durationMinutes = isCustom ? (parseInt(customMinutes, 10) || 0) : selectedMinutes;
  const isValid = durationMinutes >= 1;

  async function handleSubmit() {
    if (!isValid || isSubmitting) return;
    setIsSubmitting(true);
    setError(null);
    try {
      await onSubmit(durationMinutes, prefix + userComment);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create maintenance window.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onClose}>
      <div
        className="bg-slate-900 rounded-lg p-6 w-full max-w-md mx-4 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div>
          <h2 className="text-lg font-semibold text-white">Create Maintenance Window</h2>
          <p className="text-sm text-slate-400 mt-1">{deviceName}</p>
        </div>

        <div>
          <label className="text-xs text-slate-500 uppercase tracking-wide font-semibold">Duration</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {DURATION_OPTIONS.map((opt) => (
              <button
                key={opt.label}
                className={`px-3 py-1.5 rounded text-sm font-semibold transition-colors ${
                  !isCustom && selectedMinutes === opt.minutes
                    ? 'bg-sky-600 text-white'
                    : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
                }`}
                onClick={() => { setSelectedMinutes(opt.minutes); setIsCustom(false); }}
              >
                {opt.label}
              </button>
            ))}
            <button
              className={`px-3 py-1.5 rounded text-sm font-semibold transition-colors ${
                isCustom
                  ? 'bg-sky-600 text-white'
                  : 'bg-slate-800 text-slate-300 hover:bg-slate-700'
              }`}
              onClick={() => setIsCustom(true)}
            >
              Custom
            </button>
          </div>
          {isCustom && (
            <div className="mt-2 flex items-center gap-2">
              <input
                type="number"
                min="1"
                value={customMinutes}
                onChange={(e) => setCustomMinutes(e.target.value)}
                className="bg-slate-800 border border-slate-700 text-slate-200 rounded px-3 py-2 w-24 text-sm"
              />
              <span className="text-sm text-slate-400">minutes</span>
            </div>
          )}
        </div>

        <div>
          <label className="text-xs text-slate-500 uppercase tracking-wide font-semibold">Description</label>
          <div className="mt-2 w-full bg-slate-800 border border-slate-700 rounded px-3 py-2 text-sm flex flex-wrap items-baseline gap-x-0">
            <span className="text-slate-500 select-none whitespace-pre shrink-0">{prefix}</span>
            <input
              type="text"
              value={userComment}
              onChange={(e) => setUserComment(e.target.value)}
              placeholder="optional note…"
              className="flex-1 min-w-0 bg-transparent text-slate-200 outline-none placeholder:text-slate-600"
            />
          </div>
        </div>

        {error && (
          <p className="text-sm text-red-400">{error}</p>
        )}

        <div className="flex gap-3 justify-end pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 rounded text-sm text-slate-400 border border-slate-700 hover:bg-slate-800"
            disabled={isSubmitting}
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={!isValid || isSubmitting}
            className="px-4 py-2 rounded text-sm font-semibold bg-sky-600 text-white hover:bg-sky-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isSubmitting ? 'Creating...' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  );
}
