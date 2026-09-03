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

function coerceStatus(entry: Record<string, unknown>): DeviceStatus {
  // 1. alarm_color string: "green" → up, "red" → critical, "orange"/"yellow" → warning
  const ac = entry.alarm_color;
  if (typeof ac === 'string') {
    const lower = ac.toLowerCase();
    if (lower === 'green') return 'up';
    if (lower === 'red') return 'critical';
    if (lower === 'orange' || lower === 'yellow') return 'warning';
    // alarm_color as string-encoded int: "0" → up, "1"/"2" → warning, "3" → critical
    const n = parseInt(ac, 10);
    if (!isNaN(n)) {
      if (n === 0) return 'up';
      if (n === 1 || n === 2) return 'warning';
      if (n === 3) return 'critical';
    }
  }
  // 2. alarm_color int: 0 → up, 1/2 → warning, 3 → critical
  if (typeof ac === 'number') {
    if (ac === 0) return 'up';
    if (ac === 1 || ac === 2) return 'warning';
    if (ac === 3) return 'critical';
  }
  // 3. status string field
  if (typeof entry.status === 'string') {
    const mapped = STATUS_MAP[entry.status];
    if (mapped) return mapped;
  }
  // 4. up_status int: 1 → up, 0 → down
  if (typeof entry.up_status === 'number') {
    return entry.up_status === 1 ? 'up' : 'down';
  }
  // 5. monitor flag (mirrors iOS final fallback): BHNM runs a host check on
  //    every monitor=1 device, Ping-Only (poll=0) included. `poll` is NOT a
  //    flag — on 26.3.01 it is a runtime poller-state int (0/1/2/5) that
  //    changes on its own — so it is deliberately ignored. Exact match only:
  //    an absent or exotic monitor value must fail safe to grey, never green.
  // Note: devices/list carries no live state, so this means "monitored",
  //    never "down". Upgrade path: host_status overlay from the maintenance map.
  const monitor = entry.monitor === '1' || entry.monitor === 1 || entry.monitor === true;
  return monitor ? 'up' : 'unknown';
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
    status: coerceStatus(entry),
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
// totalRecords arrives as a string on some servers and a number on others.
function coerceTotal(v: unknown, fallback: number): number {
  const n = typeof v === 'string' ? parseInt(v, 10) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

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
      const devices = parseDeviceArray(data.devices, categoryNames, siteNames);
      return { devices, totalRecords: coerceTotal(data.totalRecords, devices.length) };
    }
  }

  // Shape 2: { totalRecords, displayRecords, devices: [...] } — what BHNM 26.3.01
  // actually sends (no data wrapper). totalRecords drives the pager's "of N".
  if (Array.isArray(obj.devices)) {
    const devices = parseDeviceArray(obj.devices, categoryNames, siteNames);
    return { devices, totalRecords: coerceTotal(obj.totalRecords, devices.length) };
  }

  // Shape 3: object-keyed { key: {device}, key: {device} } (fallback) — unpaged,
  // so the total is what we have.
  const devices: Device[] = [];
  for (const value of Object.values(obj)) {
    if (!value || typeof value !== 'object') continue;
    const device = parseDevice(value as Record<string, unknown>, categoryNames, siteNames);
    if (device) devices.push(device);
  }
  return { devices, totalRecords: devices.length };
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
