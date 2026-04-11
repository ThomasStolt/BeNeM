import { usePerformanceCategories, usePerformanceInstances, useTimeSeriesBatch } from '../performance/usePerformance';
import type { TimeSeriesDataPoint } from '../../lib/api/types';

interface MiniChartSvgProps {
  points: TimeSeriesDataPoint[];
}

function MiniChartSvg({ points }: MiniChartSvgProps) {
  if (points.length < 2) return null;

  const values = points.map((p) => p.value);
  const maxVal = Math.max(...values);
  const minVal = Math.min(...values, 0);
  const range = maxVal - minVal || 1;

  const W = 120;
  const H = 72;
  const PAD = 4;

  const toX = (i: number) => PAD + (i / (points.length - 1)) * (W - PAD * 2);
  const toY = (v: number) => PAD + (1 - (v - minVal) / range) * (H - PAD * 2);

  const coords = points.map((p, i) => ({ x: toX(i), y: toY(p.value) }));
  const linePath = coords
    .map((c, i) => `${i === 0 ? 'M' : 'L'}${c.x.toFixed(1)},${c.y.toFixed(1)}`)
    .join(' ');
  const areaPath = `${linePath} L${coords[coords.length - 1].x.toFixed(1)},${H} L${coords[0].x.toFixed(1)},${H} Z`;

  const current = values[values.length - 1];
  const lastCoord = coords[coords.length - 1];

  const formatVal = (v: number) =>
    v >= 1000 ? `${(v / 1000).toFixed(1)}s` : `${Math.round(v)}ms`;

  return (
    <div className="flex flex-col h-full min-w-0">
      <span className="text-[10px] text-slate-500 text-right mb-0.5">Latency</span>
      <div className="flex-1 relative">
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="none"
          className="w-full h-full"
        >
          <path d={areaPath} fill="#0ea5e9" fillOpacity="0.15" />
          <path d={linePath} fill="none" stroke="#0ea5e9" strokeWidth="2" />
          <circle cx={lastCoord.x} cy={lastCoord.y} r="3" fill="#0ea5e9" />
          <text x="2" y="10" fill="#6b7280" fontSize="8">
            {formatVal(maxVal)}
          </text>
          <text x="2" y={H - 2} fill="#6b7280" fontSize="8">
            0
          </text>
        </svg>
      </div>
      <span className="text-[12px] font-bold text-sky-400 text-right mt-0.5">
        {formatVal(current)}
      </span>
    </div>
  );
}

interface LatencyMiniChartProps {
  deviceIndex: string;
  deviceName: string;
}

export function LatencyMiniChart({ deviceIndex, deviceName }: LatencyMiniChartProps) {
  const { data: categories } = usePerformanceCategories(deviceIndex);

  const latencyCategory = categories?.find((c) => c.category === 'Latency');

  const { data: instances } = usePerformanceInstances(
    deviceIndex,
    latencyCategory?.id ?? '',
    latencyCategory?.category ?? '',
    !!latencyCategory,
  );

  const firstInstance = instances?.[0];

  const { data: timeseries } = useTimeSeriesBatch(
    deviceName,
    firstInstance?.statGroup ?? '',
    firstInstance?.unit ?? '',
    firstInstance?.unit === '' ? firstInstance?.title : undefined,
    !!firstInstance,
  );

  const points = timeseries?.[0]?.datapoints ?? [];

  if (points.length < 2) return null;

  return <MiniChartSvg points={points} />;
}
