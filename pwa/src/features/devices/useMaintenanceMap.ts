import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchMaintenanceMap } from '../../lib/api/maintenance';

/**
 * Set of device names currently in maintenance, from the middleware's
 * maintenance-map cache. 60 s refresh, matching the other list queries.
 * Empty set = no markers (cold cache, failure, or BHNM < 26.3.01).
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
