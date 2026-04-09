import { postForm } from './client';
import { ApiException } from './types';
import type { BhnmConfig } from '../config';

export async function createMaintenanceWindow(
  config: BhnmConfig,
  deviceName: string,
  durationMinutes: number,
  comment: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    name: deviceName,
    duration: String(durationMinutes),
    comment,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/api/proxy/maintenance/create',
    params,
    config.apiKey,
  );

  const record = raw as Record<string, unknown>;
  if (record.result === 'error') {
    const detail = typeof record.detail === 'string' ? record.detail : 'Failed to create maintenance window';
    throw new ApiException({ kind: 'server', status: 200, message: detail });
  }
}
