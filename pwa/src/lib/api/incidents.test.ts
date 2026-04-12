import { describe, it, expect } from 'vitest';
import { parseIncidentsResponse, buildDisplayId, parseAckResponse } from './incidents';
import mock from '../mock/incidents.json';

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
