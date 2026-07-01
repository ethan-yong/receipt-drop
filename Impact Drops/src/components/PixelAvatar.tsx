import type { CSSProperties, ReactNode } from "react";
import { Voxel } from "./Voxel";
import type {
  AvatarState,
  AvatarConfig,
  AvatarColor,
  AvatarEyes,
  AvatarHat,
} from "@/lib/mock";

/** Pico Park / Rolife style buddy — blocky 3D character. */

const BODY_COLOR: Record<AvatarColor, string> = {
  yellow: "#FFCC29",
  coral: "#FF6655",
  lime: "#9CD650",
  blue: "#6FB8E8",
  purple: "#C7A8E8",
  pink: "#F5B5C5",
  brown: "#B89B7A",
  gray: "#BFBFBF",
  white: "#F2EFE9",
};

const INK = "#1F1F1F";
const FOOT = "#8B6B3A";

const stateAnim: Record<AvatarState, string> = {
  calm: "pixel-bob 4s ease-in-out infinite",
  active: "pixel-bob 1.6s ease-in-out infinite",
  spiky: "pixel-jitter 0.4s steps(4) infinite",
  balanced: "pixel-bob 3s ease-in-out infinite",
};

export function PixelAvatar({
  config,
  state = "calm",
  size = 220,
  spin = true,
  tiltStill = false,
  idleAnim,
}: {
  config: AvatarConfig;
  state?: AvatarState;
  size?: number;
  spin?: boolean;
  /** Suppress state-driven tilt/anim (for parent-controlled stages). */
  tiltStill?: boolean;
  /** Optional CSS animation shorthand overriding state animation. */
  idleAnim?: string;
}) {
  const u = size / 12;
  const skin = BODY_COLOR[config.color];

  // Geometry (pico-park proportions)
  const headW = 6 * u;
  const headH = 5 * u;
  const headD = 6 * u;
  const bodyW = 5 * u;
  const bodyH = 5 * u;
  const bodyD = 5 * u;
  const footW = 1.5 * u;
  const footH = 1.2 * u;
  const footD = 2 * u;

  const cx = size / 2;
  // vertical layout: top margin, head, body, feet
  const headY = size * 0.08;
  const bodyY = headY + headH;
  const footY = bodyY + bodyH;

  const stageStyle: CSSProperties = {
    width: size,
    height: size,
    perspective: 900,
    perspectiveOrigin: "50% 40%",
  };

  const rigStyle: CSSProperties = {
    position: "relative",
    width: size,
    height: size,
    transformStyle: "preserve-3d",
    transform: tiltStill ? "none" : "rotateX(-15deg)",
    animation: idleAnim ?? (tiltStill ? undefined : stateAnim[state]),
  };

  const spinnerStyle: CSSProperties = {
    position: "absolute",
    inset: 0,
    transformStyle: "preserve-3d",
    animation: spin ? "pixel-spin 14s linear infinite" : undefined,
  };

  return (
    <div style={stageStyle}>
      <div style={rigStyle}>
        <div style={spinnerStyle}>
          {/* Body */}
          <Voxel w={bodyW} h={bodyH} d={bodyD} color={skin} x={cx - bodyW / 2} y={bodyY} />

          {/* Feet */}
          <Voxel
            w={footW}
            h={footH}
            d={footD}
            color={FOOT}
            x={cx - bodyW / 2 + u * 0.5}
            y={footY}
          />
          <Voxel
            w={footW}
            h={footH}
            d={footD}
            color={FOOT}
            x={cx + bodyW / 2 - footW - u * 0.5}
            y={footY}
          />

          {/* Head wrapper (anchor for face + hat) */}
          <div
            style={{
              position: "absolute",
              left: cx - headW / 2,
              top: headY,
              width: headW,
              height: headH,
              transformStyle: "preserve-3d",
            }}
          >
            <Voxel w={headW} h={headH} d={headD} color={skin} />
            <Face eyes={config.eyes} headW={headW} headH={headH} headD={headD} unit={u} />
            <Hat hat={config.hat} headW={headW} headD={headD} unit={u} />
          </div>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------ FACE ------------------------------ */

function frontPlane(z: number, children: ReactNode, extra: CSSProperties = {}): ReactNode {
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        transform: `translateZ(${z}px)`,
        transformStyle: "preserve-3d",
        pointerEvents: "none",
        ...extra,
      }}
    >
      {children}
    </div>
  );
}

function Face({
  eyes,
  headW,
  headH,
  headD,
  unit,
}: {
  eyes: AvatarEyes;
  headW: number;
  headH: number;
  headD: number;
  unit: number;
}) {
  const z = headD / 2 + 0.5;
  const eyeY = headH * 0.42;
  const eyeSize = unit * 1.1;
  const gap = headW * 0.32;
  const lx = headW / 2 - gap - eyeSize / 2;
  const rx = headW / 2 + gap - eyeSize / 2;

  return frontPlane(z, <EyesRender eyes={eyes} lx={lx} rx={rx} y={eyeY} size={eyeSize} unit={unit} />);
}

function box(x: number, y: number, w: number, h: number, bg = INK, radius = 0): CSSProperties {
  return {
    position: "absolute",
    left: x,
    top: y,
    width: w,
    height: h,
    background: bg,
    borderRadius: radius,
  };
}

function EyesRender({
  eyes,
  lx,
  rx,
  y,
  size,
  unit,
}: {
  eyes: AvatarEyes;
  lx: number;
  rx: number;
  y: number;
  size: number;
  unit: number;
}) {
  const s = size;

  switch (eyes) {
    case "default":
      return (
        <>
          <div style={box(lx, y, s, s)} />
          <div style={box(rx, y, s, s)} />
        </>
      );
    case "dot":
      return (
        <>
          <div style={box(lx + s * 0.25, y + s * 0.25, s * 0.5, s * 0.5, INK, 9999)} />
          <div style={box(rx + s * 0.25, y + s * 0.25, s * 0.5, s * 0.5, INK, 9999)} />
        </>
      );
    case "happy":
      // ^ ^ — two upward chevrons made from two angled rects each
      return (
        <>
          <Chevron x={lx} y={y} size={s} dir="up" />
          <Chevron x={rx} y={y} size={s} dir="up" />
        </>
      );
    case "wink":
      return (
        <>
          <div style={box(lx, y, s, s)} />
          <div style={box(rx, y + s * 0.45, s, s * 0.18)} />
        </>
      );
    case "squint":
      // > <
      return (
        <>
          <Chevron x={lx} y={y} size={s} dir="right" />
          <Chevron x={rx} y={y} size={s} dir="left" />
        </>
      );
    case "sleepy":
      return (
        <>
          <div style={box(lx, y + s * 0.45, s, s * 0.18)} />
          <div style={box(rx, y + s * 0.45, s, s * 0.18)} />
        </>
      );
    case "blink":
      return (
        <>
          <div style={box(lx, y + s * 0.45, s, s * 0.18)} />
          <div style={box(rx, y, s, s)} />
        </>
      );
    case "star":
      return (
        <>
          <Plus x={lx} y={y} size={s} />
          <Plus x={rx} y={y} size={s} />
        </>
      );
    case "heart":
      return (
        <>
          <Heart x={lx} y={y} size={s} />
          <Heart x={rx} y={y} size={s} />
        </>
      );
    case "glasses":
      return (
        <>
          {/* frames */}
          <div
            style={{
              ...box(lx - unit * 0.2, y - unit * 0.2, s + unit * 0.4, s + unit * 0.4, "transparent"),
              border: `${Math.max(2, unit * 0.2)}px solid ${INK}`,
            }}
          />
          <div
            style={{
              ...box(rx - unit * 0.2, y - unit * 0.2, s + unit * 0.4, s + unit * 0.4, "transparent"),
              border: `${Math.max(2, unit * 0.2)}px solid ${INK}`,
            }}
          />
          {/* bridge */}
          <div style={box(lx + s + unit * 0.2, y + s * 0.5 - unit * 0.1, rx - lx - s - unit * 0.4, unit * 0.2)} />
          {/* pupils */}
          <div style={box(lx + s * 0.3, y + s * 0.3, s * 0.4, s * 0.4)} />
          <div style={box(rx + s * 0.3, y + s * 0.3, s * 0.4, s * 0.4)} />
        </>
      );
  }
}

function Chevron({
  x,
  y,
  size,
  dir,
}: {
  x: number;
  y: number;
  size: number;
  dir: "up" | "left" | "right";
}) {
  const t = Math.max(2, size * 0.2);
  const half = size / 2;
  // two diagonal rectangles forming a chevron via rotation
  const angle = 35;
  if (dir === "up") {
    return (
      <>
        <div
          style={{
            position: "absolute",
            left: x,
            top: y + half - t / 2,
            width: half + t,
            height: t,
            background: INK,
            transformOrigin: "0% 50%",
            transform: `rotate(-${angle}deg)`,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: x + size,
            top: y + half - t / 2,
            width: half + t,
            height: t,
            background: INK,
            transformOrigin: "100% 50%",
            transform: `rotate(${angle}deg)`,
          }}
        />
      </>
    );
  }
  // > or <
  const flip = dir === "left" ? -1 : 1;
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: x + (flip > 0 ? 0 : size),
          top: y,
          width: t,
          height: half + t,
          background: INK,
          transformOrigin: `${flip > 0 ? "0%" : "100%"} 0%`,
          transform: `rotate(${flip * -angle}deg)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: x + (flip > 0 ? 0 : size),
          top: y + half,
          width: t,
          height: half + t,
          background: INK,
          transformOrigin: `${flip > 0 ? "0%" : "100%"} 0%`,
          transform: `rotate(${flip * angle}deg)`,
        }}
      />
    </>
  );
}

function Plus({ x, y, size }: { x: number; y: number; size: number }) {
  const t = size * 0.28;
  return (
    <>
      <div style={box(x + size / 2 - t / 2, y, t, size)} />
      <div style={box(x, y + size / 2 - t / 2, size, t)} />
    </>
  );
}

function Heart({ x, y, size }: { x: number; y: number; size: number }) {
  const c = "#FF5577";
  // 3x3 pixel heart-ish using small squares
  const p = size / 3;
  const pixels = [
    [0, 1], [2, 1],
    [0, 0], [1, 0], [2, 0],
    [1, 2],
  ];
  return (
    <>
      {pixels.map(([cx, cy], i) => (
        <div key={i} style={box(x + cx * p, y + cy * p, p + 0.5, p + 0.5, c)} />
      ))}
    </>
  );
}

/* ------------------------------ HATS ------------------------------ */

function Hat({
  hat,
  headW,
  headD,
  unit,
}: {
  hat: AvatarHat;
  headW: number;
  headD: number;
  unit: number;
}) {
  if (hat === "none") return null;
  const u = unit;

  if (hat === "cap") {
    return (
      <>
        {/* crown */}
        <Voxel w={headW * 0.95} h={u * 1.3} d={headD * 0.95} color="#FF6655" x={headW * 0.025} y={-u * 1.3} />
        {/* visor */}
        <Voxel w={headW * 0.55} h={u * 0.4} d={u * 1.6} color="#FF6655" x={headW * 0.22} y={-u * 0.2} style={{ transform: `translate3d(${headW * 0.22}px, ${-u * 0.2}px, ${headD / 2}px)` }} />
      </>
    );
  }
  if (hat === "beanie") {
    return (
      <>
        <Voxel w={headW * 0.95} h={u * 1.6} d={headD * 0.95} color="#8FCB48" x={headW * 0.025} y={-u * 1.4} />
        <Voxel w={headW * 0.55} h={u * 0.4} d={headD * 0.95} color="#7BB73A" x={headW * 0.22} y={-u * 0.2} />
      </>
    );
  }
  if (hat === "crown") {
    return (
      <>
        <Voxel w={u * 1.1} h={u * 1.6} d={u * 1.1} color="#F2C24A" x={headW * 0.12} y={-u * 1.6} />
        <Voxel w={u * 1.1} h={u * 2.2} d={u * 1.1} color="#F2C24A" x={headW / 2 - u * 0.55} y={-u * 2.2} />
        <Voxel w={u * 1.1} h={u * 1.6} d={u * 1.1} color="#F2C24A" x={headW - headW * 0.12 - u * 1.1} y={-u * 1.6} />
        <Voxel w={headW * 0.85} h={u * 0.6} d={headD * 0.85} color="#D9A52E" x={headW * 0.075} y={-u * 0.4} />
      </>
    );
  }
  if (hat === "party") {
    return (
      <>
        <Voxel w={u * 3} h={u * 0.8} d={u * 3} color="#F2A6D8" x={headW / 2 - u * 1.5} y={-u * 0.6} />
        <Voxel w={u * 2.2} h={u * 0.8} d={u * 2.2} color="#C68CF2" x={headW / 2 - u * 1.1} y={-u * 1.4} />
        <Voxel w={u * 1.4} h={u * 0.8} d={u * 1.4} color="#F2A6D8" x={headW / 2 - u * 0.7} y={-u * 2.2} />
        <Voxel w={u * 0.7} h={u * 0.7} d={u * 0.7} color="#FFDA47" x={headW / 2 - u * 0.35} y={-u * 2.9} />
      </>
    );
  }
  if (hat === "headband") {
    return (
      <Voxel w={headW * 1.02} h={u * 0.5} d={headD * 1.02} color="#6FB8E8" x={-headW * 0.01} y={u * 0.3} />
    );
  }
  if (hat === "catEars") {
    return (
      <>
        {/* simple triangular-ish ears via rotated voxels */}
        <div
          style={{
            position: "absolute",
            left: headW * 0.1,
            top: -u * 1.2,
            transform: "rotate(-12deg)",
            transformStyle: "preserve-3d",
          }}
        >
          <Voxel w={u * 1.3} h={u * 1.3} d={u * 1.2} color="#C68CF2" />
        </div>
        <div
          style={{
            position: "absolute",
            left: headW - u * 1.4 - headW * 0.1,
            top: -u * 1.2,
            transform: "rotate(12deg)",
            transformStyle: "preserve-3d",
          }}
        >
          <Voxel w={u * 1.3} h={u * 1.3} d={u * 1.2} color="#C68CF2" />
        </div>
      </>
    );
  }
  if (hat === "plant") {
    return (
      <>
        {/* pot rim */}
        <Voxel w={u * 1.8} h={u * 0.5} d={u * 1.8} color="#B89B7A" x={headW / 2 - u * 0.9} y={-u * 0.5} />
        {/* sprout stem */}
        <Voxel w={u * 0.4} h={u * 1.2} d={u * 0.4} color="#6FA850" x={headW / 2 - u * 0.2} y={-u * 1.6} />
        {/* leaves */}
        <Voxel w={u * 0.9} h={u * 0.5} d={u * 0.5} color="#8FCB48" x={headW / 2 - u * 1.1} y={-u * 1.4} />
        <Voxel w={u * 0.9} h={u * 0.5} d={u * 0.5} color="#8FCB48" x={headW / 2 + u * 0.2} y={-u * 1.4} />
      </>
    );
  }
  if (hat === "propeller") {
    return (
      <>
        {/* base cap */}
        <Voxel w={headW * 0.7} h={u * 0.8} d={headD * 0.7} color="#FF6655" x={headW * 0.15} y={-u * 0.8} />
        {/* stick */}
        <div
          style={{
            position: "absolute",
            left: headW / 2 - u * 0.1,
            top: -u * 1.8,
            width: u * 0.2,
            height: u * 1.2,
            background: INK,
          }}
        />
        {/* spinning blade */}
        <div
          style={{
            position: "absolute",
            left: headW / 2,
            top: -u * 1.9,
            width: 0,
            height: 0,
            transformStyle: "preserve-3d",
            animation: "propeller-spin 0.6s linear infinite",
          }}
        >
          <div
            style={{
              position: "absolute",
              left: -u * 1.6,
              top: -u * 0.2,
              width: u * 3.2,
              height: u * 0.4,
              background: "#FF6655",
              borderRadius: u * 0.2,
            }}
          />
        </div>
      </>
    );
  }
  // tophat
  return (
    <>
      <Voxel w={headW * 1.1} h={u * 0.4} d={headD * 1.1} color={INK} x={-headW * 0.05} y={-u * 0.4} />
      <Voxel w={headW * 0.7} h={u * 2.4} d={headD * 0.7} color={INK} x={headW * 0.15} y={-u * 2.8} />
    </>
  );
}
