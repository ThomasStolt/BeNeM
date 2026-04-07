export async function decrypt(blob: Uint8Array, hexKey: string): Promise<string> {
  if (blob.length < 12 + 16) {
    throw new Error('Encrypted data too short (need at least IV + auth tag)');
  }

  const keyBytes = new Uint8Array(
    hexKey.match(/.{2}/g)!.map((b) => parseInt(b, 16)),
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
