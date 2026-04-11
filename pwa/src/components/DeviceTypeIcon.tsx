import type { DeviceTypeClass } from '../lib/deviceType';
import type { DeviceStatus } from '../lib/api/devices';

const STATUS_COLORS: Record<DeviceStatus, string> = {
  up: '#0284c7',
  down: '#dc2626',
  critical: '#dc2626',
  warning: '#d97706',
  maintenance: '#6b7280',
  unknown: '#374151',
};

function LinuxIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="white" width="60%" height="60%">
      <ellipse cx="12" cy="16.5" rx="6" ry="5.5" />
      <ellipse cx="12" cy="7.5" rx="5" ry="5.5" />
      <ellipse cx="5.5" cy="13" rx="2.5" ry="4" transform="rotate(-10 5.5 13)" />
      <ellipse cx="18.5" cy="13" rx="2.5" ry="4" transform="rotate(10 18.5 13)" />
      <path
        d="M9 22 L7.5 24 M9 22 L10.5 24 M15 22 L13.5 24 M15 22 L16.5 24"
        stroke="white"
        strokeWidth="1.2"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}

function WindowsIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="white" width="60%" height="60%">
      <rect x="2" y="2" width="9" height="9" rx="1" />
      <rect x="13" y="2" width="9" height="9" rx="1" />
      <rect x="2" y="13" width="9" height="9" rx="1" />
      <rect x="13" y="13" width="9" height="9" rx="1" />
    </svg>
  );
}

function RouterIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="white"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      width="62%"
      height="62%"
    >
      <rect x="4" y="7" width="16" height="10" rx="2.5" />
      <line x1="12" y1="7" x2="12" y2="4" />
      <line x1="12" y1="20" x2="12" y2="17" />
      <line x1="4" y1="12" x2="1" y2="12" />
      <line x1="23" y1="12" x2="20" y2="12" />
    </svg>
  );
}

function SwitchIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="white"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      width="62%"
      height="62%"
    >
      <path d="M4 9h16M4 9l4-4M4 9l4 4" />
      <path d="M20 15H4M20 15l-4-4M20 15l-4 4" />
    </svg>
  );
}

function UnknownIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="white"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      width="62%"
      height="62%"
    >
      <rect x="2" y="3" width="20" height="14" rx="2" />
      <line x1="8" y1="21" x2="16" y2="21" />
      <line x1="12" y1="17" x2="12" y2="21" />
    </svg>
  );
}

const ICONS: Record<DeviceTypeClass, () => JSX.Element> = {
  linux: LinuxIcon,
  windows: WindowsIcon,
  router: RouterIcon,
  switch: SwitchIcon,
  unknown: UnknownIcon,
};

interface DeviceTypeIconProps {
  type: DeviceTypeClass;
  status: DeviceStatus;
  size: number;
}

export function DeviceTypeIcon({ type, status, size }: DeviceTypeIconProps) {
  const Icon = ICONS[type];
  return (
    <div
      style={{
        width: `${size}px`,
        height: `${size}px`,
        backgroundColor: STATUS_COLORS[status],
        borderRadius: '10px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0,
      }}
    >
      <Icon />
    </div>
  );
}
