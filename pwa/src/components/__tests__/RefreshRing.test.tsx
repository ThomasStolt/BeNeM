import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { RefreshRing } from '../RefreshRing';

describe('RefreshRing', () => {
  it('renders as a tappable button', () => {
    render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={vi.fn()} />,
    );
    expect(screen.getByRole('button', { name: /refresh/i })).toBeInTheDocument();
  });

  it('calls onRefresh when clicked', () => {
    const onRefresh = vi.fn();
    render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={onRefresh} />,
    );
    fireEvent.click(screen.getByRole('button'));
    expect(onRefresh).toHaveBeenCalledOnce();
  });

  it('renders SVG circle for countdown', () => {
    const { container } = render(
      <RefreshRing lastUpdatedAt={Date.now()} intervalMs={120_000} isLoading={false} onRefresh={vi.fn()} />,
    );
    const circles = container.querySelectorAll('circle');
    expect(circles.length).toBeGreaterThanOrEqual(2);
  });
});
