import { fetchJson } from './client';
import type { BhnmConfig } from '../config';

/**
 * Fetch per-device threshold counts from the middleware cache endpoint.
 * The middleware pre-fetches and parses the BHNM threshold CSV server-side,
 * so clients receive a compact JSON dict instead of a large CSV response.
 *
 * Falls back to a live BHNM parse if the middleware cache is cold.
 *
 * Returns Map<deviceName, count>.
 */
export async function fetchThresholdCounts(config: BhnmConfig): Promise<Map<string, number>> {
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;

  const raw = await fetchJson(config.baseUrl, '/api/v1/threshold-counts', headers);

  const obj = raw as { counts?: Record<string, number> } | null;
  const counts = obj?.counts ?? {};

  return new Map(Object.entries(counts).map(([k, v]) => [k, Number(v)]));
}
