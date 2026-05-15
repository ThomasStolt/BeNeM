import { postForm } from './client';
import type { BhnmConfig } from '../config';

export type DeviceStatus = 'up' | 'down' | 'warning' | 'critical' | 'unknown' | 'maintenance';

const STATUS_MAP: Record<string, DeviceStatus> = {
  up: 'up', UP: 'up',
  down: 'down', DOWN: 'down',
  warning: 'warning', WARNING: 'warning',
  critical: 'critical', CRITICAL: 'critical',
  maintenance: 'maintenance', MAINTENANCE: 'maintenance',
};

function coerceStatus(v: unknown): DeviceStatus {
  if (typeof v === 'string') return STATUS_MAP[v] ?? 'unknown';
  return 'unknown';
}

export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
  deviceIndex: string;
  status: DeviceStatus;
}

function coerceString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

// SaaS BHNM returns numeric fields (dev_index, category, site) as integers
// rather than strings. This helper accepts both.
function coerceStringOrNum(v: unknown): string {
  if (typeof v === 'string' && v.length > 0) return v;
  if (typeof v === 'number') return String(v);
  return '';
}

// Fetch id→name map from category/list or site/list endpoints.
// Returns empty map on any failure — name resolution is best-effort.
async function fetchNameMap(config: BhnmConfig, path: string): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  try {
    const params: Record<string, string> = { password: config.apiKey };
    if (config.pin) params.pin = config.pin;
    const raw = await postForm(config.baseUrl, path, params, config.apiKey);
    const arr: unknown[] = Array.isArray(raw) ? raw : [];
    for (const item of arr) {
      if (!item || typeof item !== 'object') continue;
      const entry = item as Record<string, unknown>;
      const id = String(entry.id ?? '');
      const name = typeof entry.name === 'string' ? entry.name : '';
      if (id && name) map.set(id, name);
    }
  } catch {
    // fall back to raw IDs
  }
  return map;
}

function parseDevice(
  entry: Record<string, unknown>,
  categoryNames: Map<string, string> = new Map(),
  siteNames: Map<string, string> = new Map(),
): Device | null {
  const name = coerceString(entry.name);
  if (!name) return null;
  const rawCategory = coerceStringOrNum(entry.category);
  const rawSite = coerceStringOrNum(entry.site);
  return {
    name,
    ip: coerceString(entry.ip) || coerceString(entry.ip_address),
    category: categoryNames.get(rawCategory) ?? rawCategory,
    site: siteNames.get(rawSite) ?? rawSite,
    model: coerceString(entry.model),
    serialNumber: coerceString(entry.serial_number) || coerceString(entry.serialNumber),
    description: coerceString(entry.description),
    deviceIndex: coerceStringOrNum(entry.dev_index) || coerceStringOrNum(entry.deviceIndex),
    status: coerceStatus(entry.status),
  };
}

export interface DeviceListResult {
  devices: Device[];
  totalRecords: number;
}

function parseDeviceArray(
  arr: unknown[],
  categoryNames: Map<string, string> = new Map(),
  siteNames: Map<string, string> = new Map(),
): Device[] {
  const devices: Device[] = [];
  for (const entry of arr) {
    if (entry && typeof entry === 'object') {
      const device = parseDevice(entry as Record<string, unknown>, categoryNames, siteNames);
      if (device) devices.push(device);
    }
  }
  return devices;
}

/**
 * Parse response from `restful/devices/list`.
 * Real BHNM shape: `{ data: { totalRecords, displayRecords, devices: [...] } }`
 * possibly array-wrapped as `[{ data: { ... } }]`.
 */
export function parseDevicesResponse(
  raw: unknown,
  categoryNames: Map<string, string> = new Map(),
  siteNames: Map<string, string> = new Map(),
): DeviceListResult {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return { devices: [], totalRecords: 0 };

  const obj = root as Record<string, unknown>;

  // Shape 1: { data: { devices: [...], totalRecords } }
  if (obj.data && typeof obj.data === 'object') {
    const data = obj.data as Record<string, unknown>;
    if (Array.isArray(data.devices)) {
      const total = typeof data.totalRecords === 'string'
        ? parseInt(data.totalRecords, 10)
        : typeof data.totalRecords === 'number' ? data.totalRecords : 0;
      return { devices: parseDeviceArray(data.devices, categoryNames, siteNames), totalRecords: total || 0 };
    }
  }

  // Shape 2: { devices: [...] } (no data wrapper)
  if (Array.isArray(obj.devices)) {
    return { devices: parseDeviceArray(obj.devices, categoryNames, siteNames), totalRecords: 0 };
  }

  // Shape 3: object-keyed { key: {device}, key: {device} } (fallback)
  const devices: Device[] = [];
  for (const value of Object.values(obj)) {
    if (!value || typeof value !== 'object') continue;
    const device = parseDevice(value as Record<string, unknown>, categoryNames, siteNames);
    if (device) devices.push(device);
  }
  return { devices, totalRecords: 0 };
}

export function parseDeviceFindResponse(
  raw: unknown,
  categoryNames: Map<string, string> = new Map(),
  siteNames: Map<string, string> = new Map(),
): Device[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;

  if (Array.isArray(obj.results)) {
    const devices: Device[] = [];
    for (const entry of obj.results) {
      if (entry && typeof entry === 'object') {
        const device = parseDevice(entry as Record<string, unknown>, categoryNames, siteNames);
        if (device) devices.push(device);
      }
    }
    return devices;
  }

  const device = parseDevice(obj, categoryNames, siteNames);
  return device ? [device] : [];
}

export async function fetchDevices(
  config: BhnmConfig,
  start: number,
  count: number,
): Promise<DeviceListResult> {
  const params: Record<string, string> = {
    password: config.apiKey,
    recordStart: String(start),
    recordCount: String(count),
  };
  if (config.pin) params.pin = config.pin;
  const [raw, categoryNames, siteNames] = await Promise.all([
    postForm(config.baseUrl, '/fw/index.php?r=restful/devices/list', params, config.apiKey),
    fetchNameMap(config, '/fw/index.php?r=restful/category/list'),
    fetchNameMap(config, '/fw/index.php?r=restful/site/list'),
  ]);
  return parseDevicesResponse(raw, categoryNames, siteNames);
}

export async function searchDevices(
  config: BhnmConfig,
  name: string,
): Promise<Device[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name,
  };
  if (config.pin) params.pin = config.pin;
  const [raw, categoryNames, siteNames] = await Promise.all([
    postForm(config.baseUrl, '/fw/index.php?r=restful/devices/find', params, config.apiKey),
    fetchNameMap(config, '/fw/index.php?r=restful/category/list'),
    fetchNameMap(config, '/fw/index.php?r=restful/site/list'),
  ]);
  return parseDeviceFindResponse(raw, categoryNames, siteNames);
}
