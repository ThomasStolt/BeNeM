import { EmptyState } from '../../components/EmptyState';

export function DevicesPlaceholder() {
  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800">
        <h1 className="text-lg font-semibold">Devices</h1>
      </header>
      <EmptyState
        title="Coming Soon"
        description="Device list and search will be available in v0.4.0."
      />
    </div>
  );
}
