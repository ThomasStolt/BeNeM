import { useState } from 'react';
import { isIOS } from '../lib/platform';

const DISMISS_KEY = 'benem:ios-banner-dismissed';

export function IOSRedirectBanner() {
  const [dismissed, setDismissed] = useState(
    () => typeof sessionStorage !== 'undefined' && sessionStorage.getItem(DISMISS_KEY) === '1'
  );

  if (dismissed || !isIOS()) return null;

  const dismiss = () => {
    sessionStorage.setItem(DISMISS_KEY, '1');
    setDismissed(true);
  };

  return (
    <div className="sticky top-0 z-40 bg-amber-500 text-slate-950 px-4 py-2 flex items-center justify-between text-sm">
      <span>
        For reliable incident alerts, install the{' '}
        {/* TODO: replace with App Store URL when listing is live */}
        <a href="#" className="underline font-semibold">
          BeNeM iOS app
        </a>
        .
      </span>
      <button
        type="button"
        onClick={dismiss}
        aria-label="Dismiss"
        className="ml-4 font-bold text-lg leading-none"
      >
        ×
      </button>
    </div>
  );
}
