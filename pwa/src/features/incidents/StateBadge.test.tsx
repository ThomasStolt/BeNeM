import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StateBadge } from './StateBadge';

describe('StateBadge', () => {
  it('renders the state text', () => {
    render(<StateBadge state="CRITICAL" />);
    expect(screen.getByText('CRITICAL')).toBeInTheDocument();
  });

  it('applies red styling for CRITICAL', () => {
    const { container } = render(<StateBadge state="CRITICAL" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies red styling for DOWN', () => {
    const { container } = render(<StateBadge state="DOWN" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies red styling for OPEN', () => {
    const { container } = render(<StateBadge state="OPEN" />);
    expect(container.firstChild).toHaveClass('bg-red-700');
  });

  it('applies orange styling for MAJOR', () => {
    const { container } = render(<StateBadge state="MAJOR" />);
    expect(container.firstChild).toHaveClass('bg-orange-700');
  });

  it('applies yellow styling for WARNING', () => {
    const { container } = render(<StateBadge state="WARNING" />);
    expect(container.firstChild).toHaveClass('bg-yellow-800');
  });

  it('applies yellow styling for MINOR', () => {
    const { container } = render(<StateBadge state="MINOR" />);
    expect(container.firstChild).toHaveClass('bg-yellow-800');
  });

  it('applies green styling for OK', () => {
    const { container } = render(<StateBadge state="OK" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies green styling for ALARMS CLEARED', () => {
    const { container } = render(<StateBadge state="ALARMS CLEARED" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies green styling for CLEARED', () => {
    const { container } = render(<StateBadge state="CLEARED" />);
    expect(container.firstChild).toHaveClass('bg-green-800');
  });

  it('applies blue styling for ACKNOWLEDGED', () => {
    const { container } = render(<StateBadge state="ACKNOWLEDGED" />);
    expect(container.firstChild).toHaveClass('bg-blue-800');
  });

  it('applies blue styling for ACK', () => {
    const { container } = render(<StateBadge state="ACK" />);
    expect(container.firstChild).toHaveClass('bg-blue-800');
  });

  it('applies slate fallback for unknown state', () => {
    const { container } = render(<StateBadge state="SOME_UNKNOWN_STATE" />);
    expect(container.firstChild).toHaveClass('bg-slate-700');
  });
});
