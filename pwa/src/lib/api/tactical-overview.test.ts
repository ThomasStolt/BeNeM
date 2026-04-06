import { describe, it, expect } from 'vitest';
import { parseTacticalResponse, sumTacticalGroups } from './tactical-overview';

const MOCK_RESPONSE = {
  'Servers': {
    Status: {
      host_ok_count: 10, host_ack_count: 1, host_warn_count: 2, host_un_count: 0, host_crit_count: 3,
      service_ok_count: 20, service_ack_count: 0, service_warn_count: 1, service_un_count: 0, service_crit_count: 1,
      threshold_ok_count: 5, threshold_ack_count: 0, threshold_warn_count: 0, threshold_un_count: 0, threshold_crit_count: 0,
      anom_threshold_ok_count: 2, anom_threshold_ack_count: 0, anom_threshold_warn_count: 1, anom_threshold_un_count: 0, anom_threshold_crit_count: 0,
    },
  },
  'Network': {
    Status: {
      host_ok_count: 5, host_ack_count: 0, host_warn_count: 0, host_un_count: 1, host_crit_count: 0,
      service_ok_count: 8, service_ack_count: 2, service_warn_count: 0, service_un_count: 0, service_crit_count: 0,
      threshold_ok_count: 3, threshold_ack_count: 0, threshold_warn_count: 1, threshold_un_count: 0, threshold_crit_count: 0,
      anom_threshold_ok_count: 0, anom_threshold_ack_count: 0, anom_threshold_warn_count: 0, anom_threshold_un_count: 0, anom_threshold_crit_count: 0,
    },
  },
};

describe('parseTacticalResponse', () => {
  it('parses groups from BHNM response', () => {
    const groups = parseTacticalResponse(MOCK_RESPONSE);
    expect(groups).toHaveLength(2);
    expect(groups[0].name).toBe('Servers');
    expect(groups[0].hosts).toEqual({ ok: 10, ack: 1, warn: 2, un: 0, crit: 3 });
    expect(groups[0].services).toEqual({ ok: 20, ack: 0, warn: 1, un: 0, crit: 1 });
    expect(groups[1].name).toBe('Network');
    expect(groups[1].hosts.ok).toBe(5);
  });

  it('handles array-wrapped response', () => {
    const groups = parseTacticalResponse([MOCK_RESPONSE]);
    expect(groups).toHaveLength(2);
  });

  it('returns empty array for invalid input', () => {
    expect(parseTacticalResponse(null)).toEqual([]);
    expect(parseTacticalResponse({})).toEqual([]);
  });
});

describe('sumTacticalGroups', () => {
  it('sums counts across all groups', () => {
    const groups = parseTacticalResponse(MOCK_RESPONSE);
    const totals = sumTacticalGroups(groups);
    expect(totals.hosts).toEqual({ ok: 15, ack: 1, warn: 2, un: 1, crit: 3 });
    expect(totals.services).toEqual({ ok: 28, ack: 2, warn: 1, un: 0, crit: 1 });
    expect(totals.thresholds).toEqual({ ok: 8, ack: 0, warn: 1, un: 0, crit: 0 });
    expect(totals.anomalies).toEqual({ ok: 2, ack: 0, warn: 1, un: 0, crit: 0 });
  });

  it('returns zeros for empty groups', () => {
    const totals = sumTacticalGroups([]);
    expect(totals.hosts).toEqual({ ok: 0, ack: 0, warn: 0, un: 0, crit: 0 });
  });
});
