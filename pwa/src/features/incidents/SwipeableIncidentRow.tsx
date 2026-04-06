import { useState, useRef } from 'react';
import { useSwipeable } from 'react-swipeable';
import { useQueryClient } from '@tanstack/react-query';
import { IncidentRow } from './IncidentRow';
import { useConfig } from '../../lib/config';
import { acknowledgeIncident, unacknowledgeIncident } from '../../lib/api/incidents';
import type { Incident } from '../../lib/api/types';

const THRESHOLD = 80;

export function SwipeableIncidentRow({ incident }: { incident: Incident }) {
  const config = useConfig();
  const queryClient = useQueryClient();
  const [offsetX, setOffsetX] = useState(0);
  const [isProcessing, setIsProcessing] = useState(false);
  const triggered = useRef(false);

  const isActive = incident.status === 'active';
  const isAcked = incident.status === 'acknowledged';

  const handlers = useSwipeable({
    onSwiping: (e) => {
      if (isProcessing) return;
      // Right swipe (positive deltaX) = ACK — only for active
      if (e.deltaX > 0 && isActive) {
        setOffsetX(Math.min(e.deltaX, THRESHOLD + 40));
      }
      // Left swipe (negative deltaX) = UnACK — only for acknowledged
      if (e.deltaX < 0 && isAcked) {
        setOffsetX(Math.max(e.deltaX, -(THRESHOLD + 40)));
      }
    },
    onSwipedRight: async () => {
      if (!isActive || isProcessing || triggered.current) return;
      if (offsetX >= THRESHOLD) {
        triggered.current = true;
        setIsProcessing(true);
        try {
          await acknowledgeIncident(config, incident.incidentId);
          await queryClient.invalidateQueries({ queryKey: ['incidents'] });
        } catch {
          // Reset on failure — list will show stale state until next refresh
        } finally {
          setIsProcessing(false);
          triggered.current = false;
        }
      }
      setOffsetX(0);
    },
    onSwipedLeft: async () => {
      if (!isAcked || isProcessing || triggered.current) return;
      if (Math.abs(offsetX) >= THRESHOLD) {
        triggered.current = true;
        setIsProcessing(true);
        try {
          await unacknowledgeIncident(config, incident.incidentId);
          await queryClient.invalidateQueries({ queryKey: ['incidents'] });
        } catch {
          // Reset on failure
        } finally {
          setIsProcessing(false);
          triggered.current = false;
        }
      }
      setOffsetX(0);
    },
    onSwiped: () => {
      if (!triggered.current) setOffsetX(0);
    },
    trackMouse: false,
    trackTouch: true,
    preventScrollOnSwipe: true,
  });

  return (
    <div className="relative overflow-hidden" {...handlers}>
      {/* ACK background (green, revealed on right swipe) */}
      {isActive && (
        <div className="absolute inset-0 bg-emerald-600 flex items-center pl-5">
          <span className="text-white font-bold text-sm">✓ ACK</span>
        </div>
      )}

      {/* UnACK background (red, revealed on left swipe) */}
      {isAcked && (
        <div className="absolute inset-0 bg-red-600 flex items-center justify-end pr-5">
          <span className="text-white font-bold text-sm">UnACK ✕</span>
        </div>
      )}

      {/* Foreground row */}
      <div
        className="relative bg-slate-950 transition-transform duration-75"
        style={{ transform: `translateX(${offsetX}px)` }}
      >
        {isProcessing && (
          <div className="absolute inset-0 bg-slate-950/80 flex items-center justify-center z-10">
            <span className="text-xs text-slate-400">...</span>
          </div>
        )}
        <IncidentRow incident={incident} />
      </div>
    </div>
  );
}
