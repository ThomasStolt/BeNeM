import { useState, type FormEvent } from 'react';
import type { ServerConfig, NewServerInput } from '../../lib/serverStorage';
import { testConnection } from '../../lib/api/ha-status';
import type { HaStatusResult } from '../../lib/api/ha-status';
import { formatHaRole, formatHaStatus } from '../../lib/api/ha-status';

interface Props {
  server?: Partial<ServerConfig>;
  onSave: (input: NewServerInput) => void;
  onCancel: () => void;
  onDelete?: () => void;
}

type TestState = 'idle' | 'testing' | 'success' | 'failed';

function maskSecret(value: string): string {
  if (!value) return '';
  return '••••••••';
}

function ReadOnlyField({ label, value, masked }: { label: string; value: string; masked?: boolean }) {
  return (
    <div className="p-3">
      <div className="block text-xs text-slate-400 mb-1.5">{label}</div>
      <div className="text-sm text-slate-500 font-mono">{masked ? maskSecret(value) : value}</div>
    </div>
  );
}

export function ServerForm({ server, onSave, onCancel, onDelete }: Props) {
  const isEditing = !!server?.id;
  const isQr = server?.isQrProvisioned ?? false;

  const [name, setName] = useState(server?.name ?? '');
  const [bhnmUrl, setBhnmUrl] = useState(server?.bhnmUrl ?? '');
  const [baseUrl, setBaseUrl] = useState(server?.baseUrl ?? '/bhnm');
  const [apiKey, setApiKey] = useState(server?.apiKey ?? '');
  const [pin, setPin] = useState(server?.pin ?? '');
  const [ackUser, setAckUser] = useState(server?.ackUser ?? '');
  const [showKey, setShowKey] = useState(false);
  const [webhookSecret, setWebhookSecret] = useState(server?.pushWebhookSecret ?? '');
  const [pushEnabled, setPushEnabled] = useState(server?.pushEnabled ?? false);
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<HaStatusResult | null>(null);
  const [testError, setTestError] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setTestState('testing');
    setTestResult(null);
    setTestError('');
    try {
      const result = await testConnection({
        serverId: '',
        serverName: '',
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        pin: pin.trim() || undefined,
        isConfigured: apiKey.trim().length > 0,
        ackUser: '',
        bhnmUrl: '',
      });
      setTestResult(result);
      setTestState('success');
      onSave({
        name: name.trim() || 'BHNM Server',
        baseUrl: baseUrl.trim(),
        bhnmUrl: bhnmUrl.trim(),
        apiKey: apiKey.trim(),
        pin: pin.trim() || undefined,
        ackUser: ackUser.trim(),
        pushEnabled,
        pushWebhookSecret: webhookSecret.trim() || undefined,
        isQrProvisioned: isQr,
      });
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }
  };

  const saveDisabled =
    testState === 'testing' ||
    apiKey.trim().length === 0 ||
    (!isQr && pushEnabled && !webhookSecret.trim());

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        {isEditing ? 'Edit Server' : 'Add Server'}
      </div>

      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {/* Server Name — always editable */}
        <div className="p-3">
          <label htmlFor="server-name" className="block text-xs text-slate-400 mb-1.5">
            Server Name
          </label>
          <input
            id="server-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Production BHNM"
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* BHNM URL */}
        {isQr ? (
          <ReadOnlyField label="BHNM URL" value={bhnmUrl} />
        ) : (
          <div className="p-3">
            <label htmlFor="server-bhnm-url" className="block text-xs text-slate-400 mb-1.5">
              BHNM URL
            </label>
            <input
              id="server-bhnm-url"
              type="text"
              value={bhnmUrl}
              onChange={(e) => setBhnmUrl(e.target.value)}
              placeholder="https://bhnm.example.com"
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* Middleware URL */}
        {isQr ? (
          <ReadOnlyField label="Middleware URL" value={baseUrl} />
        ) : (
          <div className="p-3">
            <label htmlFor="server-middleware-url" className="block text-xs text-slate-400 mb-1.5">
              Middleware URL
            </label>
            <input
              id="server-middleware-url"
              type="text"
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="/bhnm"
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* API Token */}
        {isQr ? (
          <ReadOnlyField label="API Token" value={apiKey} masked />
        ) : (
          <div className="p-3">
            <label htmlFor="server-api-key" className="block text-xs text-slate-400 mb-1.5">
              API Token
            </label>
            <div className="flex items-center gap-2">
              <input
                id="server-api-key"
                type={showKey ? 'text' : 'password'}
                autoComplete="off"
                spellCheck={false}
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                className="flex-1 rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
              />
              <button
                type="button"
                onClick={() => setShowKey(!showKey)}
                className="px-2 py-2 rounded border border-slate-700 text-slate-400 hover:text-white text-xs"
                aria-label={showKey ? 'Hide key' : 'Show key'}
              >
                {showKey ? 'Hide' : 'Show'}
              </button>
            </div>
          </div>
        )}

        {/* PIN / License ID */}
        {isQr ? (
          pin ? <ReadOnlyField label="PIN / License ID" value={pin} masked /> : null
        ) : (
          <div className="p-3">
            <label htmlFor="server-pin" className="block text-xs text-slate-400 mb-1.5">
              PIN / License ID <span className="text-slate-600">(SaaS only)</span>
            </label>
            <input
              id="server-pin"
              type="text"
              autoComplete="off"
              spellCheck={false}
              placeholder="Optional"
              value={pin}
              onChange={(e) => setPin(e.target.value)}
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* User Name */}
        {isQr ? (
          ackUser ? <ReadOnlyField label="User Name" value={ackUser} /> : null
        ) : (
          <div className="p-3">
            <label htmlFor="server-ack-user" className="block text-xs text-slate-400 mb-1.5">
              User Name <span className="text-slate-600">(for incident ACK/UnACK)</span>
            </label>
            <input
              id="server-ack-user"
              type="text"
              placeholder="e.g. your.name"
              value={ackUser}
              onChange={(e) => setAckUser(e.target.value)}
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}

        {/* Push Toggle */}
        <div className="p-3 flex items-center justify-between">
          <div className="text-xs text-slate-400">Enable Push Notifications</div>
          <button
            type="button"
            onClick={() => setPushEnabled(!pushEnabled)}
            className={`relative w-11 h-6 rounded-full transition-colors ${
              pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
            }`}
            role="switch"
            aria-checked={pushEnabled}
            aria-label="Enable Push Notifications"
          >
            <span
              className="block w-5 h-5 rounded-full bg-white shadow transition-transform"
              style={{ transform: pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
            />
          </button>
        </div>

        {/* Webhook Secret */}
        {isQr ? (
          webhookSecret ? <ReadOnlyField label="Webhook Secret" value={webhookSecret} masked /> : null
        ) : (
          <div className="p-3">
            <label htmlFor="server-webhook-secret" className="block text-xs text-slate-400 mb-1.5">
              Webhook Secret <span className="text-slate-600">(for push notifications)</span>
            </label>
            <input
              id="server-webhook-secret"
              type="password"
              autoComplete="off"
              spellCheck={false}
              placeholder="Same secret as in BHNM webhook URL"
              value={webhookSecret}
              onChange={(e) => setWebhookSecret(e.target.value)}
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>
        )}
      </div>

      {/* Test result feedback */}
      {testState === 'success' && testResult && (
        <div className="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-3">
          <div className="flex items-center gap-2">
            <span className="text-emerald-400 text-sm font-semibold">Connected</span>
          </div>
          <div className="text-xs text-slate-400 mt-1">
            {formatHaRole(testResult.role)}
            {formatHaStatus(testResult.role, testResult.status) && (
              <> — {formatHaStatus(testResult.role, testResult.status)}</>
            )}
          </div>
        </div>
      )}

      {testState === 'failed' && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-3">
          <span className="text-red-400 text-sm font-semibold">Connection Failed</span>
          <p className="text-xs text-slate-400 mt-1">{testError}</p>
        </div>
      )}

      {/* Save button */}
      <button
        type="submit"
        disabled={saveDisabled}
        className="w-full px-4 py-3 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-sm font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {testState === 'testing' ? 'Testing connection...' : 'Save'}
      </button>

      {/* Delete button — edit mode only */}
      {isEditing && onDelete && (
        showDeleteConfirm ? (
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onDelete}
              className="flex-1 px-3 py-2.5 rounded-lg bg-red-600 hover:bg-red-500 text-sm font-semibold"
            >
              Confirm Delete
            </button>
            <button
              type="button"
              onClick={() => setShowDeleteConfirm(false)}
              className="flex-1 px-3 py-2.5 rounded-lg bg-slate-800 border border-slate-700 text-sm"
            >
              Cancel
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setShowDeleteConfirm(true)}
            className="w-full px-4 py-3 rounded-lg border border-red-500/50 text-red-400 text-sm font-semibold hover:bg-red-500/10"
            aria-label="Delete server"
          >
            Delete Server
          </button>
        )
      )}

      {/* Cancel */}
      <button
        type="button"
        onClick={onCancel}
        className="w-full px-4 py-2.5 rounded-lg bg-slate-900 border border-slate-700 hover:bg-slate-800 text-sm text-slate-400"
      >
        Cancel
      </button>

      <p className="text-xs text-slate-500 px-1 text-center">
        {isQr ? 'Configured via QR code. Scan again to update.' : 'Stored in your browser only.'}
      </p>
    </form>
  );
}
