/// <reference lib="webworker" />
declare const self: ServiceWorkerGlobalScope;

import { createHandlerBoundToURL, precacheAndRoute } from 'workbox-precaching';
import { NavigationRoute, registerRoute } from 'workbox-routing';

// Workbox precache manifest — injected by vite-plugin-pwa at build time
precacheAndRoute(self.__WB_MANIFEST);

// Serve every navigation from the precached shell. Without this the precache
// holds index.html but nothing routes navigations to it, so a reload while
// offline replaced the app with the browser's own error page — worst exactly
// when an on-call user taps a notification on a bad network.
registerRoute(new NavigationRoute(createHandlerBoundToURL('/index.html')));

// ── Push Notification Handler ───────────────────────────────────────────────

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data: { title?: string; body?: string; incident_id?: string };
  try {
    data = event.data.json();
  } catch {
    data = { title: 'BHNM', body: event.data.text() };
  }

  const title = data.title ?? 'BHNM';
  const body = data.body ?? '';

  event.waitUntil(
    Promise.all([
      self.registration.showNotification(title, {
        body,
        icon: '/icons/icon-192.png',
        data: { incident_id: data.incident_id },
        tag: data.incident_id ? `incident-${data.incident_id}` : undefined,
      }),
      // **Tell every open tab the cache has moved.** A push means the
      // middleware has just learned something; before 0.19.5 an already-open
      // incident list had no way to find out. The 120 s refetchInterval used to
      // cover it by accident — it re-read GET /api/v1/incidents whether or not
      // anything had happened — and removing it in 0.19.0 removed that, with C4
      // (the push carrying the change itself) not yet landed. Reported from the
      // field on iOS 54; the PWA has the same hole.
      //
      // The message says only that something changed. It carries no incident
      // data, deliberately: the client re-reads the middleware's cache, which
      // is the one place that decides what the list contains.
      notifyClients(),
    ]),
  );
});

async function notifyClients(): Promise<void> {
  const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  for (const client of clients) {
    if (new URL(client.url).origin === self.location.origin) {
      client.postMessage({ type: 'incidents-updated' });
    }
  }
}

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
            // The list reloads on the tap too, not only on the push that
            // preceded it — a tap can arrive long after the notification, on a
            // tab that was open the whole time.
            client.postMessage({ type: 'incidents-updated' });
            client.postMessage({ type: 'navigate', url: targetUrl });
            return;
          }
        }
        // Otherwise open a new window
        return self.clients.openWindow(targetUrl);
      }),
  );
});
