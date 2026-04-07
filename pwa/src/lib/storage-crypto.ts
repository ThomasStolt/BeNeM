/**
 * localStorage field-level encryption using Web Crypto API (AES-256-GCM).
 *
 * Derives a deterministic key from a fixed salt + the page origin via PBKDF2.
 * This does NOT provide protection against a same-origin attacker who can run
 * arbitrary JS (they can derive the same key). It DOES prevent:
 *  - Casual inspection of localStorage in DevTools
 *  - Credential theft via simple `localStorage.getItem()` from injected scripts
 *    that don't know the derivation scheme
 *  - Cross-origin reads (already blocked by the browser, but belt-and-suspenders)
 */

const SALT = 'benem-storage-v1';

/** Encrypted values are prefixed with this marker so we can distinguish them. */
const ENCRYPTED_PREFIX = '$enc$';

let cachedKey: CryptoKey | null = null;

async function deriveKey(): Promise<CryptoKey> {
  if (cachedKey) return cachedKey;

  const material = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(SALT + location.origin),
    'PBKDF2',
    false,
    ['deriveKey'],
  );
  cachedKey = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: new TextEncoder().encode(SALT),
      iterations: 100_000,
      hash: 'SHA-256',
    },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
  return cachedKey;
}

/**
 * Encrypt a plaintext string. Returns a string prefixed with `$enc$`
 * followed by base64-encoded IV + ciphertext.
 */
export async function encryptField(plaintext: string): Promise<string> {
  const key = await deriveKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(plaintext),
  );
  const combined = new Uint8Array(iv.length + new Uint8Array(ciphertext).length);
  combined.set(iv);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return ENCRYPTED_PREFIX + btoa(String.fromCharCode(...combined));
}

/**
 * Decrypt a value previously encrypted by `encryptField`.
 * If the value is not encrypted (no `$enc$` prefix), returns it as-is
 * (transparent migration from plaintext).
 */
export async function decryptField(value: string): Promise<string> {
  if (!value.startsWith(ENCRYPTED_PREFIX)) {
    return value; // plaintext — not yet encrypted
  }
  const encoded = value.slice(ENCRYPTED_PREFIX.length);
  const key = await deriveKey();
  const combined = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
  const iv = combined.slice(0, 12);
  const ciphertext = combined.slice(12);
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(plaintext);
}

/** Returns true if the value was encrypted by `encryptField`. */
export function isEncryptedField(value: string): boolean {
  return value.startsWith(ENCRYPTED_PREFIX);
}

/** Reset the cached key (for testing only). */
export function _resetKeyCache(): void {
  cachedKey = null;
}
