import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import { loadApiKey, saveApiKey, clearApiKey, loadPin, savePin, clearPin } from './settingsStorage';
import { testConnection } from '../../lib/api/ha-status';
import { formatHaRole, formatHaStatus } from '../../lib/api/ha-status';
import type { HaStatusResult } from '../../lib/api/ha-status';

type TestState = 'idle' | 'testing' | 'success' | 'failed';

export function SettingsScreen() {
  const config = useConfig();
  const [apiKey, setApiKey] = useState<string>(() => loadApiKey() ?? '');
  const [pin, setPin] = useState<string>(() => loadPin() ?? '');
  const [showKey, setShowKey] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string>('');
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<HaStatusResult | null>(null);
  const [testError, setTestError] = useState<string>('');

  const onSave = (event: FormEvent) => {
    event.preventDefault();
    saveApiKey(apiKey);
    savePin(pin);
    notifyConfigChanged();
    setApiKey(loadApiKey() ?? '');
    setPin(loadPin() ?? '');
    setStatusMessage('Saved.');
  };

  const onClear = () => {
    clearApiKey();
    clearPin();
    notifyConfigChanged();
    setApiKey('');
    setPin('');
    setStatusMessage('Cleared.');
    setTestState('idle');
    setTestResult(null);
  };

  const onTestConnection = async () => {
    setTestState('testing');
    setTestResult(null);
    setTestError('');
    try {
      // Build a temporary config with current form values
      const tempConfig = {
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        pin: pin.length > 0 ? pin : undefined,
        isConfigured: apiKey.length > 0,
      };
      const result = await testConnection(tempConfig);
      setTestResult(result);
      setTestState('success');
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }
  };

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between">
        <Link to="/" className="text-sm text-slate-300 hover:text-white" aria-label="Back to incidents">
          ← Back
        </Link>
        <h1 className="text-lg font-semibold">Settings</h1>
        <span aria-hidden="true" className="w-10" />
      </header>

      <form className="p-4 space-y-6 max-w-md" onSubmit={onSave}>
        {/* Connection section */}
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">BHNM Connection</div>
          <div className="bg-slate-900 rounded-lg overflow-hidden">
            {/* API Key */}
            <div className="p-3 border-b border-slate-800">
              <label htmlFor="bhnm-api-key" className="block text-xs text-slate-400 mb-1.5">
                API Key
              </label>
              <div className="flex items-center gap-2">
                <input
                  id="bhnm-api-key"
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
                  {showKey ? '🙈' : '👁'}
                </button>
              </div>
            </div>
            {/* PIN */}
            <div className="p-3">
              <label htmlFor="bhnm-pin" className="block text-xs text-slate-400 mb-1.5">
                PIN / License ID <span className="text-slate-600">(SaaS only)</span>
              </label>
              <input
                id="bhnm-pin"
                type="text"
                autoComplete="off"
                spellCheck={false}
                placeholder="Optional"
                value={pin}
                onChange={(e) => setPin(e.target.value)}
                className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
              />
            </div>
          </div>
          <p className="mt-2 text-xs text-slate-500 px-1">
            Stored in your browser only. Sent to BHNM via the BeNeM middleware, nowhere else.
          </p>
        </div>

        {/* Test Connection */}
        <div>
          <button
            type="button"
            onClick={onTestConnection}
            disabled={testState === 'testing' || apiKey.length === 0}
            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-4 py-3 text-sm hover:bg-slate-800 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {testState === 'testing' ? 'Testing connection...' : 'Test Connection'}
          </button>

          {testState === 'success' && testResult && (
            <div className="mt-2 bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-3">
              <div className="flex items-center gap-2 mb-1">
                <span className="text-emerald-400 text-sm">✓</span>
                <span className="text-emerald-400 font-semibold text-sm">Connected</span>
              </div>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
                <dt className="text-slate-500">HA Role</dt>
                <dd className="text-slate-300">{formatHaRole(testResult.role)}</dd>
                {formatHaStatus(testResult.role, testResult.status) && (
                  <>
                    <dt className="text-slate-500">Status</dt>
                    <dd className="text-slate-300">{formatHaStatus(testResult.role, testResult.status)}</dd>
                  </>
                )}
              </dl>
            </div>
          )}

          {testState === 'failed' && (
            <div className="mt-2 bg-red-500/10 border border-red-500/30 rounded-lg p-3">
              <div className="flex items-center gap-2">
                <span className="text-red-400 text-sm">✕</span>
                <span className="text-red-400 font-semibold text-sm">Failed</span>
              </div>
              <p className="text-xs text-slate-400 mt-1">{testError}</p>
            </div>
          )}
        </div>

        {/* Save / Clear */}
        <div className="flex gap-2">
          <button
            type="submit"
            className="flex-1 px-3 py-2 rounded bg-sky-600 hover:bg-sky-500 text-sm font-semibold"
          >
            Save
          </button>
          <button
            type="button"
            onClick={onClear}
            className="flex-1 px-3 py-2 rounded bg-slate-900 border border-slate-700 hover:bg-slate-800 text-sm"
          >
            Clear
          </button>
        </div>

        <div className="text-xs text-slate-400" aria-live="polite" role="status">
          {statusMessage || (config.isConfigured ? '✓ Configured' : 'Not configured')}
        </div>

        {/* About */}
        <div className="border-t border-slate-800 pt-6">
          <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">About</div>
          <div className="bg-slate-900 rounded-lg p-3">
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
              <dt className="text-slate-500">Version</dt>
              <dd>0.1.1</dd>
              <dt className="text-slate-500">Platform</dt>
              <dd>PWA (Web Push)</dd>
            </dl>
          </div>
        </div>
      </form>
    </div>
  );
}
