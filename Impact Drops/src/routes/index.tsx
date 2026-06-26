import { createFileRoute, Link } from "@tanstack/react-router";
import { Diorama } from "@/components/Diorama";
import { useDrops } from "@/lib/drops-context";
import { getThemeForCategory } from "@/lib/diorama-themes";
import { TopBadgesGrid } from "@/components/TopBadgesGrid";
import { Sparkles, Wand2, ChevronRight } from "lucide-react";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Receipt Drop — Home" },
      { name: "description", content: "Your awareness state today." },
    ],
  }),
  component: Home,
});

function Home() {
  const { avatarState, avatarConfig, drops } = useDrops();
  const lastDrop = drops[drops.length - 1];
  const theme = getThemeForCategory(lastDrop?.category);
  const isIdle = theme.id === "idle";

  return (
    <div className="flex-1 flex flex-col px-5 pt-8">
      <header className="flex items-center justify-between mb-2">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Today</p>
          <h1 className="text-2xl font-extrabold">Receipt Drop</h1>
        </div>
        <div className="rounded-full bg-card border border-border px-3 py-1.5 text-xs font-semibold flex items-center gap-1.5">
          <Sparkles className="w-3.5 h-3.5" />
          {drops.length} drops
        </div>
      </header>

      <div className="flex-1 flex flex-col items-center justify-center -mt-2">
        <Diorama theme={theme} config={avatarConfig} state={avatarState} size={300} />
        <div className="mt-3 text-center max-w-[280px]">
          <p className="text-[11px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
            {isIdle ? "No scene yet" : theme.label}
          </p>
          <p className="text-sm text-foreground/80 mt-1">{theme.caption}</p>
          <p className="text-[11px] text-muted-foreground mt-2">Swipe to look around</p>
        </div>
        <Link
          to="/avatar"
          className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-card border border-border px-4 py-2 text-xs font-bold"
        >
          <Wand2 className="w-3.5 h-3.5" />
          Customize avatar
        </Link>
      </div>

      <Link
        to="/drop"
        className="block w-full bg-primary text-primary-foreground rounded-3xl py-5 text-center text-lg font-extrabold shadow-lg active:scale-[0.98] transition-transform"
      >
        Drop Receipt
      </Link>

      <div className="mt-5 mb-2">
        <div className="flex items-center justify-between mb-2">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Badges</p>
            <p className="text-[11px] text-muted-foreground">Top 6 — drag to reorder</p>
          </div>
          <Link to="/badges" className="flex items-center gap-0.5 text-xs font-bold text-primary">
            View All <ChevronRight className="w-3.5 h-3.5" />
          </Link>
        </div>
        <TopBadgesGrid />
      </div>
    </div>
  );
}
