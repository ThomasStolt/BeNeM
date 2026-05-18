// pwa/src/features/devices/DeviceDetailScreen.tsx
import { useState, useMemo } from 'react';
import { useParams } from 'react-router-dom';
import { useDeviceSearch } from './useDeviceSearch';
import { useIncidents } from '../incidents/useIncidents';
import { SeverityBadge } from '../incidents/SeverityBadge';
import { EmptyState } from '../../components/EmptyState';
import { PerformanceSection } from '../performance/PerformanceSection';
import { MaintenanceDialog } from './MaintenanceDialog';
import { LatencyMiniChart } from './LatencyMiniChart';
import { DeviceTypeIcon } from '../../components/DeviceTypeIcon';
import { createMaintenanceWindow } from '../../lib/api/maintenance';
import { useConfig } from '../../lib/config';
import { classifyDevice } from '../../lib/deviceType';
import { buildDeviceAlarmMap } from '../../lib/deviceAlarms';
import { useThresholds } from './useThresholds';
import { useDeviceServices } from './useDeviceServices';
import type { Incident } from '../../lib/api/types';

// ── Status helpers ────────────────────────────────────────────────
const STATUS_LABELS: Record<string, string> = {
  up: 'UP', down: 'DOWN', warning: 'WARNING',
  critical: 'CRITICAL', maintenance: 'MAINTENANCE', unknown: 'UNKNOWN',
};
const STATUS_COLORS: Record<string, string> = {
  up: 'text-green-400', down: 'text-red-400', warning: 'text-amber-400',
  critical: 'text-red-400', maintenance: 'text-slate-400', unknown: 'text-slate-500',
};

// ── Duration helper ───────────────────────────────────────────────
function duration(start: Date): string {
  const ms = Date.now() - start.getTime();
  const m = Math.floor(ms / 60_000);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ${m % 60}m`;
  return `${Math.floor(h / 24)}d ${h % 24}h`;
}

// ── Collapsible section wrapper ───────────────────────────────────
function CollapsibleSection({
  title,
  badge,
  defaultOpen = false,
  children,
}: {
  title: string;
  badge?: number;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  const panelId = `section-${title.toLowerCase().replace(/\s+/g, '-')}`;
  return (
    <div className="bg-slate-800 rounded-xl overflow-hidden">
      <button
        aria-expanded={open}
        aria-controls={panelId}
        className="w-full flex items-center justify-between px-4 py-3 text-left"
        onClick={() => setOpen((v) => !v)}
      >
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-slate-100">{title}</span>
          {badge !== undefined && badge > 0 && (
            <span className="bg-red-600 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full">
              {badge}
            </span>
          )}
        </div>
        <svg
          viewBox="0 0 20 20"
          fill="currentColor"
          className={`w-4 h-4 text-slate-400 transition-transform duration-200 ${open ? 'rotate-180' : ''}`}
        >
          <path
            fillRule="evenodd"
            d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
            clipRule="evenodd"
          />
        </svg>
      </button>
      {open && (
        <div id={panelId} className="border-t border-slate-700">
          {children}
        </div>
      )}
    </div>
  );
}

// ── InfoRow ───────────────────────────────────────────────────────
function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex justify-between items-start gap-4 text-sm px-4 py-2">
      <span className="text-slate-500 shrink-0">{label}</span>
      <span className={`text-slate-200 text-right break-all ${mono ? 'font-mono' : ''}`}>{value}</span>
    </div>
  );
}

// ── Incident table row ────────────────────────────────────────────
function IssueRow({ incident }: { incident: Incident }) {
  return (
    <div
      className="grid px-4 py-2.5 border-b border-slate-700 last:border-0"
      style={{ gridTemplateColumns: '80px 1fr 56px', gap: '8px', alignItems: 'start' }}
    >
      <SeverityBadge severity={incident.severity} />
      <p className="text-xs text-slate-200 line-clamp-2">{incident.summary}</p>
      <p className="text-[11px] text-slate-500 text-right">{duration(incident.startTime)}</p>
    </div>
  );
}

// ── Main screen ───────────────────────────────────────────────────
export function DeviceDetailScreen() {
  const { name } = useParams<{ name: string }>();
  const decodedName = name ? decodeURIComponent(name) : '';

  const config = useConfig();
  const [showMaintenance, setShowMaintenance] = useState(false);

  const { data: searchResults, isLoading, isError } = useDeviceSearch(decodedName);
  const { data: allIncidents } = useIncidents();

  const device = searchResults?.[0];

  const deviceIncidents = useMemo(
    () => (allIncidents ?? []).filter((inc) => inc.deviceName === decodedName),
    [allIncidents, decodedName],
  );

  const { data: thresholdCounts } = useThresholds();
  const { data: okServices = 0 } = useDeviceServices(decodedName);

  const alarmSummary = useMemo(() => {
    const map = buildDeviceAlarmMap(allIncidents ?? [], thresholdCounts ?? new Map());
    return map.get(decodedName);
  }, [allIncidents, thresholdCounts, decodedName]);

  // HEALTHY = (thresholds − active incidents) + ok service checks
  const rawCounts = alarmSummary?.counts ?? { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };
  const counts = { ...rawCounts, green: rawCounts.green + okServices };

  return (
    <div className="min-h-full">
      {isLoading && <EmptyState title="Loading..." description="Fetching device details." />}
      {isError && (
        <EmptyState title="Could not load device" description="Failed to fetch device details." />
      )}

      {device && (
        <div className="p-4 space-y-3">
          {/* ── Screen title ── */}
          <div className="text-center">
            <h1 className="text-xl font-bold text-slate-100 truncate">{device.name}</h1>
            <p className="text-sm text-slate-400 font-mono mt-0.5">{device.ip}</p>
          </div>

          {/* ── Header card ── */}
          <div className="bg-slate-800 rounded-xl p-3.5 flex items-center gap-3" style={{ minHeight: '80px' }}>
            {/* Icon */}
            <div className="self-center shrink-0">
              <DeviceTypeIcon type={classifyDevice(device)} status={device.status} size={52} />
            </div>

            {/* Info column */}
            <div className="flex flex-col justify-center gap-1 min-w-0" style={{ flex: '0 0 38%' }}>
              {device.description && (
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <svg viewBox="0 0 24 24" className="w-3 h-3 shrink-0" fill="none" stroke="currentColor" strokeWidth="2">
                    <rect x="2" y="2" width="20" height="8" rx="2" ry="2" />
                    <rect x="2" y="14" width="20" height="8" rx="2" ry="2" />
                    <line x1="6" y1="6" x2="6.01" y2="6" />
                    <line x1="6" y1="18" x2="6.01" y2="18" />
                  </svg>
                  {device.description}
                </p>
              )}
              {device.category && (
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <svg
                    viewBox="0 0 24 24"
                    className="w-3 h-3 shrink-0"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                  >
                    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
                  </svg>
                  {device.category}
                </p>
              )}
              {device.site && (
                <p className="text-[11px] text-slate-400 flex items-center gap-1">
                  <svg
                    viewBox="0 0 24 24"
                    className="w-3 h-3 shrink-0"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                  >
                    <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                  </svg>
                  {device.site}
                </p>
              )}
              <p
                className={`text-[10px] font-semibold flex items-center gap-1 ${STATUS_COLORS[device.status] ?? 'text-slate-500'}`}
              >
                <span className="w-2 h-2 rounded-full bg-current inline-block" />
                {STATUS_LABELS[device.status] ?? device.status.toUpperCase()}
              </p>
            </div>

            {/* Latency mini chart — flex-1 always reserves the column */}
            <div className="flex-1 min-w-0 self-stretch">
              <LatencyMiniChart deviceIndex={device.deviceIndex} deviceName={device.name} />
            </div>
          </div>

          {/* ── Alarm summary bar ── */}
          <div className="grid grid-cols-4">
            {[
              { label: 'HEALTHY', value: counts.green, activeColor: 'text-green-500' },
              { label: 'ACK', value: counts.blue, activeColor: 'text-blue-400' },
              { label: 'WARNING', value: counts.yellow + counts.orange, activeColor: 'text-yellow-300' },
              { label: 'CRITICAL', value: counts.red, activeColor: 'text-red-400' },
            ].map((col, i) => {
              const color = col.value === 0 ? 'text-slate-600' : col.activeColor;
              return (
                <div
                  key={col.label}
                  className={`text-center ${i > 0 ? 'border-l border-slate-700' : ''}`}
                >
                  <p className={`text-[26px] font-bold leading-none ${color}`}>{col.value}</p>
                  <p className={`text-[9px] font-semibold tracking-widest mt-0.5 ${color}`}>
                    {col.label}
                  </p>
                </div>
              );
            })}
          </div>

          {/* ── Maintenance Window card ── */}
          <button
            onClick={() => setShowMaintenance(true)}
            className="w-full bg-slate-800 rounded-xl py-3.5 text-sm font-medium text-sky-400 hover:bg-slate-700 transition-colors"
          >
            + Create Maintenance Window
          </button>

          <MaintenanceDialog
            deviceName={decodedName}
            username={config.ackUser}
            isOpen={showMaintenance}
            onClose={() => setShowMaintenance(false)}
            onSubmit={(dur, comment) =>
              createMaintenanceWindow(config, decodedName, dur, comment)
            }
          />

          {/* ── Host Information (collapsed by default) ── */}
          <CollapsibleSection title="Host Information" defaultOpen={false}>
            <InfoRow label="Current State" value={STATUS_LABELS[device.status] ?? device.status} />
            {device.description && <InfoRow label="Description" value={device.description} />}
            {device.category && <InfoRow label="Category" value={device.category} />}
            {device.site && <InfoRow label="Site" value={device.site} />}
            {device.model && <InfoRow label="Model" value={device.model} />}
            {device.serialNumber && <InfoRow label="Serial Number" value={device.serialNumber} />}
            <InfoRow label="UID" value={device.deviceIndex} mono />
          </CollapsibleSection>

          {/* ── Current Issues (expanded by default) ── */}
          <CollapsibleSection
            title="Current Issues"
            badge={deviceIncidents.length}
            defaultOpen={true}
          >
            {deviceIncidents.length === 0 ? (
              <div className="px-4 py-5 flex items-center justify-center gap-2 text-slate-400 text-sm">
                <svg
                  viewBox="0 0 24 24"
                  className="w-4 h-4"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                >
                  <path d="M20 6L9 17l-5-5" />
                </svg>
                No current issues
              </div>
            ) : (
              <div>
                {deviceIncidents.map((inc) => (
                  <IssueRow key={inc.incidentId} incident={inc} />
                ))}
              </div>
            )}
          </CollapsibleSection>

          {/* ── Performance ── */}
          <PerformanceSection deviceIndex={device.deviceIndex} deviceName={device.name} />
        </div>
      )}

      {!isLoading && !device && !isError && (
        <EmptyState
          title="Device not found"
          description={`No device named '${decodedName}'.`}
        />
      )}
    </div>
  );
}
