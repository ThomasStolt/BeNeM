import { useSyncExternalStore } from 'react';
import { getActiveServer } from './serverStorage';

export interface BhnmConfig {
  serverId: string;
  serverName: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  webhookSecret?: string;
  pushMiddlewareUrl?: string;
  isConfigured: boolean;
  ackUser: string;
  bhnmUrl: string;
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
 * Call after mutating server config (add/edit/delete/switch) to force
 * every `useConfig()` consumer to re-read its snapshot.
 */
export function notifyConfigChanged(): void {
  cachedSnapshot = null;
  listeners.forEach((cb) => cb());
}

function buildSnapshot(): BhnmConfig {
  const server = getActiveServer();
  if (!server) {
    // Fall back to env vars for unconfigured state
    const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
    return {
      serverId: '',
      serverName: '',
      baseUrl: '/bhnm',
      apiKey: envKey,
      isConfigured: envKey.length > 0,
      ackUser: '',
      bhnmUrl: '',
    };
  }
  return {
    serverId: server.id,
    serverName: server.name,
    baseUrl: server.baseUrl,
    apiKey: server.apiKey,
    pin: server.pin,
    webhookSecret: server.pushWebhookSecret,
    pushMiddlewareUrl: server.pushMiddlewareUrl,
    isConfigured: server.apiKey.length > 0,
    ackUser: server.ackUser ?? '',
    bhnmUrl: server.bhnmUrl ?? '',
  };
}

function getSnapshot(): BhnmConfig {
  if (cachedSnapshot === null) {
    cachedSnapshot = buildSnapshot();
  }
  return cachedSnapshot;
}

/** Exported for tests only. */
export function getSnapshotForTest(): BhnmConfig {
  cachedSnapshot = null;
  return buildSnapshot();
}

function getServerSnapshot(): BhnmConfig {
  const envKey = (import.meta.env.VITE_BHNM_API_KEY as string | undefined) ?? '';
  return {
    serverId: '',
    serverName: '',
    baseUrl: '/bhnm',
    apiKey: envKey,
    isConfigured: envKey.length > 0,
    ackUser: '',
    bhnmUrl: '',
  };
}

export function useConfig(): BhnmConfig {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
