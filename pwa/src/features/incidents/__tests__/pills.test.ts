import { describe, it, expect } from 'vitest';
import { parseIncidentsResponse } from '../../../lib/api/incidents';
import {
  DEFAULT_PILL,
  PILLS,
  inPill,
  matchesSearch,
  pillCounts,
  selectIncidents,
} from '../pills';

/** The nine from the design note's §5, against the REAL selector and the REAL
 * parseIncidentsResponse — never a reimplementation of either.
 *
 * Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §5.
 * The iOS suite must stay symmetrical with this one: the two platforms derive
 * status with identical logic today, and they will drift the moment one side's
 * tests stop matching.
 */

// A served payload as middleware 2.20.0 actually produces one.
const SERVED = {
  cache_age_seconds: 12,
  active_incidents: [
    { incident_id: '30005', name: 'UAP-AC-Pro-DB', title: 'Anomaly Bandwidth on UAP-AC-Pro-DB',
      state: 'OPEN', acknowledged: false, ack_user: null, closed_at: null,
      incident_state: 'OPEN', open_time: '2026-09-21T17:40:10', alert_type: 'anomaly' },
    { incident_id: '27516', name: 'C9200CX', title: 'Service Configuration Save Check on C9200CX',
      state: 'OPEN', acknowledged: true, ack_user: 'Thomas iPhone 13 ProMax', closed_at: null,
      incident_state: 'ACKNOWLEDGED', open_time: '2026-09-01T11:16:12', alert_type: 'service' },
    { incident_id: '30014', name: 'UAP_AC_M', title: 'Anomaly Bandwidth on UAP_AC_M',
      state: 'ALARMS CLEARED', acknowledged: false, ack_user: null, closed_at: null,
      incident_state: 'ALARMS CLEARED', open_time: '2026-09-21T17:55:09', alert_type: 'anomaly' },
  ],
  closed_incidents: [
    { incident_id: '30007', name: 'raspi-050', title: 'Host raspi-050',
      state: 'CLOSED', acknowledged: false, ack_user: null, closed_at: 1789928537.339,
      incident_state: 'CLOSED', open_time: '2026-09-21T16:14:13', alert_type: 'host' },
  ],
};

const parsed = () => parseIncidentsResponse(SERVED);

describe('the five pills', () => {
  it('OPEN is unacknowledged ONLY', () => {
    // Ruled 2026-09-21 (Thomas): the five are DISJOINT. The design note had
    // ACKD as a subset of OPEN; it is a peer.
    const open = selectIncidents(parsed(), 'OPEN', '');
    expect(open.map((i) => i.incidentId)).toEqual(['30005']);
    expect(open.some((i) => i.acknowledged)).toBe(false);
  });

  it('the five pills are DISJOINT', () => {
    const list = parsed();
    for (const i of list) {
      const member = PILLS.filter((p) => p !== 'TOTL' && inPill(i, p));
      expect(member, `incident ${i.incidentId}`).toHaveLength(1);
    }
    const c = pillCounts(list);
    expect([c.OPEN, c.ACKD, c.CLRD, c.CLSD]).toEqual([1, 1, 1, 1]);
    // TOTL is the union of the first three, and EXCLUDES CLSD.
    expect(c.TOTL).toBe(c.OPEN + c.ACKD + c.CLRD);
    expect(c.TOTL).toBe(3);
  });

  it('CLRD is exactly state ALARMS CLEARED', () => {
    expect(selectIncidents(parsed(), 'CLRD', '').map((i) => i.incidentId)).toEqual(['30014']);
  });

  it('CLSD is exactly state CLOSED', () => {
    expect(selectIncidents(parsed(), 'CLSD', '').map((i) => i.incidentId)).toEqual(['30007']);
  });

  it('the Home tile count equals the TOTL pill count', () => {
    // The tile IS the TOTL pill. The same class of defect as 2026-09-19: the
    // tile and the list computed the same idea twice, and one of them dropped
    // acknowledged incidents.
    const list = parsed();
    expect(pillCounts(list).TOTL).toBe(selectIncidents(list, 'TOTL', '').length);
  });

  it('the tile count does NOT drop when somebody acknowledges', () => {
    // Why the tile is TOTL and not OPEN. With disjoint pills an OPEN count
    // would fall the moment a user acted — the 0.18.1 defect by another route.
    const before = pillCounts(parsed()).TOTL;
    const acked = {
      ...SERVED,
      active_incidents: SERVED.active_incidents.map((r) =>
        r.incident_id === '30005'
          ? { ...r, acknowledged: true, incident_state: 'ACKNOWLEDGED', ack_user: 'Someone' }
          : r),
    };
    const after = pillCounts(parseIncidentsResponse(acked));
    expect(after.TOTL).toBe(before);
    expect(after.OPEN).toBe(0);
    expect(after.OPEN).not.toBe(after.TOTL);
  });

  it('the default pill is TOTL', () => {
    expect(DEFAULT_PILL).toBe('TOTL');
  });

  it('TOTL excludes closed incidents', () => {
    // Ruled 2026-09-21 (Thomas), changing the design note. TOTL is the default
    // tab, and a closed incident is not something to show somebody before they
    // have asked for it. CLSD is the one tab you opt into.
    const list = parsed();
    expect(selectIncidents(list, 'TOTL', '').map((i) => i.incidentId).sort())
      .toEqual(['27516', '30005', '30014']);
    expect(selectIncidents(list, 'TOTL', '').some((i) => i.state === 'CLOSED')).toBe(false);
    expect(selectIncidents(list, 'TOTL', '').some((i) => i.acknowledged)).toBe(true);
    expect(pillCounts(list).CLSD).toBe(1);
    const closed = list.find((i) => i.state === 'CLOSED')!;
    expect(PILLS.filter((p) => inPill(closed, p))).toEqual(['CLSD']);
  });

  it('acking moves a row from OPEN to ACKD and leaves TOTL unmoved', () => {
    // With disjoint pills an ack DOES move the row out of OPEN — by design.
    // **What keeps that from being the 2026-09-19 defect is that TOTL is the
    // default tab**, so the row is still on the screen the user was looking at.
    const before = pillCounts(parsed());
    const acked = {
      ...SERVED,
      active_incidents: SERVED.active_incidents.map((r) =>
        r.incident_id === '30005'
          ? { ...r, acknowledged: true, incident_state: 'ACKNOWLEDGED', ack_user: 'Someone' }
          : r),
    };
    const after = pillCounts(parseIncidentsResponse(acked));
    expect(after.OPEN).toBe(0);
    expect(after.ACKD).toBe(2);
    expect(after.TOTL).toBe(before.TOTL);
    expect(DEFAULT_PILL).toBe('TOTL');
  });
});

describe('search', () => {
  it('matches title, device, incident id and ack user within the selected pill', () => {
    const list = parsed();
    expect(selectIncidents(list, 'OPEN', 'Anomaly').map((i) => i.incidentId)).toEqual(['30005']);
    // 27516 is acknowledged, so it lives in ACKD now.
    expect(selectIncidents(list, 'ACKD', 'c9200').map((i) => i.incidentId)).toEqual(['27516']);
    expect(selectIncidents(list, 'ACKD', '27516').map((i) => i.incidentId)).toEqual(['27516']);
    expect(selectIncidents(list, 'ACKD', 'ProMax').map((i) => i.incidentId)).toEqual(['27516']);
  });

  it('does NOT escape the selected pill', () => {
    // raspi-050 exists and matches, but it is CLOSED. A search that widened the
    // filter would falsify the pill, which is a statement about what is on screen.
    const list = parsed();
    expect(selectIncidents(list, 'OPEN', 'raspi')).toEqual([]);
    expect(selectIncidents(list, 'CLSD', 'raspi').map((i) => i.incidentId)).toEqual(['30007']);
  });

  it('an empty query matches everything in the pill', () => {
    const list = parsed();
    for (const q of ['', '   ']) {
      expect(selectIncidents(list, 'TOTL', q)).toHaveLength(3);
    }
    expect(list.every((i) => matchesSearch(i, ''))).toBe(true);
  });
});

describe('the transition fallback', () => {
  it('a row with no state field falls back to incident_state, ACKNOWLEDGED included', () => {
    // A middleware older than 2.20.0, or the legacy getincidents fall-through.
    const old = {
      active_incidents: [
        { incident_id: '1', title: 'a', incident_state: 'OPEN' },
        { incident_id: '2', title: 'b', incident_state: 'ACKNOWLEDGED' },
        { incident_id: '3', title: 'c', incident_state: 'ALARMS CLEARED' },
      ],
      closed_incidents: [{ incident_id: '4', title: 'd', incident_state: 'CLOSED' }],
    };
    const c = pillCounts(parseIncidentsResponse(old));
    expect(c).toEqual({ TOTL: 3, OPEN: 1, ACKD: 1, CLRD: 1, CLSD: 1 });

    const acked = parseIncidentsResponse(old).find((i) => i.incidentId === '2')!;
    expect(acked.state).toBe('OPEN');
    expect(acked.acknowledged).toBe(true);
  });

  it('a closed_incidents row with no state field is still CLOSED', () => {
    // The bucket is the only signal an older middleware gives.
    const old = { active_incidents: [], closed_incidents: [{ incident_id: '9', title: 'x' }] };
    const [row] = parseIncidentsResponse(old);
    expect(row.state).toBe('CLOSED');
    expect(inPill(row, 'CLSD')).toBe(true);
  });

  it('an unrecognised state becomes OPEN rather than vanishing', () => {
    // TOTL is OPEN + CLRD, so a state in neither — and not CLOSED — would drop
    // the row out of EVERY pill. Mirrors the middleware's own state_of().
    const odd = { active_incidents: [{ incident_id: '7', title: 'z', state: 'SOMETHING NEW' }] };
    const [row] = parseIncidentsResponse(odd);
    expect(row.state).toBe('OPEN');
    expect(PILLS.filter((p) => inPill(row, p))).toEqual(['TOTL', 'OPEN']);
  });
});

describe('a closed row', () => {
  it('parses with its closed_at and renders under CLSD', () => {
    const row = parsed().find((i) => i.incidentId === '30007')!;
    expect(row.state).toBe('CLOSED');
    expect(row.closedAt).toBeInstanceOf(Date);
    expect(row.closedAt!.getTime()).toBe(Math.round(1789928537.339 * 1000));
    expect(inPill(row, 'CLSD')).toBe(true);
    expect(inPill(row, 'TOTL')).toBe(false);
    expect(inPill(row, 'OPEN')).toBe(false);
  });

  it('carries its ack user through to search', () => {
    const row = parsed().find((i) => i.incidentId === '27516')!;
    expect(row.ackUser).toBe('Thomas iPhone 13 ProMax');
  });
});
