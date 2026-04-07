import { Link, useParams } from 'react-router-dom';
import { useDeviceSearch } from './useDeviceSearch';
import { useIncidents } from '../incidents/useIncidents';
import { SwipeableIncidentRow } from '../incidents/SwipeableIncidentRow';
import { EmptyState } from '../../components/EmptyState';
import { PerformanceSection } from '../performance/PerformanceSection';

export function DeviceDetailScreen() {
  const { name } = useParams<{ name: string }>();
  const decodedName = name ? decodeURIComponent(name) : '';

  const { data: searchResults, isLoading, isError } = useDeviceSearch(decodedName);
  const { data: allIncidents } = useIncidents();

  const device = searchResults?.[0];
  const deviceIncidents = (allIncidents ?? []).filter(
    (inc) => inc.deviceName === decodedName,
  );

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800">
        <Link to="/devices" className="text-xs text-sky-400 hover:text-sky-300">
          &larr; Devices
        </Link>
        <h1 className="text-lg font-semibold mt-1">{decodedName}</h1>
      </header>

      {isLoading && (
        <EmptyState title="Loading..." description="Fetching device details." />
      )}

      {isError && (
        <EmptyState title="Could not load device" description="Failed to fetch device details." />
      )}

      {device && (
        <div className="p-4 space-y-4">
          {/* Device Info Card */}
          <div className="bg-slate-900 rounded-lg p-4 space-y-2">
            <h2 className="text-sm font-semibold text-slate-300 mb-2">Device Info</h2>
            <InfoRow label="IP Address" value={device.ip} mono />
            {device.model && <InfoRow label="Model" value={device.model} />}
            {device.serialNumber && <InfoRow label="Serial Number" value={device.serialNumber} />}
            <InfoRow label="Category" value={device.category || 'N/A'} />
            <InfoRow label="Site" value={device.site || 'N/A'} />
            {device.description && <InfoRow label="Description" value={device.description} />}
          </div>

          {/* Host Current Issues */}
          <div>
            <h2 className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
              Current Issues
            </h2>
            {deviceIncidents.length === 0 ? (
              <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
                No current issues
              </div>
            ) : (
              <div className="rounded-lg overflow-hidden">
                {deviceIncidents.map((incident) => (
                  <SwipeableIncidentRow key={incident.incidentId} incident={incident} />
                ))}
              </div>
            )}
          </div>

          {/* Performance */}
          <PerformanceSection
            deviceIndex={device.deviceIndex}
            deviceName={device.name}
          />
        </div>
      )}

      {!isLoading && !device && !isError && (
        <EmptyState title="Device not found" description={`No device named '${decodedName}'.`} />
      )}
    </div>
  );
}

function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex justify-between items-center text-sm">
      <span className="text-slate-500">{label}</span>
      <span className={`text-slate-200 ${mono ? 'font-mono' : ''}`}>{value}</span>
    </div>
  );
}
