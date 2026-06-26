import { createContext, useContext, useMemo, useState, type ReactNode } from "react";
import { allBadges, type Badge } from "./badges";

type BadgesCtx = {
  badges: Badge[];
  topOrder: string[];
  setTopOrder: (ids: string[]) => void;
  topBadges: Badge[];
};

const Ctx = createContext<BadgesCtx | null>(null);

export function BadgesProvider({ children }: { children: ReactNode }) {
  const earnedIds = allBadges.filter(b => b.earned).map(b => b.id);
  const [topOrder, setTopOrder] = useState<string[]>(earnedIds.slice(0, 6));

  const topBadges = useMemo(() => {
    return topOrder
      .map(id => allBadges.find(b => b.id === id))
      .filter((b): b is Badge => Boolean(b));
  }, [topOrder]);

  return (
    <Ctx.Provider value={{ badges: allBadges, topOrder, setTopOrder, topBadges }}>
      {children}
    </Ctx.Provider>
  );
}

export function useBadges() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useBadges must be used within BadgesProvider");
  return v;
}
