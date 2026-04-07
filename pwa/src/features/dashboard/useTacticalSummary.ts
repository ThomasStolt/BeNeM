import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import {
  fetchTacticalOverview,
  sumTacticalGroups,
  type TacticalSummary,
} from '../../lib/api/tactical-overview';
import { REFETCH_INTERVAL_MS } from '../../lib/constants';

export function useTacticalSummary() {
  const config = useConfig();

  return useQuery({
    queryKey: ['tactical-summary', config.serverId, config.baseUrl],
    queryFn: async (): Promise<TacticalSummary> => {
      const groups = await fetchTacticalOverview(config, 'category');
      return sumTacticalGroups(groups);
    },
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
