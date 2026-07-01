import { createFileRoute, Link } from "@tanstack/react-router";
import { useDrops } from "@/lib/drops-context";
import { awarenessSummary } from "@/lib/awareness";
import { BlobAvatar } from "@/components/BlobAvatar";

export const Route = createFileRoute("/summary")({
  head: () => ({ meta: [{ title: "Today's Awareness" }] }),
  component: Summary,
});

function Summary() {
  const { drops, avatarState } = useDrops();
  const { headline, sub } = awarenessSummary(drops);

  const intensity = drops.filter(d => d.impact === "high").length >= 2 ? "more intense" :
    drops.length >= 4 ? "busier" : drops.length <= 2 ? "calmer" : "balanced";

  return (
    <div className="flex-1 flex flex-col px-6 pt-12 pb-8">
      <p className="text-[11px] font-semibold uppercase tracking-[0.3em] text-muted-foreground text-center">Today's awareness</p>

      <div className="flex justify-center my-6">
        <BlobAvatar state={avatarState} size={140} />
      </div>

      <div className="bg-card rounded-3xl border border-border p-6 shadow-sm">
        <h1 className="text-2xl font-extrabold leading-tight">{headline}</h1>
        <p className="mt-3 text-base text-muted-foreground leading-relaxed">{sub}</p>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3">
        <div className="bg-card rounded-2xl border border-border p-4">
          <p className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Vs. last week</p>
          <p className="text-lg font-extrabold mt-1 capitalize">{intensity}</p>
        </div>
        <div className="bg-card rounded-2xl border border-border p-4">
          <p className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Rhythm</p>
          <p className="text-lg font-extrabold mt-1 capitalize">{avatarState}</p>
        </div>
      </div>

      <div className="flex-1" />

      <Link
        to="/"
        className="mt-6 block w-full bg-primary text-primary-foreground rounded-3xl py-5 text-center font-extrabold text-lg active:scale-[0.98] transition-transform"
      >
        Back home
      </Link>
    </div>
  );
}
