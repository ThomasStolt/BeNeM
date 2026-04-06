import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import {
  loadApiKey, saveApiKey, clearApiKey,
  loadPin, savePin, clearPin,
  loadWebhookSecret, saveWebhookSecret, clearWebhookSecret,
  loadPushEnabled, savePushEnabled,
} from './settingsStorage';
import { subscribeToPush, unsubscribeFromPush, getPushState, type PushState } from '../../lib/pushRegistration';
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
  const [webhookSecret, setWebhookSecret] = useState<string>(() => loadWebhookSecret() ?? '');
  const [pushEnabled, setPushEnabled] = useState<boolean>(() => loadPushEnabled());
  const [pushState, setPushState] = useState<PushState>(getPushState);
  const [pushLoading, setPushLoading] = useState(false);

  const onSave = (event: FormEvent) => {
    event.preventDefault();
    saveApiKey(apiKey);
    savePin(pin);
    saveWebhookSecret(webhookSecret);
    notifyConfigChanged();
    setApiKey(loadApiKey() ?? '');
    setPin(loadPin() ?? '');
    setWebhookSecret(loadWebhookSecret() ?? '');
    setStatusMessage('Saved.');
    setTestState('idle');
    setTestResult(null);
  };

  const onClear = () => {
    clearApiKey();
    clearPin();
    clearWebhookSecret();
    savePushEnabled(false);
    notifyConfigChanged();
    setApiKey('');
    setPin('');
    setWebhookSecret('');
    setPushEnabled(false);
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

  const onTogglePush = async () => {
    if (pushLoading) return;
    setPushLoading(true);
    try {
      if (pushEnabled) {
        await unsubscribeFromPush();
        savePushEnabled(false);
        setPushEnabled(false);
        setPushState({ status: 'unregistered' });
      } else {
        if (!webhookSecret) {
          setPushState({ status: 'error', message: 'Webhook secret is required for push notifications' });
          setPushLoading(false);
          return;
        }
        const endpoint = await subscribeToPush(config.baseUrl, webhookSecret);
        savePushEnabled(true);
        setPushEnabled(true);
        setPushState({ status: 'registered', endpoint });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Push registration failed';
      setPushState({ status: 'error', message: msg });
      if (pushEnabled) {
        savePushEnabled(false);
        setPushEnabled(false);
      }
    } finally {
      setPushLoading(false);
    }
  };

  const onReRegisterPush = async () => {
    if (!webhookSecret) return;
    setPushLoading(true);
    try {
      await unsubscribeFromPush();
      const endpoint = await subscribeToPush(config.baseUrl, webhookSecret);
      savePushEnabled(true);
      setPushEnabled(true);
      setPushState({ status: 'registered', endpoint });
    } catch (err) {
      setPushState({ status: 'error', message: err instanceof Error ? err.message : 'Re-registration failed' });
    } finally {
      setPushLoading(false);
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
            <div className="p-3 border-b border-slate-800">
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
            {/* Webhook Secret */}
            <div className="p-3">
              <label htmlFor="webhook-secret" className="block text-xs text-slate-400 mb-1.5">
                Webhook Secret <span className="text-slate-600">(for push notifications)</span>
              </label>
              <input
                id="webhook-secret"
                type="password"
                autoComplete="off"
                spellCheck={false}
                placeholder="Same secret as in BHNM webhook URL"
                value={webhookSecret}
                onChange={(e) => setWebhookSecret(e.target.value)}
                className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
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

        {/* Push Notifications */}
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">Push Notifications</div>
          <div className="bg-slate-900 rounded-lg overflow-hidden">
            {/* Enable/disable toggle */}
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
                onClick={onTogglePush}
                disabled={pushLoading || pushState.status === 'unsupported' || pushState.status === 'denied'}
                className={`relative w-11 h-6 rounded-full transition-colors ${
                  pushEnabled ? 'bg-sky-600' : 'bg-slate-700'
                } disabled:opacity-50 disabled:cursor-not-allowed`}
                role="switch"
                aria-checked={pushEnabled}
              >
                <span
                  className={`block w-5 h-5 rounded-full bg-white shadow transition-transform`}
                  style={{ transform: pushEnabled ? 'translateX(22px)' : 'translateX(2px)' }}
                />
              </button>
            </div>

            {/* Re-register button */}
            {pushEnabled && (
              <div className="p-3 border-t border-slate-800">
                <button
                  type="button"
                  onClick={onReRegisterPush}
                  disabled={pushLoading}
                  className="w-full text-sm text-slate-400 hover:text-white py-1 disabled:opacity-50"
                >
                  {pushLoading ? 'Registering...' : 'Re-register Push Subscription'}
                </button>
              </div>
            )}
          </div>
        </div>

        {/* About */}
        <div className="border-t border-slate-800 pt-6">
          <div className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-3">About</div>
          <div className="bg-slate-900 rounded-lg p-3">
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-sm">
              <dt className="text-slate-500">Version</dt>
              <dd>0.2.0</dd>
              <dt className="text-slate-500">Platform</dt>
              <dd>PWA (Web Push)</dd>
            </dl>
          </div>
        </div>
      </form>
    </div>
  );
}
