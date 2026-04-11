import type { Incident, AlarmCounts } from './api/types';

export interface DeviceAlarmSummary {
  counts: AlarmCounts;
  activeSummaries: string[];
}

const SEVERITY_ORDER = ['critical', 'major', 'minor', 'warning', 'informational'] as const;

function emptyCounts(): AlarmCounts {
  return { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
}

/**
 * Build a map of deviceName → alarm summary from a list of incidents.
 *
 * When thresholdCounts is provided, counts.green is computed as:
 *   thresholds_for_device − active_incident_count
 * (clamped to 0). This represents how many monitored checks are currently
 * healthy. The device detail screen adds ok service checks on top.
 *
 * When thresholdCounts is omitted, counts.green stays 0.
 */
export function buildDeviceAlarmMap(
  incidents: Incident[],
  thresholdCounts: Map<string, number> = new Map(),
): Map<string, DeviceAlarmSummary> {
  const map = new Map<string, DeviceAlarmSummary>();
  const activeCountByDevice = new Map<string, number>();
  const activeByDevice = new Map<string, Incident[]>();

  for (const inc of incidents) {
    if (!inc.deviceName) continue;

    if (!map.has(inc.deviceName)) {
      map.set(inc.deviceName, { counts: emptyCounts(), activeSummaries: [] });
      activeByDevice.set(inc.deviceName, []);
      activeCountByDevice.set(inc.deviceName, 0);
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
      activeCountByDevice.set(inc.deviceName, (activeCountByDevice.get(inc.deviceName) ?? 0) + 1);
    }
    // resolved/closed incidents are not counted — they are gone
  }

  // Compute green for devices with threshold data
  for (const [deviceName, thresholds] of thresholdCounts) {
    if (!map.has(deviceName)) {
      map.set(deviceName, { counts: emptyCounts(), activeSummaries: [] });
    }
    const entry = map.get(deviceName)!;
    const activeCount = activeCountByDevice.get(deviceName) ?? 0;
    entry.counts.green = Math.max(0, thresholds - activeCount);
  }

  // Sort active summaries: critical first
  for (const [deviceName, entry] of map.entries()) {
    const active = activeByDevice.get(deviceName) ?? [];
    active.sort(
      (a, b) => SEVERITY_ORDER.indexOf(a.severity) - SEVERITY_ORDER.indexOf(b.severity),
    );
    entry.activeSummaries = active.map((i) => i.summary);
  }

  return map;
}
