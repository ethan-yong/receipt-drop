import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { ChevronLeft } from "lucide-react";
import { useBadges } from "@/lib/badges-context";
import { BadgeHex } from "@/components/BadgeHex";
import { BadgeDetailDialog } from "@/components/BadgeDetailDialog";
import type { Badge } from "@/lib/badges";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/badges")({
  head: () => ({
    meta: [
      { title: "All Badges — Receipt Drop" },
      { name: "description", content: "Browse all badges you've earned and can still unlock." },
    ],
  }),
  component: BadgesPage,
});

type Filter = "all" | "earned" | "locked";

function BadgesPage() {
  const { badges } = useBadges();
  const [filter, setFilter] = useState<Filter>("all");
  const [selected, setSelected] = useState<Badge | null>(null);

  const filtered = badges.filter(b =>
    filter === "all" ? true : filter === "earned" ? b.earned : !b.earned,
  );

  const tabs: { id: Filter; label: string }[] = [
    { id: "all", label: "All" },
    { id: "earned", label: "Earned" },
    { id: "locked", label: "Locked" },
  ];

  return (
    <div className="flex-1 flex flex-col px-5 pt-6 pb-8">
      <header className="flex items-center justify-between mb-5">
        <div className="flex items-center gap-2">
          <Link to="/" className="w-9 h-9 rounded-full bg-card border border-border flex items-center justify-center">
            <ChevronLeft className="w-4 h-4" />
          </Link>
          <h1 className="text-xl font-extrabold">All Badges</h1>
        </div>
        <div className="flex bg-card border border-border rounded-full p-1">
          {tabs.map(t => (
            <button
              key={t.id}
              onClick={() => setFilter(t.id)}
              className={cn(
                "px-3 py-1 text-xs font-bold rounded-full transition-colors",
                filter === t.id ? "bg-primary text-primary-foreground" : "text-muted-foreground",
              )}
            >
              {t.label}
            </button>
          ))}
        </div>
      </header>

      <div className="grid grid-cols-3 gap-4">
        {filtered.map(b => (
          <BadgeHex key={b.id} badge={b} onClick={() => setSelected(b)} />
        ))}
      </div>

      {filtered.length === 0 && (
        <p className="text-center text-sm text-muted-foreground mt-10">No badges here yet.</p>
      )}

      <BadgeDetailDialog badge={selected} open={!!selected} onOpenChange={o => !o && setSelected(null)} />
    </div>
  );
}
