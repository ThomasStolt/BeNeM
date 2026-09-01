import { fetchJson } from './client';
import type { BhnmConfig } from '../config';

/**
 * Connection diagnostics from the middleware's `GET /api/v1/diagnostics`.
 * The BHNM hop comes from the middleware's background monitor (cached — the
 * endpoint never probes live, so it is fast and safe to fetch on screen open).
 * `bhnm.reachable === null` means the monitor has no verdict yet (startup
 * window) and must render as "checking", never as down.
 */
export interface DiagnosticsBhnm {
  reachable: boolean | null;
  source: string | null; // "monitor" | "none" | "error"
  latency_ms: number | null;
  last_success_age_seconds: number | null;
  last_error: string | null;
  last_error_age_seconds: number | null;
  consecutive_failures: number;
}

export interface DiagnosticsFeed {
  cached: boolean;
  age_seconds: number | null;
  count: number | null;
  consecutive_failures: number;
  last_error: string | null;
}

export interface Diagnostics {
  middleware: {
    version: string | null;
    registered_devices: number | null;
    server_time: number | null;
  };
  server: {
    name: string;
    host: string;
    cache_enabled: boolean;
    bhnm: DiagnosticsBhnm;
    feeds: Record<string, DiagnosticsFeed>;
  };
}

export interface DiagnosticsResult {
  diagnostics: Diagnostics;
  /** Client-measured round-trip of this fetch — the App→Middleware hop latency. */
  appToMiddlewareMs: number;
}

function num(v: unknown): number | null {
  return typeof v === 'number' ? v : null;
}

function str(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

export function parseDiagnostics(raw: unknown): Diagnostics {
  if (raw === null || typeof raw !== 'object') {
    throw new Error('Invalid diagnostics payload');
  }
  const o = raw as Record<string, Record<string, unknown>>;
  const mw = o.middleware ?? {};
  const server = (o.server ?? {}) as Record<string, unknown>;
  const bhnm = (server.bhnm ?? {}) as Record<string, unknown>;
  const feedsRaw = (server.feeds ?? {}) as Record<string, Record<string, unknown>>;

  const feeds: Record<string, DiagnosticsFeed> = {};
  for (const [key, f] of Object.entries(feedsRaw)) {
    feeds[key] = {
      cached: f.cached === true,
      age_seconds: num(f.age_seconds),
      count: num(f.count),
      consecutive_failures: num(f.consecutive_failures) ?? 0,
      last_error: str(f.last_error),
    };
  }

  return {
    middleware: {
      version: str(mw.version),
      registered_devices: num(mw.registered_devices),
      server_time: num(mw.server_time),
    },
    server: {
      name: str(server.name) ?? '',
      host: str(server.host) ?? '',
      cache_enabled: server.cache_enabled === true,
      bhnm: {
        reachable: typeof bhnm.reachable === 'boolean' ? bhnm.reachable : null,
        source: str(bhnm.source),
        latency_ms: num(bhnm.latency_ms),
        last_success_age_seconds: num(bhnm.last_success_age_seconds),
        last_error: str(bhnm.last_error),
        last_error_age_seconds: num(bhnm.last_error_age_seconds),
        consecutive_failures: num(bhnm.consecutive_failures) ?? 0,
      },
      feeds,
    },
  };
}

export async function fetchDiagnostics(config: BhnmConfig): Promise<DiagnosticsResult> {
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;

  const started = performance.now();
  const raw = await fetchJson(config.baseUrl, '/api/v1/diagnostics', headers);
  const appToMiddlewareMs = Math.round(performance.now() - started);
  return { diagnostics: parseDiagnostics(raw), appToMiddlewareMs };
}
