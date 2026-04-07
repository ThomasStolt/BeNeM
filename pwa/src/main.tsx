import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import { migrateFromLegacyConfig, initStorage } from './lib/serverStorage';
import './index.css';

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
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            <App />
          </BrowserRouter>
        </QueryClientProvider>
      </React.StrictMode>,
    );
  });
