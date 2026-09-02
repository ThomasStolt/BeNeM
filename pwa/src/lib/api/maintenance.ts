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
}

export function parseMaintenanceStatus(raw: unknown): MaintenanceStatus {
  const record = (raw ?? {}) as Record<string, unknown>;
  const rawWindows = Array.isArray(record.windows) ? record.windows : [];
  return {
    inMaintenance: record.inMaintenance === true,
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

/**
 * Server-wide in-maintenance device names from the middleware's background
 * cache (GET /api/v1/maintenance-map). Best-effort: empty set on any failure
 * or cold cache — rows simply show no maintenance state.
 * Staleness = the map's cache_age (worst case ≈ refresh interval + BHNM's
 * ~85 s poll lag ≈ 3.5 min at defaults); Device Detail stays the fresher truth.
 */
export async function fetchMaintenanceMap(config: BhnmConfig): Promise<Set<string>> {
  try {
    const raw = await fetchJson(config.baseUrl, '/api/v1/maintenance-map', {
      'X-Proxy-Token': config.apiKey,
    });
    const record = (raw ?? {}) as Record<string, unknown>;
    const names = Array.isArray(record.in_maintenance) ? record.in_maintenance : [];
    return new Set(names.filter((n): n is string => typeof n === 'string'));
  } catch {
    return new Set();
  }
}
