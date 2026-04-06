import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { fetchDevices } from '../../lib/api/devices';

export const PAGE_SIZE = 50;
const REFETCH_INTERVAL_MS = 120_000;

export function useDevices(page: number) {
  const config = useConfig();
  const start = page * PAGE_SIZE;

  return useQuery({
    queryKey: ['devices', config.serverId, page],
    queryFn: () => fetchDevices(config, start, PAGE_SIZE),
    enabled: config.isConfigured,
    refetchInterval: REFETCH_INTERVAL_MS,
    refetchOnWindowFocus: true,
  });
}
