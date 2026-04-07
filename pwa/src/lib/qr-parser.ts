import { decrypt } from './crypto';

const QR_KEY = import.meta.env.VITE_QR_ENCRYPTION_KEY ?? '';

export interface ParsedServerConfig {
  name: string;
  baseUrl: string;
  apiKey: string;
  pin?: string;
  pushMiddlewareUrl?: string;
  pushWebhookSecret?: string;
}

function base64ToBytes(b64: string): Uint8Array {
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

  // Compact format: single `p` parameter
  const compactParam = params.get('p');
  if (compactParam) {
    const blob = base64ToBytes(compactParam);
    const json = await decrypt(blob, QR_KEY);
    const data = JSON.parse(json);

    if (!data.bhnmURL || !data.apiKey) {
      throw new Error('Missing required fields in QR code');
    }

    try {
      const parsed = new URL(data.bhnmURL);
      if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
        throw new Error('Server URL must use HTTP(S)');
      }
    } catch {
      throw new Error('Invalid server URL in QR code');
    }

    return {
      name: data.name ?? 'BHNM Server',
      baseUrl: data.bhnmURL,
      apiKey: data.apiKey,
      pin: data.pin || undefined,
      pushMiddlewareUrl: data.middlewareURL || undefined,
      pushWebhookSecret: data.pushSecret || undefined,
    };
  }

  // Legacy format: individual encrypted parameters
  const serverParam = params.get('server');
  const apiKeyParam = params.get('api_key');
  if (!serverParam || !apiKeyParam) {
    throw new Error('No configuration data in QR code');
  }

  const server = await decrypt(base64ToBytes(serverParam), QR_KEY);
  const apiKey = await decrypt(base64ToBytes(apiKeyParam), QR_KEY);

  const pinParam = params.get('pin');
  const pin = pinParam ? await decrypt(base64ToBytes(pinParam), QR_KEY) : undefined;

  const nameParam = params.get('name');
  const name = nameParam ? await decrypt(base64ToBytes(nameParam), QR_KEY) : 'BHNM Server';

  return {
    name,
    baseUrl: server,
    apiKey,
    pin: pin || undefined,
    pushMiddlewareUrl: undefined,
    pushWebhookSecret: undefined,
  };
}
