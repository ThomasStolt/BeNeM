/// <reference lib="webworker" />
declare const self: ServiceWorkerGlobalScope;

import { precacheAndRoute } from 'workbox-precaching';

// Workbox precache manifest — injected by vite-plugin-pwa at build time
precacheAndRoute(self.__WB_MANIFEST);

// ── Push Notification Handler ───────────────────────────────────────────────

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data: { title?: string; body?: string; incident_id?: string };
  try {
    data = event.data.json();
  } catch {
    data = { title: 'BeNeM', body: event.data.text() };
  }

  const title = data.title ?? 'BeNeM';
  const body = data.body ?? '';

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/icons/icon-192.png',
      badge: '/icons/badge-96.png',
      data: { incident_id: data.incident_id },
      tag: data.incident_id ? `incident-${data.incident_id}` : undefined,
    }),
  );
});

// ── Notification Click — Deep-link to Incident Detail ───────────────────────

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const incidentId = event.notification.data?.incident_id;
  const targetUrl = incidentId ? `/incidents/${incidentId}` : '/';

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((windowClients) => {
        // If the PWA is already open, focus it and navigate
        for (const client of windowClients) {
          if (new URL(client.url).origin === self.location.origin) {
            client.focus();
            client.postMessage({ type: 'navigate', url: targetUrl });
            return;
          }
        }
        // Otherwise open a new window
        return self.clients.openWindow(targetUrl);
      }),
  );
});
