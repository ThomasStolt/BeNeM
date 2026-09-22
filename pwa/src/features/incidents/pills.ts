import type { Incident } from '../../lib/api/types';

/** The five pills, and the definitions behind them.
 *
 * Design: docs/superpowers/specs/2026-09-21-incident-list-filter-design.md §1.
 *
 *   OPEN  = state OPEN and NOT acknowledged
 *   ACKD  = state OPEN and acknowledged
 *   CLRD  = state ALARMS CLEARED
 *   CLOSED  = state CLOSED, inside the middleware's 24-hour retention window
 *   TOTAL  = OPEN + ACKD + CLRD                    everything EXCEPT closed
 *
 * **The five are DISJOINT, and TOTAL excludes CLOSED. Ruled 2026-09-21 (Thomas),
 * changing the design note twice over.** The note had ACKD as a *subset* of
 * OPEN and `TOTAL = OPEN + CLRD + CLOSED`; it is neither. Every incident is in
 * exactly one of OPEN / ACKD / CLRD / CLOSED, and TOTAL is the union of the first
 * three — which makes TOTAL exactly "not closed", the predicate this product has
 * called "active" since 0.18.1.
 *
 * **Acknowledging therefore MOVES a row from OPEN to ACKD.** That is the
 * 2026-09-19 symptom by design rather than by accident, and the thing that keeps
 * it from being the 2026-09-19 *defect* is that **TOTAL is the default tab**: the
 * row the user just acked is still on the screen they were on. Anything that
 * changes the default away from TOTAL re-opens that wound.
 *
 * Splitting the state from the flag is still the whole reason this module
 * exists. Until middleware 2.20.0 both clients computed acknowledgement by
 * reading `incident_state === 'ACKNOWLEDGED'` — a value BHNM never uses for a
 * state — so "acknowledged" and "alarms cleared" shared one field and could not
 * both be true.
 */
export type Pill = 'TOTAL' | 'OPEN' | 'ACKD' | 'CLRD' | 'CLOSED';

export const PILLS: readonly Pill[] = ['TOTAL', 'OPEN', 'ACKD', 'CLRD', 'CLOSED'];

/** Ruled 2026-09-21 (Thomas): the list opens on TOTAL — everything that is not
 * closed. **The Home tile still lands on OPEN and still counts OPEN** (Q5); the
 * tile names its pill in the URL rather than relying on this. */
export const DEFAULT_PILL: Pill = 'TOTAL';

export function isPill(v: string | null | undefined): v is Pill {
  return !!v && (PILLS as readonly string[]).includes(v);
}

export function inPill(incident: Incident, pill: Pill): boolean {
  switch (pill) {
    case 'OPEN': return incident.state === 'OPEN' && !incident.acknowledged;
    case 'ACKD': return incident.state === 'OPEN' && incident.acknowledged;
    case 'CLRD': return incident.state === 'ALARMS CLEARED';
    case 'CLOSED': return incident.state === 'CLOSED';
    // Written as the union of its parts rather than `state !== 'CLOSED'`, so
    // that TOTAL and the sum of the pills beside it cannot drift apart.
    case 'TOTAL': return inPill(incident, 'OPEN')
      || inPill(incident, 'ACKD')
      || inPill(incident, 'CLRD');
  }
}

export type PillCounts = Record<Pill, number>;

/** Counts are computed CLIENT-SIDE from the served list. There is no count
 * endpoint — the list is already in hand, and a second source would be a second
 * thing that can disagree with the rows on screen. */
export function pillCounts(incidents: readonly Incident[]): PillCounts {
  const counts: PillCounts = { TOTAL: 0, OPEN: 0, ACKD: 0, CLRD: 0, CLOSED: 0 };
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
