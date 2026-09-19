import { useState } from 'react';
import { isIOS } from '../lib/platform';

const DISMISS_KEY = 'benem:ios-banner-dismissed';

// The listing is titled "BHNM", so the link text must say BHNM — the name on
// the App Store page is the one the user has to recognise when they land there.
const APP_STORE_URL = 'https://apps.apple.com/app/id6761024731';

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
        For reliable incident alerts, install{' '}
        <a
          href={APP_STORE_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="underline font-semibold"
        >
          BHNM on the App Store
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
