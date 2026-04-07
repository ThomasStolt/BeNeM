import { useQuery } from '@tanstack/react-query';
import { useConfig } from '../../lib/config';
import {
  fetchPerformanceCategories,
  fetchPerformanceInstances,
  fetchTimeSeriesBatch,
} from '../../lib/api/performance';

export function usePerformanceCategories(deviceIndex: string) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-categories', config.serverId, deviceIndex],
    queryFn: () => fetchPerformanceCategories(config, deviceIndex),
    enabled: config.isConfigured && deviceIndex !== '',
    staleTime: 5 * 60 * 1000,
  });
}

export function usePerformanceInstances(
  deviceIndex: string,
  categoryId: string,
  statGroup: string,
  enabled: boolean,
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-instances', config.serverId, deviceIndex, categoryId],
    queryFn: () => fetchPerformanceInstances(config, deviceIndex, categoryId, statGroup),
    enabled: config.isConfigured && enabled && deviceIndex !== '',
    staleTime: 5 * 60 * 1000,
  });
}

export function useTimeSeriesBatch(
  deviceName: string,
  statGroup: string,
  units: string,
  metricTitle: string | undefined,
  enabled: boolean,
) {
  const config = useConfig();
  return useQuery({
    queryKey: ['perf-timeseries', config.serverId, deviceName, statGroup, units],
    queryFn: () => fetchTimeSeriesBatch(config, deviceName, statGroup, units, metricTitle),
    enabled: config.isConfigured && enabled,
    staleTime: 60 * 1000,
  });
}
