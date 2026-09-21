export type Severity = 'critical' | 'major' | 'minor' | 'warning' | 'informational';
export type IncidentStatus = 'active' | 'acknowledged' | 'resolved' | 'closed';

/** BHNM has THREE incident states. Acknowledged is a FLAG on an OPEN incident,
 * not a fourth state — which is the whole reason for the split: with one field,
 * an acknowledged incident whose alarms then clear can only be shown as one or
 * the other. Middleware 2.20.0 serves `state` and `acknowledged` separately. */
export type IncidentState = 'OPEN' | 'ALARMS CLEARED' | 'CLOSED';

export interface AlarmCounts {
  red: number;
  orange: number;
  yellow: number;
  green: number;
  blue: number;
}

export interface Incident {
  incidentId: string;
  displayId: string;
  deviceName: string | null;
  deviceIp: string | null;
  summary: string;
  severity: Severity;
  /** Derived from `state` + `acknowledged` so the two can never disagree.
   * Kept because StatusBadge, SwipeableIncidentRow and the detail screen read
   * it; it is a view of the two fields below, never a third source. */
  status: IncidentStatus;
  /** The raw `incident_state` exactly as served, `ACKNOWLEDGED` and all.
   * Retained until the middleware's M1-drop. Do not filter on it — use `state`. */
  incidentState: string;
  state: IncidentState;
  acknowledged: boolean;
  ackUser: string | null;
  /** When the middleware recorded the close. Present only on CLOSED. */
  closedAt: Date | null;
  startTime: Date;
  acknowledgedBy: string | null;
  alarmCounts: AlarmCounts | null;
}

export type ApiError =
  | { kind: 'network'; message: string }
  | { kind: 'auth'; message: string }
  | { kind: 'server'; status: number; message: string }
  | { kind: 'parse'; message: string };

export class ApiException extends Error {
  constructor(public readonly error: ApiError) {
    super(error.message);
    this.name = 'ApiException';
  }
}

export interface IncidentAlarm {
  state: string;    // e.g. "CRITICAL", "MAJOR", "OK"
  type: string;     // e.g. "Host", "Service", "Threshold"
  name: string;
  output: string;   // HTML-stripped alarm output
  time: Date | null;
}

export interface IncidentLogEntry {
  state: string;
  time: Date | null;
  username: string;
  comment: string;
}

export interface IncidentDetail {
  incidentId: string;
  title: string;
  deviceName: string;
  deviceIp: string | null;
  incidentState: string;
  alertType: string | null;
  openTime: Date | null;
  acknowledged: boolean;
  ackTime: Date | null;
  ackUser: string | null;
  ackComment: string | null;
  alarmCounts: AlarmCounts;          // computed from primary + related alarms
  primaryAlarms: IncidentAlarm[];
  relatedAlarms: IncidentAlarm[];
  incidentLog: IncidentLogEntry[];
}

export interface PerformanceCategory {
  id: string;
  category: string;
}

export interface PerformanceInstance {
  key: string;
  title: string;
  unit: string;
  statGroup: string;
  valueKey: 'value1' | 'value2';
}

export interface TimeSeriesDataPoint {
  timestamp: number;
  value: number;
}

export interface TimeSeriesResult {
  instanceDescr: string;
  metricId: string;
  datapoints: TimeSeriesDataPoint[];
}
