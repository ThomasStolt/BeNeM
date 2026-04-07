import { describe, it, expect } from 'vitest';
import {
  parsePerformanceCategories,
  parsePerformanceInstances,
  parseTimeSeriesResponse,
} from './performance';

/* ------------------------------------------------------------------ */
/*  parsePerformanceCategories                                        */
/* ------------------------------------------------------------------ */
describe('parsePerformanceCategories', () => {
  it('parses categories from BHNM response with string ids', () => {
    const raw = [
      { id: 1, category: 'CPU' },
      { id: 9, category: 'Disk' },
      { id: 'interfaces', cat: 'Network' },
    ];
    const result = parsePerformanceCategories(raw);
    expect(result).toEqual([
      { id: '1', category: 'CPU' },
      { id: '9', category: 'Disk' },
      { id: 'interfaces', category: 'Network' },
    ]);
  });

  it('normalizes Network category from cat to category', () => {
    const raw = [{ id: 'interfaces', cat: 'Network' }];
    const result = parsePerformanceCategories(raw);
    expect(result).toEqual([{ id: 'interfaces', category: 'Network' }]);
  });

  it('handles array-wrapped response [[{...}]]', () => {
    const raw = [[{ id: 1, category: 'CPU' }, { id: 9, category: 'Disk' }]];
    const result = parsePerformanceCategories(raw);
    expect(result).toEqual([
      { id: '1', category: 'CPU' },
      { id: '9', category: 'Disk' },
    ]);
  });

  it('returns empty array for null input', () => {
    expect(parsePerformanceCategories(null)).toEqual([]);
  });

  it('returns empty array for undefined input', () => {
    expect(parsePerformanceCategories(undefined)).toEqual([]);
  });

  it('returns empty array for non-array input', () => {
    expect(parsePerformanceCategories('hello')).toEqual([]);
    expect(parsePerformanceCategories(42)).toEqual([]);
    expect(parsePerformanceCategories({})).toEqual([]);
  });
});

/* ------------------------------------------------------------------ */
/*  parsePerformanceInstances                                         */
/* ------------------------------------------------------------------ */
describe('parsePerformanceInstances', () => {
  const statGroup = 'myStatGroup';

  it('parses standard metric instances (type oid)', () => {
    const raw = [
      {
        key: 'cpu-1',
        title: 'CPU Utilization',
        unit: '%',
        type: 'oid',
        description: 'CPU Utilization',
        bandwidth: null,
      },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result).toEqual([
      { key: 'cpu-1', title: 'CPU Utilization', unit: '%', statGroup, valueKey: 'value1' },
    ]);
  });

  it('filters out per-process metrics (title contains "by Process")', () => {
    const raw = [
      { key: 'proc-1', title: 'CPU by Process', unit: '%', type: 'oid', description: '', bandwidth: null },
      { key: 'cpu-1', title: 'CPU Utilization', unit: '%', type: 'oid', description: '', bandwidth: null },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result).toHaveLength(1);
    expect(result[0].key).toBe('cpu-1');
  });

  it('filters out swap metrics (title contains "swap", case-insensitive)', () => {
    const raw = [
      { key: 'swap-1', title: 'Swap Usage', unit: '%', type: 'oid', description: '', bandwidth: null },
      { key: 'swap-2', title: 'SWAP Free', unit: 'MB', type: 'oid', description: '', bandwidth: null },
      { key: 'mem-1', title: 'Memory Usage', unit: '%', type: 'oid', description: '', bandwidth: null },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result).toHaveLength(1);
    expect(result[0].key).toBe('mem-1');
  });

  it('filters out raw-byte metrics (unit === "B")', () => {
    const raw = [
      { key: 'bytes-1', title: 'Disk Bytes', unit: 'B', type: 'oid', description: '', bandwidth: null },
      { key: 'disk-1', title: 'Disk %', unit: '%', type: 'oid', description: '', bandwidth: null },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result).toHaveLength(1);
    expect(result[0].key).toBe('disk-1');
  });

  it('creates in/out pairs for interface entries', () => {
    const raw = [
      {
        key: 'eth0',
        title: 'Ethernet',
        unit: '',
        type: 'interface',
        description: 'GigabitEthernet0/0',
        bandwidth: { unit: 'Mbps' },
      },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({
      key: 'eth0-in',
      title: 'GigabitEthernet0/0 — In',
      unit: 'Mbps',
      statGroup,
      valueKey: 'value1',
    });
    expect(result[1]).toEqual({
      key: 'eth0-out',
      title: 'GigabitEthernet0/0 — Out',
      unit: 'Mbps',
      statGroup,
      valueKey: 'value2',
    });
  });

  it('defaults interface unit to % when bandwidth.unit is missing', () => {
    const raw = [
      {
        key: 'eth1',
        title: 'Ethernet1',
        unit: '',
        type: 'interface',
        description: 'Port1',
        bandwidth: {},
      },
    ];
    const result = parsePerformanceInstances(raw, statGroup);
    expect(result[0].unit).toBe('%');
    expect(result[1].unit).toBe('%');
  });

  it('returns empty array for null/invalid input', () => {
    expect(parsePerformanceInstances(null, statGroup)).toEqual([]);
    expect(parsePerformanceInstances(undefined, statGroup)).toEqual([]);
    expect(parsePerformanceInstances('bad', statGroup)).toEqual([]);
  });
});

/* ------------------------------------------------------------------ */
/*  parseTimeSeriesResponse                                           */
/* ------------------------------------------------------------------ */
describe('parseTimeSeriesResponse', () => {
  it('parses datapoints from metrics array', () => {
    const raw = {
      metrics: [
        {
          instanceDescr: 'CPU Utilization',
          metricId: 'cpu-1',
          datapoints: [
            { '1712400000': '45.2', '1712403600': '52.8' },
          ],
        },
      ],
    };
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(1);
    expect(result[0].instanceDescr).toBe('CPU Utilization');
    expect(result[0].metricId).toBe('cpu-1');
    expect(result[0].datapoints).toEqual([
      { timestamp: 1712400000, value: 45.2 },
      { timestamp: 1712403600, value: 52.8 },
    ]);
  });

  it('sorts datapoints by timestamp', () => {
    const raw = {
      metrics: [
        {
          instanceDescr: 'test',
          metricId: 'm1',
          datapoints: [
            { '1712403600': '10', '1712400000': '20', '1712401800': '15' },
          ],
        },
      ],
    };
    const result = parseTimeSeriesResponse(raw);
    const timestamps = result[0].datapoints.map((d) => d.timestamp);
    expect(timestamps).toEqual([1712400000, 1712401800, 1712403600]);
  });

  it('handles multiple metrics in one response', () => {
    const raw = {
      metrics: [
        { instanceDescr: 'A', metricId: 'a', datapoints: [{ '100': '1' }] },
        { instanceDescr: 'B', metricId: 'b', datapoints: [{ '200': '2' }] },
      ],
    };
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(2);
  });

  it('returns empty array for missing/null metrics', () => {
    expect(parseTimeSeriesResponse(null)).toEqual([]);
    expect(parseTimeSeriesResponse(undefined)).toEqual([]);
    expect(parseTimeSeriesResponse({})).toEqual([]);
    expect(parseTimeSeriesResponse({ metrics: null })).toEqual([]);
  });

  it('handles array-wrapped response', () => {
    const raw = [
      {
        metrics: [
          {
            instanceDescr: 'CPU',
            metricId: 'cpu-1',
            datapoints: [{ '100': '50' }],
          },
        ],
      },
    ];
    const result = parseTimeSeriesResponse(raw);
    expect(result).toHaveLength(1);
    expect(result[0].instanceDescr).toBe('CPU');
  });
});
