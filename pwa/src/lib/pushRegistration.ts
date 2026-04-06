/**
 * Convert a VAPID public key from base64url to Uint8Array
 * (required by pushManager.subscribe).
 */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

/**
 * Fetch the VAPID public key from the middleware.
 */
export async function fetchVapidKey(baseUrl: string): Promise<string> {
  const resp = await fetch(`${baseUrl}/vapid-key`);
  if (!resp.ok) throw new Error(`Failed to fetch VAPID key: HTTP ${resp.status}`);
  const data = await resp.json();
  return data.publicKey;
}

export type PushState =
  | { status: 'unsupported' }
  | { status: 'denied' }
  | { status: 'unregistered' }
  | { status: 'registered'; endpoint: string }
  | { status: 'error'; message: string };

/**
 * Get the current push registration state.
 */
export function getPushState(): PushState {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    return { status: 'unsupported' };
  }
  if (Notification.permission === 'denied') {
    return { status: 'denied' };
  }
  return { status: 'unregistered' };
}

/**
 * Subscribe to Web Push and register with the middleware.
 * Returns the push subscription endpoint on success.
 */
export async function subscribeToPush(
  baseUrl: string,
  webhookSecret: string,
): Promise<string> {
  // 1. Request notification permission
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    throw new Error('Notification permission denied');
  }

  // 2. Get VAPID key
  const vapidKey = await fetchVapidKey(baseUrl);

  // 3. Get service worker registration
  const swReg = await navigator.serviceWorker.ready;

  // 4. Subscribe to push
  const subscription = await swReg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidKey).buffer as ArrayBuffer,
  });

  const subJson = subscription.toJSON();
  if (!subJson.endpoint || !subJson.keys?.p256dh || !subJson.keys?.auth) {
    throw new Error('Invalid push subscription — missing keys');
  }

  // 5. Register with middleware
  const resp = await fetch(`${baseUrl}/register-webpush`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Token': webhookSecret,
    },
    body: JSON.stringify({
      endpoint: subJson.endpoint,
      p256dh: subJson.keys.p256dh,
      auth: subJson.keys.auth,
    }),
  });

  if (!resp.ok) {
    throw new Error(`Push registration failed: HTTP ${resp.status}`);
  }

  return subJson.endpoint;
}

/**
 * Unsubscribe from Web Push.
 */
export async function unsubscribeFromPush(): Promise<void> {
  const swReg = await navigator.serviceWorker.ready;
  const subscription = await swReg.pushManager.getSubscription();
  if (subscription) {
    await subscription.unsubscribe();
  }
}
