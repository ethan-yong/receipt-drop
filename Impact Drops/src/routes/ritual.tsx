import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useDrops } from "@/lib/drops-context";
import { ReceiptStrip } from "@/components/ReceiptStrip";

export const Route = createFileRoute("/ritual")({
  head: () => ({ meta: [{ title: "Receipt Drop Machine" }] }),
  component: Ritual,
});

function Ritual() {
  const { drops } = useDrops();
  const navigate = useNavigate();
  const [step, setStep] = useState(0); // -1 idle, 0..n-1 processing, n done
  const [phase, setPhase] = useState<"intro" | "running" | "done">("intro");

  useEffect(() => {
    const t = setTimeout(() => setPhase("running"), 900);
    return () => clearTimeout(t);
  }, []);

  useEffect(() => {
    if (phase !== "running") return;
    if (step >= drops.length) {
      const t = setTimeout(() => navigate({ to: "/summary" }), 700);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => setStep(s => s + 1), 900);
    return () => clearTimeout(t);
  }, [phase, step, drops.length, navigate]);

  const current = drops[step];

  return (
    <div className="fixed inset-0 z-50 bg-background flex flex-col items-center justify-between py-12 px-6">
      <div className="text-center">
        <p className="text-[11px] font-semibold uppercase tracking-[0.3em] text-muted-foreground">Ritual</p>
        <h1 className="text-2xl font-extrabold mt-1">Receipt Drop Machine</h1>
      </div>

      {/* Drop slot */}
      <div className="relative w-full max-w-xs h-[260px] flex items-end justify-center overflow-hidden">
        {phase === "running" && current && (
          <div key={step} className="animate-drop-in absolute top-0">
            <ReceiptStrip impact={current.impact} label={current.category} />
          </div>
        )}
        {phase === "running" && step >= drops.length && (
          <p className="text-sm text-muted-foreground self-center">Wrapping up…</p>
        )}
      </div>

      {/* Machine */}
      <div className="w-full max-w-xs">
        <div className="bg-card border-2 border-border rounded-3xl p-6 shadow-xl animate-machine-pulse">
          <div className="h-3 bg-foreground/80 rounded-full mb-4 animate-chomp" />
          <div className="flex items-end gap-1.5 justify-center h-16">
            {drops.map((d, i) => (
              <div
                key={d.id}
                className="w-3 rounded-t transition-all duration-500"
                style={{
                  height: i < step ? (d.impact === "high" ? 56 : d.impact === "med" ? 36 : 20) : 6,
                  background: i < step ? "var(--primary)" : "var(--muted)",
                }}
              />
            ))}
          </div>
          <p className="text-center text-[10px] font-bold uppercase tracking-widest text-muted-foreground mt-4">
            {phase === "intro" && "Warming up…"}
            {phase === "running" && step < drops.length && `Processing ${step + 1} of ${drops.length}`}
            {phase === "running" && step >= drops.length && "Complete"}
          </p>
        </div>
      </div>

      <div className="h-2" />
    </div>
  );
}
