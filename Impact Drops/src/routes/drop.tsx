import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useDrops } from "@/lib/drops-context";
import type { Impact, Category } from "@/lib/mock";
import { ReceiptStrip } from "@/components/ReceiptStrip";
import { ArrowLeft, Upload, Check } from "lucide-react";

export const Route = createFileRoute("/drop")({
  head: () => ({ meta: [{ title: "Drop a Receipt" }] }),
  component: Drop,
});

const impacts: { value: Impact; label: string; sub: string }[] = [
  { value: "low", label: "Low impact", sub: "A small, everyday moment." },
  { value: "med", label: "Medium impact", sub: "A noticeable choice." },
  { value: "high", label: "High impact", sub: "A standout, intense one." },
];

const categories: { value: Category; emoji: string; label: string }[] = [
  { value: "food", emoji: "🍜", label: "Food" },
  { value: "shopping", emoji: "🛍️", label: "Shopping" },
  { value: "transport", emoji: "🛵", label: "Transport" },
  { value: "other", emoji: "✨", label: "Other" },
];

function Drop() {
  const navigate = useNavigate();
  const { addDrop } = useDrops();
  const [impact, setImpact] = useState<Impact | null>(null);
  const [category, setCategory] = useState<Category | null>(null);
  const [uploaded, setUploaded] = useState(false);

  const canSubmit = uploaded && impact && category;

  function submit() {
    if (!canSubmit || !impact || !category) return;
    addDrop({ impact, category });
    navigate({ to: "/ritual" });
  }

  return (
    <div className="flex-1 flex flex-col px-5 pt-8 pb-8">
      <div className="flex items-center justify-between mb-6">
        <Link to="/" className="rounded-full bg-card border border-border p-2">
          <ArrowLeft className="w-5 h-5" />
        </Link>
        <p className="text-sm font-semibold">New Drop</p>
        <div className="w-9" />
      </div>

      {/* Upload */}
      <label className="block">
        <input
          type="file"
          accept="image/*"
          className="hidden"
          onChange={() => setUploaded(true)}
        />
        <div className={`rounded-3xl border-2 border-dashed p-6 flex flex-col items-center gap-3 cursor-pointer transition-colors ${uploaded ? "border-primary bg-primary/20" : "border-border bg-card"}`}>
          {uploaded ? (
            <>
              <div className="rounded-full bg-primary p-3"><Check className="w-6 h-6" /></div>
              <p className="font-bold">Receipt added</p>
              <p className="text-xs text-muted-foreground">Tap to replace</p>
            </>
          ) : (
            <>
              <div className="rounded-full bg-muted p-3"><Upload className="w-6 h-6" /></div>
              <p className="font-bold">Upload receipt</p>
              <p className="text-xs text-muted-foreground">Photo or screenshot</p>
            </>
          )}
        </div>
      </label>

      {/* Category */}
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mt-6 mb-2">Category</p>
      <div className="grid grid-cols-4 gap-2">
        {categories.map(c => (
          <button
            key={c.value}
            onClick={() => setCategory(c.value)}
            className={`rounded-2xl border-2 p-3 flex flex-col items-center gap-1 transition-colors ${category === c.value ? "border-primary bg-primary/30" : "border-border bg-card"}`}
          >
            <span className="text-2xl">{c.emoji}</span>
            <span className="text-[10px] font-bold">{c.label}</span>
          </button>
        ))}
      </div>

      {/* Impact */}
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mt-6 mb-2">Impact</p>
      <div className="space-y-2.5">
        {impacts.map(i => (
          <button
            key={i.value}
            onClick={() => setImpact(i.value)}
            className={`w-full rounded-2xl border-2 p-3 flex items-center gap-4 text-left transition-colors ${impact === i.value ? "border-primary bg-primary/20" : "border-border bg-card"}`}
          >
            <div className="shrink-0 scale-50 origin-left -my-6">
              <ReceiptStrip impact={i.value} />
            </div>
            <div className="-ml-8">
              <p className="font-extrabold">{i.label}</p>
              <p className="text-xs text-muted-foreground">{i.sub}</p>
            </div>
          </button>
        ))}
      </div>

      <button
        onClick={submit}
        disabled={!canSubmit}
        className="mt-6 w-full bg-primary text-primary-foreground rounded-3xl py-5 font-extrabold text-lg disabled:opacity-40 disabled:cursor-not-allowed active:scale-[0.98] transition-transform"
      >
        Drop into Machine
      </button>
    </div>
  );
}
