export type DioramaThemeId =
  | "idle"
  | "grocery"
  | "petrol"
  | "cafe"
  | "shopping"
  | "fast_food"
  | "gym"
  | "electronics"
  | "beauty"
  | "transport"
  | "home";

export type DioramaTheme = {
  id: DioramaThemeId;
  label: string;
  floor: string;
  wallA: string;
  wallB: string;
  accent: string;
  trim: string;
  /** Avatar idle animation (defined in styles.css). */
  idleAnim: string;
  caption: string;
};

export const themes: Record<DioramaThemeId, DioramaTheme> = {
  idle: {
    id: "idle",
    label: "Empty Room",
    floor: "oklch(0.88 0.02 90)",
    wallA: "oklch(0.96 0.015 90)",
    wallB: "oklch(0.92 0.02 90)",
    accent: "oklch(0.78 0.10 90)",
    trim: "oklch(0.55 0.06 60)",
    idleAnim: "diorama-bob 3s ease-in-out infinite",
    caption: "We couldn't identify your last receipt. Update it to unlock your space.",
  },
  grocery: {
    id: "grocery",
    label: "Grocery Store",
    floor: "oklch(0.88 0.02 90)",
    wallA: "oklch(0.92 0.04 110)",
    wallB: "oklch(0.86 0.08 130)",
    accent: "oklch(0.65 0.18 140)",
    trim: "oklch(0.50 0.06 60)",
    idleAnim: "diorama-cart 3.6s ease-in-out infinite",
    caption: "Your last receipt was from groceries 🛒",
  },
  petrol: {
    id: "petrol",
    label: "Petrol Station",
    floor: "oklch(0.60 0.02 250)",
    wallA: "oklch(0.85 0.04 230)",
    wallB: "oklch(0.55 0.15 250)",
    accent: "oklch(0.70 0.20 30)",
    trim: "oklch(0.30 0.02 250)",
    idleAnim: "diorama-tap 1.0s ease-in-out infinite",
    caption: "Your last receipt was from a petrol station ⛽",
  },
  cafe: {
    id: "cafe",
    label: "Cozy Cafe",
    floor: "oklch(0.78 0.05 60)",
    wallA: "oklch(0.95 0.04 110)",
    wallB: "oklch(0.45 0.10 60)",
    accent: "oklch(0.50 0.13 60)",
    trim: "oklch(0.40 0.05 60)",
    idleAnim: "diorama-sip 2.4s ease-in-out infinite",
    caption: "Your last receipt was from a cafe ☕",
  },
  shopping: {
    id: "shopping",
    label: "Clothing Store",
    floor: "oklch(0.92 0.04 0)",
    wallA: "oklch(0.93 0.06 0)",
    wallB: "oklch(0.85 0.10 350)",
    accent: "oklch(0.70 0.20 0)",
    trim: "oklch(0.55 0.05 30)",
    idleAnim: "diorama-spin-mirror 3s ease-in-out infinite",
    caption: "Your last receipt was from shopping 🛍️",
  },
  fast_food: {
    id: "fast_food",
    label: "Fast Food",
    floor: "oklch(0.92 0.04 60)",
    wallA: "oklch(0.94 0.04 60)",
    wallB: "oklch(0.65 0.22 30)",
    accent: "oklch(0.65 0.22 30)",
    trim: "oklch(0.40 0.06 60)",
    idleAnim: "diorama-eat 1.2s ease-in-out infinite",
    caption: "Your last receipt was from fast food 🍔",
  },
  gym: {
    id: "gym",
    label: "Gym",
    floor: "oklch(0.70 0.02 250)",
    wallA: "oklch(0.85 0.02 250)",
    wallB: "oklch(0.78 0.03 250)",
    accent: "oklch(0.65 0.18 30)",
    trim: "oklch(0.35 0.02 250)",
    idleAnim: "diorama-lift 1.0s ease-in-out infinite",
    caption: "Your last receipt was from a gym 💪",
  },
  electronics: {
    id: "electronics",
    label: "Gaming Store",
    floor: "oklch(0.30 0.04 280)",
    wallA: "oklch(0.25 0.06 280)",
    wallB: "oklch(0.35 0.12 320)",
    accent: "oklch(0.80 0.22 320)",
    trim: "oklch(0.20 0.04 280)",
    idleAnim: "diorama-press 0.8s ease-in-out infinite",
    caption: "Your last receipt was from electronics 🎮",
  },
  beauty: {
    id: "beauty",
    label: "Beauty Room",
    floor: "oklch(0.93 0.04 0)",
    wallA: "oklch(0.95 0.05 0)",
    wallB: "oklch(0.88 0.08 350)",
    accent: "oklch(0.78 0.15 340)",
    trim: "oklch(0.55 0.06 30)",
    idleAnim: "diorama-sparkle 2.2s ease-in-out infinite",
    caption: "Your last receipt was from beauty ✨",
  },
  transport: {
    id: "transport",
    label: "Transit Platform",
    floor: "oklch(0.72 0.02 250)",
    wallA: "oklch(0.85 0.03 230)",
    wallB: "oklch(0.55 0.08 230)",
    accent: "oklch(0.65 0.18 240)",
    trim: "oklch(0.30 0.02 250)",
    idleAnim: "diorama-tap 0.9s ease-in-out infinite",
    caption: "Your last receipt was from transport 🚇",
  },
  home: {
    id: "home",
    label: "Home",
    floor: "oklch(0.72 0.05 60)",
    wallA: "oklch(0.85 0.03 80)",
    wallB: "oklch(0.80 0.04 80)",
    accent: "oklch(0.62 0.15 40)",
    trim: "oklch(0.45 0.06 60)",
    idleAnim: "diorama-slump 4s ease-in-out infinite",
    caption: "Your last receipt was for home expenses 🏠",
  },
};

/** Forgiving category → theme mapping. */
export function getThemeForCategory(category?: string | null): DioramaTheme {
  if (!category) return themes.idle;
  const c = category.toLowerCase();
  const match: Array<[string[], DioramaThemeId]> = [
    [["grocery", "groceries", "market", "supermarket"], "grocery"],
    [["fuel", "petrol", "gas", "station"], "petrol"],
    [["coffee", "cafe", "espresso", "latte", "tea", "boba", "bubble"], "cafe"],
    [["clothes", "clothing", "fashion", "shop", "shopping", "mall", "boutique"], "shopping"],
    [["fast food", "fastfood", "burger", "takeaway", "takeout", "fries", "mcd", "kfc"], "fast_food"],
    [["gym", "fitness", "workout", "yoga"], "gym"],
    [["electronics", "gaming", "game", "console", "tech", "pc"], "electronics"],
    [["beauty", "cosmetics", "skincare", "makeup", "salon"], "beauty"],
    [["transport", "transit", "train", "mrt", "bus", "ticket", "grab", "uber"], "transport"],
    [["bill", "utility", "rent", "home", "internet", "electric", "water"], "home"],
    // legacy fall-throughs to keep older categories useful
    [["food", "restaurant", "meal", "dining"], "fast_food"],
  ];
  for (const [keys, id] of match) {
    if (keys.some(k => c.includes(k))) return themes[id];
  }
  return themes.idle;
}
