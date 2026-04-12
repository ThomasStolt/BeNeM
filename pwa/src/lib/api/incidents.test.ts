import { describe, it, expect } from 'vitest';
import { parseIncidentsResponse, buildDisplayId, parseAckResponse, parseIncidentDetailResponse } from './incidents';
import mock from '../mock/incidents.json';
import detailMock from '../mock/incident-detail.json';

describe('buildDisplayId', () => {
  it('strips prefix before last dash and prepends #', () => {
    expect(buildDisplayId('NetreoCloudDemo-58431')).toBe('#58431');
  });
  it('prepends # to bare numeric ids', () => {
    expect(buildDisplayId('58431')).toBe('#58431');
  });
  it('preserves leading # if already present', () => {
    expect(buildDisplayId('#58431')).toBe('#58431');
  });
});

describe('parseIncidentsResponse', () => {
  it('parses array-wrapped response with active + closed incidents', () => {
    const incidents = parseIncidentsResponse(mock);
    expect(incidents).toHaveLength(3);
    expect(incidents[0].incidentId).toBe('58431');
    expect(incidents[0].severity).toBe('critical');
    expect(incidents[0].status).toBe('active');
    expect(incidents[0].displayId).toBe('#58431');
  });

  it('forces closed_incidents to resolved status', () => {
    const incidents = parseIncidentsResponse(mock);
    const closed = incidents.find((i) => i.incidentId === '58400');
    expect(closed).toBeDefined();
    expect(closed!.status).toBe('resolved');
  });

  it('maps alert_level=major to severity=major', () => {
    const incidents = parseIncidentsResponse(mock);
    const ack = incidents.find((i) => i.displayId === '#58432');
    expect(ack).toBeDefined();
    expect(ack!.severity).toBe('major');
    expect(ack!.status).toBe('acknowledged');
    expect(ack!.acknowledgedBy).toBe('oncall@example.com');
  });

  it('handles plain object (non-array) response', () => {
    const plain = {
      active_incidents: [
        { incident_id: 1, title: 'x', name: 'host', incident_state: 'OPEN', severity: 'warning', start_time: 1712000000 },
      ],
      success: true,
    };
    const incidents = parseIncidentsResponse(plain);
    expect(incidents).toHaveLength(1);
    expect(incidents[0].severity).toBe('warning');
  });

  it('falls back to critical when severity is missing', () => {
    const plain = {
      active_incidents: [
        { incident_id: 2, title: 'y', name: 'h', incident_state: 'OPEN', start_time: 1712000000 },
      ],
    };
    const incidents = parseIncidentsResponse(plain);
    expect(incidents[0].severity).toBe('critical');
  });

  it('throws ApiException kind=server when success=false', () => {
    const plain = { success: false, error: 'Bad key' };
    expect(() => parseIncidentsResponse(plain)).toThrow(/Bad key/);
  });

  it('returns empty array on unrecognised shape', () => {
    expect(parseIncidentsResponse({})).toEqual([]);
  });

  it('parses start_time from incident_open_time field when start_time absent', () => {
    const payload = {
      active_incidents: [
        {
          incident_id: 99,
          title: 'test',
          name: 'host',
          incident_state: 'OPEN',
          severity: 'critical',
          incident_open_time: 1712332800,
        },
      ],
    };
    const incidents = parseIncidentsResponse(payload);
    expect(incidents[0].startTime.getTime()).toBe(1712332800 * 1000);
  });

  it('parses start_time from open_time field when start_time absent', () => {
    const payload = {
      active_incidents: [
        {
          incident_id: 100,
          title: 'test2',
          name: 'host2',
          incident_state: 'OPEN',
          severity: 'major',
          open_time: 1712332800,
        },
      ],
    };
    const incidents = parseIncidentsResponse(payload);
    expect(incidents[0].startTime.getTime()).toBe(1712332800 * 1000);
  });

  it('parses start_time from startTime camelCase field when start_time absent', () => {
    const payload = {
      active_incidents: [
        {
          incident_id: 101,
          title: 'camel',
          name: 'host3',
          incident_state: 'OPEN',
          severity: 'minor',
          startTime: 1712332800,
        },
      ],
    };
    const incidents = parseIncidentsResponse(payload);
    expect(incidents[0].startTime.getTime()).toBe(1712332800 * 1000);
  });

  it('startTime falls back to a recent Date when all time fields absent', () => {
    const before = Date.now();
    const payload = {
      active_incidents: [
        { incident_id: 102, title: 'no-time', name: 'host4', incident_state: 'OPEN', severity: 'major' },
      ],
    };
    const incidents = parseIncidentsResponse(payload);
    const after = Date.now();
    expect(incidents[0].startTime.getTime()).toBeGreaterThanOrEqual(before);
    expect(incidents[0].startTime.getTime()).toBeLessThanOrEqual(after);
  });
});

describe('parseAckResponse', () => {
  it('parses successful ACK response', () => {
    const raw = { result: 'completed', detail: 'This incident has been ACKNOWLEDGED.' };
    expect(() => parseAckResponse(raw)).not.toThrow();
  });

  it('parses array-wrapped ACK response', () => {
    const raw = [{ result: 'completed', detail: 'ACKNOWLEDGED' }];
    expect(() => parseAckResponse(raw)).not.toThrow();
  });

  it('throws on failure response', () => {
    const raw = { result: 'failed', detail: 'Incident not found' };
    expect(() => parseAckResponse(raw)).toThrow(/Incident not found/);
  });

  it('throws on unrecognised shape', () => {
    expect(() => parseAckResponse(null)).toThrow();
  });
});

describe('parseIncidentDetailResponse', () => {
  it('parses incidentId, title, deviceName and deviceIp', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.incidentId).toBe('58431');
    expect(d.title).toBe('CPU utilization high on core-switch-01');
    expect(d.deviceName).toBe('core-switch-01');
    expect(d.deviceIp).toBe('10.0.0.1');
  });

  it('parses openTime from incident_open_time ISO string', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.openTime).toBeInstanceOf(Date);
    expect(d.openTime!.toISOString()).toMatch(/^2026-04-12/);
  });

  it('parses primaryAlarms with HTML stripped from output', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.primaryAlarms).toHaveLength(2);
    expect(d.primaryAlarms[0].state).toBe('CRITICAL');
    expect(d.primaryAlarms[0].name).toBe('core-switch-01');
    expect(d.primaryAlarms[0].output).not.toMatch(/<br/);
    expect(d.primaryAlarms[0].output).toContain('Packet loss');
  });

  it('parses relatedAlarms', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.relatedAlarms).toHaveLength(1);
    expect(d.relatedAlarms[0].state).toBe('OK');
  });

  it('parses incidentLog entries', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.incidentLog).toHaveLength(2);
    expect(d.incidentLog[1].username).toBe('thomas.stolt');
    expect(d.incidentLog[1].comment).toBe('Investigating — core switch unreachable');
  });

  it('computes alarmCounts from primary + related alarms', () => {
    const d = parseIncidentDetailResponse(detailMock);
    // primary: CRITICAL → red, MAJOR → orange; related: OK → green
    expect(d.alarmCounts.red).toBe(1);
    expect(d.alarmCounts.orange).toBe(1);
    expect(d.alarmCounts.green).toBe(1);
    expect(d.alarmCounts.yellow).toBe(0);
    expect(d.alarmCounts.blue).toBe(0);
  });

  it('returns acknowledged=false when field is 0', () => {
    const d = parseIncidentDetailResponse(detailMock);
    expect(d.acknowledged).toBe(false);
  });

  it('returns acknowledged=true when field is 1', () => {
    const acked = { incident: { ...detailMock.incident, acknowledged: 1, ack_user: 'alice', ack_time: '2026-04-12T10:00:00', ack_comment: 'on it' } };
    const d = parseIncidentDetailResponse(acked);
    expect(d.acknowledged).toBe(true);
    expect(d.ackUser).toBe('alice');
    expect(d.ackComment).toBe('on it');
  });

  it('handles array-wrapped response', () => {
    const d = parseIncidentDetailResponse([detailMock]);
    expect(d.incidentId).toBe('58431');
  });

  it('throws ApiException on missing incident key', () => {
    expect(() => parseIncidentDetailResponse({})).toThrow();
  });

  it('returns empty arrays when detail key is missing', () => {
    const d = parseIncidentDetailResponse({ incident: { incident_id: '1', incident_state: 'OPEN' } });
    expect(d.primaryAlarms).toHaveLength(0);
    expect(d.relatedAlarms).toHaveLength(0);
    expect(d.incidentLog).toHaveLength(0);
    expect(d.alarmCounts.red).toBe(0);
  });
});
