// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useRefreshOnForeground } from '../useIncidents';

/** `visibilitychange` fires on BOTH edges — going to the background as well as
 * coming back. Refreshing on the hidden edge would spend a server-side refresh
 * slot on a tab nobody is looking at, and under the 30 s window that is the
 * slot the real resume a moment later would have used: the user returns and
 * gets a coalesced answer from when they left.
 */

function setVisibility(state: DocumentVisibilityState) {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => state,
  });
  document.dispatchEvent(new Event('visibilitychange'));
}

let refresh: ReturnType<typeof vi.fn>;

beforeEach(() => { refresh = vi.fn(); });
afterEach(() => { setVisibility('visible'); });

describe('useRefreshOnForeground', () => {
  it('refreshes when the document becomes visible', () => {
    renderHook(() => useRefreshOnForeground(refresh));
    setVisibility('visible');
    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it('does NOT refresh when the document becomes hidden', () => {
    renderHook(() => useRefreshOnForeground(refresh));
    setVisibility('hidden');
    expect(refresh).not.toHaveBeenCalled();
  });

  it('refreshes once per resume, not once per visibilitychange', () => {
    // The realistic sequence: leave, come back, leave, come back.
    renderHook(() => useRefreshOnForeground(refresh));
    setVisibility('hidden');
    setVisibility('visible');
    setVisibility('hidden');
    setVisibility('visible');
    expect(refresh).toHaveBeenCalledTimes(2);
  });

  it('stops listening on unmount', () => {
    const { unmount } = renderHook(() => useRefreshOnForeground(refresh));
    unmount();
    setVisibility('visible');
    expect(refresh).not.toHaveBeenCalled();
  });
});
