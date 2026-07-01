import { createFileRoute } from "@tanstack/react-router";
import { SpendingMap } from "@/components/SpendingMap";

export const Route = createFileRoute("/map")({
  head: () => ({
    meta: [
      { title: "Spending Map — Selangor" },
      { name: "description", content: "Explore where your money goes across Selangor." },
    ],
  }),
  component: MapPage,
});

function MapPage() {
  return (
    <div className="fixed inset-0 w-screen h-screen">
      <SpendingMap />
    </div>
  );
}
