// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { usePollWhileVisible, useReloadOnPush } from '../useIncidents';

/** The field defect, on this platform.
 *
 * Reported on iOS 54 and true of the PWA for the same reason: with the list
 * open, an acknowledgement made in the BHNM UI never reached the screen. The
 * 120 s `refetchInterval` used to cover it **by accident** — it re-read
 * `GET /api/v1/incidents` whether or not anything had happened — and 0.19.0
 * removed it as part of removing the countdown, with C4 (the push carrying the
 * change itself) not yet landed. That left an open list with no update path
 * except a tap.
 *
 * Both halves are tested here, and so is the thing that makes them safe
 * together: **they must not double up.**
 */

function setVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => state,
  });
  document.dispatchEvent(new Event('visibilitychange'));
}

/** A stand-in for the service worker's message channel. jsdom has no
 * `navigator.serviceWorker`, so the real listener has nothing to attach to. */
function installServiceWorkerStub() {
  const listeners = new Set<(e: MessageEvent) => void>();
  Object.defineProperty(navigator, 'serviceWorker', {
    configurable: true,
    value: {
      addEventListener: (_t: string, fn: (e: MessageEvent) => void) => listeners.add(fn),
      removeEventListener: (_t: string, fn: (e: MessageEvent) => void) => listeners.delete(fn),
    },
  });
  return {
    post: (data: unknown) => listeners.forEach((fn) => fn({ data } as MessageEvent)),
    listenerCount: () => listeners.size,
  };
}

let reload: ReturnType<typeof vi.fn>;

beforeEach(() => {
  reload = vi.fn();
  vi.useFakeTimers();
  setVisibility('visible');
});
afterEach(() => {
  vi.useRealTimers();
  setVisibility('visible');
});

describe('a push reloads the open list', () => {
  it('reloads ONCE for one push', () => {
    const sw = installServiceWorkerStub();
    renderHook(() => useReloadOnPush(reload));
    sw.post({ type: 'incidents-updated' });
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('ignores the service worker’s other messages', () => {
    // `navigate` is the deep-link message App.tsx handles. If this hook took
    // every message, a tap would reload twice — once for `incidents-updated`
    // and once for the `navigate` that follows it in the same handler.
    const sw = installServiceWorkerStub();
    renderHook(() => useReloadOnPush(reload));
    sw.post({ type: 'navigate', url: '/incidents/30017' });
    sw.post({ type: 'something-else' });
    sw.post(undefined);
    expect(reload).not.toHaveBeenCalled();
  });

  it('detaches its listener on unmount', () => {
    const sw = installServiceWorkerStub();
    const { unmount } = renderHook(() => useReloadOnPush(reload));
    expect(sw.listenerCount()).toBe(1);
    unmount();
    expect(sw.listenerCount()).toBe(0);
    sw.post({ type: 'incidents-updated' });
    expect(reload).not.toHaveBeenCalled();
  });
});

describe('the silent safety net', () => {
  it('re-reads the cache every 60 s while the tab is visible', () => {
    renderHook(() => usePollWhileVisible(reload));
    expect(reload).not.toHaveBeenCalled();     // and NOT immediately — see below
    vi.advanceTimersByTime(60_000);
    expect(reload).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(120_000);
    expect(reload).toHaveBeenCalledTimes(3);
  });

  it('does NOT fire on the instant the tab becomes visible', () => {
    // **This is what keeps it from doubling up with the foreground refresh.**
    // A resume fires useRefreshOnForeground immediately AND restarts this
    // timer. If the timer also fired at zero there would be two requests on
    // the wire for one event — and the second, arriving inside the
    // middleware's 30 s window, would be answered from the first.
    renderHook(() => usePollWhileVisible(reload));
    setVisibility('hidden');
    setVisibility('visible');
    expect(reload).not.toHaveBeenCalled();
    vi.advanceTimersByTime(59_999);
    expect(reload).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('STOPS while the tab is hidden', () => {
    renderHook(() => usePollWhileVisible(reload));
    setVisibility('hidden');
    vi.advanceTimersByTime(600_000);           // ten minutes in the background
    expect(reload).not.toHaveBeenCalled();
    setVisibility('visible');
    vi.advanceTimersByTime(60_000);
    expect(reload).toHaveBeenCalledTimes(1);   // and it picks up again
  });

  it('does not stack a second timer when visibility flaps', () => {
    // visibilitychange fires on both edges, and a mobile browser fires it
    // liberally. Two timers would mean two requests per interval, for ever.
    renderHook(() => usePollWhileVisible(reload));
    for (let i = 0; i < 5; i++) setVisibility('visible');
    vi.advanceTimersByTime(60_000);
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('clears the timer on unmount', () => {
    const { unmount } = renderHook(() => usePollWhileVisible(reload));
    unmount();
    vi.advanceTimersByTime(600_000);
    expect(reload).not.toHaveBeenCalled();
  });
});
