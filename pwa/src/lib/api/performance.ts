import type { BhnmConfig } from '../config';
import type {
  PerformanceCategory,
  PerformanceInstance,
  TimeSeriesResult,
  TimeSeriesDataPoint,
} from './types';
import { postForm } from './client';

/* ------------------------------------------------------------------ */
/*  Parsers (exported for testing)                                    */
/* ------------------------------------------------------------------ */

export function parsePerformanceCategories(raw: unknown): PerformanceCategory[] {
  if (!Array.isArray(raw)) return [];
  // Handle array-wrapped: [[{...}]]
  const arr = Array.isArray(raw[0]) ? (raw[0] as unknown[]) : raw;
  return arr
    .filter((item): item is Record<string, unknown> => item != null && typeof item === 'object')
    .map((obj) => ({
      id: String(obj.id ?? ''),
      category: String((obj.category ?? obj.cat) ?? ''),
    }));
}

export function parsePerformanceInstances(
  raw: unknown,
  statGroup: string,
): PerformanceInstance[] {
  if (!Array.isArray(raw)) return [];

  const results: PerformanceInstance[] = [];

  for (const item of raw) {
    if (item == null || typeof item !== 'object') continue;
    const obj = item as Record<string, unknown>;
    const title = String(obj.title ?? '');
    const unit = String(obj.unit ?? '');
    const type = String(obj.type ?? '');
    const key = String(obj.key ?? '');
    const description = String(obj.description ?? '');

    // Filter out per-process metrics
    if (/by process/i.test(title)) continue;
    // Filter out swap metrics
    if (/swap/i.test(title)) continue;
    // Filter out raw-byte metrics
    if (unit === 'B') continue;

    if (type === 'interface') {
      const bw = obj.bandwidth as Record<string, unknown> | null | undefined;
      const bwUnit = bw && typeof bw === 'object' && bw.unit ? String(bw.unit) : '%';
      results.push(
        { key: `${key}-in`, title: `${description} — In`, unit: bwUnit, statGroup, valueKey: 'value1' },
        { key: `${key}-out`, title: `${description} — Out`, unit: bwUnit, statGroup, valueKey: 'value2' },
      );
    } else {
      results.push({ key, title, unit, statGroup, valueKey: 'value1' });
    }
  }

  return results;
}

export function parseTimeSeriesResponse(raw: unknown): TimeSeriesResult[] {
  if (raw == null || typeof raw !== 'object') return [];

  // Handle array-wrapped
  let obj = raw as Record<string, unknown>;
  if (Array.isArray(raw)) {
    if (raw.length === 0) return [];
    obj = raw[0] as Record<string, unknown>;
    if (obj == null || typeof obj !== 'object') return [];
  }

  const metrics = obj.metrics;
  if (!Array.isArray(metrics)) return [];

  return metrics
    .filter((m): m is Record<string, unknown> => m != null && typeof m === 'object')
    .map((m) => {
      const dpArray = Array.isArray(m.datapoints) ? m.datapoints : [];
      const dpObj = dpArray.length > 0 && dpArray[0] != null && typeof dpArray[0] === 'object'
        ? (dpArray[0] as Record<string, string>)
        : {};

      const datapoints: TimeSeriesDataPoint[] = Object.entries(dpObj)
        .map(([k, v]) => ({ timestamp: Number(k), value: parseFloat(v) }))
        .sort((a, b) => a.timestamp - b.timestamp);

      return {
        instanceDescr: String(m.instanceDescr ?? ''),
        metricId: String(m.metricId ?? ''),
        datapoints,
      };
    });
}

/* ------------------------------------------------------------------ */
/*  API functions                                                     */
/* ------------------------------------------------------------------ */

export async function fetchPerformanceCategories(
  config: BhnmConfig,
  deviceId: string,
): Promise<PerformanceCategory[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    device_id: deviceId,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/performance-category',
    params,
  );
  return parsePerformanceCategories(raw);
}

export async function fetchPerformanceInstances(
  config: BhnmConfig,
  deviceId: string,
  categoryId: string,
  statGroup: string,
): Promise<PerformanceInstance[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    device_id: deviceId,
    id: categoryId,
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/performance-instance-per-category',
    params,
  );
  return parsePerformanceInstances(raw, statGroup);
}

/** Override map for empty-unit metrics. */
const EMPTY_UNIT_OVERRIDES: Record<string, string> = {
  'Running Processes': 'Processes',
};

export async function fetchTimeSeriesBatch(
  config: BhnmConfig,
  deviceName: string,
  statGroup: string,
  units: string,
  metricTitle?: string,
): Promise<TimeSeriesResult[]> {
  // For empty-unit metrics, derive metricFilterUnits from metricTitle
  let metricFilterUnits = units;
  if (units === '' && metricTitle) {
    metricFilterUnits = EMPTY_UNIT_OVERRIDES[metricTitle] ?? metricTitle;
  }

  const params: Record<string, string> = {
    password: config.apiKey,
    groupFilterBy: 'device',
    groupFilterValue: deviceName,
    metricFilterStatGroup: statGroup,
    metricFilterUnits: metricFilterUnits,
    timeFrameFilterBy: 'time_offset',
    timeFrameFilterValue: 'Last 24 Hours',
    returnFormatFilterBy: 'average',
  };
  if (config.pin) params.pin = config.pin;

  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/devices/timeseries-metrics',
    params,
  );
  return parseTimeSeriesResponse(raw);
}
