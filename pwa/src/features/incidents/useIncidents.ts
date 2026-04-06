import { useQuery } from '@tanstack/react-query';
import { getIncidents, parseIncidentsResponse } from '../../lib/api/incidents';
import { useConfig } from '../../lib/config';
import mockData from '../../lib/mock/incidents.json';

const REFETCH_INTERVAL_MS = 120_000;

function useMockMode(): boolean {
  if (typeof window === 'undefined') return false;
  return new URLSearchParams(window.location.search).get('mock') === '1';
}

export function useIncidents() {
  const config = useConfig();
  const mockMode = useMockMode();

  return useQuery({
    queryKey: ['incidents', mockMode ? 'mock' : config.serverId, config.baseUrl],
    queryFn: async () => {
      if (mockMode) return parseIncidentsResponse(mockData);
      if (!config.isConfigured) {
        return parseIncidentsResponse(mockData); // show fixture when no key set
      }
      return getIncidents(config);
    },
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
