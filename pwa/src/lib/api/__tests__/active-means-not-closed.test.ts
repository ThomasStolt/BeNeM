/**
 * "Active" means NOT CLOSED.
 *
 * Observed on a phone 2026-09-19 (iOS): acknowledging an incident from the app
 * made it vanish from the list, because the Home tile filtered to
 * `status === 'active'` and `'acknowledged'` is a separate value of the same
 * union. The PWA's tile links to an UNFILTERED list, so the row stayed — but
 * the count dropped the moment the user acted. Same defect, quieter symptom.
 *
 * An acknowledged incident is still open and still the user's problem, and
 * BHNM's own UI keeps it.
 */
import { describe, it, expect } from 'vitest';
import { isActiveIncident } from '../incidents';

describe('isActiveIncident', () => {
  it('counts an ACKNOWLEDGED incident as active', () => {
    expect(isActiveIncident({ status: 'acknowledged' })).toBe(true);
  });

  it('counts an open incident as active', () => {
    expect(isActiveIncident({ status: 'active' })).toBe(true);
  });

  it('does NOT count resolved or closed', () => {
    expect(isActiveIncident({ status: 'resolved' })).toBe(false);
    expect(isActiveIncident({ status: 'closed' })).toBe(false);
  });

  it('the tile count does not drop when somebody acknowledges', () => {
    const before = [
      { status: 'active' as const },
      { status: 'active' as const },
      { status: 'closed' as const },
    ];
    // The same set, after one incident is acknowledged.
    const after = [
      { status: 'active' as const },
      { status: 'acknowledged' as const },
      { status: 'closed' as const },
    ];
    expect(after.filter(isActiveIncident).length)
      .toBe(before.filter(isActiveIncident).length);
    expect(after.filter(isActiveIncident).length).toBe(2);
  });
});
