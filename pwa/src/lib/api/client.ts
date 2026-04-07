import { ApiException } from './types';

/** Fetch timeout in milliseconds — aligns with middleware proxy timeout (60 s). */
const FETCH_TIMEOUT_MS = 50_000;

/**
 * POST form-urlencoded to the BHNM middleware proxy.
 * Returns parsed JSON (may be object or array — caller handles shape).
 */
export async function postForm(
  baseUrl: string,
  path: string,
  params: Record<string, string>,
  proxyToken?: string,
): Promise<unknown> {
  const body = new URLSearchParams(params).toString();
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  if (proxyToken) {
    headers['X-Proxy-Token'] = proxyToken;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  let response: Response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers,
      body,
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new ApiException({ kind: 'network', message: 'Request timed out' });
    }
    throw new ApiException({
      kind: 'network',
      message: err instanceof Error ? err.message : 'Network error',
    });
  } finally {
    clearTimeout(timer);
  }

  if (response.status === 401 || response.status === 403) {
    throw new ApiException({ kind: 'auth', message: `HTTP ${response.status}` });
  }
  if (!response.ok) {
    throw new ApiException({
      kind: 'server',
      status: response.status,
      message: `HTTP ${response.status}`,
    });
  }

  try {
    return await response.json();
  } catch (err) {
    throw new ApiException({
      kind: 'parse',
      message: err instanceof Error ? err.message : 'JSON parse error',
    });
  }
}
