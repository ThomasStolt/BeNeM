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
