import type { Drop } from "./mock";

const lines = [
  "Compared to last week at this time, your activity feels calmer.",
  "Your most impactful drop today was less intense than your weekend average.",
  "You had fewer high-impact moments than last Tuesday.",
  "Today's rhythm is steadier than your usual mid-week pattern.",
  "Your activity clustered around fewer categories than yesterday.",
  "A quieter day than most — closer to your calm baseline.",
  "More spread out than last week — a balanced kind of day.",
  "Your impact peaks today were softer than the past few days.",
];

export function awarenessSummary(drops: Drop[]): { headline: string; sub: string } {
  const high = drops.filter(d => d.impact === "high").length;
  const total = drops.length;

  let headline: string;
  if (total === 0) headline = "A quiet day. Nothing dropped yet.";
  else if (high >= 2) headline = "Today had more intensity than usual.";
  else if (total >= 4) headline = "A busy rhythm — many small moments.";
  else headline = "A steady, balanced day.";

  // Deterministic-ish pick based on drops content
  const idx = (total * 3 + high * 7) % lines.length;
  return { headline, sub: lines[idx] };
}
