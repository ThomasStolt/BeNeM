import { useConfig } from '../lib/config';
import { ConnectionBadge, type ConnectionStatus } from './ConnectionBadge';
import { RefreshRing } from './RefreshRing';

interface AppHeaderProps {
  title: string;
  isLoading?: boolean;
  isError?: boolean;
  dataUpdatedAt?: number;
  intervalMs?: number;
  onRefresh?: () => void;
}

export function AppHeader({
  title,
  isLoading = false,
  isError = false,
  dataUpdatedAt = 0,
  intervalMs = 120_000,
  onRefresh,
}: AppHeaderProps) {
  const config = useConfig();
  const handleRefresh = onRefresh ?? (() => {});

  const derivedStatus: ConnectionStatus =
    !config.isConfigured ? 'disconnected' :
    isLoading             ? 'checking'     :
    isError               ? 'disconnected' :
    dataUpdatedAt > 0     ? 'connected'    :
                            'unknown';

  return (
    <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
      <ConnectionBadge status={derivedStatus} onRetry={handleRefresh} />
      <div className="text-center">
        <div className="flex items-center justify-center gap-1.5">
          <div className="w-6 h-6 bg-blue-600 rounded-md flex items-center justify-center text-[12px] font-bold text-white flex-shrink-0">
            B
          </div>
          <h1 className="text-lg font-bold">{title}</h1>
        </div>
        {config.serverName && (
          <p className="text-[11px] text-slate-500">{config.serverName}</p>
        )}
      </div>
      {dataUpdatedAt > 0 ? (
        <RefreshRing
          lastUpdatedAt={dataUpdatedAt}
          intervalMs={intervalMs}
          isLoading={isLoading}
          onRefresh={handleRefresh}
        />
      ) : (
        <div className="w-10" />
      )}
    </header>
  );
}
