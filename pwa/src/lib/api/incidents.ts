import { fetchJson, postForm } from './client';
import { AlarmCounts, ApiException, Incident, IncidentAlarm, IncidentDetail, IncidentLogEntry, IncidentStatus, Severity } from './types';
import type { BhnmConfig } from '../config';

const SEVERITY_MAP: Record<string, Severity> = {
  critical: 'critical', '1': 'critical',
  major: 'major', '2': 'major',
  minor: 'minor', '3': 'minor',
  warning: 'warning', '4': 'warning',
  informational: 'informational', info: 'informational', '5': 'informational',
};

export function buildDisplayId(rawId: string): string {
  const bare = rawId.startsWith('#') ? rawId.slice(1) : rawId;
  const dash = bare.lastIndexOf('-');
  if (dash >= 0) return '#' + bare.slice(dash + 1);
  return '#' + bare;
}

function coerceId(raw: unknown, index: number): string {
  if (typeof raw === 'number') return String(raw);
  if (typeof raw === 'string' && raw.length > 0) return raw;
  return `unknown_${index}`;
}

function coerceSeverity(row: Record<string, unknown>): Severity {
  const candidates = [row.severity, row.alert_level, row.level, row.priority, row.type_name];
  for (const c of candidates) {
    if (typeof c === 'string') {
      const mapped = SEVERITY_MAP[c.toLowerCase()];
      if (mapped) return mapped;
    }
    if (typeof c === 'number') {
      const mapped = SEVERITY_MAP[String(c)];
      if (mapped) return mapped;
    }
  }
  // iOS fallback: active service-check failures default to critical.
  return 'critical';
}

function coerceStartTime(raw: unknown): Date {
  if (typeof raw === 'number') return new Date(raw * 1000);
  if (typeof raw === 'string') {
    const asNum = Number(raw);
    if (!Number.isNaN(asNum)) return new Date(asNum * 1000);
    const parsed = Date.parse(raw);
    if (!Number.isNaN(parsed)) return new Date(parsed);
  }
  return new Date();
}

function coerceString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function stripHtml(s: string): string {
  return s
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .trim();
}

function parseDetailDate(raw: unknown): Date | null {
  if (typeof raw !== 'string' || !raw) return null;
  const d = new Date(raw);
  if (!isNaN(d.getTime())) return d;
  // No-timezone ISO string — treat as local time
  const d2 = new Date(raw.replace('T', ' '));
  return isNaN(d2.getTime()) ? null : d2;
}

function alarmStateToColorKey(state: string): keyof AlarmCounts {
  switch (state.toUpperCase()) {
    case 'CRITICAL': case 'DOWN': case 'OPEN': return 'red';
    case 'MAJOR': case 'UNREACHABLE': return 'orange';
    case 'WARNING': case 'MINOR': return 'yellow';
    case 'OK': case 'NORMAL': case 'RECOVERY': case 'CLEARED': case 'UP': return 'green';
    default: return 'blue';
  }
}

function parseRow(row: Record<string, unknown>, index: number, forcedStatus?: IncidentStatus): Incident {
  const incidentId = coerceId(row.incident_id ?? row.id, index);
  const stateString = typeof row.incident_state === 'string' ? row.incident_state : 'OPEN';
  let status: IncidentStatus;
  if (forcedStatus) status = forcedStatus;
  else if (stateString === 'ACKNOWLEDGED') status = 'acknowledged';
  else status = 'active';

  // Alarm counts from middleware cache (null if cache cold)
  let alarmCounts: AlarmCounts | null = null;
  const rawCounts = row.alarm_counts;
  if (rawCounts && typeof rawCounts === 'object' && !Array.isArray(rawCounts)) {
    const c = rawCounts as Record<string, unknown>;
    alarmCounts = {
      red: typeof c.red === 'number' ? c.red : 0,
      orange: typeof c.orange === 'number' ? c.orange : 0,
      yellow: typeof c.yellow === 'number' ? c.yellow : 0,
      green: typeof c.green === 'number' ? c.green : 0,
      blue: typeof c.blue === 'number' ? c.blue : 0,
    };
  }

  return {
    incidentId,
    displayId: buildDisplayId(incidentId),
    deviceName: coerceString(row.name) ?? coerceString(row.device_name),
    deviceIp:
      coerceString(row.ip) ??
      coerceString(row.device_ip) ??
      coerceString(row.ip_address) ??
      coerceString(row.host_ip),
    summary: typeof row.title === 'string' ? row.title : (typeof row.summary === 'string' ? row.summary : 'Unknown'),
    severity: coerceSeverity(row),
    status,
    incidentState: stateString,
    // Field name fallback chain: BHNM REST uses start_time, legacy API uses
    // incident_open_time; some older versions use open_time. Prefer the more
    // specific names first.
    startTime: coerceStartTime(
      row.start_time ?? row.startTime ?? row.incident_open_time ?? row.open_time
    ),
    acknowledgedBy: coerceString(row.acknowledged_by) ?? coerceString(row.acknowledgedBy),
    alarmCounts,
  };
}

export function parseIncidentsResponse(raw: unknown): Incident[] {
  // BHNM may wrap the response in a single-element array. See project memory.
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') return [];
  const obj = root as Record<string, unknown>;

  if (obj.success === false) {
    const msg =
      (typeof obj.error === 'string' && obj.error) ||
      (typeof obj.failure === 'string' && obj.failure) ||
      'Unknown BHNM error';
    throw new ApiException({ kind: 'server', status: 200, message: msg });
  }

  const result: Incident[] = [];

  if (Array.isArray(obj.active_incidents)) {
    (obj.active_incidents as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    if (Array.isArray(obj.closed_incidents)) {
      (obj.closed_incidents as unknown[]).forEach((row, i) => {
        if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i, 'resolved'));
      });
    }
    return result;
  }

  if (Array.isArray(obj.incidents)) {
    (obj.incidents as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    return result;
  }

  if (Array.isArray(obj.data)) {
    (obj.data as unknown[]).forEach((row, i) => {
      if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i));
    });
    return result;
  }

  return [];
}

export function parseIncidentDetailResponse(raw: unknown): IncidentDetail {
  const root: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!root || typeof root !== 'object') {
    throw new ApiException({ kind: 'parse', message: 'Invalid detail response' });
  }
  const obj = root as Record<string, unknown>;
  const incident = obj.incident as Record<string, unknown> | undefined;
  if (!incident) {
    throw new ApiException({ kind: 'parse', message: 'No incident key in detail response' });
  }
  const detail = (typeof incident.detail === 'object' && incident.detail !== null
    ? incident.detail
    : {}) as Record<string, unknown>;

  function parseAlarms(arr: unknown): IncidentAlarm[] {
    if (!Array.isArray(arr)) return [];
    return arr
      .filter((a): a is Record<string, unknown> => !!a && typeof a === 'object')
      .map((a) => ({
        state: String(a.state ?? ''),
        type: String(a.type ?? ''),
        name: String(a.name ?? ''),
        output: stripHtml(String(a.output ?? '')),
        time: parseDetailDate(a.time),
      }));
  }

  const primaryAlarms = parseAlarms(detail.primary_alarm_log);
  const relatedAlarms = parseAlarms(detail.relatedalarms);

  const incidentLog: IncidentLogEntry[] = Array.isArray(detail.incident_log)
    ? (detail.incident_log as unknown[])
        .filter((e): e is Record<string, unknown> => !!e && typeof e === 'object')
        .map((e) => ({
          state: String(e.state ?? ''),
          time: parseDetailDate(e.time),
          username: String(e.username ?? ''),
          comment: String(e.comment ?? ''),
        }))
    : [];

  const alarmCounts: AlarmCounts = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
  for (const alarm of [...primaryAlarms, ...relatedAlarms]) {
    alarmCounts[alarmStateToColorKey(alarm.state)]++;
  }

  const ackRaw = incident.acknowledged;
  const acknowledged = ackRaw === 1 || ackRaw === '1' || ackRaw === true;

  const deviceIp =
    coerceString(incident.ip) ??
    coerceString(incident.device_ip) ??
    coerceString(incident.ip_address) ??
    coerceString(incident.host_ip);

  return {
    incidentId: String(incident.incident_id ?? ''),
    title: String(incident.title ?? ''),
    deviceName: String(incident.name ?? ''),
    deviceIp,
    incidentState: String(incident.incident_state ?? ''),
    alertType: coerceString(incident.alert_type),
    openTime: parseDetailDate(incident.incident_open_time),
    acknowledged,
    ackTime: acknowledged ? parseDetailDate(incident.ack_time) : null,
    ackUser: acknowledged ? coerceString(incident.ack_user) : null,
    ackComment: acknowledged ? coerceString(incident.ack_comment) : null,
    alarmCounts,
    primaryAlarms,
    relatedAlarms,
    incidentLog,
  };
}

export async function getIncidentDetail(
  config: BhnmConfig,
  incidentId: string,
): Promise<IncidentDetail> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'getincidentdetail',
    incident_id: incidentId,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(
    config.baseUrl,
    '/api/incident_api.php',
    params,
    config.apiKey,
  );
  return parseIncidentDetailResponse(raw);
}

export async function getCachedIncidents(config: BhnmConfig): Promise<Incident[]> {
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;
  try {
    const raw = await fetchJson(config.baseUrl, '/api/v1/incidents', headers);
    return parseIncidentsResponse(raw);
  } catch {
    // Fall back to legacy endpoint if cached endpoint unavailable
    return getIncidents(config);
  }
}

export async function getIncidents(config: BhnmConfig): Promise<Incident[]> {
  const params: Record<string, string> = {
    pwd: config.apiKey,
    method: 'getincidents',
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/incident_api.php', params, config.apiKey);
  return parseIncidentsResponse(raw);
}

export function parseAckResponse(raw: unknown): void {
  const obj: unknown = Array.isArray(raw) ? raw[0] : raw;
  if (!obj || typeof obj !== 'object') {
    throw new ApiException({ kind: 'parse', message: 'Invalid ACK response' });
  }
  const record = obj as Record<string, unknown>;
  if (typeof record.result === 'string' && record.result !== 'completed') {
    const detail = typeof record.detail === 'string' ? record.detail : 'ACK failed';
    throw new ApiException({ kind: 'server', status: 200, message: detail });
  }
}

export async function acknowledgeIncident(
  config: BhnmConfig,
  incidentId: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    incident_id: incidentId,
    user: config.ackUser || 'BeNeM PWA',
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/proxy/incident/acknowledge', params, config.apiKey);
  parseAckResponse(raw);
}

export async function unacknowledgeIncident(
  config: BhnmConfig,
  incidentId: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    incident_id: incidentId,
    user: config.ackUser || 'BeNeM PWA',
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/proxy/incident/unacknowledge', params, config.apiKey);
  parseAckResponse(raw);
}
