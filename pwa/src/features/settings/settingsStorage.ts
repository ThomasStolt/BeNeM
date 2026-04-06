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
