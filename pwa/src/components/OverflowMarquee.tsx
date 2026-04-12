import { useEffect, useRef, useState } from 'react';

const GAP_PX = 48; // px gap between the two text copies
const FADE_MASK =
  'linear-gradient(to right, transparent 0%, black 4%, black 96%, transparent 100%)';

interface Props {
  text: string;
  /** Applied to the outer clip div — include flex layout + text style classes here. */
  className?: string;
  /** Scroll speed in px/s. Default 40. */
  speed?: number;
}

export function OverflowMarquee({ text, className = '', speed = 40 }: Props) {
  const clipRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const [overflows, setOverflows] = useState(false);
  const [animDuration, setAnimDuration] = useState('8s');

  useEffect(() => {
    function measure() {
      const clip = clipRef.current;
      const measureEl = measureRef.current;
      if (!clip || !measureEl) return;

      const textWidth = measureEl.scrollWidth;

      const containerWidth = clip.clientWidth;
      const doesOverflow = textWidth > containerWidth;
      setOverflows(doesOverflow);
      if (doesOverflow) {
        setAnimDuration(`${(textWidth + GAP_PX) / speed}s`);
      }
    }

    measure();
    const ro = new ResizeObserver(measure);
    if (clipRef.current) ro.observe(clipRef.current);
    return () => ro.disconnect();
  }, [text, speed]);

  return (
    <div
      ref={clipRef}
      className={`overflow-hidden ${className}`}
      style={
        overflows
          ? { maskImage: FADE_MASK, WebkitMaskImage: FADE_MASK }
          : undefined
      }
    >
      {/* Hidden measurement span — always in DOM, out of flow, never animated */}
      <span
        ref={measureRef}
        data-testid="marquee-measure"
        style={{
          visibility: 'hidden',
          position: 'absolute',
          whiteSpace: 'nowrap',
          pointerEvents: 'none',
        }}
        aria-hidden="true"
      >
        {text}
      </span>


      {overflows ? (
        // Dual-copy track — animates from 0 to -50% (= one full copy width + gap)
        <div
          className="flex w-max animate-marquee motion-reduce:animate-none"
          style={{ animationDuration: animDuration }}
        >
          <span className="whitespace-nowrap" style={{ paddingRight: `${GAP_PX}px` }}>
            {text}
          </span>
          <span
            className="whitespace-nowrap"
            style={{ paddingRight: `${GAP_PX}px` }}
            aria-hidden="true"
          >
            {text}
          </span>
        </div>
      ) : (
        <span className="whitespace-nowrap block truncate">{text}</span>
      )}
    </div>
  );
}
