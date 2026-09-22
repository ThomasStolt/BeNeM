import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it('shows OPEN in red for an unacknowledged open incident', () => {
    const { container } = render(<StatusBadge state="OPEN" acknowledged={false} />);
    expect(screen.getByText('OPEN')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-red-600');
  });

  it('shows ACKD in blue for an acknowledged open incident', () => {
    const { container } = render(<StatusBadge state="OPEN" acknowledged={true} />);
    expect(screen.getByText('ACKD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-blue-600');
  });

  it('shows CLRD in green for ALARMS CLEARED', () => {
    const { container } = render(<StatusBadge state="ALARMS CLEARED" acknowledged={false} />);
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });

  it('shows CLRD, not ACKD, when an acknowledged incident has its alarms cleared', () => {
    // Ruled 2026-09-21 (Q3): ACKD stays a subset of OPEN exactly as defined, so
    // an acked incident whose alarms clear appears in CLRD and not in ACKD.
    const { container } = render(<StatusBadge state="ALARMS CLEARED" acknowledged={true} />);
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });

  it('shows CLOSED in grey for CLOSED — NOT the green CLRD chip', () => {
    // The defect this replaces: until 0.19.0, `status === 'closed'` and the
    // literal 'ALARMS CLEARED' shared one branch, so a closed incident and a
    // cleared one rendered the SAME green CLRD chip. They are different facts.
    const { container } = render(<StatusBadge state="CLOSED" acknowledged={false} />);
    expect(screen.getByText('CLOSED')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-slate-500');
    expect(screen.queryByText('CLRD')).not.toBeInTheDocument();
  });

  it('shows CLOSED for a CLOSED incident that was acknowledged before it closed', () => {
    render(<StatusBadge state="CLOSED" acknowledged={true} />);
    expect(screen.getByText('CLOSED')).toBeInTheDocument();
  });
});
