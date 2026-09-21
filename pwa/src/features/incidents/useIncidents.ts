import { useCallback, useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getCachedIncidents, parseIncidentsResponse, refreshIncidents } from '../../lib/api/incidents';
import { useConfig, type BhnmConfig } from '../../lib/config';
import mockData from '../../lib/mock/incidents.json';
import { REFETCH_INTERVAL_MS } from '../../lib/constants';

function useMockMode(): boolean {
  if (typeof window === 'undefined') return false;
  return new URLSearchParams(window.location.search).get('mock') === '1';
}

/** One home for the key, so the query and the refresh cannot address different
 * caches — the class of defect where a refresh "works" and the screen does not
 * move. */
export function incidentsQueryKey(config: BhnmConfig, mockMode: boolean) {
  return ['incidents', mockMode ? 'mock' : config.serverId, config.baseUrl] as const;
}

export function useIncidents() {
  const config = useConfig();
  const mockMode = useMockMode();

  return useQuery({
    queryKey: incidentsQueryKey(config, mockMode),
    queryFn: async () => {
      if (mockMode) return parseIncidentsResponse(mockData);
      if (!config.isConfigured) {
        return parseIncidentsResponse(mockData); // show fixture when no key set
      }
      return getCachedIncidents(config);
    },
    refetchInterval: REFETCH_INTERVAL_MS,
    // OFF, deliberately. A resume now goes through useRefreshIncidents, which
    // POSTs the refresh endpoint; leaving this on would fire a second, plain
    // GET beside it. One trigger, one request.
    refetchOnWindowFocus: false,
  });
}

/** C7's Refresh, and the same call the app makes when it comes to the
 * foreground. Writes the answer straight into the query cache, so the screen
 * re-renders from what the refresh returned rather than from a second fetch. */
export function useRefreshIncidents() {
  const config = useConfig();
  const mockMode = useMockMode();
  const queryClient = useQueryClient();
  const [isRefreshing, setIsRefreshing] = useState(false);

  const refresh = useCallback(async () => {
    if (mockMode || !config.isConfigured) {
      await queryClient.invalidateQueries({ queryKey: incidentsQueryKey(config, mockMode) });
      return;
    }
    setIsRefreshing(true);
    try {
      const incidents = await refreshIncidents(config);
      queryClient.setQueryData(incidentsQueryKey(config, mockMode), incidents);
    } catch {
      // A failed refresh must not blank the list. The rows on screen are still
      // the last thing the server actually confirmed; the header's Updated time
      // keeps saying when that was, rather than implying this moment.
      await queryClient.invalidateQueries({ queryKey: incidentsQueryKey(config, mockMode) });
    } finally {
      setIsRefreshing(false);
    }
  }, [config, mockMode, queryClient]);

  return { refresh, isRefreshing };
}

/** Every resume refreshes. Ruled 2026-09-21 (Q4): no client-side staleness
 * check — the middleware's 30 s window is the ONLY bound, and keeping it in one
 * place is what makes "one user's refresh serves everyone" true rather than
 * approximately true. */
export function useRefreshOnForeground(refresh: () => void) {
  useEffect(() => {
    if (typeof document === 'undefined') return;
    const onVisible = () => {
      if (document.visibilityState === 'visible') refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);
}
