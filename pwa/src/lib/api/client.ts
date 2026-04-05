import { ApiException } from './types';

/**
 * POST form-urlencoded to the BHNM middleware proxy.
 * Returns parsed JSON (may be object or array — caller handles shape).
 */
export async function postForm(
  baseUrl: string,
  path: string,
  params: Record<string, string>
): Promise<unknown> {
  const body = new URLSearchParams(params).toString();
  let response: Response;
  try {
    response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
  } catch (err) {
    throw new ApiException({
      kind: 'network',
      message: err instanceof Error ? err.message : 'Network error',
    });
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
