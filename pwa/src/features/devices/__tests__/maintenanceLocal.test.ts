import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import {
  noteLocalMaintenance,
  clearLocalMaintenance,
  noteLocalClose,
  getPendingStart,
  getPendingNames,
  getRecentLocalClose,
  _resetLocalMaintenance,
} from '../useMaintenanceMap';

describe('local maintenance store (survives navigation)', () => {
  beforeEach(() => _resetLocalMaintenance());
  afterEach(() => vi.useRealTimers());

  it('remembers the pending start per device', () => {
    const start = new Date(Date.now() + 5 * 60_000);
    noteLocalMaintenance('sw-01', start);
    expect(getPendingStart('sw-01')?.getTime()).toBe(start.getTime());
    expect(getPendingStart('other')).toBeNull();
    expect(getPendingNames()).toEqual(new Set(['sw-01']));
  });

  it('clear removes a noted device (cancel path)', () => {
    noteLocalMaintenance('sw-01', new Date());
    clearLocalMaintenance('sw-01');
    expect(getPendingStart('sw-01')).toBeNull();
    expect(getPendingNames()).toEqual(new Set());
  });

  it('a note expires ~4 min past its start time', () => {
    vi.useFakeTimers();
    const start = new Date(Date.now() + 5 * 60_000);
    noteLocalMaintenance('sw-01', start);
    vi.advanceTimersByTime(5 * 60_000 + 3 * 60_000); // start passed + 3 min
    expect(getPendingStart('sw-01')).not.toBeNull();
    vi.advanceTimersByTime(2 * 60_000); // now > start + 4 min
    expect(getPendingStart('sw-01')).toBeNull();
  });

  it('noteLocalClose records a recent close and drops the pending note', () => {
    noteLocalMaintenance('sw-01', new Date());
    noteLocalClose('sw-01');
    expect(getPendingStart('sw-01')).toBeNull();
    expect(getRecentLocalClose('sw-01')).not.toBeNull();
    expect(getRecentLocalClose('other')).toBeNull();
  });

  it('a recent close expires after ~3 min (defers to the server again)', () => {
    vi.useFakeTimers();
    noteLocalClose('sw-01');
    vi.advanceTimersByTime(4 * 60_000);
    expect(getRecentLocalClose('sw-01')).toBeNull();
  });
});
