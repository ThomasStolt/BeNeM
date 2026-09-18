import { postForm } from './client';
import { ApiException } from './types';
import type { BhnmConfig } from '../config';

export interface HaStatusResult {
  role: string;
  status: string;
}

export function parseHaStatusResponse(raw: unknown): HaStatusResult {
  // BHNM wraps response in an array: [{"role":"master","status":"1"}]
  const obj: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!obj || typeof obj !== 'object') {
    throw new ApiException({ kind: 'parse', message: 'Invalid ha_status response' });
  }
  const record = obj as Record<string, unknown>;
  const role = typeof record.role === 'string' ? record.role : '';
  const status = typeof record.status === 'string' ? record.status : '';
  return { role, status };
}

const ROLE_MAP: Record<string, string> = {
  standalone: 'Standalone',
  primary: 'Primary',
  master: 'Primary',
  slave: 'Replica',
};

export function formatHaRole(role: string): string {
  return ROLE_MAP[role.toLowerCase()] ?? role;
}

const STATUS_MAP: Record<string, Record<string, string>> = {
  primary: { '1': 'Active', '2': 'Inactive' },
  master: { '1': 'Active', '2': 'Inactive' },
  slave: { '1': 'Active', '2': 'Takeover', '3': 'Inactive' },
};

export function formatHaStatus(role: string, status: string): string | null {
  const map = STATUS_MAP[role.toLowerCase()];
  if (!map) return null; // standalone — status not shown
  return map[status] ?? status;
}

export interface ConnectionCheckResult {
  /** BHNM's own reply, e.g. "Method not supported." — proof it answered as BHNM. */
  detail: string;
}

/**
 * Verify a connection: reachable, proxy token accepted, target allowed for that
 * token, and the BHNM credential good — in one call against the endpoint the app
 * actually uses.
 *
 * The method is deliberately unsupported. BHNM checks the credential BEFORE the
 * method, so this answers "is the key good" in a CONSTANT 51 bytes whatever the
 * size of the estate — measured 2026-09-18:
 *   wrong key -> {"result":"error","detail":"Password failed."}        46 B
 *   good key  -> {"result":"error","detail":"Method not supported."}   51 B
 * getincidents answers the same question in ~209 bytes per incident, about 204 KB
 * at n=1000, and neither `limit` nor `count` bounds it.
 *
 * A parse error is a FAILURE and is no longer swallowed. The previous version
 * returned `{role:'unknown'}` for any non-JSON 200 on the grounds that "a parse
 * error on a reachable server still means the connection works" — but BHNM returns
 * those before it ever looks at the credential, so that reported a verified
 * connection it had not verified. See the root CLAUDE.md doctrine.
 */
export async function testConnection(config: BhnmConfig): Promise<ConnectionCheckResult> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'benem_connection_check',
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(config.baseUrl, '/api/incident_api.php', params, config.apiKey);
  if (!raw || typeof raw !== 'object' || !('result' in (raw as Record<string, unknown>))) {
    throw new ApiException({
      kind: 'parse',
      message: 'The server answered, but not with a BHNM API response. Check the BHNM URL.',
    });
  }
  const detail = String((raw as Record<string, unknown>).detail ?? '');
  if (detail.toLowerCase().includes('password')) {
    throw new ApiException({ kind: 'auth', message: `BHNM rejected the API key: ${detail}` });
  }
  return { detail };
}
