import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { ChevronLeft, Check } from "lucide-react";
import { PixelAvatar } from "@/components/PixelAvatar";
import { useDrops } from "@/lib/drops-context";
import type {
  AvatarConfig,
  AvatarColor,
  AvatarEyes,
  AvatarHat,
} from "@/lib/mock";

export const Route = createFileRoute("/avatar")({
  head: () => ({
    meta: [
      { title: "Receipt Drop — Customize Buddy" },
      { name: "description", content: "Mix and match your buddy." },
    ],
  }),
  component: AvatarPage,
});

type Tab = "color" | "eyes" | "hat";

const COLORS: AvatarColor[] = [
  "yellow", "coral", "lime", "blue", "purple", "pink", "brown", "gray", "white",
];
const EYES: AvatarEyes[] = [
  "default", "dot", "happy", "wink", "squint", "sleepy", "blink", "star", "heart", "glasses",
];
const HATS: AvatarHat[] = [
  "none", "cap", "beanie", "crown", "party", "headband", "catEars", "plant", "propeller", "tophat",
];

const swatch: Record<AvatarColor, string> = {
  yellow: "#FFCC29",
  coral: "#FF6655",
  lime: "#9CD650",
  blue: "#6FB8E8",
  purple: "#C7A8E8",
  pink: "#F5B5C5",
  brown: "#B89B7A",
  gray: "#BFBFBF",
  white: "#F2EFE9",
};

const HAT_LABEL: Record<AvatarHat, string> = {
  none: "None",
  cap: "Cap",
  beanie: "Beanie",
  crown: "Crown",
  party: "Party",
  headband: "Headband",
  catEars: "Cat Ears",
  plant: "Plant",
  propeller: "Prop",
  tophat: "Top Hat",
};

function AvatarPage() {
  const { avatarConfig, setAvatarConfig, avatarState } = useDrops();
  const navigate = useNavigate();
  const [draft, setDraft] = useState<AvatarConfig>(avatarConfig);
  const [tab, setTab] = useState<Tab>("color");

  function update<K extends keyof AvatarConfig>(k: K, v: AvatarConfig[K]) {
    setDraft(d => ({ ...d, [k]: v }));
  }

  function save() {
    setAvatarConfig(draft);
    navigate({ to: "/" });
  }

  return (
    <div className="flex-1 flex flex-col">
      <header className="flex items-center justify-between px-5 pt-6 pb-3">
        <Link
          to="/"
          className="w-10 h-10 rounded-full bg-card border border-border flex items-center justify-center"
          aria-label="Back"
        >
          <ChevronLeft className="w-5 h-5" />
        </Link>
        <h1 className="text-lg font-extrabold">Customize</h1>
        <button
          onClick={save}
          className="w-10 h-10 rounded-full bg-primary flex items-center justify-center"
          aria-label="Save"
        >
          <Check className="w-5 h-5" />
        </button>
      </header>

      {/* Stage */}
      <div
        className="mx-5 rounded-3xl flex items-center justify-center overflow-hidden"
        style={{
          background: "linear-gradient(180deg, #FBF6E8 0%, #F2EAD3 100%)",
          aspectRatio: "1 / 1",
        }}
      >
        <PixelAvatar config={draft} state={avatarState} size={260} />
      </div>

      {/* Tabs */}
      <div className="flex gap-2 px-5 mt-5">
        {(["color", "eyes", "hat"] as Tab[]).map(t => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`flex-1 py-2.5 rounded-2xl text-xs font-bold uppercase tracking-wider border transition-colors ${
              tab === t
                ? "bg-foreground text-background border-foreground"
                : "bg-card text-muted-foreground border-border"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {/* Options */}
      <div className="px-5 mt-4 pb-8 flex-1 overflow-y-auto">
        {tab === "color" && (
          <div className="grid grid-cols-3 gap-3">
            {COLORS.map(c => (
              <button
                key={c}
                onClick={() => update("color", c)}
                className={`aspect-square rounded-2xl border-4 flex flex-col items-center justify-center gap-1 ${
                  draft.color === c ? "border-foreground" : "border-transparent"
                }`}
                style={{ background: swatch[c], color: "#1F1F1F" }}
              >
                <PixelAvatar
                  config={{ color: c, eyes: "default", hat: "none" }}
                  size={70}
                  spin={false}
                  tiltStill
                />
                <span className="text-[10px] font-bold uppercase tracking-wider">{c}</span>
              </button>
            ))}
          </div>
        )}

        {tab === "eyes" && (
          <div className="grid grid-cols-3 gap-3">
            {EYES.map(e => (
              <button
                key={e}
                onClick={() => update("eyes", e)}
                className={`aspect-square rounded-2xl border-2 flex flex-col items-center justify-center gap-1 bg-card ${
                  draft.eyes === e ? "border-foreground" : "border-border"
                }`}
              >
                <div className="flex-1 flex items-center justify-center w-full">
                  <PixelAvatar
                    config={{ color: draft.color, eyes: e, hat: "none" }}
                    size={90}
                    spin={false}
                    tiltStill
                  />
                </div>
                <span className="text-[10px] font-bold uppercase tracking-wider">{e}</span>
              </button>
            ))}
          </div>
        )}

        {tab === "hat" && (
          <div className="grid grid-cols-3 gap-3">
            {HATS.map(h => (
              <button
                key={h}
                onClick={() => update("hat", h)}
                className={`aspect-square rounded-2xl border-2 flex flex-col items-center justify-center gap-1 bg-card ${
                  draft.hat === h ? "border-foreground" : "border-border"
                }`}
              >
                <div className="flex-1 flex items-center justify-center w-full">
                  <PixelAvatar
                    config={{ color: draft.color, eyes: "default", hat: h }}
                    size={90}
                    spin={false}
                    tiltStill
                  />
                </div>
                <span className="text-[10px] font-bold uppercase tracking-wider">
                  {HAT_LABEL[h]}
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
