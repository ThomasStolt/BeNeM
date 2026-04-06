import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import { searchDevices } from '../../lib/api/devices';

export function useDeviceSearch(query: string) {
  const config = useConfig();

  return useQuery({
    queryKey: ['device-search', config.serverId, query],
    queryFn: () => searchDevices(config, query),
    enabled: config.isConfigured && query.length > 0,
    refetchOnWindowFocus: false,
  });
}
