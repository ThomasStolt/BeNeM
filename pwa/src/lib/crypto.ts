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

/**
 * Decrypt and zlib-decompress a payload produced by the middleware's
 * encrypt_payload() (JSON → zlib compress → AES-256-GCM → base64url).
 */
export async function decryptCompressed(blob: Uint8Array, hexKey: string): Promise<string> {
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

  const compressed = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    ciphertextWithTag,
  );

  // Decompress zlib stream (Python's zlib.compress output)
  const ds = new DecompressionStream('deflate');
  const writer = ds.writable.getWriter();
  writer.write(new Uint8Array(compressed));
  writer.close();

  const reader = ds.readable.getReader();
  const chunks: Uint8Array[] = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }
  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder().decode(result);
}
