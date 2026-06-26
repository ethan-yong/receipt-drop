import type { Badge } from "@/lib/badges";
import { rarityStyles } from "@/lib/badges";
import { Lock } from "lucide-react";
import { cn } from "@/lib/utils";

type Props = {
  badge: Badge;
  size?: number;
  showLabel?: boolean;
  dragHandle?: boolean;
  onClick?: () => void;
};

export function BadgeHex({ badge, size = 88, showLabel = true, dragHandle, onClick }: Props) {
  const rarity = rarityStyles[badge.rarity];
  const locked = !badge.earned;

  return (
    <button
      type="button"
      onClick={onClick}
      className="group flex flex-col items-center gap-1.5 select-none focus:outline-none"
    >
      <div className="relative" style={{ width: size, height: size }}>
        <div
          className={cn(
            "absolute inset-0 transition-transform group-active:scale-95",
            locked && "grayscale opacity-60",
          )}
          style={{
            clipPath:
              "polygon(50% 0%, 95% 25%, 95% 75%, 50% 100%, 5% 75%, 5% 25%)",
            background: locked
              ? "linear-gradient(135deg, oklch(0.85 0.01 80), oklch(0.78 0.01 80))"
              : "linear-gradient(135deg, var(--primary), color-mix(in oklab, var(--primary) 60%, white))",
            padding: 4,
          }}
        >
          <div
            className="w-full h-full flex items-center justify-center bg-card"
            style={{
              clipPath:
                "polygon(50% 0%, 95% 25%, 95% 75%, 50% 100%, 5% 75%, 5% 25%)",
              fontSize: size * 0.45,
            }}
          >
            <span aria-hidden>{badge.emoji}</span>
          </div>
        </div>
        {locked && (
          <div className="absolute bottom-0 right-0 w-6 h-6 rounded-full bg-card border border-border flex items-center justify-center shadow">
            <Lock className="w-3 h-3 text-muted-foreground" />
          </div>
        )}
        {dragHandle && !locked && (
          <div className="absolute top-0 right-0 w-5 h-5 rounded-md bg-card/90 border border-border flex items-center justify-center text-[10px] text-muted-foreground shadow-sm">
            ⋮⋮
          </div>
        )}
        <div className={cn("absolute -bottom-1 left-1/2 -translate-x-1/2 px-1.5 py-0.5 rounded-full text-[8px] font-bold tracking-wider", rarity.chip)}>
          {rarity.label}
        </div>
      </div>
      {showLabel && (
        <span className={cn("text-[11px] font-bold mt-1.5 text-center", locked && "text-muted-foreground")}>
          {badge.label}
        </span>
      )}
    </button>
  );
}
