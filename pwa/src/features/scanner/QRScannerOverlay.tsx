import { useEffect, useRef } from 'react';
import { Html5Qrcode } from 'html5-qrcode';

interface QRScannerOverlayProps {
  onScanned: (decodedText: string) => void | Promise<void>;
  onCancel: () => void;
  onError?: (error: string) => void;
}

export function QRScannerOverlay({ onScanned, onCancel, onError }: QRScannerOverlayProps) {
  const scannerRef = useRef<Html5Qrcode | null>(null);
  const containerRef = useRef<string>('qr-reader-' + Math.random().toString(36).slice(2));
  // Use refs for callbacks to avoid restarting the scanner on every render
  const onScannedRef = useRef(onScanned);
  const onErrorRef = useRef(onError);
  onScannedRef.current = onScanned;
  onErrorRef.current = onError;
  const stoppedRef = useRef(false);

  useEffect(() => {
    const scanner = new Html5Qrcode(containerRef.current);
    scannerRef.current = scanner;
    stoppedRef.current = false;

    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: 250 },
        (decodedText) => {
          if (stoppedRef.current) return;
          stoppedRef.current = true;
          scanner.stop()
            .catch(() => {}) // proceed even if stop fails
            .then(() => {
              const result = onScannedRef.current(decodedText);
              if (result instanceof Promise) {
                result.catch((err) => {
                  onErrorRef.current?.(err instanceof Error ? err.message : String(err));
                });
              }
            });
        },
        undefined,
      )
      .catch((err) => {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('Permission') || msg.includes('NotAllowed')) {
          onErrorRef.current?.('Camera permission denied. Enable it in browser settings.');
        } else {
          onErrorRef.current?.(msg);
        }
      });

    return () => {
      stoppedRef.current = true;
      scanner.stop()
        .catch(() => {})
        .finally(() => { scanner.clear(); });
    };
  }, []); // stable deps — callbacks accessed via refs

  return (
    <div className="fixed inset-0 z-50 bg-black flex flex-col items-center justify-center">
      <div className="relative w-full max-w-sm">
        <div id={containerRef.current} className="w-full" />
        <p className="text-center text-sm text-slate-300 mt-4">
          Point at a BeNeM QR code
        </p>
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="mt-8 px-6 py-2.5 rounded-lg bg-slate-800 text-sm text-white hover:bg-slate-700"
        aria-label="Cancel"
      >
        Cancel
      </button>
    </div>
  );
}
