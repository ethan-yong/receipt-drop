import { createFileRoute } from "@tanstack/react-router";
import { feed, friends } from "@/lib/mock";
import { BlobAvatar } from "@/components/BlobAvatar";

export const Route = createFileRoute("/feed")({
  head: () => ({ meta: [{ title: "Social Feed — Receipt Drop" }] }),
  component: Feed,
});

function Feed() {
  return (
    <div className="px-5 pt-8">
      <h1 className="text-2xl font-extrabold mb-1">Feed</h1>
      <p className="text-sm text-muted-foreground mb-5">What friends are dropping.</p>

      <ul className="space-y-3">
        {feed.map(post => {
          const friend = friends.find(f => f.id === post.friendId)!;
          return (
            <li key={post.id} className="bg-card rounded-3xl border border-border p-4 shadow-sm">
              <div className="flex items-start gap-3">
                <div className="shrink-0"><BlobAvatar state={friend.state} size={48} animate={false} /></div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline justify-between gap-2">
                    <p className="font-extrabold truncate">{friend.name}</p>
                    <span className="text-[10px] text-muted-foreground shrink-0">{post.ago}</span>
                  </div>
                  <p className="text-sm mt-0.5 leading-snug">{post.line}</p>
                  <div className="flex gap-2 mt-3">
                    <ReactionChip emoji="🔥" count={post.reactions.fire} />
                    <ReactionChip emoji="😂" count={post.reactions.laugh} />
                    <ReactionChip emoji="👀" count={post.reactions.eyes} />
                  </div>
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function ReactionChip({ emoji, count }: { emoji: string; count: number }) {
  return (
    <button className="flex items-center gap-1.5 rounded-full bg-muted border border-border px-3 py-1 text-xs font-bold active:scale-95 transition-transform">
      <span>{emoji}</span>
      <span className="text-muted-foreground">{count}</span>
    </button>
  );
}
