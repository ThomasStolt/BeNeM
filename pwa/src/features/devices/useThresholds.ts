import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchThresholdCounts } from '../../lib/api/thresholds';

/**
 * Fetch threshold counts for all devices in a single CSV call.
 * Returns a Map<deviceName, count>. Stale after 10 minutes — thresholds
 * change infrequently.
 */
export function useThresholds() {
  const config = useConfig();
  return useQuery({
    queryKey: ['thresholds', config.serverId],
    queryFn: () => fetchThresholdCounts(config),
    enabled: config.isConfigured,
    staleTime: 10 * 60 * 1000,
  });
}
