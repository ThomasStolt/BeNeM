import { useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useConfig } from '../lib/config';
import { ConnectionBadge, type ConnectionStatus } from './ConnectionBadge';
import { UpdatedAt } from './UpdatedAt';

interface AppHeaderProps {
  title: string;
  isLoading?: boolean;
  isError?: boolean;
  dataUpdatedAt?: number;
  onRefresh?: () => void;
}

export function AppHeader({
  title,
  isLoading = false,
  isError = false,
  dataUpdatedAt = 0,
  onRefresh,
}: AppHeaderProps) {
  const config = useConfig();
  const navigate = useNavigate();
  // Badge tap opens Diagnostics (parity with iOS — refresh lives beside it).
  const handleBadgeTap = useCallback(() => {
    navigate('/diagnostics');
  }, [navigate]);
  const handleRefresh = useCallback(() => {
    onRefresh?.();
  }, [onRefresh]);

  const derivedStatus: ConnectionStatus =
    !config.isConfigured ? 'disconnected' :
    isLoading             ? 'checking'     :
    isError               ? 'disconnected' :
    dataUpdatedAt > 0     ? 'connected'    :
                            'unknown';

  return (
    <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
      <ConnectionBadge status={derivedStatus} onRetry={handleBadgeTap} />
      <div className="text-center">
        <div className="flex items-center justify-center gap-1.5">
          <img src="/app-mark.png" alt="BHNM" className="w-6 h-6 rounded-md flex-shrink-0" />
          <h1 className="text-lg font-bold">{title}</h1>
        </div>
        {config.serverName && (
          <p className="text-[11px] text-slate-500">{config.serverName}</p>
        )}
      </div>
      {dataUpdatedAt > 0 ? (
        <UpdatedAt updatedAt={dataUpdatedAt} isLoading={isLoading} onRefresh={handleRefresh} />
      ) : (
        <div className="w-10" />
      )}
    </header>
  );
}
