import { postForm } from './client';
import type { BhnmConfig } from '../config';

export interface Device {
  name: string;
  ip: string;
  category: string;
  site: string;
  model: string;
  serialNumber: string;
  description: string;
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
  };
}

export function parseDevicesResponse(raw: unknown): Device[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;
  const devices: Device[] = [];

  for (const value of Object.values(obj)) {
    if (!value || typeof value !== 'object') continue;
    const device = parseDevice(value as Record<string, unknown>);
    if (device) devices.push(device);
  }

  return devices;
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
): Promise<Device[]> {
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
  );
  return parseDeviceFindResponse(raw);
}
