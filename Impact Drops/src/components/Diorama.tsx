import type { CSSProperties } from "react";
import { Voxel } from "./Voxel";
import { PixelAvatar } from "./PixelAvatar";
import { GlbDiorama } from "./GlbDiorama";
import { useSwipeRotate } from "@/hooks/use-swipe-rotate";
import type { DioramaTheme } from "@/lib/diorama-themes";
import type { AvatarConfig, AvatarState } from "@/lib/mock";

type Props = {
  theme: DioramaTheme;
  config: AvatarConfig;
  state: AvatarState;
  size?: number;
};

const FLOOR = 190; // px square (top surface)
const PLINTH_H = 26; // thick raised base
const WALL_H = 96;
const WALL_T = 6;

export function Diorama({ theme, config, state, size = 300 }: Props) {
  if (theme.id === "shopping") {
    return (
      <GlbDiorama
        theme={theme}
        config={config}
        state={state}
        size={size}
        modelUrl="/models/clothing_store.glb"
      />
    );
  }
  const { rotation, bind } = useSwipeRotate(25);


  const stageStyle: CSSProperties = {
    width: size,
    height: size,
    perspective: 1100,
    perspectiveOrigin: "50% 38%",
    userSelect: "none",
    WebkitUserSelect: "none",
  };

  const worldStyle: CSSProperties = {
    position: "relative",
    width: size,
    height: size,
    transformStyle: "preserve-3d",
    transform: `rotateX(-22deg) rotateY(${rotation}deg)`,
    transition: "none",
  };

  // Floor top surface (tiled pattern overlay on top of plinth)
  const ox = size / 2;
  const oy = size / 2 + 40; // floor top y
  const floorLeft = ox - FLOOR / 2;
  const floorTop = oy;

  const floorStyle: CSSProperties = {
    position: "absolute",
    left: floorLeft,
    top: floorTop,
    width: FLOOR,
    height: FLOOR,
    transform: "rotateX(90deg)",
    transformOrigin: "top left",
    background: theme.floor,
    backgroundImage: `repeating-linear-gradient(0deg, transparent 0 22px, color-mix(in oklab, ${theme.trim} 28%, transparent) 22px 23px), repeating-linear-gradient(90deg, transparent 0 22px, color-mix(in oklab, ${theme.trim} 28%, transparent) 22px 23px)`,
    boxShadow: `inset 0 0 0 3px color-mix(in oklab, ${theme.trim} 55%, black)`,
  };

  // Avatar pinned to floor center
  const avatarSize = 118;
  const avatarStyle: CSSProperties = {
    position: "absolute",
    left: ox - avatarSize / 2,
    top: oy - avatarSize + 6,
    transformStyle: "preserve-3d",
    pointerEvents: "none",
    animation: theme.idleAnim,
  };

  return (
    <div
      {...bind}
      style={stageStyle}
      role="img"
      aria-label={`${theme.label} diorama with your avatar`}
    >
      <div style={worldStyle}>
        {/* Soft ground shadow */}
        <div
          style={{
            position: "absolute",
            left: floorLeft + 18,
            top: floorTop + PLINTH_H + 4,
            width: FLOOR - 36,
            height: 24,
            background: "color-mix(in oklab, black 32%, transparent)",
            borderRadius: "50%",
            filter: "blur(14px)",
            transform: "rotateX(90deg) translateZ(-1px)",
          }}
        />

        {/* Raised plinth base */}
        <Voxel
          w={FLOOR}
          h={PLINTH_H}
          d={FLOOR}
          color={`color-mix(in oklab, ${theme.trim} 35%, white)`}
          x={floorLeft}
          y={floorTop}
          z={-FLOOR / 2}
        />

        {/* Back wall (thin slab along back edge) */}
        <Voxel
          w={FLOOR}
          h={WALL_H}
          d={WALL_T}
          color={theme.wallA}
          x={floorLeft}
          y={floorTop - WALL_H}
          z={-FLOOR / 2 + WALL_T / 2}
        />
        {/* Left wall */}
        <Voxel
          w={WALL_T}
          h={WALL_H}
          d={FLOOR}
          color={theme.wallB}
          x={floorLeft + WALL_T / 2}
          y={floorTop - WALL_H}
          z={-FLOOR / 2 + WALL_T / 2}
        />

        {/* Theme props */}
        <Scene theme={theme} size={size} />

        {/* Avatar */}
        <div style={avatarStyle}>
          <PixelAvatar config={config} state={state} size={avatarSize} spin={false} tiltStill />
        </div>
      </div>
    </div>
  );
}


/* ---------- per-theme scene content ---------- */

function Scene({ theme, size }: { theme: DioramaTheme; size: number }) {
  const ox = size / 2; // origin x
  const oy = size / 2 + 40; // floor top
  const back = -FLOOR / 2 + 8; // near back wall
  const left = -FLOOR / 2 + 8; // near left wall
  switch (theme.id) {
    case "cafe":
      return (
        <>
          {/* Counter */}
          <Voxel w={70} h={28} d={26} color={theme.accent} x={ox - 60} y={oy - 28} z={back + 6} />
          {/* Espresso machine */}
          <Voxel w={26} h={24} d={18} color="oklch(0.95 0.02 90)" x={ox - 50} y={oy - 52} z={back + 10} />
          <Voxel w={6} h={8} d={6} color={theme.trim} x={ox - 38} y={oy - 32} z={back + 22} />
          {/* Menu board */}
          <Voxel w={36} h={22} d={2} color={theme.trim} x={ox + 18} y={oy - 110} z={back + 1} />
          {/* Table */}
          <Voxel w={20} h={3} d={20} color={theme.trim} x={ox + 20} y={oy - 24} z={back + 50} />
          <Voxel w={4} h={22} d={4} color={theme.trim} x={ox + 28} y={oy - 22} z={back + 58} />
          {/* Sign */}
          <Voxel w={28} h={14} d={3} color={theme.accent} x={left + 6} y={oy - 110} z={back + 30} />
        </>
      );
    case "shopping":
      return (
        <>
          {/* Clothing rack bar */}
          <Voxel w={70} h={3} d={3} color={theme.trim} x={ox - 35} y={oy - 80} z={back + 30} />
          <Voxel w={3} h={70} d={3} color={theme.trim} x={ox - 35} y={oy - 80} z={back + 30} />
          <Voxel w={3} h={70} d={3} color={theme.trim} x={ox + 32} y={oy - 80} z={back + 30} />
          {/* Hanging clothes */}
          {[0, 1, 2, 3, 4].map(i => (
            <Voxel
              key={i}
              w={10}
              h={28}
              d={4}
              color={["oklch(0.75 0.18 0)", "oklch(0.85 0.12 350)", "oklch(0.70 0.16 30)", "oklch(0.55 0.12 280)", "oklch(0.90 0.06 90)"][i]}
              x={ox - 28 + i * 12}
              y={oy - 76}
              z={back + 30}
            />
          ))}
          {/* Mirror */}
          <Voxel w={22} h={48} d={2} color="oklch(0.92 0.02 230)" x={left + 6} y={oy - 90} z={back + 60} />
          {/* Shopping bag */}
          <Voxel w={14} h={18} d={10} color={theme.accent} x={ox + 36} y={oy - 18} z={back + 70} />
        </>
      );
    case "grocery":
      return (
        <>
          {/* Shelves */}
          {[0, 1, 2].map(i => (
            <Voxel key={i} w={80} h={3} d={14} color={theme.trim} x={ox - 40} y={oy - 30 - i * 28} z={back + 6} />
          ))}
          {/* Cans on shelves */}
          {[0, 1, 2].map(row =>
            [0, 1, 2, 3, 4, 5].map(col => (
              <Voxel
                key={`${row}-${col}`}
                w={10}
                h={18}
                d={10}
                color={["oklch(0.70 0.18 30)", "oklch(0.75 0.16 130)", "oklch(0.78 0.15 60)"][col % 3]}
                x={ox - 38 + col * 12}
                y={oy - 30 - row * 28 - 18}
                z={back + 6}
              />
            ))
          )}
          {/* Basket */}
          <Voxel w={20} h={14} d={14} color={theme.accent} x={ox + 30} y={oy - 14} z={back + 60} />
        </>
      );
    case "fast_food":
      return (
        <>
          {/* Counter */}
          <Voxel w={90} h={26} d={26} color={theme.accent} x={ox - 45} y={oy - 26} z={back + 10} />
          {/* Menu board panels */}
          {[0, 1, 2].map(i => (
            <Voxel
              key={i}
              w={26}
              h={20}
              d={2}
              color={["oklch(0.92 0.10 60)", "oklch(0.90 0.08 40)", "oklch(0.88 0.06 30)"][i]}
              x={ox - 42 + i * 30}
              y={oy - 116}
              z={back + 1}
            />
          ))}
          {/* Tray with burger */}
          <Voxel w={18} h={3} d={14} color="oklch(0.85 0.04 60)" x={ox - 8} y={oy - 30} z={back + 18} />
          <Voxel w={14} h={6} d={12} color="oklch(0.55 0.12 50)" x={ox - 6} y={oy - 36} z={back + 19} />
          <Voxel w={14} h={4} d={12} color="oklch(0.80 0.16 60)" x={ox - 6} y={oy - 40} z={back + 19} />
          {/* Booth seat */}
          <Voxel w={26} h={10} d={18} color={theme.accent} x={ox + 36} y={oy - 10} z={back + 56} />
        </>
      );
    case "gym":
      return (
        <>
          {/* Treadmill */}
          <Voxel w={30} h={6} d={50} color={theme.trim} x={left + 6} y={oy - 6} z={back + 30} />
          <Voxel w={30} h={20} d={6} color="oklch(0.40 0.02 250)" x={left + 6} y={oy - 26} z={back + 30} />
          {/* Dumbbell rack */}
          <Voxel w={70} h={4} d={10} color={theme.trim} x={ox - 20} y={oy - 24} z={back + 6} />
          {[0, 1, 2, 3].map(i => (
            <div key={i} style={{ transformStyle: "preserve-3d" }}>
              <Voxel w={6} h={6} d={6} color={theme.accent} x={ox - 16 + i * 16} y={oy - 30} z={back + 8} />
              <Voxel w={10} h={2} d={2} color={theme.trim} x={ox - 18 + i * 16} y={oy - 28} z={back + 10} />
              <Voxel w={6} h={6} d={6} color={theme.accent} x={ox - 14 + i * 16} y={oy - 30} z={back + 8} />
            </div>
          ))}
          {/* Mat */}
          <Voxel w={36} h={2} d={20} color="oklch(0.65 0.18 30)" x={ox + 16} y={oy - 2} z={back + 60} />
        </>
      );
    case "electronics":
      return (
        <>
          {/* Wall screens */}
          {[0, 1, 2].map(i => (
            <Voxel
              key={i}
              w={26}
              h={20}
              d={2}
              color={["oklch(0.55 0.22 230)", "oklch(0.60 0.22 320)", "oklch(0.60 0.22 140)"][i]}
              x={ox - 42 + i * 30}
              y={oy - 116}
              z={back + 1}
            />
          ))}
          {/* Counter */}
          <Voxel w={90} h={24} d={24} color={theme.trim} x={ox - 45} y={oy - 24} z={back + 14} />
          {/* Consoles */}
          {[0, 1].map(i => (
            <Voxel key={i} w={18} h={6} d={14} color="oklch(0.30 0.04 280)" x={ox - 28 + i * 30} y={oy - 30} z={back + 20} />
          ))}
          {/* Neon strip */}
          <Voxel w={90} h={2} d={2} color={theme.accent} x={ox - 45} y={oy - 80} z={back + 1} />
        </>
      );
    case "beauty":
      return (
        <>
          {/* Vanity */}
          <Voxel w={80} h={26} d={24} color={theme.accent} x={ox - 40} y={oy - 26} z={back + 10} />
          {/* Mirror */}
          <Voxel w={48} h={56} d={2} color="oklch(0.96 0.01 0)" x={ox - 24} y={oy - 100} z={back + 1} />
          {/* Bulbs around mirror */}
          {[0, 1, 2, 3, 4].map(i => (
            <Voxel key={`tb${i}`} w={4} h={4} d={4} color="oklch(0.95 0.10 90)" x={ox - 22 + i * 10} y={oy - 106} z={back + 4} />
          ))}
          {/* Bottles */}
          {[0, 1, 2, 3].map(i => (
            <Voxel
              key={i}
              w={6}
              h={14}
              d={6}
              color={["oklch(0.85 0.12 350)", "oklch(0.85 0.10 30)", "oklch(0.80 0.10 280)", "oklch(0.90 0.08 90)"][i]}
              x={ox - 30 + i * 10}
              y={oy - 40}
              z={back + 16}
            />
          ))}
          {/* Stool */}
          <Voxel w={16} h={3} d={16} color={theme.trim} x={ox + 30} y={oy - 18} z={back + 60} />
          <Voxel w={3} h={18} d={3} color={theme.trim} x={ox + 36} y={oy - 18} z={back + 66} />
        </>
      );
    case "transport":
      return (
        <>
          {/* Platform edge stripe */}
          <Voxel w={FLOOR - 40} h={2} d={4} color={theme.accent} x={ox - (FLOOR - 40) / 2} y={oy - 2} z={back + FLOOR - 30} />
          {/* Bench */}
          <Voxel w={50} h={4} d={14} color={theme.trim} x={left + 10} y={oy - 14} z={back + 40} />
          <Voxel w={50} h={14} d={4} color={theme.trim} x={left + 10} y={oy - 28} z={back + 36} />
          {/* Pillars */}
          {[0, 1].map(i => (
            <Voxel key={i} w={8} h={120} d={8} color={theme.trim} x={ox - 50 + i * 100} y={oy - 120} z={back + 14} />
          ))}
          {/* Sign */}
          <Voxel w={44} h={14} d={3} color={theme.accent} x={ox - 22} y={oy - 110} z={back + 1} />
          {/* Train arrow on wall */}
          <Voxel w={60} h={4} d={2} color="oklch(0.30 0.04 250)" x={ox - 30} y={oy - 80} z={back + 1} />
        </>
      );
    case "home":
      return (
        <>
          {/* Sofa */}
          <Voxel w={80} h={18} d={28} color={theme.accent} x={ox - 40} y={oy - 18} z={back + 36} />
          <Voxel w={80} h={26} d={10} color={theme.accent} x={ox - 40} y={oy - 44} z={back + 30} />
          {/* Lamp */}
          <Voxel w={3} h={60} d={3} color={theme.trim} x={ox + 50} y={oy - 60} z={back + 30} />
          <Voxel w={14} h={10} d={14} color="oklch(0.92 0.04 80)" x={ox + 45} y={oy - 70} z={back + 28} />
          {/* Picture */}
          <Voxel w={20} h={14} d={2} color={theme.trim} x={ox - 30} y={oy - 100} z={back + 1} />
        </>
      );
    case "idle":
    default:
      return null;
  }
}
