import { postForm } from './client';
import type { BhnmConfig } from '../config';

/**
 * Fetch service checks for a single device and return the count of those
 * that are enabled AND in OK state — these contribute to the HEALTHY count.
 *
 * Response is a JSON array of service check objects.
 */
export async function fetchOkServiceCount(
  config: BhnmConfig,
  deviceName: string,
): Promise<number> {
  const params: Record<string, string> = {
    password: config.apiKey,
    dev_name: deviceName,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/services',
    params,
    config.apiKey,
  );

  const arr = Array.isArray(raw) ? raw : [];
  return arr.filter(
    (s): s is Record<string, unknown> =>
      s !== null &&
      typeof s === 'object' &&
      (s as Record<string, unknown>).enabled === true &&
      (s as Record<string, unknown>).state === 'OK',
  ).length;
}
