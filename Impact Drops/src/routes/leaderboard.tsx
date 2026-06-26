import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { leaderboard } from "@/lib/mock";
import { BlobAvatar } from "@/components/BlobAvatar";

export const Route = createFileRoute("/leaderboard")({
  head: () => ({ meta: [{ title: "Leaderboard — Receipt Drop" }] }),
  component: Leaderboard,
});

function Leaderboard() {
  const [mode, setMode] = useState<"friends" | "uni">("friends");

  return (
    <div className="px-5 pt-8">
      <h1 className="text-2xl font-extrabold mb-1">Ranks</h1>
      <p className="text-sm text-muted-foreground mb-5">Consistency over amounts.</p>

      <div className="bg-muted rounded-full p-1 flex mb-5">
        {(["friends", "uni"] as const).map(m => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={`flex-1 py-2 rounded-full text-sm font-bold capitalize transition-colors ${mode === m ? "bg-card shadow-sm" : "text-muted-foreground"}`}
          >
            {m === "uni" ? "Uni Group" : "Friends"}
          </button>
        ))}
      </div>

      <ul className="space-y-2">
        {leaderboard.map((row, i) => (
          <li
            key={row.id}
            className={`flex items-center gap-3 rounded-3xl border p-3 shadow-sm ${row.id === "me" ? "bg-primary/30 border-primary" : "bg-card border-border"}`}
          >
            <span className="w-8 text-center text-lg font-extrabold text-muted-foreground">{i + 1}</span>
            <BlobAvatar state={row.state} size={44} animate={false} />
            <div className="flex-1 min-w-0">
              <p className="font-extrabold truncate">{row.name}</p>
              <p className="text-xs text-muted-foreground">{row.label}</p>
            </div>
            {i < 3 && <span className="text-xl">{["🥇", "🥈", "🥉"][i]}</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}
