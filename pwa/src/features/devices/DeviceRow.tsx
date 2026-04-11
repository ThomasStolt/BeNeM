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
}

export function DeviceRow({ device, alarmSummary }: DeviceRowProps) {
  const type = classifyDevice(device);
  const counts = alarmSummary?.counts ?? EMPTY_COUNTS;
  const summaries = alarmSummary?.activeSummaries ?? [];
  const hasTicker = summaries.length > 0;
  const tickerText = summaries.join(' · ');

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
        <div className="text-sm font-semibold truncate">{device.name}</div>
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
              <div className="flex w-max animate-marquee motion-reduce:animate-none" aria-hidden="true">
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
