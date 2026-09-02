// pwa/src/features/devices/DeviceRow.tsx
import { Link } from 'react-router-dom';
import type { Device } from '../../lib/api/devices';
import type { DeviceAlarmSummary } from '../../lib/deviceAlarms';
import { DeviceTypeIcon } from '../../components/DeviceTypeIcon';
import { AlarmBadges } from '../incidents/AlarmBadges';
import { classifyDevice } from '../../lib/deviceType';

const EMPTY_COUNTS = { red: 0, orange: 0, yellow: 0, green: 0, blue: 0 };

interface DeviceRowProps {
  device: Device;
  alarmSummary?: DeviceAlarmSummary;
  /** From the maintenance map; coexists with alarm badges (never masks them). */
  inMaintenance?: boolean;
  /** Locally-noted create not yet confirmed by the server — wrench blinks. */
  maintenancePending?: boolean;
}

export function DeviceRow({ device, alarmSummary, inMaintenance, maintenancePending }: DeviceRowProps) {
  const type = classifyDevice(device);
  const counts = alarmSummary?.counts ?? EMPTY_COUNTS;
  const summaries = alarmSummary?.activeSummaries ?? [];
  const hasTicker = summaries.length > 0;
  const tickerText = summaries.join(' · ');
  // Keep scroll speed constant (~20 chars/s) regardless of how many incidents there are.
  // Minimum 6s so a single short summary doesn't flash past.
  const tickerDuration = `${Math.max(6, tickerText.length / 20)}s`;

  return (
    <Link
      to={`/devices/${encodeURIComponent(device.name)}`}
      className="flex items-stretch gap-3 px-4 py-2.5 border-b border-slate-800 hover:bg-slate-900"
    >
      {/* Device type icon */}
      <div className="self-center">
        <DeviceTypeIcon type={type} status={device.status} size={40} />
      </div>

      {/* Left info column */}
      <div className="flex-1 min-w-0 flex flex-col justify-center gap-0.5">
        <div className="flex items-center gap-1.5 min-w-0">
          <div className="text-sm font-semibold truncate">{device.name}</div>
          {inMaintenance && (
            <svg
              viewBox="0 0 24 24"
              className={`w-3.5 h-3.5 shrink-0 text-sky-400 ${maintenancePending ? 'animate-pulse motion-reduce:animate-none' : ''}`}
              fill="none"
              stroke="currentColor"
              strokeWidth="2.2"
              role="img"
              aria-label={maintenancePending ? 'Maintenance scheduled' : 'In maintenance'}
            >
              <path d="M14.7 6.3a4.5 4.5 0 0 0-6 5.7L3 17.7 6.3 21l5.7-5.7a4.5 4.5 0 0 0 5.7-6L14.6 12l-2.6-2.6z" />
            </svg>
          )}
        </div>
        <div className="text-[11px] text-slate-400 font-mono">{device.ip || 'No IP'}</div>
        <div className="text-[11px] text-slate-400 truncate">
          {[device.category, device.site].filter(Boolean).join(' · ')}
        </div>
      </div>

      {/* Right column: badges top, ticker bottom */}
      <div className="flex-1 min-w-0 flex flex-col justify-between items-end gap-1">
        <AlarmBadges counts={counts} />
        {hasTicker ? (
          <>
            <div
              className="w-full overflow-hidden"
              aria-hidden="true"
              style={{
                maskImage:
                  'linear-gradient(to right, transparent 0%, black 8%, black 92%, transparent 100%)',
                WebkitMaskImage:
                  'linear-gradient(to right, transparent 0%, black 8%, black 92%, transparent 100%)',
              }}
            >
              <div
                className="flex w-max animate-marquee motion-reduce:animate-none"
                style={{ animationDuration: tickerDuration }}
                aria-hidden="true"
              >
                <span className="text-[10px] whitespace-nowrap pr-8 text-red-400">
                  {tickerText}
                </span>
                <span className="text-[10px] whitespace-nowrap pr-8 text-red-400" aria-hidden="true">
                  {tickerText}
                </span>
              </div>
            </div>
            <span className="sr-only">{tickerText}</span>
          </>
        ) : (
          <div className="h-[14px]" />
        )}
      </div>
    </Link>
  );
}
