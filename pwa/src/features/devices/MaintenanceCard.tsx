import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import {
  activeComment,
  activeEnd,
  closeMaintenanceWindow,
  createMaintenanceWindow,
  type MaintenanceStatus,
} from '../../lib/api/maintenance';
import { MaintenanceDialog } from './MaintenanceDialog';
import { useMaintenanceStatus } from './useMaintenanceStatus';
import { noteLocalMaintenance, noteLocalClose, clearLocalMaintenance, getPendingStart, getRecentLocalClose } from './useMaintenanceMap';

/** How long local knowledge (pending start / local close) outlives its event —
 * covers BHNM's ~85 s poll lag with headroom, then defers to the server again. */
const PENDING_GRACE_MS = 3 * 60_000;

export type MaintenanceButtonState =
  | { kind: 'normal' }
  | { kind: 'starting'; startsAt: Date }
  | { kind: 'active'; endsAt: Date | null; comment: string | null };

/**
 * §3 D4b state precedence: inMaintenance wins; else a live local pending
 * start; else normal. A recent local close suppresses the (lagging) active
 * state for the grace period.
 */
export function maintenanceButtonState(
  status: MaintenanceStatus | null | undefined,
  pendingStart: Date | null,
  pendingClose: Date | null,
  now: Date,
): MaintenanceButtonState {
  const closeSuppressed =
    pendingClose !== null && now.getTime() - pendingClose.getTime() < PENDING_GRACE_MS;
  if (status?.inMaintenance && !closeSuppressed) {
    return { kind: 'active', endsAt: activeEnd(status), comment: activeComment(status) };
  }
  if (
    !status?.inMaintenance &&
    pendingStart !== null &&
    now.getTime() < pendingStart.getTime() + PENDING_GRACE_MS
  ) {
    return { kind: 'starting', startsAt: pendingStart };
  }
  return { kind: 'normal' };
}

function hhmm(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

interface ConfirmDialogProps {
  title: string;
  message: string;
  confirmLabel: string;
  dismissLabel: string;
  error: string | null;
  busy: boolean;
  onConfirm: () => void;
  onDismiss: () => void;
}

function ConfirmDialog({
  title, message, confirmLabel, dismissLabel, error, busy, onConfirm, onDismiss,
}: ConfirmDialogProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60" onClick={onDismiss}>
      <div
        className="bg-slate-900 border border-slate-700 rounded-lg p-6 w-full max-w-md mx-4 space-y-4"
        onClick={(e) => e.stopPropagation()}
      >
        <div>
          <h2 className="text-lg font-semibold text-white">{title}</h2>
          <p className="text-sm text-slate-400 mt-1">{message}</p>
        </div>
        {error && <p className="text-sm text-red-400">{error}</p>}
        <div className="flex gap-3 justify-end pt-2">
          <button
            onClick={onDismiss}
            className="px-4 py-2 rounded text-sm text-slate-400 border border-slate-700 hover:bg-slate-800"
            disabled={busy}
          >
            {dismissLabel}
          </button>
          <button
            onClick={onConfirm}
            disabled={busy}
            className="px-4 py-2 rounded text-sm font-semibold bg-red-600 text-white hover:bg-red-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {busy ? 'Ending...' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

interface MaintenanceCardProps {
  deviceName: string;
  username: string;
}

export function MaintenanceCard({ deviceName, username }: MaintenanceCardProps) {
  const config = useConfig();
  const queryClient = useQueryClient();
  const { data: status } = useMaintenanceStatus(deviceName);

  // Local knowledge lives in the shared store (survives navigation);
  // this state only forces re-renders when it changes.
  const [showCreate, setShowCreate] = useState(false);
  const [confirming, setConfirming] = useState<'active' | 'starting' | null>(null);
  const [closeError, setCloseError] = useState<string | null>(null);
  const [isClosing, setIsClosing] = useState(false);
  const [, setTick] = useState(0);

  const pendingStart = getPendingStart(deviceName);
  const pendingClose = getRecentLocalClose(deviceName);

  // Re-evaluate expiry while local knowledge is live.
  useEffect(() => {
    if (!pendingStart && !pendingClose) return;
    const t = setInterval(() => setTick((n) => n + 1), 15_000);
    return () => clearInterval(t);
  }, [pendingStart, pendingClose]);

  const state = maintenanceButtonState(status, pendingStart, pendingClose, new Date());

  async function handleClose() {
    setIsClosing(true);
    setCloseError(null);
    try {
      await closeMaintenanceWindow(config, deviceName);
      if (confirming === 'starting') clearLocalMaintenance(deviceName);
      else noteLocalClose(deviceName);
      setConfirming(null);
      setTick((n) => n + 1);
      queryClient.invalidateQueries({ queryKey: ['maintenance-status'] });
      queryClient.invalidateQueries({ queryKey: ['maintenance-map'] });
    } catch (err) {
      setCloseError(err instanceof Error ? err.message : 'Could not end maintenance.');
    } finally {
      setIsClosing(false);
    }
  }

  function openConfirm(target: 'active' | 'starting') {
    setCloseError(null);
    setConfirming(target);
  }

  return (
    <>
      {state.kind === 'normal' && (
        <button
          onClick={() => setShowCreate(true)}
          className="w-full bg-slate-800 rounded-xl py-3.5 text-sm font-medium text-sky-400 hover:bg-slate-700 transition-colors"
        >
          + Create Maintenance Window
        </button>
      )}

      {state.kind === 'starting' && (
        <button
          onClick={() => openConfirm('starting')}
          className="w-full rounded-xl py-3.5 text-sm font-medium text-sky-400 border border-sky-400/40 bg-sky-400/10 hover:bg-sky-400/20 transition-colors flex items-center justify-center gap-2"
        >
          <svg viewBox="0 0 24 24" className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="12" cy="12" r="9" />
            <polyline points="12 7 12 12 15.5 14" />
          </svg>
          Starts at {hhmm(state.startsAt)}
        </button>
      )}

      {state.kind === 'active' && (
        <div>
          <button
            onClick={() => openConfirm('active')}
            className="w-full rounded-xl py-3.5 text-sm font-medium bg-sky-600 text-white hover:bg-sky-500 transition-colors flex items-center justify-center gap-2"
          >
            <svg viewBox="0 0 24 24" className="w-3.5 h-3.5 shrink-0">
              <rect x="5" y="5" width="14" height="14" rx="2.5" fill="currentColor" />
            </svg>
            In Maintenance · ends {state.endsAt ? hhmm(state.endsAt) : '—'}
          </button>
          {state.comment && (
            <p className="text-xs text-slate-400 text-center mt-1.5">{state.comment}</p>
          )}
        </div>
      )}

      <MaintenanceDialog
        deviceName={deviceName}
        username={username}
        isOpen={showCreate}
        onClose={() => setShowCreate(false)}
        onSubmit={async (dur, comment) => {
          const start = await createMaintenanceWindow(config, deviceName, dur, comment);
          // Creator-side optimism in the shared store (survives navigation):
          // detail shows "Starts at HH:MM", list wrench blinks until the
          // server confirms.
          noteLocalMaintenance(deviceName, start ?? new Date());
          setTick((n) => n + 1);
          queryClient.invalidateQueries({ queryKey: ['maintenance-status'] });
          queryClient.invalidateQueries({ queryKey: ['maintenance-map'] });
        }}
      />

      {confirming === 'active' && (
        <ConfirmDialog
          title="End Maintenance"
          message={`End maintenance for ${deviceName} now? Alerting for this device will resume.`}
          confirmLabel="End Maintenance"
          dismissLabel="Cancel"
          error={closeError}
          busy={isClosing}
          onConfirm={handleClose}
          onDismiss={() => setConfirming(null)}
        />
      )}

      {confirming === 'starting' && (
        <ConfirmDialog
          title="Cancel Scheduled Maintenance"
          message={`Cancel scheduled maintenance for ${deviceName}? The window starting at ${pendingStart ? hhmm(pendingStart) : '—'} will not open.`}
          confirmLabel="Cancel Maintenance"
          dismissLabel="Keep"
          error={closeError}
          busy={isClosing}
          onConfirm={handleClose}
          onDismiss={() => setConfirming(null)}
        />
      )}
    </>
  );
}
