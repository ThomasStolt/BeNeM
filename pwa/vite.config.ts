/// <reference types="vitest" />
import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const middlewareBase = env.VITE_MIDDLEWARE_BASE ?? 'https://bhnm-apns.hurrikap.org';

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
          name: 'BHNM',
          short_name: 'BHNM',
          description: 'BHNM incident monitoring',
          id: '/',
          scope: '/',
          start_url: '/',
          display: 'standalone',
          display_override: ['standalone'],
          orientation: 'portrait',
          theme_color: '#0f172a',
          background_color: '#0f172a',
          categories: ['utilities', 'business'],
          icons: [
            { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
            { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
          ],
        },
        injectManifest: {
          globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        },
      }),
    ],
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
