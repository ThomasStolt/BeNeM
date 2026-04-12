import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { OverflowMarquee } from './OverflowMarquee';

// jsdom has no ResizeObserver — capture the callback so we can invoke it manually
let roCallback: ResizeObserverCallback;
const mockObserve = vi.fn();
const mockDisconnect = vi.fn();

beforeEach(() => {
  vi.stubGlobal(
    'ResizeObserver',
    vi.fn((cb: ResizeObserverCallback) => {
      roCallback = cb;
      return { observe: mockObserve, disconnect: mockDisconnect };
    }),
  );
});

describe('OverflowMarquee', () => {
  it('renders text in static mode when dimensions are equal (no overflow)', () => {
    const { container } = render(<OverflowMarquee text="Short text" />);
    // In jsdom scrollWidth = clientWidth = 0 → no overflow → no animate-marquee
    expect(container.querySelector('.animate-marquee')).not.toBeInTheDocument();
    expect(screen.getAllByText('Short text').length).toBeGreaterThan(0);
  });

  it('activates continuous marquee when measure span overflows clip container', () => {
    const { container } = render(<OverflowMarquee text="A very long incident title that overflows" />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    Object.defineProperty(measureEl, 'scrollWidth', { value: 400, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 150, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    expect(container.querySelector('.animate-marquee')).toBeInTheDocument();
  });

  it('renders two text copies in overflow mode (for seamless loop)', () => {
    const { container } = render(<OverflowMarquee text="Long title" />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    Object.defineProperty(measureEl, 'scrollWidth', { value: 300, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 100, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    const track = container.querySelector('.animate-marquee') as HTMLElement;
    expect(track.querySelectorAll('span')).toHaveLength(2);
  });

  it('sets animationDuration on the track from text width and speed', () => {
    const { container } = render(<OverflowMarquee text="Long" speed={50} />);
    const clip = container.firstChild as HTMLElement;
    const measureEl = clip.querySelector('[data-testid="marquee-measure"]') as HTMLElement;

    // textWidth=200, gap=48 → duration = (200+48)/50 = 4.96s
    Object.defineProperty(measureEl, 'scrollWidth', { value: 200, configurable: true });
    Object.defineProperty(clip, 'clientWidth', { value: 100, configurable: true });

    act(() => {
      roCallback([], null as unknown as ResizeObserver);
    });

    const track = container.querySelector('.animate-marquee') as HTMLElement;
    expect(track.style.animationDuration).toBe('4.96s');
  });

  it('disconnects the ResizeObserver on unmount', () => {
    const { unmount } = render(<OverflowMarquee text="Test" />);
    unmount();
    expect(mockDisconnect).toHaveBeenCalled();
  });
});
