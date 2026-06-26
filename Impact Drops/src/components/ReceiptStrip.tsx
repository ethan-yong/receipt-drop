import type { Impact } from "@/lib/mock";

const lengths: Record<Impact, number> = { low: 80, med: 140, high: 220 };
const colors: Record<Impact, string> = {
  low: "var(--impact-low)",
  med: "var(--impact-med)",
  high: "var(--impact-high)",
};

export function ReceiptStrip({
  impact,
  label,
  className = "",
  style,
}: {
  impact: Impact;
  label?: string;
  className?: string;
  style?: React.CSSProperties;
}) {
  const height = lengths[impact];
  return (
    <div
      className={`relative bg-card shadow-md ${className}`}
      style={{
        width: 88,
        height,
        borderRadius: 6,
        border: "1.5px dashed var(--border)",
        backgroundImage:
          "repeating-linear-gradient(0deg, transparent 0 14px, color-mix(in oklab, var(--foreground) 8%, transparent) 14px 15px)",
        ...style,
      }}
    >
      <div
        className="absolute top-0 left-0 right-0 h-2"
        style={{ background: colors[impact], borderTopLeftRadius: 6, borderTopRightRadius: 6 }}
      />
      {label && (
        <div className="absolute bottom-2 left-0 right-0 text-center text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
          {label}
        </div>
      )}
    </div>
  );
}
