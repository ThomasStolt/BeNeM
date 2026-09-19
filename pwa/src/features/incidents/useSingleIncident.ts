import { useQuery } from '@tanstack/react-query';
import { getSingleIncident } from '../../lib/api/incidents';
import { ApiException } from '../../lib/api/types';
import { useConfig } from '../../lib/config';

/** Fetch ONE incident, for when it is not in the loaded list.
 *
 * A tap can beat the cache cycle, the cache can be cold after a middleware
 * restart, caching can be off for the server, or a notification can be hours old
 * and name an incident that has since closed and gone. In every one of those the
 * list lookup fails and the screen used to say `Incident not found.` — which is
 * true in exactly one of them.
 *
 * `bounded` is the wait: react-query retries transport failures a couple of
 * times and then stops, so the screen reaches a verdict instead of spinning.
 * A 404 is NEVER retried: it is a terminal fact, and retrying it would turn an
 * answer into a hang.
 */
export function useSingleIncident(incidentId: string, options?: { enabled?: boolean }) {
  const config = useConfig();
  return useQuery({
    queryKey: ['singleIncident', incidentId],
    queryFn: () => getSingleIncident(config, incidentId),
    enabled: (options?.enabled ?? true) && Boolean(incidentId),
    staleTime: 30_000,
    retry: (failureCount, error) => {
      if (error instanceof ApiException && error.error.kind === 'server'
          && error.error.status === 404) {
        return false;
      }
      return failureCount < 2;
    },
    // The bound is wall-clock, not just a count. Default backoff is exponential
    // and unbounded in practice; somebody woken at 3am is watching this screen,
    // so two fixed 1 s retries means a verdict within ~2 s, every time.
    retryDelay: 1_000,
  });
}

/** Did this failure mean "gone" (terminal) or "could not reach" (try again)? */
export function isGone(error: unknown): boolean {
  return error instanceof ApiException
    && error.error.kind === 'server'
    && error.error.status === 404;
}
