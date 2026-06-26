import type { CSSProperties, ReactNode } from "react";

type Props = {
  w: number;
  h?: number;
  d?: number;
  color: string;
  x?: number;
  y?: number;
  z?: number;
  style?: CSSProperties;
  children?: ReactNode;
};

/**
 * A 3D box (non-uniform OK) built from 6 face divs with directional shading.
 */
export function Voxel({ w, h = w, d = w, color, x = 0, y = 0, z = 0, style, children }: Props) {
  const face = (extra: CSSProperties): CSSProperties => ({
    position: "absolute",
    left: 0,
    top: 0,
    backfaceVisibility: "hidden",
    ...extra,
  });

  return (
    <div
      style={{
        position: "absolute",
        width: w,
        height: h,
        transformStyle: "preserve-3d",
        transform: `translate3d(${x}px, ${y}px, ${z}px)`,
        ...style,
      }}
    >
      {/* front */}
      <div style={face({ width: w, height: h, background: color, transform: `translateZ(${d / 2}px)` })}>
        {children}
      </div>
      {/* back */}
      <div
        style={face({
          width: w,
          height: h,
          background: `color-mix(in oklab, ${color} 70%, black)`,
          transform: `translateZ(${-d / 2}px) rotateY(180deg)`,
        })}
      />
      {/* right */}
      <div
        style={face({
          width: d,
          height: h,
          background: `color-mix(in oklab, ${color} 82%, black)`,
          left: w - d / 2 - d / 2 + w / 2 - d / 2,
          transform: `translate3d(${w - d / 2}px, 0, 0) rotateY(90deg) translateZ(${d / 2}px)`,
        })}
      />
      {/* left */}
      <div
        style={face({
          width: d,
          height: h,
          background: `color-mix(in oklab, ${color} 82%, black)`,
          transform: `translate3d(${-d / 2}px, 0, 0) rotateY(-90deg) translateZ(${d / 2}px)`,
        })}
      />
      {/* top */}
      <div
        style={face({
          width: w,
          height: d,
          background: `color-mix(in oklab, ${color} 80%, white)`,
          transform: `translate3d(0, ${-d / 2}px, 0) rotateX(90deg) translateZ(${d / 2}px)`,
        })}
      />
      {/* bottom */}
      <div
        style={face({
          width: w,
          height: d,
          background: `color-mix(in oklab, ${color} 60%, black)`,
          transform: `translate3d(0, ${h - d / 2}px, 0) rotateX(-90deg) translateZ(${d / 2}px)`,
        })}
      />
    </div>
  );
}
