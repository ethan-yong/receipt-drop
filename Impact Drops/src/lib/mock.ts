export type Impact = "low" | "med" | "high";
export type Category = "food" | "shopping" | "transport" | "other";

export type Drop = {
  id: string;
  impact: Impact;
  category: Category;
  time: string; // "14:32"
};

export type AvatarState = "calm" | "active" | "spiky" | "balanced";

export type AvatarColor =
  | "yellow"
  | "coral"
  | "lime"
  | "blue"
  | "purple"
  | "pink"
  | "brown"
  | "gray"
  | "white";

export type AvatarEyes =
  | "default"
  | "dot"
  | "happy"
  | "wink"
  | "squint"
  | "sleepy"
  | "blink"
  | "star"
  | "heart"
  | "glasses";

export type AvatarHat =
  | "none"
  | "cap"
  | "beanie"
  | "crown"
  | "party"
  | "headband"
  | "catEars"
  | "plant"
  | "propeller"
  | "tophat";

export type AvatarConfig = {
  color: AvatarColor;
  eyes: AvatarEyes;
  hat: AvatarHat;
};

export const defaultAvatarConfig: AvatarConfig = {
  color: "yellow",
  eyes: "default",
  hat: "cap",
};

export const seedDrops: Drop[] = [
  { id: "d1", impact: "low", category: "food", time: "08:14" },
  { id: "d2", impact: "med", category: "transport", time: "11:02" },
  { id: "d3", impact: "high", category: "shopping", time: "15:47" },
];

export const friends = [
  { id: "f1", name: "Joshua", state: "spiky" as AvatarState },
  { id: "f2", name: "Aina", state: "calm" as AvatarState },
  { id: "f3", name: "Wei Jie", state: "balanced" as AvatarState },
  { id: "f4", name: "Priya", state: "active" as AvatarState },
  { id: "f5", name: "Hakim", state: "calm" as AvatarState },
];

export type FeedPost = {
  id: string;
  friendId: string;
  line: string;
  ago: string;
  reactions: { fire: number; laugh: number; eyes: number };
};

export const feed: FeedPost[] = [
  { id: "p1", friendId: "f1", line: "dropped a luxury-level impact today", ago: "12m", reactions: { fire: 4, laugh: 2, eyes: 1 } },
  { id: "p2", friendId: "f2", line: "had a low activity day — calm energy", ago: "1h", reactions: { fire: 1, laugh: 0, eyes: 3 } },
  { id: "p3", friendId: "f3", line: "logged a steady, balanced afternoon", ago: "2h", reactions: { fire: 2, laugh: 1, eyes: 0 } },
  { id: "p4", friendId: "f4", line: "had a spiky lunch break", ago: "3h", reactions: { fire: 5, laugh: 4, eyes: 2 } },
  { id: "p5", friendId: "f5", line: "kept it quiet — observer mode", ago: "5h", reactions: { fire: 0, laugh: 0, eyes: 6 } },
];

export const leaderboard = [
  { id: "f3", name: "Wei Jie", label: "Consistent Observer", state: "balanced" as AvatarState },
  { id: "f2", name: "Aina", label: "Calm Week", state: "calm" as AvatarState },
  { id: "me", name: "You", label: "Steady Logger", state: "balanced" as AvatarState },
  { id: "f4", name: "Priya", label: "Active Tracker", state: "active" as AvatarState },
  { id: "f1", name: "Joshua", label: "Spiky Streak", state: "spiky" as AvatarState },
  { id: "f5", name: "Hakim", label: "Quiet Mode", state: "calm" as AvatarState },
];

export const mapZones = [
  { id: "z1", category: "food" as Category, x: 30, y: 35, intensity: 0.8 },
  { id: "z2", category: "shopping" as Category, x: 65, y: 55, intensity: 0.6 },
  { id: "z3", category: "transport" as Category, x: 50, y: 75, intensity: 0.4 },
  { id: "z4", category: "food" as Category, x: 75, y: 25, intensity: 0.5 },
  { id: "z5", category: "other" as Category, x: 20, y: 65, intensity: 0.3 },
];

export const badges = [
  { id: "b1", label: "First Drop", earned: true },
  { id: "b2", label: "7-Day Logger", earned: true },
  { id: "b3", label: "Consistent Observer", earned: false },
  { id: "b4", label: "Social Tracker", earned: false },
];

export function deriveAvatarState(drops: Drop[]): AvatarState {
  const high = drops.filter(d => d.impact === "high").length;
  if (drops.length === 0) return "calm";
  if (high >= 2) return "spiky";
  if (drops.length >= 4) return "active";
  if (high === 0 && drops.length <= 2) return "calm";
  return "balanced";
}
