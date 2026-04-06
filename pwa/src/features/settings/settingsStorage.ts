const KEY = 'benem:bhnm-api-key';
const PIN_KEY = 'benem:bhnm-pin';

export function loadApiKey(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(KEY);
}

export function saveApiKey(value: string): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(KEY, value.trim());
}

export function clearApiKey(): void {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(KEY);
}

export function loadPin(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(PIN_KEY);
}

export function savePin(value: string): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(PIN_KEY, value.trim());
}

export function clearPin(): void {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(PIN_KEY);
}

const WEBHOOK_SECRET_KEY = 'benem:webhook-secret';
const PUSH_ENABLED_KEY = 'benem:push-enabled';

export function loadWebhookSecret(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(WEBHOOK_SECRET_KEY);
}

export function saveWebhookSecret(value: string): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(WEBHOOK_SECRET_KEY, value.trim());
}

export function clearWebhookSecret(): void {
  if (typeof window === 'undefined') return;
  window.localStorage.removeItem(WEBHOOK_SECRET_KEY);
}

export function loadPushEnabled(): boolean {
  if (typeof window === 'undefined') return false;
  return window.localStorage.getItem(PUSH_ENABLED_KEY) === 'true';
}

export function savePushEnabled(enabled: boolean): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(PUSH_ENABLED_KEY, String(enabled));
}
