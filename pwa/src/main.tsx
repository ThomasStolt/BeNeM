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
  { error: unknown; info: string }
> {
  state: { error: unknown; info: string } = { error: null, info: '' };

  static getDerivedStateFromError(error: unknown) {
    return { error };
  }

  componentDidCatch(error: unknown, errorInfo: React.ErrorInfo) {
    this.setState({
      info: errorInfo.componentStack || '',
    });
  }

  render() {
    if (this.state.error !== null) {
      const err = this.state.error;
      const msg = err instanceof Error ? err.message : String(err);
      const stack = err instanceof Error ? err.stack : '';
      const type = Object.prototype.toString.call(err);
      const json = (() => { try { return JSON.stringify(err, null, 2); } catch { return ''; } })();

      return React.createElement('div', {
        style: {
          position: 'fixed', inset: 0, background: '#7f1d1d', color: '#fff',
          fontFamily: 'monospace', fontSize: '12px', padding: '16px',
          overflow: 'auto', zIndex: 99999,
        },
      },
        React.createElement('h2', { style: { margin: '0 0 8px' } }, 'App Crash'),
        React.createElement('p', null, `Type: ${type}`),
        React.createElement('p', null, `Message: ${msg}`),
        json && React.createElement('pre', { style: { whiteSpace: 'pre-wrap', fontSize: '11px', marginTop: '8px', background: '#450a0a', padding: '8px', borderRadius: '4px' } }, `JSON: ${json}`),
        stack && React.createElement('pre', { style: { whiteSpace: 'pre-wrap', fontSize: '11px', marginTop: '8px' } }, `Stack: ${stack}`),
        this.state.info && React.createElement('pre', { style: { whiteSpace: 'pre-wrap', fontSize: '11px', marginTop: '8px', color: '#fca5a5' } }, `Component: ${this.state.info}`),
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
