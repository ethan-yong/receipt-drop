import type { AvatarState } from "@/lib/mock";

const stateMap: Record<AvatarState, { fill: string; label: string; eyes: "happy" | "neutral" | "wide" | "wow" }> = {
  calm: { fill: "var(--calm)", label: "Calm", eyes: "happy" },
  active: { fill: "var(--active)", label: "Active", eyes: "wide" },
  spiky: { fill: "var(--spiky)", label: "Spiky", eyes: "wow" },
  balanced: { fill: "var(--balanced)", label: "Balanced", eyes: "neutral" },
};

export function BlobAvatar({
  state = "calm",
  size = 200,
  animate = true,
}: { state?: AvatarState; size?: number; animate?: boolean }) {
  const s = stateMap[state];
  const path =
    state === "spiky"
      ? "M50,8 L62,22 L82,18 L74,38 L92,50 L74,62 L82,82 L62,78 L50,92 L38,78 L18,82 L26,62 L8,50 L26,38 L18,18 L38,22 Z"
      : "M50,10 C72,10 90,28 90,50 C90,70 74,90 50,90 C26,90 10,70 10,50 C10,28 28,10 50,10 Z";

  return (
    <div className={animate ? "animate-wobble" : ""} style={{ width: size, height: size }} aria-label={`${s.label} avatar`}>
      <svg viewBox="0 0 100 100" width={size} height={size}>
        <defs>
          <filter id="blob-shadow" x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur in="SourceAlpha" stdDeviation="2" />
            <feOffset dy="3" result="offsetblur" />
            <feComponentTransfer><feFuncA type="linear" slope="0.25" /></feComponentTransfer>
            <feMerge><feMergeNode /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
        </defs>
        <path d={path} fill={s.fill} filter="url(#blob-shadow)" />
        {/* eyes */}
        <ellipse cx="38" cy="46" rx={s.eyes === "wow" ? 4 : 3} ry={s.eyes === "happy" ? 1.5 : 4} fill="#1a1a1a" />
        <ellipse cx="62" cy="46" rx={s.eyes === "wow" ? 4 : 3} ry={s.eyes === "happy" ? 1.5 : 4} fill="#1a1a1a" />
        {/* mouth */}
        {s.eyes === "happy" && <path d="M42 60 Q50 66 58 60" stroke="#1a1a1a" strokeWidth="2" fill="none" strokeLinecap="round" />}
        {s.eyes === "neutral" && <line x1="44" y1="62" x2="56" y2="62" stroke="#1a1a1a" strokeWidth="2" strokeLinecap="round" />}
        {s.eyes === "wide" && <ellipse cx="50" cy="62" rx="4" ry="3" fill="#1a1a1a" />}
        {s.eyes === "wow" && <ellipse cx="50" cy="63" rx="5" ry="5" fill="#1a1a1a" />}
      </svg>
    </div>
  );
}
