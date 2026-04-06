import { useEffect } from 'react';

export interface ToastMessage {
  text: string;
  type: 'success' | 'error';
}

interface ToastProps {
  message: ToastMessage | null;
  onDismiss: () => void;
  durationMs?: number;
}

export function Toast({ message, onDismiss, durationMs = 3000 }: ToastProps) {
  useEffect(() => {
    if (!message) return;
    const timer = setTimeout(onDismiss, durationMs);
    return () => clearTimeout(timer);
  }, [message, onDismiss, durationMs]);

  if (!message) return null;

  const bgClass = message.type === 'success'
    ? 'bg-emerald-600'
    : 'bg-red-600';

  return (
    <div
      className={`fixed bottom-4 left-4 right-4 z-50 ${bgClass} text-white text-sm font-medium px-4 py-3 rounded-lg shadow-lg text-center`}
      role="status"
      aria-live="polite"
    >
      {message.text}
    </div>
  );
}
