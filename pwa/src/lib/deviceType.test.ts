import { describe, it, expect } from 'vitest';
import { classifyDevice } from './deviceType';
import type { Device } from './api/devices';

function device(overrides: Partial<Device>): Device {
  return {
    name: 'host', ip: '1.2.3.4', category: '', site: '',
    model: '', serialNumber: '', description: '', deviceIndex: '1',
    status: 'up',
    ...overrides,
  };
}

describe('classifyDevice', () => {
  it('classifies Linux by category', () => {
    expect(classifyDevice(device({ category: 'Linux Servers' }))).toBe('linux');
  });
  it('classifies Linux by description', () => {
    expect(classifyDevice(device({ description: 'Ubuntu linux host' }))).toBe('linux');
  });
  it('classifies Windows by category', () => {
    expect(classifyDevice(device({ category: 'Windows' }))).toBe('windows');
  });
  it('classifies router by description', () => {
    expect(classifyDevice(device({ description: 'Cisco Router' }))).toBe('router');
  });
  it('classifies switch by category', () => {
    expect(classifyDevice(device({ category: 'Network Switch' }))).toBe('switch');
  });
  it('falls back to unknown', () => {
    expect(classifyDevice(device({ category: 'Firewall', description: 'Palo Alto' }))).toBe('unknown');
  });
  it('is case-insensitive', () => {
    expect(classifyDevice(device({ category: 'LINUX' }))).toBe('linux');
    expect(classifyDevice(device({ category: 'WINDOWS Server' }))).toBe('windows');
  });
});
