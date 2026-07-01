import { useState } from "react";
import {
  DndContext,
  PointerSensor,
  TouchSensor,
  useSensor,
  useSensors,
  closestCenter,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  rectSortingStrategy,
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { BadgeHex } from "@/components/BadgeHex";
import { BadgeDetailDialog } from "@/components/BadgeDetailDialog";
import { useBadges } from "@/lib/badges-context";
import type { Badge } from "@/lib/badges";

function SortableTile({ badge, onClick }: { badge: Badge; onClick: () => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: badge.id });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };
  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners} className="touch-none">
      <BadgeHex badge={badge} onClick={onClick} dragHandle />
    </div>
  );
}

export function TopBadgesGrid() {
  const { topBadges, topOrder, setTopOrder } = useBadges();
  const [selected, setSelected] = useState<Badge | null>(null);
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 180, tolerance: 6 } }),
  );

  function handleDragEnd(e: DragEndEvent) {
    const { active, over } = e;
    if (!over || active.id === over.id) return;
    const oldIndex = topOrder.indexOf(active.id as string);
    const newIndex = topOrder.indexOf(over.id as string);
    setTopOrder(arrayMove(topOrder, oldIndex, newIndex));
  }

  return (
    <>
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <SortableContext items={topOrder} strategy={rectSortingStrategy}>
          <div className="grid grid-cols-3 gap-3 p-4 rounded-3xl border-2 border-dashed border-primary/50 bg-primary/5">
            {topBadges.map(b => (
              <SortableTile key={b.id} badge={b} onClick={() => setSelected(b)} />
            ))}
          </div>
        </SortableContext>
      </DndContext>
      <p className="text-[10px] text-muted-foreground mt-2 px-1 flex items-center gap-1">
        <span>⋮⋮</span> Drag to reorder. First badge appears on your home screen.
      </p>
      <BadgeDetailDialog badge={selected} open={!!selected} onOpenChange={o => !o && setSelected(null)} />
    </>
  );
}
