import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { Toast, type ToastMessage } from '../Toast';

describe('Toast', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('renders nothing when message is null', () => {
    const { container } = render(<Toast message={null} onDismiss={() => {}} />);
    expect(container.firstChild).toBeNull();
  });

  it('renders success message', () => {
    const msg: ToastMessage = { text: 'Acknowledged!', type: 'success' };
    render(<Toast message={msg} onDismiss={() => {}} />);
    expect(screen.getByText('Acknowledged!')).toBeInTheDocument();
  });

  it('renders error message', () => {
    const msg: ToastMessage = { text: 'Failed', type: 'error' };
    render(<Toast message={msg} onDismiss={() => {}} />);
    expect(screen.getByText('Failed')).toBeInTheDocument();
  });

  it('auto-dismisses after timeout', () => {
    const onDismiss = vi.fn();
    const msg: ToastMessage = { text: 'Done', type: 'success' };
    render(<Toast message={msg} onDismiss={onDismiss} />);

    act(() => {
      vi.advanceTimersByTime(3000);
    });

    expect(onDismiss).toHaveBeenCalledOnce();
  });
});
