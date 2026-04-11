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

function parseDevice(entry: Record<string, unknown>): Device | null {
  const name = coerceString(entry.name);
  if (!name) return null;
  return {
    name,
    ip: coerceString(entry.ip) || coerceString(entry.ip_address),
    category: coerceString(entry.category),
    site: coerceString(entry.site),
    model: coerceString(entry.model),
    serialNumber: coerceString(entry.serial_number) || coerceString(entry.serialNumber),
    description: coerceString(entry.description),
    deviceIndex: coerceString(entry.dev_index) || coerceString(entry.deviceIndex),
    status: coerceStatus(entry.status),
  };
}

export interface DeviceListResult {
  devices: Device[];
  totalRecords: number;
}

function parseDeviceArray(arr: unknown[]): Device[] {
  const devices: Device[] = [];
  for (const entry of arr) {
    if (entry && typeof entry === 'object') {
      const device = parseDevice(entry as Record<string, unknown>);
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
export function parseDevicesResponse(raw: unknown): DeviceListResult {
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
      return { devices: parseDeviceArray(data.devices), totalRecords: total || 0 };
    }
  }

  // Shape 2: { devices: [...] } (no data wrapper)
  if (Array.isArray(obj.devices)) {
    return { devices: parseDeviceArray(obj.devices), totalRecords: 0 };
  }

  // Shape 3: object-keyed { key: {device}, key: {device} } (fallback)
  const devices: Device[] = [];
  for (const value of Object.values(obj)) {
    if (!value || typeof value !== 'object') continue;
    const device = parseDevice(value as Record<string, unknown>);
    if (device) devices.push(device);
  }
  return { devices, totalRecords: 0 };
}

export function parseDeviceFindResponse(raw: unknown): Device[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;

  if (Array.isArray(obj.results)) {
    const devices: Device[] = [];
    for (const entry of obj.results) {
      if (entry && typeof entry === 'object') {
        const device = parseDevice(entry as Record<string, unknown>);
        if (device) devices.push(device);
      }
    }
    return devices;
  }

  const device = parseDevice(obj);
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
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/list',
    params,
    config.apiKey,
  );
  return parseDevicesResponse(raw);
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
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/find',
    params,
    config.apiKey,
  );
  return parseDeviceFindResponse(raw);
}
