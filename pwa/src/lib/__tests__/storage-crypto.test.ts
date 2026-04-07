import { describe, it, expect, beforeEach } from 'vitest';
import { encryptField, decryptField, isEncryptedField, _resetKeyCache } from '../storage-crypto';

beforeEach(() => {
  _resetKeyCache();
});

describe('storage-crypto', () => {
  it('round-trips a string through encrypt/decrypt', async () => {
    const original = 'my-secret-api-key-12345';
    const encrypted = await encryptField(original);
    const decrypted = await decryptField(encrypted);
    expect(decrypted).toBe(original);
  });

  it('encrypted output starts with $enc$ prefix', async () => {
    const encrypted = await encryptField('test');
    expect(encrypted).toMatch(/^\$enc\$/);
  });

  it('isEncryptedField detects encrypted values', async () => {
    const encrypted = await encryptField('test');
    expect(isEncryptedField(encrypted)).toBe(true);
  });

  it('isEncryptedField returns false for plaintext', () => {
    expect(isEncryptedField('plaintext-key')).toBe(false);
    expect(isEncryptedField('')).toBe(false);
  });

  it('decryptField passes through plaintext transparently', async () => {
    const plaintext = 'not-encrypted-value';
    const result = await decryptField(plaintext);
    expect(result).toBe(plaintext);
  });

  it('produces different ciphertext for same input (random IV)', async () => {
    const input = 'same-input';
    const a = await encryptField(input);
    const b = await encryptField(input);
    expect(a).not.toBe(b);
    // But both decrypt to the same value
    expect(await decryptField(a)).toBe(input);
    expect(await decryptField(b)).toBe(input);
  });

  it('handles empty string', async () => {
    const encrypted = await encryptField('');
    const decrypted = await decryptField(encrypted);
    expect(decrypted).toBe('');
  });

  it('handles unicode', async () => {
    const original = 'Schlüssel mit Ümlauten: äöü';
    const encrypted = await encryptField(original);
    const decrypted = await decryptField(encrypted);
    expect(decrypted).toBe(original);
  });
});
