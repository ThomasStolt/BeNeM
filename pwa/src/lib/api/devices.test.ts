import { describe, it, expect } from 'vitest';
import { parseDeviceFindResponse } from './devices';

describe('parseDeviceFindResponse', () => {
  it('parses dev_index from find response', () => {
    const raw = [
      {
        results: [
          {
            name: 'raspi-054',
            ip: '192.168.1.54',
            category: 'Linux',
            site: 'Home',
            model: 'RPi 4',
            serial_number: 'ABC',
            description: 'Test',
            dev_index: '3',
          },
        ],
      },
    ];
    const devices = parseDeviceFindResponse(raw);
    expect(devices[0].deviceIndex).toBe('3');
  });

  it('defaults deviceIndex to empty string when missing', () => {
    const raw = [
      {
        results: [
          { name: 'switch-01', ip: '10.0.0.1' },
        ],
      },
    ];
    const devices = parseDeviceFindResponse(raw);
    expect(devices[0].deviceIndex).toBe('');
  });
});
