import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchTacticalOverview, type GroupingType } from '../../lib/api/tactical-overview';
import { REFETCH_INTERVAL_MS } from '../../lib/constants';

/** Map route param to API grouping_type. 'bw' maps to 'app' for the BHNM API. */
function toApiGroupingType(routeType: string): GroupingType {
  if (routeType === 'bw') return 'app';
  if (routeType === 'site') return 'site';
  return 'category';
}

export function useTacticalGroups(routeType: string) {
  const config = useConfig();
  const groupingType = toApiGroupingType(routeType);

  return useQuery({
    queryKey: ['tactical-groups', config.serverId, groupingType],
    queryFn: () => fetchTacticalOverview(config, groupingType),
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
