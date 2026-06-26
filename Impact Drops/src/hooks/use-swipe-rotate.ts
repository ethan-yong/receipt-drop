import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";

/**
 * Horizontal swipe → Y rotation with inertia. Returns rotation (deg) and
 * pointer-event bindings to spread on the stage element.
 */
export function useSwipeRotate(initial = 25) {
  const [rotation, setRotation] = useState(initial);
  const rotRef = useRef(initial);
  const lastXRef = useRef(0);
  const draggingRef = useRef(false);
  const velocityRef = useRef(0);
  const lastTimeRef = useRef(0);
  const rafRef = useRef<number | null>(null);

  // Idle auto-rotate when not dragging and no momentum
  useEffect(() => {
    let raf: number;
    const tick = () => {
      if (!draggingRef.current && Math.abs(velocityRef.current) < 0.05) {
        rotRef.current += 0.12;
        setRotation(rotRef.current);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const stopInertia = () => {
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
  };

  const runInertia = () => {
    stopInertia();
    const step = () => {
      velocityRef.current *= 0.93;
      if (Math.abs(velocityRef.current) < 0.05) {
        velocityRef.current = 0;
        return;
      }
      rotRef.current += velocityRef.current;
      setRotation(rotRef.current);
      rafRef.current = requestAnimationFrame(step);
    };
    rafRef.current = requestAnimationFrame(step);
  };

  const onPointerDown = (e: ReactPointerEvent) => {
    draggingRef.current = true;
    lastXRef.current = e.clientX;
    lastTimeRef.current = performance.now();
    velocityRef.current = 0;
    stopInertia();
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  };

  const onPointerMove = (e: ReactPointerEvent) => {
    if (!draggingRef.current) return;
    const now = performance.now();
    const dx = e.clientX - lastXRef.current;
    const dt = Math.max(1, now - lastTimeRef.current);
    const deg = dx * 0.5;
    rotRef.current += deg;
    velocityRef.current = (deg / dt) * 16; // per-frame at ~60fps
    setRotation(rotRef.current);
    lastXRef.current = e.clientX;
    lastTimeRef.current = now;
  };

  const onPointerUp = (e: ReactPointerEvent) => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    try {
      (e.currentTarget as Element).releasePointerCapture(e.pointerId);
    } catch {}
    runInertia();
  };

  return {
    rotation,
    bind: {
      onPointerDown,
      onPointerMove,
      onPointerUp,
      onPointerCancel: onPointerUp,
      style: { touchAction: "pan-y" as const, cursor: "grab" as const },
    },
  };
}
