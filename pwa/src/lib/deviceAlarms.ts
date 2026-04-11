import type { Incident, AlarmCounts } from './api/types';

export interface DeviceAlarmSummary {
  counts: AlarmCounts;
  activeSummaries: string[];
}

const SEVERITY_ORDER = ['critical', 'major', 'minor', 'warning', 'informational'] as const;

function emptyCounts(): AlarmCounts {
  return { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
}

export function buildDeviceAlarmMap(incidents: Incident[]): Map<string, DeviceAlarmSummary> {
  const map = new Map<string, DeviceAlarmSummary>();
  // Track active incidents per device for sorting
  const activeByDevice = new Map<string, Incident[]>();

  for (const inc of incidents) {
    if (!inc.deviceName) continue;

    if (!map.has(inc.deviceName)) {
      map.set(inc.deviceName, { counts: emptyCounts(), activeSummaries: [] });
      activeByDevice.set(inc.deviceName, []);
    }
    const entry = map.get(inc.deviceName)!;

    if (inc.status === 'acknowledged') {
      entry.counts.blue += 1;
    } else if (inc.status === 'active') {
      if (inc.severity === 'critical') entry.counts.red += 1;
      else if (inc.severity === 'major' || inc.severity === 'minor') entry.counts.orange += 1;
      else if (inc.severity === 'warning') entry.counts.yellow += 1;
      else if (inc.severity === 'informational') entry.counts.blue += 1;
      activeByDevice.get(inc.deviceName)!.push(inc);
    } else {
      // resolved or closed
      entry.counts.green += 1;
    }
  }

  // Build sorted activeSummaries for each device
  for (const [deviceName, entry] of map.entries()) {
    const active = activeByDevice.get(deviceName) ?? [];
    active.sort(
      (a, b) => SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity),
    );
    entry.activeSummaries = active.map((i) => i.summary);
  }

  return map;
}
