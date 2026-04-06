import { postForm } from './client';
import type { BhnmConfig } from '../config';

export interface StatusCounts {
  ok: number;
  ack: number;
  warn: number;
  un: number;
  crit: number;
}

export interface TacticalGroup {
  name: string;
  hosts: StatusCounts;
  services: StatusCounts;
  thresholds: StatusCounts;
  anomalies: StatusCounts;
}

export interface TacticalSummary {
  hosts: StatusCounts;
  services: StatusCounts;
  thresholds: StatusCounts;
  anomalies: StatusCounts;
}

function zeroCounts(): StatusCounts {
  return { ok: 0, ack: 0, warn: 0, un: 0, crit: 0 };
}

function extractCounts(
  status: Record<string, unknown>,
  prefix: string,
): StatusCounts {
  const num = (key: string) => {
    const v = status[key];
    return typeof v === 'number' ? v : 0;
  };
  return {
    ok: num(`${prefix}ok_count`),
    ack: num(`${prefix}ack_count`),
    warn: num(`${prefix}warn_count`),
    un: num(`${prefix}un_count`),
    crit: num(`${prefix}crit_count`),
  };
}

export function parseTacticalResponse(raw: unknown): TacticalGroup[] {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];

  const obj = root as Record<string, unknown>;
  const groups: TacticalGroup[] = [];

  for (const [name, value] of Object.entries(obj)) {
    if (!value || typeof value !== 'object') continue;
    const entry = value as Record<string, unknown>;
    const status = entry.Status;
    if (!status || typeof status !== 'object') continue;
    const s = status as Record<string, unknown>;

    groups.push({
      name,
      hosts: extractCounts(s, 'host_'),
      services: extractCounts(s, 'service_'),
      thresholds: extractCounts(s, 'threshold_'),
      anomalies: extractCounts(s, 'anom_threshold_'),
    });
  }

  return groups;
}

function addCounts(a: StatusCounts, b: StatusCounts): StatusCounts {
  return {
    ok: a.ok + b.ok,
    ack: a.ack + b.ack,
    warn: a.warn + b.warn,
    un: a.un + b.un,
    crit: a.crit + b.crit,
  };
}

export function sumTacticalGroups(groups: TacticalGroup[]): TacticalSummary {
  let hosts = zeroCounts();
  let services = zeroCounts();
  let thresholds = zeroCounts();
  let anomalies = zeroCounts();
  for (const g of groups) {
    hosts = addCounts(hosts, g.hosts);
    services = addCounts(services, g.services);
    thresholds = addCounts(thresholds, g.thresholds);
    anomalies = addCounts(anomalies, g.anomalies);
  }
  return { hosts, services, thresholds, anomalies };
}

export type GroupingType = 'category' | 'site' | 'app';

export async function fetchTacticalOverview(
  config: BhnmConfig,
  groupingType: GroupingType = 'category',
): Promise<TacticalGroup[]> {
  const params: Record<string, string> = {
    password: config.apiKey,
    grouping_type: groupingType,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/fw/index.php?r=restful/tactical-overview/data',
    params,
  );
  return parseTacticalResponse(raw);
}
