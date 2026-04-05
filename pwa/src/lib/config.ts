import { useSyncExternalStore } from 'react';
import { loadApiKey } from '../features/settings/settingsStorage';

export interface BhnmConfig {
  /** Base URL the client should hit. `/bhnm` in both dev (Vite proxy) and prod (Caddy handle_path). */
  baseUrl: string;
  apiKey: string;
  pin?: string;
  isConfigured: boolean;
}

const listeners = new Set<() => void>();
let cachedSnapshot: BhnmConfig | null = null;

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  return () => {
    listeners.delete(cb);
  };
}

/**
 * Call after mutating config (e.g. from SettingsScreen Save/Clear) to force
 * every `useConfig()` consumer to re-read its snapshot.
 */
export function notifyConfigChanged(): void {
  cachedSnapshot = null;
  listeners.forEach((cb) => cb());
}

function buildSnapshot(): BhnmConfig {
  const storedKey = loadApiKey();
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  const envPin = (import.meta.env.VITE_BHNM_PIN as string | undefined) ?? '';
  const apiKey = storedKey && storedKey.length > 0 ? storedKey : envKey;
  return {
    baseUrl: '/bhnm',
    apiKey,
    pin: envPin.length > 0 ? envPin : undefined,
    isConfigured: apiKey.length > 0,
  };
}

function getSnapshot(): BhnmConfig {
  if (cachedSnapshot === null) {
    cachedSnapshot = buildSnapshot();
  }
  return cachedSnapshot;
}

// Server snapshot for SSR safety — returns the same shape with no storage access.
function getServerSnapshot(): BhnmConfig {
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  return {
    baseUrl: '/bhnm',
    apiKey: envKey,
    pin: undefined,
    isConfigured: envKey.length > 0,
  };
}

export function useConfig(): BhnmConfig {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
