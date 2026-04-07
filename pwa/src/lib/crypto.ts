export async function decrypt(blob: Uint8Array, hexKey: string): Promise<string> {
  if (blob.length < 12 + 16) {
    throw new Error('Encrypted data too short (need at least IV + auth tag)');
  }

  const pairs = hexKey.match(/.{2}/g);
  if (!pairs || pairs.length !== 32) {
    throw new Error('Invalid encryption key: expected 32-byte hex string');
  }
  const keyBytes = new Uint8Array(
    pairs.map((b) => parseInt(b, 16)),
  );
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    'AES-GCM',
    false,
    ['decrypt'],
  );

  const iv = blob.slice(0, 12);
  const ciphertextWithTag = blob.slice(12);

  const plainBuffer = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertextWithTag,
  );
  return new TextDecoder().decode(plainBuffer);
}
