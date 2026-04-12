export type Severity = 'critical' | 'major' | 'minor' | 'warning' | 'informational';
export type IncidentStatus = 'active' | 'acknowledged' | 'resolved' | 'closed';

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
  status: IncidentStatus;
  incidentState: string;
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
