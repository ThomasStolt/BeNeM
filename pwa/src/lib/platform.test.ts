import { describe, it, expect } from 'vitest';
import { isIOSUserAgent } from './platform';

describe('isIOSUserAgent', () => {
  it('returns true for iPhone UA', () => {
    const ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15';
    expect(isIOSUserAgent(ua)).toBe(true);
  });

  it('returns true for iPad UA', () => {
    const ua = 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15';
    expect(isIOSUserAgent(ua)).toBe(true);
  });

  it('returns false for Android UA', () => {
    const ua = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36';
    expect(isIOSUserAgent(ua)).toBe(false);
  });

  it('returns false for desktop Chrome UA', () => {
    const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0.0.0';
    expect(isIOSUserAgent(ua)).toBe(false);
  });
});
