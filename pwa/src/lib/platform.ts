export function isIOSUserAgent(ua: string): boolean {
  return /iPad|iPhone|iPod/.test(ua);
}

export function isIOS(): boolean {
  if (typeof navigator === 'undefined') return false;
  // @ts-expect-error — legacy IE flag, absence is meaningful on iOS
  if (typeof window !== 'undefined' && window.MSStream) return false;
  return isIOSUserAgent(navigator.userAgent);
}
