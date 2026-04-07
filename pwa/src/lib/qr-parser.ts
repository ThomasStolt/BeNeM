import { decrypt, decryptCompressed } from './crypto';

/** Read the QR encryption key lazily so it picks up env stubs in tests. */
function getQRKey(): string {
  return import.meta.env.VITE_QR_ENCRYPTION_KEY ?? '';
}

export interface ParsedServerConfig {
  name: string;
  baseUrl: string;
  bhnmUrl: string;
  apiKey: string;
  pin?: string;
  ackUser?: string;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
}

/** Decode base64url (no-padding, URL-safe alphabet) to bytes. */
function base64urlToBytes(b64url: string): Uint8Array {
  // Convert base64url → standard base64
  let b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
  // Restore padding
  const remainder = b64.length % 4;
  if (remainder === 2) b64 += '==';
  else if (remainder === 3) b64 += '=';

  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

export async function parseQRUrl(urlString: string): Promise<ParsedServerConfig> {
  let url: URL;
  try {
    url = new URL(urlString);
  } catch {
    throw new Error('Not a BeNeM configuration URL');
  }

  if (url.protocol !== 'benem:' || url.hostname !== 'configure') {
    throw new Error('Not a BeNeM configuration URL');
  }

  const params = url.searchParams;

  // Compact format: single `p` parameter (base64url, zlib-compressed, AES-256-GCM)
  const compactParam = params.get('p');
  if (compactParam) {
    if (!getQRKey() || getQRKey().length !== 64) {
      throw new Error('QR encryption key is not configured (set VITE_QR_ENCRYPTION_KEY)');
    }
    const blob = base64urlToBytes(compactParam);
    const json = await decryptCompressed(blob, getQRKey());
    const data = JSON.parse(json);

    // Middleware uses snake_case field names: bhnm_url, api_key, middleware_url, push_secret
    const bhnmUrl = data.bhnm_url ?? data.bhnmURL ?? '';
    const apiKey = data.api_key ?? data.apiKey ?? '';

    if (!bhnmUrl || !apiKey) {
      throw new Error('Missing required fields in QR code');
    }

    try {
      const parsed = new URL(bhnmUrl);
      if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
        throw new Error('Server URL must use HTTP(S)');
      }
    } catch {
      throw new Error('Invalid server URL in QR code');
    }

    const middlewareUrl = data.middleware_url || data.middlewareURL || '';
    const ackUser = data.user || data.ackUser || undefined;

    return {
      name: data.name ?? 'BHNM Server',
      baseUrl: '/bhnm',
      bhnmUrl,
      apiKey,
      pin: data.pin || undefined,
      ackUser,
      pushMiddlewareUrl: middlewareUrl || undefined,
      pushWebhookSecret: data.push_secret || data.pushSecret || undefined,
    };
  }

  // Legacy format: individual encrypted parameters (no zlib, just AES-GCM)
  const serverParam = params.get('server');
  const apiKeyParam = params.get('api_key');
  if (!serverParam || !apiKeyParam) {
    throw new Error('No configuration data in QR code');
  }

  if (!getQRKey() || getQRKey().length !== 64) {
    throw new Error('QR encryption key is not configured (set VITE_QR_ENCRYPTION_KEY)');
  }
  const server = await decrypt(base64urlToBytes(serverParam), getQRKey());
  const apiKey = await decrypt(base64urlToBytes(apiKeyParam), getQRKey());

  const pinParam = params.get('pin');
  const pin = pinParam ? await decrypt(base64urlToBytes(pinParam), getQRKey()) : undefined;

  const nameParam = params.get('name');
  const name = nameParam ? await decrypt(base64urlToBytes(nameParam), getQRKey()) : 'BHNM Server';

  return {
    name,
    baseUrl: '/bhnm',
    bhnmUrl: server,
    apiKey,
    pin: pin || undefined,
    ackUser: undefined,
    pushMiddlewareUrl: undefined,
    pushWebhookSecret: undefined,
  };
}
