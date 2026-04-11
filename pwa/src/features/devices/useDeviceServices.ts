import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchOkServiceCount } from '../../lib/api/services';

/**
 * Fetch the count of enabled+OK service checks for a single device.
 * Used on the device detail screen to compute the full HEALTHY count.
 * Stale after 5 minutes.
 */
export function useDeviceServices(deviceName: string) {
  const config = useConfig();
  return useQuery({
    queryKey: ['device-services', config.serverId, deviceName],
    queryFn: () => fetchOkServiceCount(config, deviceName),
    enabled: config.isConfigured && deviceName.length > 0,
    staleTime: 5 * 60 * 1000,
  });
}
