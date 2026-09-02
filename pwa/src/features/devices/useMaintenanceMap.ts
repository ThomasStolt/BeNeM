import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchMaintenanceMap } from '../../lib/api/maintenance';

/**
 * Module-level per-device store for creator-side local knowledge, so it
 * survives navigation (screen state does not). Openly documented optimism:
 * after a successful create, the device is "pending" — list wrench blinks,
 * detail button shows "Starts at HH:MM" — until the server map confirms
 * (solid wrench / active button) or the note expires ~4 min past its start.
 * A local close suppresses lagging server state for ~3 min. The server set
 * stays the truth everyone else sees.
 */
const PENDING_GRACE_PAST_START_MS = 4 * 60_000;
const CLOSE_GRACE_MS = 3 * 60_000;

interface LocalNote {
  startsAt: number;
  expiry: number;
}

const localNotes = new Map<string, LocalNote>();
const localCloses = new Map<string, number>(); // name -> closedAt epoch ms

export function noteLocalMaintenance(deviceName: string, startsAt: Date): void {
  localNotes.set(deviceName, {
    startsAt: startsAt.getTime(),
    expiry: startsAt.getTime() + PENDING_GRACE_PAST_START_MS,
  });
  localCloses.delete(deviceName);
}

export function clearLocalMaintenance(deviceName: string): void {
  localNotes.delete(deviceName);
}

/** Close/cancel: drop the pending note and suppress lagging server state. */
export function noteLocalClose(deviceName: string): void {
  localNotes.delete(deviceName);
  localCloses.set(deviceName, Date.now());
}

export function getPendingStart(deviceName: string): Date | null {
  const note = localNotes.get(deviceName);
  if (!note) return null;
  if (note.expiry < Date.now()) {
    localNotes.delete(deviceName);
    return null;
  }
  return new Date(note.startsAt);
}

export function getPendingNames(): Set<string> {
  const now = Date.now();
  const out = new Set<string>();
  for (const [name, note] of localNotes) {
    if (note.expiry < now) localNotes.delete(name);
    else out.add(name);
  }
  return out;
}

export function getRecentLocalClose(deviceName: string): Date | null {
  const closedAt = localCloses.get(deviceName);
  if (closedAt === undefined) return null;
  if (Date.now() - closedAt > CLOSE_GRACE_MS) {
    localCloses.delete(deviceName);
    return null;
  }
  return new Date(closedAt);
}

export function _resetLocalMaintenance(): void {
  localNotes.clear();
  localCloses.clear();
}

/**
 * Server truth: set of device names currently in maintenance, from the
 * middleware's maintenance-map cache. 60 s refresh. Empty set = no markers
 * (cold cache, failure, or BHNM < 26.3.01). Pending local notes are read
 * separately via getPendingNames/getPendingStart.
 */
export function useMaintenanceMap() {
  const config = useConfig();
  return useQuery({
    queryKey: ['maintenance-map', config.serverId],
    queryFn: () => fetchMaintenanceMap(config),
    enabled: config.isConfigured,
    refetchInterval: 60_000,
  });
}
