import { postFormText } from './client';
import type { BhnmConfig } from '../config';

/**
 * Fetch all device thresholds via the CSV endpoint and return a map of
 * deviceName → threshold count. One call covers every device.
 *
 * CSV columns: Description, Action_Group, Renotify_Interval, Esc_Group,
 *              Device_Name (index 4), IP, Statistical_Category
 */
export async function fetchThresholdCounts(config: BhnmConfig): Promise<Map<string, number>> {
  const params: Record<string, string> = { password: config.apiKey };
  if (config.pin) params.pin = config.pin;

  const text = await postFormText(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/list-thresholds-csv',
    params,
    config.apiKey,
  );
  const counts = new Map<string, number>();
  const lines = text.split('\n');

  // Skip header row
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const parts = line.split(',');
    const deviceName = parts[4]?.trim();
    if (deviceName) {
      counts.set(deviceName, (counts.get(deviceName) ?? 0) + 1);
    }
  }

  return counts;
}
