import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ConnectionBadge } from '../ConnectionBadge';

describe('ConnectionBadge', () => {
  it('renders as a button', () => {
    render(<ConnectionBadge status="connected" onRetry={vi.fn()} />);
    expect(screen.getByRole('button', { name: /connection/i })).toBeInTheDocument();
  });

  it('calls onRetry when clicked', () => {
    const onRetry = vi.fn();
    render(<ConnectionBadge status="connected" onRetry={onRetry} />);
    fireEvent.click(screen.getByRole('button'));
    expect(onRetry).toHaveBeenCalledOnce();
  });

  it('renders SVG chain links', () => {
    const { container } = render(<ConnectionBadge status="connected" onRetry={vi.fn()} />);
    const rects = container.querySelectorAll('rect');
    expect(rects.length).toBe(2);
  });
});
