import { useState, type FormEvent } from 'react';
import type { ServerConfig, NewServerInput } from '../../lib/serverStorage';
import { testConnection } from '../../lib/api/ha-status';
import type { HaStatusResult } from '../../lib/api/ha-status';
import { formatHaRole, formatHaStatus } from '../../lib/api/ha-status';

interface Props {
  server?: Partial<ServerConfig>;
  onSave: (input: NewServerInput) => void;
  onCancel: () => void;
}

type TestState = 'idle' | 'testing' | 'success' | 'failed';

export function ServerForm({ server, onSave, onCancel }: Props) {
  const [name, setName] = useState(server?.name ?? '');
  const [baseUrl, setBaseUrl] = useState(server?.baseUrl ?? '/bhnm');
  const [apiKey, setApiKey] = useState(server?.apiKey ?? '');
  const [pin, setPin] = useState(server?.pin ?? '');
  const [showKey, setShowKey] = useState(false);
  const [webhookSecret, setWebhookSecret] = useState(server?.pushWebhookSecret ?? '');
  const [middlewareUrl, setMiddlewareUrl] = useState(server?.pushMiddlewareUrl ?? '');
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<HaStatusResult | null>(null);
  const [testError, setTestError] = useState('');

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    onSave({
      name: name.trim() || 'BHNM Server',
      baseUrl: baseUrl.trim(),
      apiKey: apiKey.trim(),
      pin: pin.trim() || undefined,
      pushWebhookSecret: webhookSecret.trim() || undefined,
      pushMiddlewareUrl: middlewareUrl.trim() || undefined,
    });
  };

  const handleTestConnection = async () => {
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
      });
      setTestResult(result);
      setTestState('success');
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">
        {server?.id ? 'Edit Server' : 'Add Server'}
      </div>

      <div className="bg-slate-900 rounded-lg overflow-hidden divide-y divide-slate-800">
        {/* Server Name */}
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

        {/* Base URL */}
        <div className="p-3">
          <label htmlFor="base-url" className="block text-xs text-slate-400 mb-1.5">
            Base URL
          </label>
          <input
            id="base-url"
            type="text"
            value={baseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            placeholder="/bhnm"
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>

        {/* API Key */}
        <div className="p-3">
          <label htmlFor="server-api-key" className="block text-xs text-slate-400 mb-1.5">
            API Key
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

        {/* PIN */}
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

        {/* Webhook Secret */}
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

        {/* Push Middleware URL (optional override) */}
        <div className="p-3">
          <label htmlFor="server-middleware-url" className="block text-xs text-slate-400 mb-1.5">
            Push Middleware URL <span className="text-slate-600">(optional, defaults to Base URL)</span>
          </label>
          <input
            id="server-middleware-url"
            type="text"
            placeholder="Leave empty to use Base URL"
            value={middlewareUrl}
            onChange={(e) => setMiddlewareUrl(e.target.value)}
            className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
        </div>
      </div>

      {/* Test Connection */}
      <button
        type="button"
        onClick={handleTestConnection}
        disabled={testState === 'testing' || apiKey.trim().length === 0}
        className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-3 text-sm hover:bg-slate-800 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {testState === 'testing' ? 'Testing...' : 'Test Connection'}
      </button>

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
          <span className="text-red-400 text-sm font-semibold">Failed</span>
          <p className="text-xs text-slate-400 mt-1">{testError}</p>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={apiKey.trim().length === 0}
          className="flex-1 px-3 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm font-semibold disabled:opacity-50"
        >
          Save
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 px-3 py-2 rounded bg-slate-900 border border-slate-700 hover:bg-slate-800 text-sm"
        >
          Cancel
        </button>
      </div>

      <p className="text-xs text-slate-500 px-1">
        Stored in your browser only.
      </p>
    </form>
  );
}
