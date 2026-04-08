import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import { migrateFromLegacyConfig, initStorage } from './lib/serverStorage';
import './index.css';

/** Catch-all error boundary — shows a reload prompt instead of a blank screen. */
class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { error: unknown }
> {
  state: { error: unknown } = { error: null };

  static getDerivedStateFromError(err: unknown) {
    return { error: err };
  }

  render() {
    if (this.state.error !== null) {
      const msg = this.state.error instanceof Error
        ? this.state.error.message
        : String(this.state.error);
      return React.createElement('div', {
        style: {
          display: 'flex', flexDirection: 'column' as const, alignItems: 'center',
          justifyContent: 'center', minHeight: '100vh', padding: '24px',
          fontFamily: '-apple-system, system-ui, sans-serif', color: '#94a3b8',
        },
      },
        React.createElement('p', { style: { fontSize: '14px', marginBottom: '8px' } }, 'Something went wrong.'),
        React.createElement('p', { style: { fontSize: '12px', color: '#64748b', marginBottom: '16px' } }, msg),
        React.createElement('button', {
          onClick: () => window.location.reload(),
          style: {
            padding: '8px 20px', borderRadius: '8px', border: '1px solid #334155',
            background: '#1e293b', color: '#e2e8f0', fontSize: '14px', cursor: 'pointer',
          },
        }, 'Reload'),
      );
    }
    return this.props.children;
  }
}

// Migrate single-server config to multi-server format (one-time, idempotent)
migrateFromLegacyConfig();

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: true,
      retry: 1,
      staleTime: 30_000,
    },
  },
});

// Decrypt server config from localStorage before first render,
// then mount the app. If decryption fails, the app still renders
// (loadServers falls back to raw reads).
initStorage()
  .catch((err) => {
    // eslint-disable-next-line no-console
    console.error('[BeNeM] Storage init failed:', err);
  })
  .finally(() => {
    ReactDOM.createRoot(document.getElementById('root')!).render(
      <React.StrictMode>
        <ErrorBoundary>
          <QueryClientProvider client={queryClient}>
            <BrowserRouter>
              <App />
            </BrowserRouter>
          </QueryClientProvider>
        </ErrorBoundary>
      </React.StrictMode>,
    );
  });
