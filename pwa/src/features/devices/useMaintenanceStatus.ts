import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchMaintenanceStatus } from '../../lib/api/maintenance';

/**
 * Merged maintenance read for one device: {inMaintenance, windows}.
 * Best-effort — resolves null on failure (callers render the plain create button).
 * 60 s refresh, matching the other device-detail queries.
 */
export function useMaintenanceStatus(deviceName: string) {
  const config = useConfig();
  return useQuery({
    queryKey: ['maintenance-status', config.serverId, deviceName],
    queryFn: () => fetchMaintenanceStatus(config, deviceName),
    enabled: config.isConfigured && deviceName.length > 0,
    refetchInterval: 60_000,
  });
}
