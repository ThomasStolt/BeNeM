import { describe, it, expect } from 'vitest';
import { parseDevicesResponse, parseDeviceFindResponse } from '../devices';

describe('parseDevicesResponse', () => {
  it('parses a normal device list response', () => {
    const raw = [{
      raspi: {
        name: 'raspi-054',
        ip: '192.168.1.54',
        category: 'Linux',
        site: 'Home',
        model: 'RPi 4',
        serial_number: 'ABC123',
        description: 'Raspberry Pi',
      },
      switch: {
        name: 'core-switch',
        ip: '10.0.0.1',
        category: 'Network',
        site: 'Office',
      },
    }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toHaveLength(2);
    expect(devices[0]).toEqual({
      name: 'raspi-054',
      ip: '192.168.1.54',
      category: 'Linux',
      site: 'Home',
      model: 'RPi 4',
      serialNumber: 'ABC123',
      description: 'Raspberry Pi',
    });
    expect(devices[1]).toEqual({
      name: 'core-switch',
      ip: '10.0.0.1',
      category: 'Network',
      site: 'Office',
      model: '',
      serialNumber: '',
      description: '',
    });
  });

  it('handles array-wrapped response', () => {
    const raw = [{ dev1: { name: 'host-1', ip: '1.2.3.4' } }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toHaveLength(1);
    expect(devices[0].name).toBe('host-1');
  });

  it('returns empty array for null/undefined', () => {
    expect(parseDevicesResponse(null)).toEqual([]);
    expect(parseDevicesResponse(undefined)).toEqual([]);
  });

  it('returns empty array for empty object', () => {
    expect(parseDevicesResponse([{}])).toEqual([]);
    expect(parseDevicesResponse({})).toEqual([]);
  });

  it('skips entries without a name', () => {
    const raw = [{ dev: { ip: '1.2.3.4' } }];
    const devices = parseDevicesResponse(raw);
    expect(devices).toEqual([]);
  });
});

describe('parseDeviceFindResponse', () => {
  it('parses a find response with direct device object', () => {
    const raw = [{
      name: 'raspi-054',
      ip: '192.168.1.54',
      category: 'Linux',
      site: 'Home',
      model: 'RPi 4',
      serial_number: 'ABC123',
      description: 'Test device',
    }];
    const devices = parseDeviceFindResponse(raw);
    expect(devices).toHaveLength(1);
    expect(devices[0].name).toBe('raspi-054');
    expect(devices[0].serialNumber).toBe('ABC123');
  });

  it('parses find response with nested results', () => {
    const raw = [{
      results: [
        { name: 'host-a', ip: '1.1.1.1' },
        { name: 'host-b', ip: '2.2.2.2' },
      ],
    }];
    const devices = parseDeviceFindResponse(raw);
    expect(devices).toHaveLength(2);
  });

  it('returns empty array for no matches', () => {
    expect(parseDeviceFindResponse([{}])).toEqual([]);
    expect(parseDeviceFindResponse(null)).toEqual([]);
  });
});
