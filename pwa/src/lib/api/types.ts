export type Severity = 'critical' | 'major' | 'minor' | 'warning' | 'informational';
export type IncidentStatus = 'active' | 'acknowledged' | 'resolved' | 'closed';

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
