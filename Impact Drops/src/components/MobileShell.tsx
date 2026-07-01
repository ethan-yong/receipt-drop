import { Link, useLocation } from "@tanstack/react-router";
import type { ReactNode } from "react";
import { Home, Users, Map, Trophy } from "lucide-react";

const tabs = [
  { to: "/", label: "Home", Icon: Home },
  { to: "/feed", label: "Feed", Icon: Users },
  { to: "/map", label: "Map", Icon: Map },
  { to: "/leaderboard", label: "Ranks", Icon: Trophy },
] as const;

export function MobileShell({ children }: { children: ReactNode }) {
  const { pathname } = useLocation();
  const hideTabs =
    pathname === "/ritual" ||
    pathname === "/drop" ||
    pathname === "/summary" ||
    pathname === "/avatar" ||
    pathname === "/map" ||
    pathname === "/finance-map";

  return (
    <div className="min-h-screen bg-background flex justify-center">
      <div className="w-full max-w-[480px] min-h-screen flex flex-col relative pb-24">
        <main className="flex-1 flex flex-col">{children}</main>
        {!hideTabs && (
          <nav className="fixed bottom-0 left-0 right-0 mx-auto w-full max-w-[480px] bg-card/95 backdrop-blur border-t border-border">
            <ul className="flex items-center justify-around px-2 py-2 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
              {tabs.map(({ to, label, Icon }) => (
                <li key={to}>
                  <Link
                    to={to}
                    activeOptions={{ exact: true }}
                    className="flex flex-col items-center gap-1 px-4 py-1.5 rounded-2xl text-muted-foreground data-[status=active]:text-foreground data-[status=active]:bg-primary/30 transition-colors"
                  >
                    <Icon className="w-5 h-5" />
                    <span className="text-[10px] font-semibold">{label}</span>
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        )}
      </div>
    </div>
  );
}
