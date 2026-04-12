import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusBadge } from './StatusBadge';

describe('StatusBadge', () => {
  it('shows OPEN in red for active incidents', () => {
    const { container } = render(
      <StatusBadge status="active" incidentState="OPEN" />,
    );
    expect(screen.getByText('OPEN')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-red-600');
  });

  it('shows ACKD in blue for acknowledged incidents', () => {
    const { container } = render(
      <StatusBadge status="acknowledged" incidentState="ACKNOWLEDGED" />,
    );
    expect(screen.getByText('ACKD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-blue-600');
  });

  it('shows CLRD in green for resolved incidents', () => {
    const { container } = render(
      <StatusBadge status="resolved" incidentState="RESOLVED" />,
    );
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });

  it('shows CLRD in green for closed incidents', () => {
    render(<StatusBadge status="closed" incidentState="CLOSED" />);
    expect(screen.getByText('CLRD')).toBeInTheDocument();
  });

  it('shows CLRD in green when incidentState is ALARMS CLEARED', () => {
    const { container } = render(
      <StatusBadge status="active" incidentState="ALARMS CLEARED" />,
    );
    expect(screen.getByText('CLRD')).toBeInTheDocument();
    expect(container.firstChild).toHaveClass('bg-emerald-600');
  });
});
