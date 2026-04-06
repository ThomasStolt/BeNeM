import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { RefreshCountdown } from '../RefreshCountdown';

afterEach(() => {
  vi.useRealTimers();
});

describe('RefreshCountdown', () => {
  it('displays remaining seconds', () => {
    const now = Date.now();
    render(<RefreshCountdown lastUpdatedAt={now} intervalMs={120_000} />);
    expect(screen.getByText(/2:00/)).toBeInTheDocument();
  });

  it('counts down over time', () => {
    vi.useFakeTimers();
    const now = Date.now();
    render(<RefreshCountdown lastUpdatedAt={now} intervalMs={120_000} />);
    act(() => { vi.advanceTimersByTime(10_000); });
    expect(screen.getByText(/1:50/)).toBeInTheDocument();
  });

  it('shows 0:00 when past interval', () => {
    const past = Date.now() - 130_000;
    render(<RefreshCountdown lastUpdatedAt={past} intervalMs={120_000} />);
    expect(screen.getByText(/0:00/)).toBeInTheDocument();
  });
});
