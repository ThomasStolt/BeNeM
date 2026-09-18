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

/**
 * What the probe proved. THREE outcomes, never two: a reply we do not recognise is
 * INCONCLUSIVE, not a pass.
 *
 * The rule this replaces — "a password error is the one failure, anything else is a
 * pass" — treated an unrecognised reply as success and hung the verdict on BHNM's
 * exact wording of "Password failed.". Had that string changed, a WRONG KEY would
 * have read as a good connection. The failure direction now runs the safe way: a
 * wording change degrades to "could not verify", never to a false pass.
 */
export interface ConnectionCheckResult {
  /** BHNM's own words, e.g. "Method not supported." */
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
 * Matching is on structure first and the narrowest possible words second, because
 * BHNM's API carries no error code — only `result` and a human `detail`:
 *  - `result: "completed"` is structural: BHNM did work, so the key was accepted.
 *  - a credential word is checked FIRST, so an auth error cannot read as anything else.
 *  - a METHOD word means BHNM got past the credential to complain about the thing we
 *    deliberately got wrong. Covers "Method not supported.", "Missing method in your
 *    request." and "Missing required information for this method.", all observed.
 *  - anything else, a non-JSON body included, is inconclusive.
 */
export async function testConnection(config: BhnmConfig): Promise<ConnectionCheckResult> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'benem_connection_check',
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(config.baseUrl, '/api/incident_api.php', params, config.apiKey);
  const preview = typeof raw === 'string' ? raw.slice(0, 300) : JSON.stringify(raw).slice(0, 300);
  const record = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const result = typeof record.result === 'string' ? record.result : '';
  const detail = typeof record.detail === 'string' ? record.detail : '';
  const has = (s: string, word: string) => s.toLowerCase().includes(word);

  if (!result) {
    throw new ApiException({ kind: 'parse', message: `Not a BHNM API response: ${preview}` });
  }
  if (has(detail, 'password') || has(detail, 'credential')) {
    // BHNM never says WHICH credential it rejected, so we must not either. The form
    // knows whether a PIN was entered, so it can point at the right field instead of
    // making the user work out whether they are on SaaS.
    const next = config.pin
      ? 'Check the API key and the PIN.'
      : 'Check the API key. SaaS servers also require a PIN.';
    throw new ApiException({
      kind: 'auth',
      message: `BHNM rejected these credentials: "${detail}" ${next}`,
    });
  }
  if (result.toLowerCase() === 'completed' || has(detail, 'method')) {
    return { detail };
  }
  throw new ApiException({
    kind: 'parse',
    message: `BHNM answered, but not in a way this app recognises: ${preview}`,
  });
}
