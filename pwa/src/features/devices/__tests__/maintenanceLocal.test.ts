import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
  noteLocalMaintenance,
  clearLocalMaintenance,
  withLocalMaintenance,
  _resetLocalMaintenance,
} from '../useMaintenanceMap';

describe('local maintenance optimism', () => {
  beforeEach(() => _resetLocalMaintenance());
  afterEach(() => vi.useRealTimers());

  it('unions locally noted names into the fetched set', () => {
    noteLocalMaintenance('sw-01');
    const set = withLocalMaintenance(new Set(['srv-09']));
    expect(set).toEqual(new Set(['srv-09', 'sw-01']));
  });

  it('clear removes a noted name (close/cancel path)', () => {
    noteLocalMaintenance('sw-01');
    clearLocalMaintenance('sw-01');
    expect(withLocalMaintenance(new Set())).toEqual(new Set());
  });

  it('noted names expire after the grace period', () => {
    vi.useFakeTimers();
    noteLocalMaintenance('sw-01');
    vi.advanceTimersByTime(9 * 60_000);
    expect(withLocalMaintenance(new Set())).toEqual(new Set());
  });

  it('a server set that already contains the name is unaffected', () => {
    noteLocalMaintenance('sw-01');
    expect(withLocalMaintenance(new Set(['sw-01']))).toEqual(new Set(['sw-01']));
  });
});
