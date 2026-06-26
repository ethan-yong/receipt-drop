import { createContext, useContext, useState, type ReactNode } from "react";
import {
  seedDrops,
  deriveAvatarState,
  defaultAvatarConfig,
  type Drop,
  type AvatarState,
  type AvatarConfig,
} from "./mock";

type DropsCtx = {
  drops: Drop[];
  addDrop: (d: Omit<Drop, "id" | "time">) => void;
  avatarState: AvatarState;
  avatarConfig: AvatarConfig;
  setAvatarConfig: (c: AvatarConfig) => void;
};

const Ctx = createContext<DropsCtx | null>(null);

export function DropsProvider({ children }: { children: ReactNode }) {
  const [drops, setDrops] = useState<Drop[]>(seedDrops);
  const [avatarConfig, setAvatarConfig] = useState<AvatarConfig>(defaultAvatarConfig);

  function addDrop(d: Omit<Drop, "id" | "time">) {
    const now = new Date();
    const time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
    setDrops(prev => [...prev, { ...d, id: `d${prev.length + 1}-${Date.now()}`, time }]);
  }

  return (
    <Ctx.Provider
      value={{
        drops,
        addDrop,
        avatarState: deriveAvatarState(drops),
        avatarConfig,
        setAvatarConfig,
      }}
    >
      {children}
    </Ctx.Provider>
  );
}

export function useDrops() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useDrops must be used within DropsProvider");
  return v;
}
