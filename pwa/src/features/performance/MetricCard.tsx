import { useState } from 'react';
import { usePerformanceInstances, useTimeSeriesBatch } from './usePerformance';
import { MetricChart } from './MetricChart';
import type { PerformanceCategory, PerformanceInstance } from '../../lib/api/types';

interface MetricCardProps {
  category: PerformanceCategory;
  deviceIndex: string;
  deviceName: string;
}

interface InstanceGroup {
  statGroup: string;
  unit: string;
  metricTitle: string | undefined;
  instances: PerformanceInstance[];
}

function groupByStatGroupAndUnit(instances: PerformanceInstance[]): InstanceGroup[] {
  const map = new Map<string, InstanceGroup>();
  for (const inst of instances) {
    const key = `${inst.statGroup}|${inst.unit}`;
    if (!map.has(key)) {
      map.set(key, {
        statGroup: inst.statGroup,
        unit: inst.unit,
        metricTitle: inst.unit === '' ? inst.title : undefined,
        instances: [],
      });
    }
    map.get(key)!.instances.push(inst);
  }
  return Array.from(map.values());
}

function ChevronIcon({ expanded }: { expanded: boolean }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      className={`w-4 h-4 text-slate-400 transition-transform duration-200 ${expanded ? 'rotate-180' : ''}`}
    >
      <path
        fillRule="evenodd"
        d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z"
        clipRule="evenodd"
      />
    </svg>
  );
}

function ExpandedContent({
  deviceIndex,
  deviceName,
  category,
}: {
  deviceIndex: string;
  deviceName: string;
  category: PerformanceCategory;
}) {
  const {
    data: instances,
    isLoading: instancesLoading,
    isError: instancesError,
    refetch: refetchInstances,
  } = usePerformanceInstances(deviceIndex, category.id, category.category, true);

  const groups = instances ? groupByStatGroupAndUnit(instances) : [];
  const firstGroup = groups[0] ?? null;

  const {
    data: timeseries,
    isLoading: timeseriesLoading,
    isError: timeseriesError,
    refetch: refetchTimeseries,
  } = useTimeSeriesBatch(
    deviceName,
    firstGroup?.statGroup ?? '',
    firstGroup?.unit ?? '',
    firstGroup?.metricTitle,
    !!firstGroup,
  );

  const isLoading = instancesLoading || (!!firstGroup && timeseriesLoading);
  const isError = instancesError || (!!firstGroup && timeseriesError);

  if (isLoading) {
    return (
      <div className="flex justify-center py-6">
        <div className="w-5 h-5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col items-center gap-2 py-6">
        <span className="text-sm text-slate-400">Failed to load metrics</span>
        <button
          className="text-xs text-sky-400"
          onClick={() => {
            void refetchInstances();
            void refetchTimeseries();
          }}
        >
          Retry
        </button>
      </div>
    );
  }

  if (!timeseries || timeseries.length === 0) {
    return (
      <div className="flex justify-center py-6">
        <span className="text-sm text-slate-500">No data for the last 24 hours</span>
      </div>
    );
  }

  return <MetricChart series={timeseries} unit={firstGroup?.unit ?? ''} />;
}

export function MetricCard({ category, deviceIndex, deviceName }: MetricCardProps) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="bg-gray-800 rounded-lg overflow-hidden">
      <button
        className="w-full flex items-center justify-between px-4 py-3 text-left"
        onClick={() => setExpanded((prev) => !prev)}
      >
        <span className="text-sm text-slate-200">{category.category}</span>
        <ChevronIcon expanded={expanded} />
      </button>

      {expanded && (
        <div className="px-4 pb-4">
          <ExpandedContent
            deviceIndex={deviceIndex}
            deviceName={deviceName}
            category={category}
          />
        </div>
      )}
    </div>
  );
}
