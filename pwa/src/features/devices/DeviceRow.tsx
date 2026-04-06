import { Link } from 'react-router-dom';
import type { Device } from '../../lib/api/devices';

export function DeviceRow({ device }: { device: Device }) {
  return (
    <Link
      to={`/devices/${encodeURIComponent(device.name)}`}
      className="block border-b border-slate-800 px-4 py-3 hover:bg-slate-900"
    >
      <div className="flex items-center gap-3">
        <div className="flex-1 min-w-0">
          <div className="text-sm font-medium truncate">{device.name}</div>
          <div className="text-xs text-slate-400 font-mono truncate">{device.ip || 'No IP'}</div>
        </div>
        {device.category && (
          <span className="text-xs px-2 py-0.5 rounded bg-slate-800 text-slate-400 shrink-0">
            {device.category}
          </span>
        )}
      </div>
    </Link>
  );
}
