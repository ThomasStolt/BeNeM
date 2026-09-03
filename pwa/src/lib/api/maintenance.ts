import { fetchJson, postForm, postFormResponse, parseJsonResponse } from './client';
import { ApiException } from './types';
import type { BhnmConfig } from '../config';

export interface MaintenanceWindow {
  start: Date;
  end: Date;
  comment: string;
}

/** Merged read from /api/proxy/maintenance/status. inMaintenance is the
 * source of truth for the badge/button state; windows are detail only. */
export interface MaintenanceStatus {
  inMaintenance: boolean;
  windows: MaintenanceWindow[];
  /** Middleware-remembered scheduled window (all users see it); null when none. */
  scheduledStart: Date | null;
}

export function parseMaintenanceStatus(raw: unknown): MaintenanceStatus {
  const record = (raw ?? {}) as Record<string, unknown>;
  const rawWindows = Array.isArray(record.windows) ? record.windows : [];
  const sched = record.scheduled as Record<string, unknown> | null | undefined;
  return {
    inMaintenance: record.inMaintenance === true,
    scheduledStart:
      sched && typeof sched.start_time === 'number'
        ? new Date(sched.start_time * 1000)
        : null,
    windows: rawWindows.map((w) => {
      const win = (w ?? {}) as Record<string, unknown>;
      return {
        start: new Date(Number(win.start_time ?? 0) * 1000),
        end: new Date(Number(win.end_time ?? 0) * 1000),
        comment: typeof win.comment === 'string' ? win.comment : '',
      };
    }),
  };
}

/** Latest end across active windows ("suppressed until"), null if none. */
export function activeEnd(status: MaintenanceStatus): Date | null {
  if (status.windows.length === 0) return null;
  return status.windows.reduce((a, b) => (a.end > b.end ? a : b)).end;
}

/** Comment of the latest-ending window, null if none. */
export function activeComment(status: MaintenanceStatus): string | null {
  if (status.windows.length === 0) return null;
  return status.windows.reduce((a, b) => (a.end > b.end ? a : b)).comment;
}

function throwOnErrorResult(raw: unknown, fallback: string): void {
  const record = raw as Record<string, unknown>;
  if (record?.result === 'error') {
    const detail = typeof record.detail === 'string' ? record.detail : fallback;
    throw new ApiException({ kind: 'server', status: 200, message: detail });
  }
}

/**
 * Create a maintenance window. Returns the snapped start time echoed by the
 * middleware (X-Maintenance-Start), or null on an older middleware without it.
 */
export async function createMaintenanceWindow(
  config: BhnmConfig,
  deviceName: string,
  durationMinutes: number,
  comment: string,
): Promise<Date | null> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name: deviceName,
    duration: String(durationMinutes),
    comment,
  };
  if (config.pin) params.pin = config.pin;

  const response = await postFormResponse(
    config.baseUrl,
    '/api/proxy/maintenance/create',
    params,
    config.apiKey,
  );
  const raw = await parseJsonResponse(response);
  throwOnErrorResult(raw, 'Failed to create maintenance window');

  const startHeader = response.headers.get('X-Maintenance-Start');
  const startEpoch = startHeader ? Number(startHeader) : NaN;
  return Number.isFinite(startEpoch) ? new Date(startEpoch * 1000) : null;
}

/** End maintenance for a device. BHNM closes ALL its windows, scheduled ones included. */
export async function closeMaintenanceWindow(
  config: BhnmConfig,
  deviceName: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name: deviceName,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/api/proxy/maintenance/close',
    params,
    config.apiKey,
  );
  throwOnErrorResult(raw, 'Failed to end maintenance');
}

/** Best-effort read: null on any failure — callers render the plain create button. */
export async function fetchMaintenanceStatus(
  config: BhnmConfig,
  deviceName: string,
): Promise<MaintenanceStatus | null> {
  try {
    const raw = await postForm(
      config.baseUrl,
      '/api/proxy/maintenance/status',
      { name: deviceName },
      config.apiKey,
    );
    return parseMaintenanceStatus(raw);
  } catch {
    return null;
  }
}

export interface MaintenanceMap {
  /** Server-confirmed in-maintenance names — solid wrench. */
  active: Set<string>;
  /** Middleware-remembered scheduled windows (name → start) — blinking wrench,
   * visible to every user, not just the creator. */
  scheduled: Map<string, Date>;
  /** Names whose host row BHNM reports as DOWN (middleware 2.12.0 `host_down`) —
   * red icon. Empty unless the map is usable (see HOST_DOWN_MAX_AGE_S). */
  down: Set<string>;
}

/**
 * host_down is accepted only when the middleware reports a fresh cache:
 * `cache_age_seconds` null means cold / cache-off / unresolved server, and an
 * age above this bound means the crawl loop is stalled — either way the list
 * is parsed as empty and rows fall back to their devices/list colour.
 * 300 s = one failed crawl attempt survives (60 s timeout + 60 s sleep + a
 * crawl); a second one trips it. Decided once here, at parse time — never
 * per render (iOS holds the map for the user's refresh interval).
 */
export const HOST_DOWN_MAX_AGE_S = 300;

/**
 * Server-wide maintenance state from GET /api/v1/maintenance-map.
 * Best-effort: empty on any failure or cold cache — no state shown.
 */
export async function fetchMaintenanceMap(config: BhnmConfig): Promise<MaintenanceMap> {
  const empty: MaintenanceMap = { active: new Set(), scheduled: new Map(), down: new Set() };
  try {
    const raw = await fetchJson(config.baseUrl, '/api/v1/maintenance-map', {
      'X-Proxy-Token': config.apiKey,
    });
    const record = (raw ?? {}) as Record<string, unknown>;
    const names = Array.isArray(record.in_maintenance) ? record.in_maintenance : [];
    const sched = Array.isArray(record.scheduled) ? record.scheduled : [];
    const scheduled = new Map<string, Date>();
    for (const entry of sched) {
      const e = (entry ?? {}) as Record<string, unknown>;
      if (typeof e.name === 'string' && typeof e.start_time === 'number') {
        scheduled.set(e.name, new Date(e.start_time * 1000));
      }
    }
    const age = record.cache_age_seconds;
    const mapUsable = typeof age === 'number' && age <= HOST_DOWN_MAX_AGE_S;
    const downRaw = mapUsable && Array.isArray(record.host_down) ? record.host_down : [];
    return {
      active: new Set(names.filter((n): n is string => typeof n === 'string')),
      scheduled,
      down: new Set(downRaw.filter((n): n is string => typeof n === 'string')),
    };
  } catch {
    return empty;
  }
}
