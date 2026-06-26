export type BadgeRarity = "common" | "rare" | "epic" | "legendary";

export type Badge = {
  id: string;
  label: string;
  emoji: string;
  description: string;
  rarity: BadgeRarity;
  earned: boolean;
  progress: number;
  goal: number;
  earnedOn?: string;
  hint?: string;
};

export const allBadges: Badge[] = [
  { id: "savvy_shopper", label: "Savvy Shopper", emoji: "🛍️", description: "You've recorded 25 shopping receipts.", rarity: "epic", earned: true, progress: 25, goal: 25, earnedOn: "12 May 2025" },
  { id: "caffeine_club", label: "Caffeine Club", emoji: "☕", description: "Logged 15 coffee runs. Your barista knows you.", rarity: "common", earned: true, progress: 15, goal: 15, earnedOn: "08 May 2025" },
  { id: "receipt_keeper", label: "Receipt Keeper", emoji: "🧾", description: "Saved 50 receipts in total. Organized!", rarity: "rare", earned: true, progress: 50, goal: 50, earnedOn: "01 May 2025" },
  { id: "budget_buddy", label: "Budget Buddy", emoji: "🐷", description: "Stayed under budget 4 weeks in a row.", rarity: "rare", earned: true, progress: 4, goal: 4, earnedOn: "20 Apr 2025" },
  { id: "streak_master", label: "Streak Master", emoji: "🏅", description: "Logged a receipt every day for 14 days.", rarity: "epic", earned: true, progress: 14, goal: 14, earnedOn: "15 Apr 2025" },
  { id: "fuel_saver", label: "Fuel Saver", emoji: "⛽", description: "Tracked 10 fuel receipts and spotted patterns.", rarity: "common", earned: true, progress: 10, goal: 10, earnedOn: "10 Apr 2025" },
  { id: "explorer", label: "Explorer", emoji: "🔍", description: "Categorize 10 different merchant types.", rarity: "common", earned: false, progress: 3, goal: 10, hint: "Keep exploring!" },
  { id: "early_bird", label: "Early Bird", emoji: "⏰", description: "Log 5 receipts before 9am.", rarity: "common", earned: false, progress: 2, goal: 5, hint: "Catch the morning runs." },
  { id: "smart_spender", label: "Smart Spender", emoji: "👛", description: "Compare prices on 20 items before buying.", rarity: "rare", earned: false, progress: 7, goal: 20, hint: "Compare and conquer." },
  { id: "category_master", label: "Category Master", emoji: "🗂️", description: "Properly categorize 100 receipts.", rarity: "rare", earned: false, progress: 42, goal: 100, hint: "Sort it out." },
  { id: "no_spend_ninja", label: "No-Spend Ninja", emoji: "🥷", description: "Complete a 7-day no-spend streak.", rarity: "epic", earned: false, progress: 0, goal: 7, hint: "Stealth mode." },
  { id: "big_saver", label: "Big Saver", emoji: "🔐", description: "Save $1000 across one month.", rarity: "legendary", earned: false, progress: 320, goal: 1000, hint: "Vault it up." },
];

export const rarityStyles: Record<BadgeRarity, { ring: string; chip: string; label: string }> = {
  common: { ring: "ring-stone-300", chip: "bg-stone-200 text-stone-700", label: "COMMON" },
  rare: { ring: "ring-sky-300", chip: "bg-sky-200 text-sky-800", label: "RARE" },
  epic: { ring: "ring-purple-300", chip: "bg-purple-200 text-purple-800", label: "EPIC" },
  legendary: { ring: "ring-primary", chip: "bg-primary text-primary-foreground", label: "LEGENDARY" },
};
