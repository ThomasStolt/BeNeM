import { describe, it, expect } from 'vitest';
import { decrypt, decryptCompressed } from './crypto';
import { deflateSync } from 'node:zlib';

// To test decryption, we encrypt first using Web Crypto API.
async function encrypt(plaintext: string, hexKey: string): Promise<Uint8Array> {
  const keyBytes = new Uint8Array(hexKey.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
  // Compact format: [12-byte IV | ciphertext + 16-byte auth tag]
  const result = new Uint8Array(12 + ciphertext.byteLength);
  result.set(iv, 0);
  result.set(new Uint8Array(ciphertext), 12);
  return result;
}

/** Encrypt with zlib compression, matching middleware's encrypt_payload(). */
async function encryptCompressed(plaintext: string, hexKey: string): Promise<Uint8Array> {
  const keyBytes = new Uint8Array(hexKey.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  // zlib compress (Python's zlib.compress uses deflate wrapped in zlib header)
  const compressed = deflateSync(Buffer.from(plaintext, 'utf-8'));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, compressed);
  const result = new Uint8Array(12 + ciphertext.byteLength);
  result.set(iv, 0);
  result.set(new Uint8Array(ciphertext), 12);
  return result;
}

const TEST_KEY = 'aa'.repeat(32); // 32 bytes of 0xAA

describe('decrypt', () => {
  it('round-trips encryption and decryption', async () => {
    const plaintext = '{"bhnm_url":"https://bhnm.example.com","api_key":"secret123"}';
    const blob = await encrypt(plaintext, TEST_KEY);
    const result = await decrypt(blob, TEST_KEY);
    expect(result).toBe(plaintext);
  });

  it('throws on wrong key', async () => {
    const blob = await encrypt('test', TEST_KEY);
    const wrongKey = 'bb'.repeat(32);
    await expect(decrypt(blob, wrongKey)).rejects.toThrow();
  });

  it('throws on truncated data', async () => {
    const blob = new Uint8Array(10); // too short for IV + auth tag
    await expect(decrypt(blob, TEST_KEY)).rejects.toThrow();
  });

  it('throws on invalid key length', async () => {
    const blob = await encrypt('test', TEST_KEY);
    await expect(decrypt(blob, 'aa'.repeat(16))).rejects.toThrow('expected 32-byte hex string');
  });
});

describe('decryptCompressed', () => {
  it('round-trips zlib-compressed encryption and decryption', async () => {
    const plaintext = '{"bhnm_url":"https://bhnm.example.com","api_key":"secret"}';
    const blob = await encryptCompressed(plaintext, TEST_KEY);
    const result = await decryptCompressed(blob, TEST_KEY);
    expect(result).toBe(plaintext);
  });

  it('throws on wrong key', async () => {
    const blob = await encryptCompressed('test', TEST_KEY);
    const wrongKey = 'bb'.repeat(32);
    await expect(decryptCompressed(blob, wrongKey)).rejects.toThrow();
  });
});
