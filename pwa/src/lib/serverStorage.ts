const STORAGE_KEY = 'benem_servers';

export interface ServerConfig {
  id: string;
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushEnabled: boolean;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
  isActive: boolean;
}

export interface NewServerInput {
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushEnabled?: boolean;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
}

export function createServerConfig(input: NewServerInput): ServerConfig {
  return {
    id: crypto.randomUUID(),
    name: input.name,
    baseUrl: input.baseUrl,
    apiKey: input.apiKey,
    pin: input.pin,
    pushEnabled: input.pushEnabled ?? false,
    pushMiddlewareUrl: input.pushMiddlewareUrl,
    pushWebhookSecret: input.pushWebhookSecret,
    isActive: false,
  };
}

export function loadServers(): ServerConfig[] {
  if (typeof window === 'undefined') return [];
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveServers(servers: ServerConfig[]): void {
  if (typeof window === 'undefined') return;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(servers));
}

export function addServer(input: NewServerInput): ServerConfig {
  const servers = loadServers();
  const server = createServerConfig(input);
  // First server is automatically active
  server.isActive = servers.length === 0;
  servers.push(server);
  saveServers(servers);
  return server;
}

export function updateServer(
  id: string,
  updates: Partial<Omit<ServerConfig, 'id'>>,
): void {
  const servers = loadServers();
  const index = servers.findIndex((s) => s.id === id);
  if (index === -1) return;
  servers[index] = { ...servers[index], ...updates, id };
  saveServers(servers);
}

export function removeServer(id: string): void {
  let servers = loadServers();
  const wasActive = servers.find((s) => s.id === id)?.isActive ?? false;
  servers = servers.filter((s) => s.id !== id);
  // If the removed server was active, activate the first remaining
  if (wasActive && servers.length > 0) {
    servers[0].isActive = true;
  }
  saveServers(servers);
}

export function getActiveServer(): ServerConfig | null {
  const servers = loadServers();
  return servers.find((s) => s.isActive) ?? null;
}

export function setActiveServer(id: string): void {
  const servers = loadServers();
  for (const s of servers) {
    s.isActive = s.id === id;
  }
  saveServers(servers);
}

const LEGACY_API_KEY = 'benem:bhnm-api-key';
const LEGACY_PIN = 'benem:bhnm-pin';
const LEGACY_WEBHOOK_SECRET = 'benem:webhook-secret';
const LEGACY_PUSH_ENABLED = 'benem:push-enabled';

export function migrateFromLegacyConfig(): void {
  if (typeof window === 'undefined') return;

  // Skip if servers already exist
  if (loadServers().length > 0) return;

  const apiKey = localStorage.getItem(LEGACY_API_KEY);
  if (!apiKey) return;

  const pin = localStorage.getItem(LEGACY_PIN) || undefined;
  const webhookSecret = localStorage.getItem(LEGACY_WEBHOOK_SECRET) || undefined;
  const pushEnabled = localStorage.getItem(LEGACY_PUSH_ENABLED) === 'true';

  const server = createServerConfig({
    name: 'BHNM Server',
    baseUrl: '/bhnm',
    apiKey,
    pin,
    pushEnabled,
    pushWebhookSecret: webhookSecret,
  });
  server.isActive = true;
  saveServers([server]);

  // Clean up legacy keys
  localStorage.removeItem(LEGACY_API_KEY);
  localStorage.removeItem(LEGACY_PIN);
  localStorage.removeItem(LEGACY_WEBHOOK_SECRET);
  localStorage.removeItem(LEGACY_PUSH_ENABLED);
}
