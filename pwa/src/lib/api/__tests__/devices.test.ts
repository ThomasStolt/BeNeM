import { describe, it, expect } from 'vitest';
import { parseDevicesResponse, parseDeviceFindResponse } from '../devices';

describe('parseDevicesResponse', () => {
  it('parses real BHNM response with data.devices array', () => {
    const raw = [{
      data: {
        totalRecords: '40',
        displayRecords: 2,
        devices: [
          { name: 'raspi-054', ip: '192.168.2.54', category: '23', site: '19', description: 'Linux raspi' },
          { name: 'Synology920', ip: '192.168.2.11', category: '27', site: '19', serial_number: null },
        ],
      },
    }];
    const result = parseDevicesResponse(raw);
    expect(result.totalRecords).toBe(40);
    expect(result.devices).toHaveLength(2);
    expect(result.devices[0].name).toBe('raspi-054');
    expect(result.devices[1].name).toBe('Synology920');
  });

  it('parses object-keyed fallback format', () => {
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
    const result = parseDevicesResponse(raw);
    expect(result.devices).toHaveLength(2);
    expect(result.devices[0]).toEqual({
      name: 'raspi-054',
      ip: '192.168.1.54',
      category: 'Linux',
      site: 'Home',
      model: 'RPi 4',
      serialNumber: 'ABC123',
      description: 'Raspberry Pi',
      deviceIndex: '',
      status: 'unknown',
    });
    expect(result.devices[1]).toEqual({
      name: 'core-switch',
      ip: '10.0.0.1',
      category: 'Network',
      site: 'Office',
      model: '',
      serialNumber: '',
      description: '',
      deviceIndex: '',
      status: 'unknown',
    });
  });

  it('handles array-wrapped response', () => {
    const raw = [{ data: { totalRecords: 1, devices: [{ name: 'host-1', ip: '1.2.3.4' }] } }];
    const result = parseDevicesResponse(raw);
    expect(result.devices).toHaveLength(1);
    expect(result.devices[0].name).toBe('host-1');
  });

  it('returns empty for null/undefined', () => {
    expect(parseDevicesResponse(null).devices).toEqual([]);
    expect(parseDevicesResponse(undefined).devices).toEqual([]);
  });

  it('returns empty for empty object', () => {
    expect(parseDevicesResponse([{}]).devices).toEqual([]);
    expect(parseDevicesResponse({}).devices).toEqual([]);
  });

  it('skips entries without a name', () => {
    const raw = [{ data: { devices: [{ ip: '1.2.3.4' }] } }];
    expect(parseDevicesResponse(raw).devices).toEqual([]);
  });

  it('parses totalRecords as string', () => {
    const raw = [{ data: { totalRecords: '100', devices: [{ name: 'a', ip: '1.1.1.1' }] } }];
    expect(parseDevicesResponse(raw).totalRecords).toBe(100);
  });

  it('parses status UP to "up"', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
        serial_number: '', description: '', dev_index: '1', status: 'UP' }
    ]}}];
    const result = parseDevicesResponse(raw);
    expect(result.devices[0].status).toBe('up');
  });

  it('falls back to "unknown" for unrecognised status', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
        serial_number: '', description: '', dev_index: '1', status: 'PURPLE' }
    ]}}];
    const result = parseDevicesResponse(raw);
    expect(result.devices[0].status).toBe('unknown');
  });

  it('defaults to "unknown" when status field is absent', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', category: '', site: '', model: '',
        serial_number: '', description: '', dev_index: '1' }
    ]}}];
    const result = parseDevicesResponse(raw);
    expect(result.devices[0].status).toBe('unknown');
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
