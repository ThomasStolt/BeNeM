import { useState, useDeferredValue, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { useDevices, PAGE_SIZE } from './useDevices';
import { useDeviceSearch } from './useDeviceSearch';
import { DeviceRow } from './DeviceRow';
import { RefreshCountdown } from '../../components/RefreshCountdown';
import { EmptyState } from '../../components/EmptyState';
import { useIncidents } from '../incidents/useIncidents';
import { buildDeviceAlarmMap } from '../../lib/deviceAlarms';

export function DeviceListScreen() {
  const config = useConfig();
  const [page, setPage] = useState(0);
  const [searchInput, setSearchInput] = useState('');
  const deferredQuery = useDeferredValue(searchInput);

  const { data: result, isLoading, isError, error, dataUpdatedAt } = useDevices(page);
  const { data: searchResults, isFetching: isSearching } = useDeviceSearch(deferredQuery);
  const { data: allIncidents } = useIncidents();
  const deviceAlarmMap = useMemo(
    () => buildDeviceAlarmMap(allIncidents ?? []),
    [allIncidents],
  );

  const devices = result?.devices;
  const totalRecords = result?.totalRecords ?? 0;
  const totalPages = totalRecords > 0 ? Math.ceil(totalRecords / PAGE_SIZE) : 0;

  const isSearchActive = deferredQuery.length > 0;
  const displayDevices = isSearchActive ? searchResults : devices;

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold">Devices</h1>
          {!isSearchActive && devices && devices.length > 0 && (
            <p className="text-xs text-slate-500">
              Page {page + 1}{totalPages > 0 ? ` of ${totalPages}` : ''}
            </p>
          )}
        </div>
        <div className="flex items-center gap-3">
          {dataUpdatedAt > 0 && (
            <RefreshCountdown lastUpdatedAt={dataUpdatedAt} intervalMs={120_000} />
          )}
        </div>
      </header>

      {!config.isConfigured && (
        <EmptyState
          title="Not configured"
          description="Add a server in Settings to view devices."
          action={
            <Link to="/settings" className="px-4 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm text-white">
              Configure
            </Link>
          }
        />
      )}

      {config.isConfigured && (
        <>
          <div className="px-4 py-2 border-b border-slate-800">
            <div className="relative">
              <input
                type="text"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                placeholder="Search devices by name..."
                className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder:text-slate-500 focus:outline-none focus:border-sky-600"
              />
              {searchInput && (
                <button
                  onClick={() => setSearchInput('')}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300 text-sm px-1"
                >
                  ✕
                </button>
              )}
            </div>
            {isSearchActive && isSearching && (
              <p className="text-xs text-slate-500 mt-1">Searching...</p>
            )}
          </div>

          {isLoading && !isSearchActive && (
            <EmptyState title="Loading..." description="Fetching devices from BHNM." />
          )}

          {isError && !isSearchActive && (
            <EmptyState title="Could not load devices" description={(error as Error).message} />
          )}

          {displayDevices && displayDevices.length === 0 && (
            <EmptyState
              title={isSearchActive ? `No devices matching '${deferredQuery}'` : 'No devices found'}
            />
          )}

          {displayDevices && displayDevices.length > 0 && (
            <div>
              {displayDevices.map((device) => (
                <DeviceRow
                  key={device.name}
                  device={device}
                  alarmSummary={deviceAlarmMap.get(device.name)}
                />
              ))}
            </div>
          )}

          {!isSearchActive && devices && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-slate-800">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}
                className="px-3 py-1.5 text-sm rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                Previous
              </button>
              <span className="text-xs text-slate-500">
                Page {page + 1}{totalPages > 0 ? ` of ${totalPages}` : ''}
              </span>
              <button
                onClick={() => setPage((p) => p + 1)}
                disabled={totalPages > 0 ? page + 1 >= totalPages : devices.length < PAGE_SIZE}
                className="px-3 py-1.5 text-sm rounded bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
