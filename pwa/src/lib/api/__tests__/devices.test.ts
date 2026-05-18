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

  it('derives "up" from alarm_color string "green"', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: 'green' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('up');
  });

  it('derives "critical" from alarm_color string "red"', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: 'red' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('critical');
  });

  it('derives "warning" from alarm_color string "orange"', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: 'orange' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('warning');
  });

  it('derives "up" from alarm_color int 0', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: 0 }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('up');
  });

  it('derives "critical" from alarm_color int 3', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: 3 }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('critical');
  });

  it('derives "up" from alarm_color string-encoded "0"', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', alarm_color: '0' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('up');
  });

  it('derives "up" from up_status 1 when no alarm_color or status', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', up_status: 1 }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('up');
  });

  it('derives "down" from up_status 0', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', up_status: 0 }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('down');
  });

  it('derives "up" from poll+monitor flags when all else absent', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', poll: '1', monitor: '1' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('up');
  });

  it('returns "unknown" when poll is true but monitor is false', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', dev_index: '1', poll: '1', monitor: '0' }
    ]}}];
    expect(parseDevicesResponse(raw).devices[0].status).toBe('unknown');
  });

  it('resolves numeric category/site IDs to names when name maps provided', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'raspi-054', ip: '192.168.1.1', category: 23, site: 19 }
    ]}}];
    const categoryNames = new Map([['23', 'Linux Servers']]);
    const siteNames = new Map([['19', 'Home Lab']]);
    const result = parseDevicesResponse(raw, categoryNames, siteNames);
    expect(result.devices[0].category).toBe('Linux Servers');
    expect(result.devices[0].site).toBe('Home Lab');
  });

  it('falls back to raw ID when no name map entry exists', () => {
    const raw = [{ data: { totalRecords: 1, devices: [
      { name: 'host', ip: '1.2.3.4', category: 42, site: 7 }
    ]}}];
    const result = parseDevicesResponse(raw, new Map(), new Map());
    expect(result.devices[0].category).toBe('42');
    expect(result.devices[0].site).toBe('7');
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
