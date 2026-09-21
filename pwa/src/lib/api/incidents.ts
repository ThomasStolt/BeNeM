import { fetchJson, postForm } from './client';
import { AlarmCounts, ApiException, Incident, IncidentAlarm, IncidentDetail, IncidentLogEntry, IncidentState, IncidentStatus, Severity } from './types';
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
  // Try standard parse first (handles ISO 8601 with Z or offset)
  const d = new Date(raw);
  if (!isNaN(d.getTime())) return d;
  // BHNM returns timezone-naive strings like "2026-04-12T09:14:02".
  // Append 'Z' to treat as UTC — consistent with iOS interpretation.
  const d2 = new Date(raw + 'Z');
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

const BHNM_STATES: readonly string[] = ['OPEN', 'ALARMS CLEARED', 'CLOSED'];

/** BHNM's own state, with the ack flag taken back out of it.
 *
 * An unrecognised value becomes OPEN rather than passing through. TOTL is
 * OPEN + CLRD + CLSD, so a state in none of the three would drop the incident
 * out of every pill and vanish it from the list entirely. Loud beats gone —
 * and this mirrors the middleware's own `state_of()` exactly, so the two ends
 * cannot disagree about what an unknown value means.
 */
function normaliseState(raw: string): IncidentState {
  const up = raw.trim().toUpperCase();
  return BHNM_STATES.includes(up) ? (up as IncidentState) : 'OPEN';
}

function coerceBool(v: unknown): boolean {
  return v === true || v === 1 || v === '1' || v === 'true';
}

function coerceEpoch(v: unknown): Date | null {
  if (typeof v === 'number' && Number.isFinite(v)) return new Date(v * 1000);
  return null;
}

function parseRow(row: Record<string, unknown>, index: number, forcedState?: IncidentState): Incident {
  const incidentId = coerceId(row.incident_id ?? row.id, index);
  const stateString = typeof row.incident_state === 'string' ? row.incident_state : 'OPEN';

  // Read the NEW fields, and fall back to incident_state ONLY when `state` is
  // absent — i.e. a middleware older than 2.20.0, or the legacy getincidents
  // fall-through. The fallback maps ACKNOWLEDGED onto state OPEN + flag true,
  // which is the same mapping normaliseState makes. It is deleted at M1-drop.
  const servedState = typeof row.state === 'string' ? row.state : null;
  const state: IncidentState =
    servedState !== null ? normaliseState(servedState)
    : forcedState ?? normaliseState(stateString);
  const acknowledged =
    'acknowledged' in row ? coerceBool(row.acknowledged)
    : stateString === 'ACKNOWLEDGED';

  // status is a VIEW of the two fields above, never a third source of truth.
  const status: IncidentStatus =
    state === 'CLOSED' ? 'closed'
    : acknowledged ? 'acknowledged'
    : 'active';

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
    state,
    acknowledged,
    ackUser: coerceString(row.ack_user),
    closedAt: coerceEpoch(row.closed_at),
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

/** "Active" means NOT CLOSED.
 *
 * An acknowledged incident is still open and still the user's problem — somebody
 * said "I am on it", not "it is fine" — and BHNM's own UI keeps it in the list.
 *
 * `status === 'active'` silently EXCLUDES `'acknowledged'`, because they are
 * separate values of the same union. Observed on a phone 2026-09-19 (iOS, where
 * the Home tile also filtered the list): acking made the row vanish. On the PWA
 * the tile links to an unfiltered list, so the row stayed — but the COUNT
 * dropped the moment the user acted, which is the same defect with a quieter
 * symptom.
 */
export function isActiveIncident(incident: Pick<Incident, 'status'>): boolean {
  return incident.status !== 'resolved' && incident.status !== 'closed';
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
        // A row in closed_incidents IS closed. 2.20.0 says so in `state`; an
        // older middleware does not, and the bucket is the only signal there is.
        if (row && typeof row === 'object') result.push(parseRow(row as Record<string, unknown>, i, 'CLOSED'));
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
  if (!incidentId) {
    throw new ApiException({ kind: 'parse', message: 'incidentId is required' });
  }
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

/** One incident from the middleware's single-incident route.
 *
 * The route keeps 404 and 502 DISTINCT, and so must every caller: "this incident
 * is gone" is a terminal fact, "we could not reach the server" is ask-again-later.
 * Collapsing them is what produced `Incident not found.` shown to somebody whose
 * network was simply down — banned 2026-09-15, still rendered until today.
 *
 * Throws ApiException {kind:'server', status:404} when BHNM says it is gone, and
 * {kind:'network'} / {kind:'server', status:5xx} when the server did not answer.
 */
export async function getSingleIncident(
  config: BhnmConfig,
  incidentId: string,
): Promise<Incident> {
  if (!incidentId) {
    throw new ApiException({ kind: 'parse', message: 'incidentId is required' });
  }
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;
  const raw = await fetchJson(
    config.baseUrl,
    `/api/v1/incidents/${encodeURIComponent(incidentId)}`,
    headers,
  );
  if (!raw || typeof raw !== 'object') {
    throw new ApiException({ kind: 'parse', message: 'Invalid single-incident response' });
  }
  return parseRow(raw as Record<string, unknown>, 0);
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

/** C7 / M2 — the Refresh control and the foreground resume both land here.
 *
 * ONE `getincidents` on the middleware, single-flight, at most one per server
 * per 30 s, and NO per-incident detail call. The rate limit lives server-side
 * and ONLY server-side: that is what makes "one user's refresh serves everyone
 * on that server" true rather than approximately true, and it is why there is
 * no client-side staleness check here to go with it (design Q4, ruled 2026-09-21
 * — every resume, the 30 s window is the only bound).
 *
 * The answer is the same shape as GET /api/v1/incidents, so one tap is one
 * round trip and the caller re-renders straight from it.
 */
export async function refreshIncidents(config: BhnmConfig): Promise<Incident[]> {
  const headers: Record<string, string> = {};
  if (config.apiKey) headers['X-Proxy-Token'] = config.apiKey;
  if (config.bhnmUrl) headers['X-BHNM-Target'] = config.bhnmUrl;
  const raw = await fetchJson(config.baseUrl, '/api/v1/incidents/refresh', headers, 'POST');
  return parseIncidentsResponse(raw);
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

/// Last resort only. The acknowledging user is `config.ackUser` — the **Username**
/// typed into the admin portal's QR generator, where the field is REQUIRED for
/// exactly this reason, carried in the QR payload as `user`. That is the source of
/// truth for ack attribution and it must reach BHNM.
///
/// Do not replace it with a constant. 0.17.2 did, on the reasoning that values like
/// "Thomas Android PWA" looked like device names; the admin link log shows they are
/// the usernames someone typed (`admin.jsonl`, 2026-09-02T13:53:03). A constant
/// throws away the only per-person attribution the system has.
const ACK_USER_FALLBACK = 'BHNM Mobile';

export async function acknowledgeIncident(
  config: BhnmConfig,
  incidentId: string,
): Promise<void> {
  const params: Record<string, string> = {
    password: config.apiKey,
    incident_id: incidentId,
    user: config.ackUser || ACK_USER_FALLBACK,
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
    user: config.ackUser || ACK_USER_FALLBACK,
  };
  if (config.pin) params.pin = config.pin;
  const raw = await postForm(config.baseUrl, '/api/proxy/incident/unacknowledge', params, config.apiKey);
  parseAckResponse(raw);
}
