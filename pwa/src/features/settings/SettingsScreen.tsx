import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useConfig, notifyConfigChanged } from '../../lib/config';
import { loadApiKey, saveApiKey, clearApiKey } from './settingsStorage';

export function SettingsScreen() {
  const config = useConfig();
  const [value, setValue] = useState<string>(() => loadApiKey() ?? '');
  const [statusMessage, setStatusMessage] = useState<string>('');

  const onSave = (event: FormEvent) => {
    event.preventDefault();
    saveApiKey(value);
    notifyConfigChanged();
    setValue(loadApiKey() ?? '');
    setStatusMessage('Saved.');
  };

  const onClear = () => {
    clearApiKey();
    notifyConfigChanged();
    setValue('');
    setStatusMessage('Cleared.');
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

      <form className="p-4 space-y-4 max-w-md" onSubmit={onSave}>
        <div>
          <label htmlFor="bhnm-api-key" className="block text-sm font-medium text-slate-200">
            BHNM API key
          </label>
          <input
            id="bhnm-api-key"
            type="password"
            autoComplete="off"
            spellCheck={false}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            aria-describedby="bhnm-api-key-help"
            className="mt-1 w-full rounded bg-slate-900 border border-slate-700 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sky-500"
          />
          <p id="bhnm-api-key-help" className="mt-1 text-xs text-slate-400">
            Stored in your browser only. Sent to BHNM via the BeNeM middleware, nowhere else.
          </p>
        </div>

        <div className="flex gap-2">
          <button
            type="submit"
            className="px-3 py-1.5 rounded bg-sky-600 hover:bg-sky-500 text-sm"
          >
            Save
          </button>
          <button
            type="button"
            onClick={onClear}
            className="px-3 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-sm"
          >
            Clear
          </button>
        </div>

        <div className="text-xs text-slate-400" aria-live="polite" role="status">
          {statusMessage || (config.isConfigured ? '✓ Configured' : 'Not configured')}
        </div>
      </form>
    </div>
  );
}
