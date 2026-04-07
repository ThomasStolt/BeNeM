import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import { migrateFromLegacyConfig, initStorage } from './lib/serverStorage';
import './index.css';

/** Error boundary that displays the crash reason visibly on screen. */
class CrashBoundary extends React.Component<
  { children: React.ReactNode },
  { error: Error | null }
> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    if (this.state.error) {
      return React.createElement('div', {
        style: {
          position: 'fixed', inset: 0, background: '#7f1d1d', color: '#fff',
          fontFamily: 'monospace', fontSize: '13px', padding: '16px',
          overflow: 'auto', zIndex: 99999,
        },
      },
        React.createElement('h2', { style: { margin: '0 0 8px' } }, 'App Crash'),
        React.createElement('p', null, this.state.error.message),
        React.createElement('pre', { style: { whiteSpace: 'pre-wrap', fontSize: '11px', marginTop: '8px' } },
          this.state.error.stack),
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
        <CrashBoundary>
          <QueryClientProvider client={queryClient}>
            <BrowserRouter>
              <App />
            </BrowserRouter>
          </QueryClientProvider>
        </CrashBoundary>
      </React.StrictMode>,
    );
  });
