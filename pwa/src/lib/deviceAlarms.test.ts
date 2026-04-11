import { describe, it, expect } from 'vitest';
import { buildDeviceAlarmMap } from './deviceAlarms';
import type { Incident } from './api/types';

function incident(overrides: Partial<Incident>): Incident {
  return {
    incidentId: '1',
    displayId: '#1',
    deviceName: 'host-a',
    deviceIp: '1.2.3.4',
    summary: 'Test incident',
    severity: 'critical',
    status: 'active',
    incidentState: 'OPEN',
    startTime: new Date(),
    acknowledgedBy: null,
    alarmCounts: null,
    ...overrides,
  };
}

describe('buildDeviceAlarmMap', () => {
  it('returns empty map for empty incidents', () => {
    expect(buildDeviceAlarmMap([]).size).toBe(0);
  });

  it('counts critical active as red', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'critical', status: 'active' })]);
    expect(map.get('host-a')?.counts.red).toBe(1);
  });

  it('counts major/minor active as orange', () => {
    const map = buildDeviceAlarmMap([
      incident({ severity: 'major', status: 'active' }),
      incident({ incidentId: '2', severity: 'minor', status: 'active' }),
    ]);
    expect(map.get('host-a')?.counts.orange).toBe(2);
  });

  it('counts warning active as yellow', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'warning', status: 'active' })]);
    expect(map.get('host-a')?.counts.yellow).toBe(1);
  });

  it('counts acknowledged as blue regardless of severity', () => {
    const map = buildDeviceAlarmMap([incident({ severity: 'critical', status: 'acknowledged' })]);
    expect(map.get('host-a')?.counts.blue).toBe(1);
    expect(map.get('host-a')?.counts.red).toBe(0);
  });

  it('counts resolved/closed as green', () => {
    const map = buildDeviceAlarmMap([
      incident({ status: 'resolved' }),
      incident({ incidentId: '2', status: 'closed' }),
    ]);
    expect(map.get('host-a')?.counts.green).toBe(2);
  });

  it('collects activeSummaries only for active incidents, critical first', () => {
    const map = buildDeviceAlarmMap([
      incident({ incidentId: '1', severity: 'warning', status: 'active', summary: 'Warn msg' }),
      incident({ incidentId: '2', severity: 'critical', status: 'active', summary: 'Crit msg' }),
      incident({ incidentId: '3', severity: 'critical', status: 'acknowledged', summary: 'Acked' }),
    ]);
    const summaries = map.get('host-a')?.activeSummaries ?? [];
    expect(summaries[0]).toBe('Crit msg');
    expect(summaries[1]).toBe('Warn msg');
    expect(summaries).not.toContain('Acked');
  });

  it('groups incidents by deviceName', () => {
    const map = buildDeviceAlarmMap([
      incident({ deviceName: 'host-a', severity: 'critical', status: 'active' }),
      incident({ deviceName: 'host-b', severity: 'warning', status: 'active' }),
    ]);
    expect(map.get('host-a')?.counts.red).toBe(1);
    expect(map.get('host-b')?.counts.yellow).toBe(1);
  });

  it('ignores incidents with null deviceName', () => {
    const map = buildDeviceAlarmMap([incident({ deviceName: null })]);
    expect(map.size).toBe(0);
  });
});
