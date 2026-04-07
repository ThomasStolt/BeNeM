import type { ParsedServerConfig } from '../../lib/qr-parser';

interface QRConfirmScreenProps {
  config: ParsedServerConfig;
  onConfirm: () => void;
  onCancel: () => void;
  existingServerId?: string;
}

function maskKey(key: string): string {
  if (key.length <= 6) return '***';
  return key.slice(0, 3) + '***' + key.slice(-3);
}

export function QRConfirmScreen({
  config,
  onConfirm,
  onCancel,
  existingServerId,
}: QRConfirmScreenProps) {
  const isUpdate = !!existingServerId;

  return (
    <div className="p-4 space-y-4 max-w-md">
      <h2 className="text-lg font-semibold text-white">
        {isUpdate ? 'Update Server' : 'Add Server'}
      </h2>
      <p className="text-sm text-slate-400">
        {isUpdate
          ? 'A server with this URL already exists. Update its configuration?'
          : 'Add this server to your configuration?'}
      </p>
      <div className="bg-slate-900 rounded-lg p-4 space-y-2">
        <InfoRow label="Name" value={config.name} />
        {config.bhnmUrl && <InfoRow label="BHNM URL" value={config.bhnmUrl} />}
        {config.pushMiddlewareUrl && <InfoRow label="Middleware URL" value={config.pushMiddlewareUrl} />}
        <InfoRow label="API Key" value={maskKey(config.apiKey)} />
        {config.pin && <InfoRow label="PIN" value="••••" />}
        {config.ackUser && <InfoRow label="User Name" value={config.ackUser} />}
        {config.pushWebhookSecret && <InfoRow label="Push Secret" value="[set]" />}
      </div>
      <div className="flex gap-3">
        <button
          type="button"
          onClick={onCancel}
          className="flex-1 py-2.5 rounded-lg bg-slate-800 text-sm text-white hover:bg-slate-700"
          aria-label="Cancel"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onConfirm}
          className="flex-1 py-2.5 rounded-lg bg-sky-600 text-sm text-white hover:bg-sky-500"
          aria-label={isUpdate ? 'Update Server' : 'Add Server'}
        >
          {isUpdate ? 'Update Server' : 'Add Server'}
        </button>
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-center text-sm">
      <span className="text-slate-500">{label}</span>
      <span className="text-slate-200 font-mono text-xs break-all text-right max-w-[60%]">{value}</span>
    </div>
  );
}
