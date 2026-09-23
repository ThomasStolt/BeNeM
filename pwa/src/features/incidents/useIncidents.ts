import { useCallback, useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getCachedIncidents, parseIncidentsResponse, refreshIncidents } from '../../lib/api/incidents';
import { useConfig, type BhnmConfig } from '../../lib/config';
import mockData from '../../lib/mock/incidents.json';

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
    // **No timer on the incident list.** Ruled 2026-09-21: only this screen
    // loses it. Under webhook mode the list is pushed to, not polled — the
    // countdown was removed for being a promise that nothing kept, and leaving
    // the poll behind it would keep the cost without the honesty. Home, Devices
    // and Groups keep their 120 s refetchInterval; they have no webhook.
    //
    // refetchOnWindowFocus is off for a different reason: a resume goes through
    // useRefreshIncidents, which POSTs the refresh endpoint. Leaving this on
    // would fire a second, plain GET beside it. One trigger, one request.
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

/** A plain re-read of `GET /api/v1/incidents` — **the middleware's cache, and
 * no BHNM call.**
 *
 * Deliberately NOT `useRefreshIncidents`, which POSTs `/api/v1/incidents/refresh`
 * and makes the middleware call BHNM's `getincidents`. That belongs to a
 * deliberate user action — a tap, a pull, a resume. The two callers below fire
 * on their own, and a self-firing BHNM call is a cost nobody asked for.
 *
 * Invalidating is how the re-read happens rather than a second fetch path: the
 * query's own `queryFn` runs, so `Updated HH:MM` (`dataUpdatedAt`) moves with it
 * and the screen has exactly one source. */
export function useReloadIncidents() {
  const config = useConfig();
  const mockMode = useMockMode();
  const queryClient = useQueryClient();
  return useCallback(
    () => queryClient.invalidateQueries({ queryKey: incidentsQueryKey(config, mockMode) }),
    [config, mockMode, queryClient],
  );
}

/** A push reloads the list.
 *
 * The service worker posts `{type:'incidents-updated'}` to every open tab on
 * every push and on every notification tap. Before 0.19.5 an already-open list
 * had no way to learn that the middleware's cache had moved: the 120 s
 * `refetchInterval` used to cover it by accident and was removed in 0.19.0,
 * while C4 — the push carrying the change itself — has not landed. Reported
 * from the field on iOS 54; this is the same hole on this platform. */
export function useReloadOnPush(reload: () => void) {
  useEffect(() => {
    if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'incidents-updated') reload();
    };
    navigator.serviceWorker.addEventListener('message', handler);
    return () => navigator.serviceWorker.removeEventListener('message', handler);
  }, [reload]);
}

/** The silent safety net: re-read the cache every `intervalMs` while the tab is
 * visible. **No countdown, no UI.**
 *
 * This is the poll the 120 s countdown used to perform, minus the countdown.
 * Removing the countdown in 0.19.0 was right — it was a promise nothing kept
 * under webhook mode — but removing the *request* underneath it was not, because
 * an acknowledgement made in the BHNM UI reaches the middleware's cache with
 * nothing to carry it the last hop to an open screen.
 *
 * **The first tick is a full interval away, and that is load-bearing.** A resume
 * fires `useRefreshOnForeground` in the same instant and restarts this timer;
 * firing immediately would put two requests on the wire for one event. It stops
 * on hide, so a backgrounded tab costs nothing.
 *
 * **30 s since 0.19.9 (C19)**, matching the middleware's list cadence; at 60 s
 * the client was the largest term left in the lag. */
export function usePollWhileVisible(reload: () => void, intervalMs = 30_000) {
  useEffect(() => {
    if (typeof document === 'undefined') return;
    let timer: ReturnType<typeof setInterval> | undefined;
    const start = () => {
      if (timer === undefined) timer = setInterval(reload, intervalMs);
    };
    const stop = () => {
      if (timer !== undefined) clearInterval(timer);
      timer = undefined;
    };
    const sync = () => (document.visibilityState === 'visible' ? start() : stop());
    sync();
    document.addEventListener('visibilitychange', sync);
    return () => {
      stop();
      document.removeEventListener('visibilitychange', sync);
    };
  }, [reload, intervalMs]);
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
