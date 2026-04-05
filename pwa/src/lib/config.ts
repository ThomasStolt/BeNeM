export interface BhnmConfig {
  /** Base URL the client should hit. In dev this is "/bhnm" (Vite proxy). */
  baseUrl: string;
  apiKey: string;
  pin?: string;
  isConfigured: boolean;
}

export function useConfig(): BhnmConfig {
  const apiKey = import.meta.env.VITE_BHNM_API_KEY ?? '';
  const pin = import.meta.env.VITE_BHNM_PIN || undefined;
  // Dev proxy mounted at /bhnm in vite.config.ts. In production this will need
  // a proper absolute URL + CORS on middleware — deferred to v0.1.1.
  const baseUrl = '/bhnm';
  return {
    baseUrl,
    apiKey,
    pin,
    isConfigured: apiKey.length > 0,
  };
}
