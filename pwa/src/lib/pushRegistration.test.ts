import { describe, it, expect } from 'vitest';
import { urlBase64ToUint8Array } from './pushRegistration';

describe('urlBase64ToUint8Array', () => {
  it('converts a base64url string to Uint8Array', () => {
    // "AAAA" in base64 is [0, 0, 0]
    const result = urlBase64ToUint8Array('AAAA');
    expect(result).toBeInstanceOf(Uint8Array);
    expect(result.length).toBe(3);
    expect(result[0]).toBe(0);
  });

  it('handles base64url padding', () => {
    // base64url uses - and _ instead of + and /
    const result = urlBase64ToUint8Array('AQID');
    expect(result[0]).toBe(1);
    expect(result[1]).toBe(2);
    expect(result[2]).toBe(3);
  });
});
