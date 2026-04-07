import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart,
  Legend,
} from 'recharts';
import type { TimeSeriesResult } from '../../lib/api/types';

interface MetricChartProps {
  series: TimeSeriesResult[];
  unit: string;
}

const COLORS = ['#38bdf8', '#f472b6', '#a78bfa', '#34d399', '#fbbf24', '#fb923c'];

function formatTime(ts: number): string {
  return new Date(ts * 1000).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

function formatTooltipTime(ts: number): string {
  return new Date(ts * 1000).toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

function extractSeriesLabel(instanceDescr: string, fallback: string): string {
  const match = instanceDescr.match(/ on (.+?) \(/);
  return match ? match[1] : fallback;
}

const tooltipStyle = {
  backgroundColor: '#1e293b',
  border: '1px solid #334155',
  borderRadius: 6,
  fontSize: 12,
  color: '#e2e8f0',
};

const axisTickStyle = { fill: '#94a3b8', fontSize: 11 };

export function MetricChart({ series, unit }: MetricChartProps) {
  if (series.length === 0) return null;

  if (series.length === 1) {
    const data = series[0].datapoints.map((dp) => ({
      ts: dp.timestamp,
      value: dp.value,
    }));

    return (
      <ResponsiveContainer width="100%" height={200}>
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
          <defs>
            <linearGradient id="metricGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#38bdf8" stopOpacity={0.3} />
              <stop offset="95%" stopColor="#38bdf8" stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis
            dataKey="ts"
            tickFormatter={formatTime}
            tick={axisTickStyle}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={axisTickStyle}
            axisLine={false}
            tickLine={false}
            unit={` ${unit}`}
            hide
          />
          <Tooltip
            contentStyle={tooltipStyle}
            labelFormatter={(val) => formatTooltipTime(val as number)}
            formatter={(val) => {
            const v = typeof val === 'number' ? val : Number(val ?? 0);
            return [`${v.toFixed(2)} ${unit}`, 'Value'] as [string, string];
          }}
          />
          <Area
            type="monotone"
            dataKey="value"
            stroke="#38bdf8"
            strokeWidth={2}
            fill="url(#metricGradient)"
            dot={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    );
  }

  // Multi-series: collect all unique timestamps
  const tsSet = new Set<number>();
  series.forEach((s) => s.datapoints.forEach((dp) => tsSet.add(dp.timestamp)));
  const sortedTs = Array.from(tsSet).sort((a, b) => a - b);

  type DataRow = { ts: number } & Record<string, number | null>;
  const combined: DataRow[] = sortedTs.map((ts) => {
    const row: DataRow = { ts };
    series.forEach((s, i) => {
      const dp = s.datapoints.find((d) => d.timestamp === ts);
      row[`series_${i}`] = dp ? dp.value : null;
    });
    return row;
  });

  return (
    <ResponsiveContainer width="100%" height={200}>
      <LineChart data={combined} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
        <XAxis
          dataKey="ts"
          tickFormatter={formatTime}
          tick={axisTickStyle}
          axisLine={false}
          tickLine={false}
        />
        <YAxis
          tick={axisTickStyle}
          axisLine={false}
          tickLine={false}
          unit={` ${unit}`}
          hide
        />
        <Tooltip
          contentStyle={tooltipStyle}
          labelFormatter={(val) => formatTooltipTime(val as number)}
          formatter={(val, name) => {
            const v = typeof val === 'number' ? val : Number(val ?? 0);
            const nameStr = String(name ?? '');
            const idx = parseInt(nameStr.replace('series_', ''), 10);
            const label = !isNaN(idx)
              ? extractSeriesLabel(series[idx].instanceDescr, `Series ${idx + 1}`)
              : nameStr;
            return [`${v.toFixed(2)} ${unit}`, label] as [string, string];
          }}
        />
        <Legend wrapperStyle={{ fontSize: 11, color: '#94a3b8' }} />
        {series.map((s, i) => (
          <Line
            key={`series_${i}`}
            type="monotone"
            dataKey={`series_${i}`}
            name={extractSeriesLabel(s.instanceDescr, `Series ${i + 1}`)}
            stroke={COLORS[i % COLORS.length]}
            strokeWidth={2}
            dot={false}
            connectNulls
          />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}
