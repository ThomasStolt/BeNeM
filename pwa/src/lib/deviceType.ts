import type { Device } from './api/devices';

export type DeviceTypeClass = 'linux' | 'windows' | 'router' | 'switch' | 'unknown';

export function classifyDevice(device: Device): DeviceTypeClass {
  const haystack = `${device.category} ${device.description}`.toLowerCase();
  if (haystack.includes('linux')) return 'linux';
  if (haystack.includes('windows')) return 'windows';
  if (haystack.includes('router')) return 'router';
  if (haystack.includes('switch')) return 'switch';
  return 'unknown';
}
