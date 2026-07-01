import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { BadgeHex } from "@/components/BadgeHex";
import type { Badge } from "@/lib/badges";
import { rarityStyles } from "@/lib/badges";
import { Calendar, Sparkles } from "lucide-react";

type Props = {
  badge: Badge | null;
  open: boolean;
  onOpenChange: (o: boolean) => void;
};

export function BadgeDetailDialog({ badge, open, onOpenChange }: Props) {
  if (!badge) return null;
  const rarity = rarityStyles[badge.rarity];
  const pct = Math.min(100, Math.round((badge.progress / badge.goal) * 100));

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="rounded-3xl max-w-[340px] p-6">
        <DialogHeader>
          <DialogTitle className="sr-only">{badge.label}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col items-center gap-4">
          <BadgeHex badge={badge} size={120} showLabel={false} />
          <div className="text-center w-full">
            <div className="flex items-center justify-center gap-2 mb-1">
              <h3 className="text-lg font-extrabold">{badge.label}</h3>
              <span className={`px-2 py-0.5 rounded-md text-[9px] font-bold tracking-wider ${rarity.chip}`}>
                {rarity.label}
              </span>
            </div>
            <p className="text-sm text-foreground/80">{badge.description}</p>
          </div>

          <div className="w-full">
            <div className="flex items-center justify-between text-xs font-bold mb-1.5">
              <span className="text-primary">{badge.progress} / {badge.goal}</span>
              <span className="text-muted-foreground">{pct}%</span>
            </div>
            <div className="h-2 rounded-full bg-muted overflow-hidden">
              <div className="h-full bg-primary transition-all" style={{ width: `${pct}%` }} />
            </div>
          </div>

          {badge.earned ? (
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Calendar className="w-3.5 h-3.5" />
              Earned on {badge.earnedOn}
            </div>
          ) : (
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Sparkles className="w-3.5 h-3.5" />
              {badge.hint ?? "Keep going!"}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
