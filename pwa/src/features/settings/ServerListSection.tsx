import { useState } from 'react';
import {
  setActiveServer,
  removeServer,
  type ServerConfig,
} from '../../lib/serverStorage';
import { notifyConfigChanged } from '../../lib/config';

interface Props {
  servers: ServerConfig[];
  onServersChanged: () => void;
  onEditServer: (server: ServerConfig) => void;
  onAddServer: () => void;
}

export function ServerListSection({
  servers,
  onServersChanged,
  onEditServer,
  onAddServer,
}: Props) {
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);

  const handleSwitch = (id: string) => {
    setActiveServer(id);
    notifyConfigChanged();
    onServersChanged();
  };

  const handleDelete = (id: string) => {
    if (confirmDeleteId === id) {
      removeServer(id);
      notifyConfigChanged();
      onServersChanged();
      setConfirmDeleteId(null);
    } else {
      setConfirmDeleteId(id);
    }
  };

  return (
    <div>
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        Servers
      </div>
      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {servers.length === 0 && (
          <div className="p-3 text-sm text-slate-500">No servers configured.</div>
        )}
        {servers.map((server) => (
          <div key={server.id} className="p-3 flex items-center gap-3">
            {/* Active indicator */}
            <button
              type="button"
              onClick={() => handleSwitch(server.id)}
              className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 ${
                server.isActive
                  ? 'border-sky-500 bg-sky-500'
                  : 'border-slate-600 hover:border-slate-400'
              }`}
              aria-label={server.isActive ? `${server.name} (active)` : `Switch to ${server.name}`}
            >
              {server.isActive && (
                <svg className="w-3 h-3 text-white" fill="none" viewBox="0 0 24 24"
                  stroke="currentColor" strokeWidth="3">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                </svg>
              )}
            </button>

            {/* Server info */}
            <button
              type="button"
              onClick={() => onEditServer(server)}
              className="flex-1 text-left"
            >
              <div className="text-sm font-medium text-slate-200">{server.name}</div>
              <div className="text-xs text-slate-500">{server.baseUrl}</div>
            </button>

            {/* Delete */}
            <button
              type="button"
              onClick={() => handleDelete(server.id)}
              className={`text-xs px-2 py-1 rounded ${
                confirmDeleteId === server.id
                  ? 'bg-red-600 text-white'
                  : 'text-slate-500 hover:text-red-400'
              }`}
            >
              {confirmDeleteId === server.id ? 'Confirm' : 'Delete'}
            </button>
          </div>
        ))}
      </div>
      <button
        type="button"
        onClick={onAddServer}
        className="mt-3 w-full py-2 rounded bg-slate-900 border border-slate-700 text-sm text-slate-300 hover:bg-slate-800"
      >
        + Add Server
      </button>
    </div>
  );
}
