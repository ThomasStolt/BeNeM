const KEY = 'benem:bhnm-api-key';

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
