import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import {
  loadServers,
  addServer,
  updateServer,
  removeServer,
  type ServerConfig,
  type NewServerInput,
} from '../../lib/serverStorage';
import { subscribeToPush, unsubscribeFromPush, getPushState, type PushState } from '../../lib/pushRegistration';
import { ServerListSection } from './ServerListSection';
import { ServerForm } from './ServerForm';
import { QRScannerOverlay } from '../scanner/QRScannerOverlay';
import { QRConfirmScreen } from '../scanner/QRConfirmScreen';
import { parseQRUrl, type ParsedServerConfig } from '../../lib/qr-parser';

type View = 'list' | 'add' | 'edit';

export function SettingsScreen() {
  useConfig(); // subscribe to config changes
  const queryClient = useQueryClient();
  const [servers, setServers] = useState(loadServers);
  const [view, setView] = useState<View>('list');
  const [editingServer, setEditingServer] = useState<ServerConfig | null>(null);
  const [pushState, setPushState] = useState<PushState>(getPushState);
  const [pushLoading, setPushLoading] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [scannedConfig, setScannedConfig] = useState<ParsedServerConfig | null>(null);
  const [existingServerId, setExistingServerId] = useState<string | undefined>(undefined);
  const hasCamera = typeof navigator !== 'undefined' && !!navigator.mediaDevices;

  const refreshServers = useCallback(() => {
    setServers(loadServers());
  }, []);

  const handleAddServer = (input: NewServerInput) => {
    addServer(input);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    queryClient.invalidateQueries();
  };

  const handleEditServer = (input: NewServerInput) => {
    if (!editingServer) return;
    updateServer(editingServer.id, input);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    setEditingServer(null);
    queryClient.invalidateQueries();
  };

  const handleEditClick = (server: ServerConfig) => {
    setEditingServer(server);
    setView('edit');
  };

  const handleDeleteServer = () => {
    if (!editingServer) return;
    removeServer(editingServer.id);
    notifyConfigChanged();
    refreshServers();
    setView('list');
    setEditingServer(null);
    queryClient.invalidateQueries();
  };

  const handleTogglePush = async () => {
    if (pushLoading) return;
    const activeServer = servers.find((s) => s.isActive);
    if (!activeServer) return;

    const webhookSecret = activeServer.pushWebhookSecret;
    const middlewareUrl = activeServer.pushMiddlewareUrl ?? activeServer.baseUrl;

    setPushLoading(true);
    try {
      if (activeServer.pushEnabled) {
        await unsubscribeFromPush();
        updateServer(activeServer.id, { pushEnabled: false });
        notifyConfigChanged();
        refreshServers();
        setPushState({ status: 'unregistered' });
      } else {
        if (!webhookSecret) {
          setPushState({ status: 'error', message: 'Webhook secret is required' });
          setPushLoading(false);
          return;
        }
        const endpoint = await subscribeToPush(middlewareUrl, webhookSecret);
        updateServer(activeServer.id, { pushEnabled: true });
        notifyConfigChanged();
        refreshServers();
        setPushState({ status: 'registered', endpoint });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Push registration failed';
      setPushState({ status: 'error', message: msg });
    } finally {
      setPushLoading(false);
    }
  };

  const handleScanResult = async (decodedText: string) => {
    setShowScanner(false);
    try {
      const config = await parseQRUrl(decodedText);
      const existing = loadServers().find((s) =>
        (config.bhnmUrl && s.bhnmUrl === config.bhnmUrl) || s.baseUrl === config.baseUrl,
      );
      setExistingServerId(existing?.id);
      setScannedConfig(config);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Could not read QR code';
      setScanError(`QR Error: ${msg}`);
    }
  };

  const handleScanConfirm = () => {
    if (!scannedConfig) return;
    if (existingServerId) {
      updateServer(existingServerId, {
        name: scannedConfig.name,
        baseUrl: scannedConfig.baseUrl,
        bhnmUrl: scannedConfig.bhnmUrl,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        ackUser: scannedConfig.ackUser ?? '',
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
        isQrProvisioned: true,
      });
    } else {
      addServer({
        name: scannedConfig.name,
        baseUrl: scannedConfig.baseUrl,
        bhnmUrl: scannedConfig.bhnmUrl,
        apiKey: scannedConfig.apiKey,
        pin: scannedConfig.pin,
        ackUser: scannedConfig.ackUser ?? '',
        pushWebhookSecret: scannedConfig.pushWebhookSecret,
        isQrProvisioned: true,
      });
    }
    notifyConfigChanged();
    refreshServers();
    setScannedConfig(null);
    setExistingServerId(undefined);
    queryClient.invalidateQueries();
  };

  const activeServer = servers.find((s) => s.isActive);

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-300 hover:text-white" aria-label="Back to dashboard">
          ← Back
        </Link>
        <h1 className="text-lg font-semibold">Settings</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      <div className="p-4 space-y-6 max-w-md">
        {view === 'list' && (
          <>
            <ServerListSection
              servers={servers}
              onServersChanged={() => {
                refreshServers();
                queryClient.invalidateQueries();
              }}
              onEditServer={handleEditClick}
              onAddServer={() => setView('add')}
            />

            {hasCamera && (
              <button
                type="button"
                onClick={() => { setScanError(null); setShowScanner(true); }}
                className="w-full py-2.5 rounded-lg bg-slate-800 text-sm text-sky-400 hover:bg-slate-700 mt-2"
              >
                Scan QR Code
              </button>
            )}

            {scanError && (
              <div className="bg-red-900/30 border border-red-800 rounded-lg p-3 mt-2">
                <p className="text-sm text-red-300">{scanError}</p>
                <div className="flex gap-2 mt-2">
                  <button
                    type="button"
                    onClick={() => { setScanError(null); setShowScanner(true); }}
                    className="text-xs text-sky-400 hover:text-sky-300"
                  >
                    Try Again
                  </button>
                  <button
                    type="button"
                    onClick={() => { setScanError(null); setView('add'); }}
                    className="text-xs text-slate-400 hover:text-slate-300"
                  >
                    Enter Server Manually
                  </button>
                </div>
              </div>
            )}

            {/* Push Notifications — for active server */}
            {activeServer && (
              <div>
                <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
                  Push Notifications
                </div>
                <div className="bg-slate-900 rounded-lg overflow-hidden">
                  <div className="p-3 flex items-center justify-between">
                    <div>
                      <div className="text-sm font-medium">Push Notifications</div>
                      <div className="text-xs text-slate-500 mt-0.5">
                        {pushState.status === 'unsupported' && 'Not supported in this browser'}
                        {pushState.status === 'denied' && 'Permission denied — enable in browser settings'}
                        {pushState.status === 'unregistered' && 'Not registered'}
                        {pushState.status === 'registered' && 'Registered and active'}
                        {pushState.status === 'error' && pushState.message}
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={handleTogglePush}
                      disabled={pushLoading || pushState.status === 'unsupported' || pushState.status === 'denied'}
                      className={`relative w-11 h-6 rounded-full transition-colors ${
                        activeServer.pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
                      } disabled:opacity-50 disabled:cursor-not-allowed`}
                      role="switch"
                      aria-checked={activeServer.pushEnabled}
                    >
                      <span
                        className="block w-5 h-5 rounded-full bg-white shadow transition-transform"
                        style={{ transform: activeServer.pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
                      />
                    </button>
                  </div>
                </div>
              </div>
            )}

            {/* About */}
            <div className="border-t border-slate-800 pt-6">
              <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">About</div>
              <div className="bg-slate-900 rounded-lg p-3">
                <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
                  <dt className="text-slate-500">Version</dt>
                  <dd>0.5.0</dd>
                  <dt className="text-slate-500">Platform</dt>
                  <dd>PWA (Web Push)</dd>
                </dl>
              </div>
            </div>
          </>
        )}

        {view === 'add' && (
          <ServerForm
            onSave={handleAddServer}
            onCancel={() => setView('list')}
          />
        )}

        {view === 'edit' && editingServer && (
          <ServerForm
            server={editingServer}
            onSave={handleEditServer}
            onCancel={() => { setView('list'); setEditingServer(null); }}
            onDelete={handleDeleteServer}
          />
        )}
      </div>

      {showScanner && (
        <QRScannerOverlay
          onScanned={handleScanResult}
          onCancel={() => setShowScanner(false)}
          onError={(msg) => { setShowScanner(false); setScanError(msg); }}
        />
      )}

      {scannedConfig && (
        <div className="fixed inset-0 z-50 bg-slate-950/90 flex items-center justify-center">
          <QRConfirmScreen
            config={scannedConfig}
            onConfirm={handleScanConfirm}
            onCancel={() => { setScannedConfig(null); setExistingServerId(undefined); }}
            existingServerId={existingServerId}
          />
          {/* Debug: visible proof the overlay rendered — remove after fixing */}
          <div className="fixed bottom-4 left-4 right-4 bg-yellow-600 text-black text-xs p-2 rounded z-[60]">
            QR parsed: {scannedConfig.name} | baseUrl: {scannedConfig.baseUrl} | bhnmUrl: {scannedConfig.bhnmUrl}
          </div>
        </div>
      )}
    </div>
  );
}
