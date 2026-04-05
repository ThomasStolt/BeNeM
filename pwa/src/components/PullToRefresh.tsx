import { useRef, useState, type ReactNode, type TouchEvent } from 'react';

const THRESHOLD = 70;

export function PullToRefresh({ onRefresh, children }: { onRefresh: () => Promise<unknown> | void; children: ReactNode }) {
  const startY = useRef<number | null>(null);
  const [pull, setPull] = useState(0);
  const [refreshing, setRefreshing] = useState(false);

  const onTouchStart = (e: TouchEvent<HTMLDivElement>) => {
    if (window.scrollY > 0) return;
    startY.current = e.touches[0].clientY;
  };

  const onTouchMove = (e: TouchEvent<HTMLDivElement>) => {
    if (startY.current == null) return;
    const dy = e.touches[0].clientY - startY.current;
    if (dy > 0) setPull(Math.min(dy, THRESHOLD * 1.5));
  };

  const onTouchEnd = async () => {
    if (pull >= THRESHOLD && !refreshing) {
      setRefreshing(true);
      try {
        await onRefresh();
      } finally {
        setRefreshing(false);
      }
    }
    startY.current = null;
    setPull(0);
  };

  return (
    <div onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd}>
      <div
        aria-hidden
        style={{ height: pull }}
        className="flex items-center justify-center text-xs text-slate-500 transition-[height]"
      >
        {refreshing ? 'Refreshing…' : pull >= THRESHOLD ? 'Release to refresh' : pull > 0 ? 'Pull to refresh' : ''}
      </div>
      {children}
    </div>
  );
}
