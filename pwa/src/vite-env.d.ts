/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
  readonly VITE_MIDDLEWARE_BASE?: string;
  readonly VITE_BHNM_API_KEY?: string;
  readonly VITE_BHNM_PIN?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
