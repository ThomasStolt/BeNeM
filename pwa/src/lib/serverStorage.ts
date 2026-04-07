import { encryptField, decryptField, isEncryptedField } from './storage-crypto';

const STORAGE_KEY = 'benem_servers';

/** Fields that contain secrets and should be encrypted at rest. */
const SENSITIVE_FIELDS: readonly (keyof ServerConfig)[] = [
  'apiKey',
  'pin',
  'pushWebhookSecret',
];

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

// ---------------------------------------------------------------------------
// In-memory cache — populated by initStorage(), read by sync loadServers()
// ---------------------------------------------------------------------------
let serverCache: ServerConfig[] | null = null;
let storageReady = false;
let pendingWrite: Promise<void> = Promise.resolve();

// ---------------------------------------------------------------------------
// Encryption helpers
// ---------------------------------------------------------------------------

/** Encrypt sensitive fields on a server config (returns a new object). */
async function encryptSensitiveFields(
  server: ServerConfig,
): Promise<ServerConfig> {
  const copy = { ...server };
  for (const field of SENSITIVE_FIELDS) {
    const value = copy[field];
    if (typeof value === 'string' && value.length > 0) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (copy as any)[field] = await encryptField(value);
    }
  }
  return copy;
}

/** Decrypt sensitive fields on a server config (returns a new object). */
async function decryptSensitiveFields(
  server: ServerConfig,
): Promise<ServerConfig> {
  const copy = { ...server };
  for (const field of SENSITIVE_FIELDS) {
    const value = copy[field];
    if (typeof value === 'string' && value.length > 0) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (copy as any)[field] = await decryptField(value);
    }
  }
  return copy;
}

/** Check if any sensitive field is still plaintext (needs encryption). */
function hasPlaintextSecrets(servers: ServerConfig[]): boolean {
  return servers.some((s) =>
    SENSITIVE_FIELDS.some((f) => {
      const v = s[f];
      return typeof v === 'string' && v.length > 0 && !isEncryptedField(v);
    }),
  );
}

// ---------------------------------------------------------------------------
// Raw localStorage access (works with encrypted data)
// ---------------------------------------------------------------------------

function readRawServers(): ServerConfig[] {
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

async function writeEncryptedServers(servers: ServerConfig[]): Promise<void> {
  if (typeof window === 'undefined') return;
  const encrypted = await Promise.all(servers.map(encryptSensitiveFields));
  localStorage.setItem(STORAGE_KEY, JSON.stringify(encrypted));
}

// ---------------------------------------------------------------------------
// Initialisation — must be awaited before first render
// ---------------------------------------------------------------------------

/**
 * Initialise the storage layer: read from localStorage, decrypt sensitive
 * fields, populate the in-memory cache, and re-encrypt any plaintext secrets
 * found during migration.
 *
 * Call this once at app startup (before rendering). After this resolves,
 * all sync functions (loadServers, addServer, etc.) work from the cache.
 */
export async function initStorage(): Promise<void> {
  if (typeof window === 'undefined') {
    serverCache = [];
    storageReady = true;
    return;
  }

  // Wait for any in-flight saveServers() to finish writing to localStorage
  await pendingWrite;

  // If the cache is already populated (e.g. saveServers was called before
  // initStorage), just ensure it's persisted encrypted and return.
  if (serverCache !== null) {
    const raw = readRawServers();
    if (hasPlaintextSecrets(raw)) {
      await writeEncryptedServers(serverCache);
    }
    storageReady = true;
    return;
  }

  const raw = readRawServers();
  const needsEncryption = hasPlaintextSecrets(raw);

  // Decrypt all servers into the cache
  serverCache = await Promise.all(raw.map(decryptSensitiveFields));
  storageReady = true;

  // If we found plaintext secrets, re-save encrypted (migration)
  if (needsEncryption) {
    await writeEncryptedServers(serverCache);
  }
}

/**
 * Returns true once initStorage() has completed. Useful for guards.
 */
export function isStorageReady(): boolean {
  return storageReady;
}

// ---------------------------------------------------------------------------
// Public sync API (unchanged signatures)
// ---------------------------------------------------------------------------

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
  if (serverCache !== null) return serverCache;
  // Fallback: if initStorage() hasn't been called yet (e.g. in tests),
  // read raw from localStorage. Sensitive fields may be encrypted strings
  // but this keeps backward compat for tests that don't call initStorage().
  return readRawServers();
}

export function saveServers(servers: ServerConfig[]): void {
  // Update the in-memory cache immediately (plaintext)
  serverCache = [...servers];

  // Persist encrypted to localStorage asynchronously
  pendingWrite = writeEncryptedServers(servers).catch((err) => {
    // eslint-disable-next-line no-console
    console.error('[BeNeM] Failed to encrypt server config:', err);
    // Fallback: save plaintext so data isn't lost
    if (typeof window !== 'undefined') {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(servers));
    }
  });
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

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/** Reset the in-memory cache (for testing only). */
export function _resetCache(): void {
  serverCache = null;
  storageReady = false;
  pendingWrite = Promise.resolve();
}
