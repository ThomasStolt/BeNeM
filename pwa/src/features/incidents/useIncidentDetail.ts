import { useQuery } from '@tanstack/react-query';
import { getIncidentDetail } from '../../lib/api/incidents';
import { useConfig } from '../../lib/config';

export function useIncidentDetail(
  incidentId: string,
  options?: { enabled?: boolean },
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['incidentDetail', incidentId],
    queryFn: () => getIncidentDetail(config, incidentId),
    staleTime: 60_000,
    enabled: (options?.enabled ?? true) && Boolean(incidentId),
  });
}
