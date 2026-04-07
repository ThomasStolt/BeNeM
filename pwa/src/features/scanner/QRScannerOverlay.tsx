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

  useEffect(() => {
    const scanner = new Html5Qrcode(containerRef.current);
    scannerRef.current = scanner;

    scanner
      .start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: 250 },
        (decodedText) => {
          scanner.stop().then(() => {
            const result = onScanned(decodedText);
            if (result instanceof Promise) {
              result.catch((err) => {
                onError?.(err instanceof Error ? err.message : String(err));
              });
            }
          });
        },
        undefined,
      )
      .catch((err) => {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes('Permission') || msg.includes('NotAllowed')) {
          onError?.('Camera permission denied. Enable it in browser settings.');
        } else {
          onError?.(msg);
        }
      });

    return () => {
      scanner.stop()
        .catch(() => {})
        .finally(() => { scanner.clear(); });
    };
  }, [onScanned, onError]);

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
