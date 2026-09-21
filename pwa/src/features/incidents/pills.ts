import type { Incident } from '../../lib/api/types';

/** The five pills, and the definitions behind them.
 *
 * Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §1.
 *
 *   OPEN  = state OPEN, acknowledged or not
 *   ACKD  = { i in OPEN : i.acknowledged }        a SUBSET, not a fourth bucket
 *   CLRD  = state ALARMS CLEARED
 *   CLSD  = state CLOSED, inside the middleware's 24-hour retention window
 *   TOTL  = OPEN + CLRD + CLSD                    (ACKD is inside OPEN and is NOT added again)
 *
 * ACKD being a subset is the whole reason this module exists. Until middleware
 * 2.20.0 both clients computed acknowledgement by reading
 * `incident_state === 'ACKNOWLEDGED'` — a value BHNM never uses for a state —
 * so "acknowledged" and "alarms cleared" shared one field and could not both
 * be true.
 */
export type Pill = 'TOTL' | 'OPEN' | 'ACKD' | 'CLRD' | 'CLSD';

export const PILLS: readonly Pill[] = ['TOTL', 'OPEN', 'ACKD', 'CLRD', 'CLSD'];

/** Ruled 2026-09-21. The Home tile lands here too. */
export const DEFAULT_PILL: Pill = 'OPEN';

export function isPill(v: string | null | undefined): v is Pill {
  return !!v && (PILLS as readonly string[]).includes(v);
}

export function inPill(incident: Incident, pill: Pill): boolean {
  switch (pill) {
    case 'OPEN': return incident.state === 'OPEN';
    case 'ACKD': return incident.state === 'OPEN' && incident.acknowledged;
    case 'CLRD': return incident.state === 'ALARMS CLEARED';
    case 'CLSD': return incident.state === 'CLOSED';
    // Every state is one of the three, so this is the whole list — but it is
    // written as the union of the three rather than `true`, so that TOTL and
    // the sum of the parts cannot drift apart.
    case 'TOTL': return incident.state === 'OPEN'
      || incident.state === 'ALARMS CLEARED'
      || incident.state === 'CLOSED';
  }
}

export type PillCounts = Record<Pill, number>;

/** Counts are computed CLIENT-SIDE from the served list. There is no count
 * endpoint — the list is already in hand, and a second source would be a second
 * thing that can disagree with the rows on screen. */
export function pillCounts(incidents: readonly Incident[]): PillCounts {
  const counts: PillCounts = { TOTL: 0, OPEN: 0, ACKD: 0, CLRD: 0, CLSD: 0 };
  for (const i of incidents) {
    for (const p of PILLS) if (inPill(i, p)) counts[p]++;
  }
  return counts;
}

/** Search matches title, device name, incident id and ack user. */
export function matchesSearch(incident: Incident, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const haystack = [
    incident.summary,
    incident.deviceName,
    incident.deviceIp,
    incident.incidentId,
    incident.displayId,
    incident.ackUser,
    incident.acknowledgedBy,
  ];
  return haystack.some((h) => typeof h === 'string' && h.toLowerCase().includes(q));
}

/** The rows to render: the selected pill, then the search WITHIN it.
 *
 * Search never escapes the pill. A query that matches a closed incident while
 * OPEN is selected returns nothing rather than quietly widening the filter the
 * user chose — the pill is a statement about what is on screen, and search
 * must not falsify it.
 *
 * Sorted by id descending, matching the list's existing order.
 */
export function selectIncidents(
  incidents: readonly Incident[],
  pill: Pill,
  query: string,
): Incident[] {
  return incidents
    .filter((i) => inPill(i, pill) && matchesSearch(i, query))
    .sort((a, b) => Number(b.incidentId) - Number(a.incidentId));
}
