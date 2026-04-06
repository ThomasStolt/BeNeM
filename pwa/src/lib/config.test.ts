import { describe, it, expect, beforeEach, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useConfig, notifyConfigChanged, getSnapshotForTest } from './config';
import { saveApiKey, clearApiKey } from '../features/settings/settingsStorage';

describe('useConfig', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.unstubAllEnvs();
    // Invalidate cache by triggering a config change
    notifyConfigChanged();
  });

  it('reads from localStorage when a key is stored', () => {
    saveApiKey('from-storage');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-storage');
    expect(result.current.isConfigured).toBe(true);
  });

  it('falls back to VITE_BHNM_API_KEY when localStorage is empty', () => {
    vi.stubEnv('VITE_BHNM_API_KEY', 'from-env');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-env');
    expect(result.current.isConfigured).toBe(true);
  });

  it('localStorage wins over env var', () => {
    vi.stubEnv('VITE_BHNM_API_KEY', 'from-env');
    saveApiKey('from-storage');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('from-storage');
  });

  it('is not configured when both are empty', () => {
    const { result } = renderHook(() => useConfig());
    expect(result.current.isConfigured).toBe(false);
    expect(result.current.apiKey).toBe('');
  });

  it('re-renders consumers when notifyConfigChanged is called after save', () => {
    const { result } = renderHook(() => useConfig());
    expect(result.current.isConfigured).toBe(false);

    act(() => {
      saveApiKey('new-key');
      notifyConfigChanged();
    });

    expect(result.current.apiKey).toBe('new-key');
    expect(result.current.isConfigured).toBe(true);
  });

  it('re-renders consumers when notifyConfigChanged is called after clear', () => {
    saveApiKey('initial');
    const { result } = renderHook(() => useConfig());
    expect(result.current.apiKey).toBe('initial');

    act(() => {
      clearApiKey();
      notifyConfigChanged();
    });

    expect(result.current.apiKey).toBe('');
    expect(result.current.isConfigured).toBe(false);
  });

  it('reads PIN from localStorage when set', () => {
    window.localStorage.setItem('benem:bhnm-pin', 'local-pin');
    notifyConfigChanged();
    const config = getSnapshotForTest();
    expect(config.pin).toBe('local-pin');
  });

  it('falls back to env var PIN when localStorage is empty', () => {
    notifyConfigChanged();
    const config = getSnapshotForTest();
    expect(config.pin).toBeUndefined();
  });
});
