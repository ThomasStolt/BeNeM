import { usePerformanceCategories } from './usePerformance';
import { MetricCard } from './MetricCard';

interface PerformanceSectionProps {
  deviceIndex: string;
  deviceName: string;
}

const PRIORITY_CATEGORIES = ['Latency', 'CPU', 'Memory', 'Disk', 'Network'];

export function PerformanceSection({ deviceIndex, deviceName }: PerformanceSectionProps) {
  const { data: categories, isLoading, isError } = usePerformanceCategories(deviceIndex);

  const sortedCategories = [...(categories ?? [])].sort((a, b) => {
    const ai = PRIORITY_CATEGORIES.indexOf(a.category);
    const bi = PRIORITY_CATEGORIES.indexOf(b.category);
    const ap = ai === -1 ? PRIORITY_CATEGORIES.length : ai;
    const bp = bi === -1 ? PRIORITY_CATEGORIES.length : bi;
    return ap - bp;
  });

  return (
    <div>
      <h2 className="text-xs text-slate-500 uppercase tracking-wide font-semibold mb-2">
        Performance · Last 24 Hours
      </h2>

      {isLoading && (
        <div className="bg-slate-900 rounded-lg p-4 flex items-center justify-center">
          <div className="w-5 h-5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
          <span className="ml-2 text-sm text-slate-400">Loading categories...</span>
        </div>
      )}

      {isError && !isLoading && (
        <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
          Could not load performance data
        </div>
      )}

      {!isLoading && !isError && sortedCategories.length === 0 && (
        <div className="bg-slate-900 rounded-lg p-4 text-sm text-slate-400 text-center">
          No performance categories available
        </div>
      )}

      {sortedCategories.length > 0 && (
        <div className="space-y-2">
          {sortedCategories.map((cat) => (
            <MetricCard
              key={cat.id}
              category={cat}
              deviceIndex={deviceIndex}
              deviceName={deviceName}
            />
          ))}
        </div>
      )}
    </div>
  );
}
