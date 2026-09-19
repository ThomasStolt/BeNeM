import { useState, type FormEvent } from 'react';
import type { ServerConfig, NewServerInput } from '../../lib/serverStorage';
import { testConnection } from '../../lib/api/ha-status';
import type { ConnectionCheckResult } from '../../lib/api/ha-status';

interface Props {
  server?: Partial<ServerConfig>;
  /** Persists the server. Must NOT navigate — see `onDone`. */
  onSave: (input: NewServerInput) => void;
  /** Leaves the form, after the user acknowledges the result. */
  onDone: () => void;
  onCancel: () => void;
  onDelete?: () => void;
}

type TestState = 'idle' | 'testing' | 'success' | 'failed';

/**
 * **Never reveal more than a quarter of a secret.**
 *
 * That sentence is the rule, not the number. The last 4 characters are shown only
 * at 16 characters or more, because a quarter of 16 is 4; below that the value is
 * dots alone. Do NOT lower the threshold so that a short key displays nicely — the
 * last 4 of a 9-character key leaves 5 characters to guess, which is not a display
 * decision, it is a giveaway.
 *
 * A secret short enough to trigger suppression is a secret too short to be safe.
 * servers.json holds a 9-character api_key today; that is parked item (e)1,
 * credential strength, and this display must not paper over it.
 *
 * There is deliberately no full reveal anywhere in the app.
 */
const SECRET_REVEAL_MINIMUM_LENGTH = 16;

export function maskSecret(value: string): string {
  if (!value) return 'not set';
  if (value.length < SECRET_REVEAL_MINIMUM_LENGTH) return '••••••••';
  return `••••••••${value.slice(-4)}`;
}

/** The stored value's tail, so one secret can be told from another while
 *  troubleshooting without ever displaying it. */
function SecretHint({ value }: { value: string }) {
  return (
    <p className="text-[11px] text-slate-500 mt-1.5 font-mono break-all">
      Stored: {maskSecret(value)}
    </p>
  );
}

export function ServerForm({ server, onSave, onDone, onCancel, onDelete }: Props) {
  const isEditing = !!server?.id;
  const isQr = server?.isQrProvisioned ?? false;

  const [name, setName] = useState(server?.name ?? '');
  const [bhnmUrl, setBhnmUrl] = useState(server?.bhnmUrl ?? '');
  const baseUrl = server?.baseUrl ?? '/bhnm';
  const [middlewareUrl, setMiddlewareUrl] = useState(server?.pushMiddlewareUrl ?? '');
  const [apiKey, setApiKey] = useState(server?.apiKey ?? '');
  const [pin, setPin] = useState(server?.pin ?? '');
  const [ackUser, setAckUser] = useState(server?.ackUser ?? '');
  const [webhookSecret, setWebhookSecret] = useState(server?.pushWebhookSecret ?? '');
  const [pushEnabled, setPushEnabled] = useState(server?.pushEnabled ?? false);
  const [testState, setTestState] = useState<TestState>('idle');
  const [testResult, setTestResult] = useState<ConnectionCheckResult | null>(null);
  const [testError, setTestError] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setTestState('testing');
    setTestResult(null);
    setTestError('');

    const serverInput = {
      name: name.trim() || 'BHNM Server',
      baseUrl: baseUrl.trim(),
      bhnmUrl: bhnmUrl.trim(),
      apiKey: apiKey.trim(),
      pin: pin.trim() || undefined,
      ackUser: ackUser.trim(),
      pushEnabled,
      pushMiddlewareUrl: middlewareUrl.trim() || undefined,
      pushWebhookSecret: webhookSecret.trim() || undefined,
      isQrProvisioned: isQr,
    };

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
    } catch (err) {
      setTestError(err instanceof Error ? err.message : 'Connection failed');
      setTestState('failed');
    }

    // Save regardless of the probe result — but do NOT leave the form here.
    // `onSave` used to navigate straight back to the list, which unmounted this
    // component in the same tick and made BOTH result panels below dead code: a
    // successful save gave no confirmation at all, and the "saved anyway, not
    // verified" warning was never once seen by anyone. The user now acknowledges
    // the outcome with OK, matching iOS, and `onDone` is what leaves.
    onSave(serverInput);
  };

  const saveDisabled =
    testState === 'testing' ||
    apiKey.trim().length === 0 ||
    // Only on ADD. A new validation rule must never trap data that already exists:
    // an existing connection with push on and no stored secret is reachable (a QR
    // payload without push_secret), and disabling Save there would stop the user
    // fixing anything else about it — including a stale middleware URL. The state is
    // surfaced as a warning below instead, which is the doctrine's answer: show the
    // broken thing, do not block the exit.
    (!isEditing && pushEnabled && !webhookSecret.trim());

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

        {/* Middleware URL */}
                  <div className="p-3">
            <label htmlFor="server-middleware-url" className="block text-xs text-slate-400 mb-1.5">
              Middleware URL
            </label>
            <input
              id="server-middleware-url"
              type="text"
              value={middlewareUrl}
              onChange={(e) => setMiddlewareUrl(e.target.value)}
              placeholder="https://middleware.example.com"
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
          </div>

        {/* API Token */}
                  <div className="p-3">
            <label htmlFor="server-api-key" className="block text-xs text-slate-400 mb-1.5">
              API Token
            </label>
            <input
              id="server-api-key"
              type="password"
              autoComplete="off"
              spellCheck={false}
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              className="w-full rounded bg-slate-950 border border-slate-700 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-sky-500"
            />
            <SecretHint value={apiKey} />
          </div>

        {/* PIN / License ID */}
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

        {/* User Name */}
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
            <SecretHint value={webhookSecret} />
            {pushEnabled && !webhookSecret.trim() && (
              <p className="text-[11px] text-amber-400 mt-1.5">
                Push is on but no webhook secret is stored, so this server cannot deliver
                notifications until one is entered.
              </p>
            )}
          </div>
      </div>

      {/* Test result feedback */}
      {testState === 'success' && testResult && (
        <div className="bg-emerald-500/10 border border-emerald-500/30 rounded-lg p-3">
          <div className="flex items-center gap-2">
            <span className="text-emerald-400 text-sm font-semibold">Connection verified</span>
          </div>
          {/* Same words as the iOS alert, deliberately. The PIN is not listed as
              uncovered: it is sent when one is entered, and BHNM checks credentials
              before the method, so a wrong PIN fails this probe as a wrong key does. */}
          <div className="text-xs text-slate-400 mt-1">
            BHNM is reachable through the middleware and accepted the credentials.
          </div>
          <button
            type="button"
            onClick={onDone}
            className="mt-3 w-full px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-sm font-semibold"
          >
            OK
          </button>
        </div>
      )}

      {testState === 'failed' && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-lg p-3">
          <span className="text-red-400 text-sm font-semibold">Not verified</span>
          <p className="text-xs text-slate-400 mt-1">{testError}</p>
          {/* The PWA saves regardless of the probe (see handleSubmit), unlike iOS
              which gates the save on it. The panel must therefore say so: a server
              sitting in the list unverified is exactly the state the doctrine says
              must not be drawn the same as a verified one. */}
          <p className="text-xs text-slate-500 mt-2">
            The server was saved anyway, but this connection is not verified.
          </p>
          <button
            type="button"
            onClick={onDone}
            className="mt-3 w-full px-4 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-sm font-semibold"
          >
            OK
          </button>
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
        {isQr ? 'Configured via QR code. Stored in your browser only.' : 'Stored in your browser only.'}
      </p>
    </form>
  );
}
