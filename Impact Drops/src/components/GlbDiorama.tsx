import { Suspense, useEffect, useRef, useState, type CSSProperties } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { useGLTF, Bounds, Environment, ContactShadows } from "@react-three/drei";
import * as THREE from "three";
import { PixelAvatar } from "./PixelAvatar";
import { useSwipeRotate } from "@/hooks/use-swipe-rotate";
import type { DioramaTheme } from "@/lib/diorama-themes";
import type { AvatarConfig, AvatarState } from "@/lib/mock";

type Props = {
  theme: DioramaTheme;
  config: AvatarConfig;
  state: AvatarState;
  size?: number;
  modelUrl: string;
};

function Model({ url, rotationY }: { url: string; rotationY: number }) {
  const { scene } = useGLTF(url);
  const ref = useRef<THREE.Group>(null);
  useFrame(() => {
    if (ref.current) {
      // smooth follow
      ref.current.rotation.y += (THREE.MathUtils.degToRad(rotationY) - ref.current.rotation.y) * 0.18;
    }
  });
  return (
    <group ref={ref}>
      <primitive object={scene} />
    </group>
  );
}

export function GlbDiorama({ theme, config, state, size = 300, modelUrl }: Props) {
  const { rotation, bind } = useSwipeRotate(25);
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const stageStyle: CSSProperties = {
    width: size,
    height: size,
    position: "relative",
    userSelect: "none",
    WebkitUserSelect: "none",
    borderRadius: 24,
    overflow: "hidden",
    background: `radial-gradient(circle at 50% 40%, color-mix(in oklab, ${theme.wallA} 60%, white), color-mix(in oklab, ${theme.floor} 80%, white))`,
  };

  const avatarSize = 96;
  const avatarStyle: CSSProperties = {
    position: "absolute",
    left: size / 2 - avatarSize / 2,
    top: size / 2 - avatarSize / 2 + 18,
    pointerEvents: "none",
    animation: theme.idleAnim,
    zIndex: 2,
  };

  return (
    <div {...bind} style={stageStyle} role="img" aria-label={`${theme.label} diorama`}>
      {mounted && (
        <Canvas
          dpr={[1, 2]}
          camera={{ position: [3.2, 2.4, 3.6], fov: 35 }}
          style={{ position: "absolute", inset: 0 }}
        >
          <ambientLight intensity={0.85} />
          <directionalLight position={[4, 6, 3]} intensity={1.1} castShadow />
          <directionalLight position={[-3, 2, -2]} intensity={0.35} />
          <Suspense fallback={null}>
            <Bounds fit clip observe margin={1.15}>
              <Model url={modelUrl} rotationY={rotation} />
            </Bounds>
            <ContactShadows position={[0, -0.01, 0]} opacity={0.4} scale={6} blur={2.4} far={3} />
            <Environment preset="city" />
          </Suspense>
        </Canvas>
      )}
      <div style={avatarStyle}>
        <PixelAvatar config={config} state={state} size={avatarSize} spin={false} tiltStill />
      </div>
    </div>
  );
}

useGLTF.preload("/models/clothing_store.glb");
