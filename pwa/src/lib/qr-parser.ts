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

async function redeemBlob(blob: string): Promise<Record<string, unknown>> {
  const res = await fetch('/bhnm/api/v1/qr-redeem', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ blob }),
  });
  if (!res.ok) {
    throw new Error('QR code could not be decrypted. Please regenerate it from the admin console.');
  }
  return res.json();
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
    const data = await redeemBlob(compactParam);

    // Middleware uses snake_case field names: bhnm_url, api_key, middleware_url, push_secret
    const bhnmUrl = (data.bhnm_url ?? data.bhnmURL ?? '') as string;
    const apiKey = (data.api_key ?? data.apiKey ?? '') as string;

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

    const middlewareUrl = (data.middleware_url || data.middlewareURL || '') as string;
    const ackUser = (data.user || data.ackUser || undefined) as string | undefined;

    return {
      name: (data.name ?? 'BHNM Server') as string,
      baseUrl: '/bhnm',
      bhnmUrl,
      apiKey,
      pin: (data.pin || undefined) as string | undefined,
      ackUser,
      pushMiddlewareUrl: middlewareUrl || undefined,
      pushWebhookSecret: (data.push_secret || data.pushSecret || undefined) as string | undefined,
    };
  }

  // Legacy format: individual encrypted parameters — no longer supported client-side.
  // Regenerate the QR code from the admin console to get a current compact-format code.
  if (params.get('server') || params.get('api_key')) {
    throw new Error(
      'This QR code uses an older format. Please regenerate it from the admin console.',
    );
  }

  throw new Error('No configuration data in QR code');
}
