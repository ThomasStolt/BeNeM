import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { useConfig } from '../../lib/config';
import { fetchDiagnostics, type DiagnosticsBhnm } from '../../lib/api/diagnostics';

/**
 * Connection diagnostics — the 📱 App → 🖥 Middleware → 🗄 BHNM pipeline.
 * Fetches /api/v1/diagnostics on open + manual refresh only (the endpoint reads
 * the middleware's cached background monitor, so the fetch is fast). No polling:
 * the screen is on-demand by design; hop truth lives in the middleware monitor.
 */
export function DiagnosticsScreen() {
  const config = useConfig();
  const navigate = useNavigate();

  const { data, isFetching, isError, error, refetch } = useQuery({
    queryKey: ['diagnostics', config.serverId, config.baseUrl],
    queryFn: () => fetchDiagnostics(config),
    enabled: config.isConfigured,
    refetchOnWindowFocus: true,
    staleTime: 0,
  });

  const bhnm: DiagnosticsBhnm | undefined = data?.diagnostics.server.bhnm;
  const reachedMiddleware = data !== undefined && !isError;
  // reachable: true → up · false → down · null → checking (amber, never down)
  const bhnmState: 'up' | 'down' | 'checking' =
    bhnm?.reachable === true ? 'up' : bhnm?.reachable === false ? 'down' : 'checking';

  return (
    <div className="min-h-full">
      <header className="px-4 py-3 border-b border-slate-800 flex items-center justify-between sticky top-0 bg-slate-950 z-10">
        <button
          type="button"
          onClick={() => navigate(-1)}
          className="text-sm text-slate-400 hover:text-slate-200"
        >
          ← Back
        </button>
        <h1 className="text-lg font-bold">Diagnostics</h1>
        <button
          type="button"
          onClick={() => refetch()}
          aria-label="Refresh diagnostics"
          className="text-slate-400 hover:text-slate-200 p-1"
        >
          <span className={isFetching ? 'inline-block animate-spin' : ''}>↻</span>
        </button>
      </header>

      <div className="p-4 space-y-4">
        <Section label="Connection path">
          <div className="flex items-start px-2 py-3">
            <HopNode icon="📱" name="App" state="up" detail="running" />
            <HopLink
              state={reachedMiddleware ? 'up' : 'down'}
              label={reachedMiddleware ? `${data.appToMiddlewareMs} ms` : 'down'}
            />
            <HopNode
              icon="🖥"
              name="Middleware"
              state={reachedMiddleware ? 'up' : 'down'}
              detail={reachedMiddleware ? 'up' : 'unreachable'}
            />
            <HopLink state={reachedMiddleware ? bhnmState : 'down'} label={bhnmLatencyLabel(bhnm)} />
            <HopNode
              icon="🗄"
              name="BHNM"
              state={reachedMiddleware ? bhnmState : 'down'}
              detail={
                !reachedMiddleware ? 'unknown'
                : bhnmState === 'up' ? 'reachable'
                : bhnmState === 'down' ? 'down'
                : 'checking'
              }
            />
          </div>
        </Section>

        {isError && (
          <Section label="Error">
            <p className="text-sm text-red-500 p-3">{(error as Error).message}</p>
          </Section>
        )}

        <Section label="Feeds">
          <div className="divide-y divide-slate-800">
            {['tactical', 'incidents', 'thresholds', 'maintenance_map'].map((key) => {
              const f = data?.diagnostics.server.feeds[key];
              if (!f) return null;
              return (
                <div key={key} className="flex items-center justify-between px-3 py-2.5">
                  <span className="text-sm font-medium capitalize w-28">{key.replace('_', ' ')}</span>
                  <span className="text-xs text-slate-500 flex-1">
                    {f.count ?? '—'}{key === 'maintenance_map' && f.count !== null ? ' hosts' : ''}
                    {f.age_seconds !== null ? ` · ${agoText(f.age_seconds)}` : ''}
                  </span>
                  <span
                    className={
                      'text-[9px] font-bold px-2 py-0.5 rounded-full ' +
                      (f.cached ? 'bg-blue-500/20 text-blue-400' : 'bg-emerald-600 text-white')
                    }
                  >
                    {f.cached ? 'CACHED' : 'LIVE'}
                  </span>
                </div>
              );
            })}
            {!data && <p className="text-xs text-slate-500 p-3">No data</p>}
          </div>
        </Section>

        {bhnm && (
          <Section label="Errors · this server">
            <div className="p-3 space-y-1.5">
              {bhnm.reachable !== false && bhnm.consecutive_failures === 0 ? (
                <p className="text-sm text-emerald-500">✓ No recent errors</p>
              ) : (
                <>
                  <p className="text-sm text-red-500">
                    ⚠ {bhnm.reachable === true ? 'Recovering' : 'BHNM unreachable'}
                  </p>
                  <Row k="Consecutive failures" v={String(bhnm.consecutive_failures)} />
                  {bhnm.last_error && (
                    <Row
                      k={`Last error${bhnm.last_error_age_seconds !== null ? ` · ${agoText(bhnm.last_error_age_seconds)}` : ''}`}
                      v={bhnm.last_error}
                    />
                  )}
                </>
              )}
            </div>
          </Section>
        )}

        <Section label="Middleware · /health">
          <div className="p-3 space-y-1.5">
            <Row k="Middleware version" v={data?.diagnostics.middleware.version ?? '—'} />
            <Row
              k="Registered devices"
              v={data?.diagnostics.middleware.registered_devices?.toString() ?? '—'}
            />
            <Row k="Server" v={data?.diagnostics.server.host || '—'} />
            <Row k="BHNM source" v={bhnm?.source ?? '—'} />
          </div>
        </Section>
      </div>
    </div>
  );
}

const STATE_COLORS = { up: '#22863a', down: '#ef4444', checking: '#f97316' } as const;
type HopState = keyof typeof STATE_COLORS;

function bhnmLatencyLabel(b: DiagnosticsBhnm | undefined): string {
  if (!b || b.reachable === null) return '—';
  if (!b.reachable || b.latency_ms === null) return 'down';
  const age = b.last_success_age_seconds;
  return age !== null ? `${b.latency_ms} ms · ${agoText(age)}` : `${b.latency_ms} ms`;
}

function HopNode({ icon, name, state, detail }: { icon: string; name: string; state: HopState; detail: string }) {
  const color = STATE_COLORS[state];
  return (
    <div className="flex flex-col items-center w-[74px] shrink-0">
      <div
        className="w-11 h-11 rounded-full bg-slate-800 flex items-center justify-center text-xl border-2"
        style={{ borderColor: color }}
      >
        {icon}
      </div>
      <span className="text-[11px] font-semibold mt-1">{name}</span>
      <span className="text-[9px]" style={{ color }}>{detail}</span>
    </div>
  );
}

function HopLink({ state, label }: { state: HopState; label: string }) {
  const color = STATE_COLORS[state];
  return (
    <div className="flex-1 flex flex-col items-center pt-5">
      {state === 'up' ? (
        <div className="h-[3px] w-full rounded-full" style={{ backgroundColor: color }} />
      ) : (
        <div className="w-full flex items-center gap-1.5">
          <div className="h-[3px] flex-1 rounded-full" style={{ backgroundColor: color }} />
          <span className="text-[11px]" style={{ color }}>⚡</span>
          <div className="h-[3px] flex-1 rounded-full" style={{ backgroundColor: color }} />
        </div>
      )}
      <span className="text-[9px] font-mono mt-1.5" style={{ color }}>{label}</span>
    </div>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="text-[11px] font-semibold text-slate-500 tracking-wider uppercase mb-1.5">
        {label}
      </h2>
      <div className="bg-slate-900 rounded-xl border border-slate-800 overflow-hidden">{children}</div>
    </section>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-xs text-slate-500">{k}</span>
      <span className="text-xs font-medium text-right break-all">{v}</span>
    </div>
  );
}

function agoText(seconds: number): string {
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  return `${Math.floor(seconds / 3600)}h ago`;
}
