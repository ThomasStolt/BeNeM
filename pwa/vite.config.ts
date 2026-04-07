/// <reference types="vitest" />
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

/** Read a key from the middleware's .env so we don't duplicate secrets. */
function readMiddlewareEnv(key: string): string {
  try {
    const raw = readFileSync(resolve(__dirname, '../middleware/.env'), 'utf-8');
    const match = raw.match(new RegExp(`^${key}=(.*)$`, 'm'));
    return match?.[1]?.trim() ?? '';
  } catch {
    return '';
  }
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const middlewareBase = env.VITE_MIDDLEWARE_BASE ?? 'https://bhnm-apns.hurrikap.org';

  // QR encryption key: prefer PWA env override, fall back to middleware's BENEM_SECRET_KEY
  const qrKey = env.VITE_QR_ENCRYPTION_KEY || readMiddlewareEnv('BENEM_SECRET_KEY');

  return {
    plugins: [
      react(),
      VitePWA({
        strategies: 'injectManifest',
        srcDir: 'src',
        filename: 'sw.ts',
        registerType: 'autoUpdate',
        includeAssets: ['icons/*'],
        manifest: {
          name: 'BeNeM',
          short_name: 'BeNeM',
          description: 'BHNM incident monitoring',
          theme_color: '#0f172a',
          background_color: '#0f172a',
          display: 'standalone',
          start_url: '/',
          icons: [],
        },
        injectManifest: {
          globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        },
      }),
    ],
    define: {
      'import.meta.env.VITE_QR_ENCRYPTION_KEY': JSON.stringify(qrKey),
    },
    server: {
      proxy: {
        '/bhnm': {
          target: middlewareBase,
          changeOrigin: true,
          secure: true,
          rewrite: (p) => p.replace(/^\/bhnm/, ''),
        },
      },
    },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: ['./src/test-setup.ts'],
    },
  };
});
