import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchMaintenanceMap } from '../../lib/api/maintenance';

/** Creator-side optimism: after a successful create, the map cache lags
 * (snap wait + BHNM poll + middleware cycle), so the creator's own device is
 * noted locally and unioned into every map read until the server catches up
 * or the grace expires. Mirror of the detail button's pendingStart. */
const LOCAL_GRACE_MS = 8 * 60_000;
const localAdds = new Map<string, number>(); // name -> expiry epoch ms

export function noteLocalMaintenance(deviceName: string): void {
  localAdds.set(deviceName, Date.now() + LOCAL_GRACE_MS);
}

export function clearLocalMaintenance(deviceName: string): void {
  localAdds.delete(deviceName);
}

export function withLocalMaintenance(set: Set<string>): Set<string> {
  const now = Date.now();
  for (const [name, expiry] of localAdds) {
    if (expiry < now) localAdds.delete(name);
    else set.add(name);
  }
  return set;
}

export function _resetLocalMaintenance(): void {
  localAdds.clear();
}

/**
 * Set of device names currently in maintenance, from the middleware's
 * maintenance-map cache, unioned with creator-side local notes.
 * 60 s refresh, matching the other list queries.
 * Empty set = no markers (cold cache, failure, or BHNM < 26.3.01).
 */
export function useMaintenanceMap() {
  const config = useConfig();
  return useQuery({
    queryKey: ['maintenance-map', config.serverId],
    queryFn: async () => withLocalMaintenance(await fetchMaintenanceMap(config)),
    enabled: config.isConfigured,
    refetchInterval: 60_000,
  });
}
