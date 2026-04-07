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

export async function testConnection(config: BhnmConfig): Promise<HaStatusResult> {
  const params: Record<string, string> = {
    password: config.apiKey,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/proxy/ha-status', params, config.apiKey);
  return parseHaStatusResponse(raw);
}
