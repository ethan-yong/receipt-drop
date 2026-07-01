/// <reference types="google.maps" />
import { useEffect, useMemo, useRef, useState } from "react";
import { useGoogleMaps } from "@/hooks/use-google-maps";
import {
  Area,
  loadCities,
  loadSectionsForCity,
  spendingColor,
  totalSpending,
  boundsOfArea,
  SELANGOR_CENTER,
} from "@/lib/selangor-geo";
import {
  Navigation2,
  Layers,
  MapPin,
  ChevronDown,
  ChevronUp,
  Loader2,
  ArrowLeft,
} from "lucide-react";

const fmt = (n: number) => `RM ${n.toLocaleString("en-MY")}`;

export function SpendingMap() {
  const { api, error } = useGoogleMaps();
  const containerRef = useRef<HTMLDivElement>(null);
  const mapDivRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<google.maps.Map | null>(null);
  const polygonsRef = useRef<google.maps.Polygon[]>([]);

  const [cities, setCities] = useState<Area[]>([]);
  const [sections, setSections] = useState<Area[]>([]);
  const [activeCity, setActiveCity] = useState<Area | null>(null);
  const view = activeCity ? "section" : "city";

  const [hovered, setHovered] = useState<Area | null>(null);
  const [selected, setSelected] = useState<Area | null>(null);
  const [tooltipPos, setTooltipPos] = useState<{ x: number; y: number } | null>(null);
  const [panelOpen, setPanelOpen] = useState(false);

  const [loadingCities, setLoadingCities] = useState(true);
  const [loadingSections, setLoadingSections] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);

  // Load cities once
  useEffect(() => {
    let alive = true;
    loadCities()
      .then((c) => {
        if (alive) setCities(c);
      })
      .catch((e: Error) => alive && setLoadErr(e.message ?? "Failed to load cities"))
      .finally(() => alive && setLoadingCities(false));
    return () => {
      alive = false;
    };
  }, []);

  // Load sections when entering a city
  useEffect(() => {
    if (!activeCity) {
      setSections([]);
      return;
    }
    let alive = true;
    setLoadingSections(true);
    setLoadErr(null);
    loadSectionsForCity(activeCity)
      .then((s) => alive && setSections(s))
      .catch((e: Error) => alive && setLoadErr(e.message ?? "Failed to load sections"))
      .finally(() => alive && setLoadingSections(false));
    return () => {
      alive = false;
    };
  }, [activeCity]);

  const areas: Area[] = view === "city" ? cities : sections;

  const maxSpend = useMemo(
    () => (areas.length ? Math.max(...areas.map((a) => a.spending)) : 0),
    [areas],
  );
  const total = useMemo(() => totalSpending(areas), [areas]);
  const highest = useMemo<Area | null>(
    () => (areas.length ? areas.reduce((a, b) => (a.spending > b.spending ? a : b)) : null),
    [areas],
  );

  const [arrow, setArrow] = useState({
    x: 0,
    y: 0,
    angle: 0,
    visible: false,
    proximity: 1,
    targetVisible: false,
  });

  // Init map
  useEffect(() => {
    if (!api || !mapDivRef.current || mapRef.current) return;
    mapRef.current = new api.maps.Map(mapDivRef.current, {
      center: SELANGOR_CENTER,
      zoom: 11,
      tilt: 0,
      heading: 0,
      disableDefaultUI: true,
      zoomControl: true,
      gestureHandling: "greedy",
      clickableIcons: false,
      backgroundColor: "transparent",
      styles: darkStyles,
    });
  }, [api]);

  // Render polygons
  useEffect(() => {
    if (!api || !mapRef.current) return;
    polygonsRef.current.forEach((p) => p.setMap(null));
    polygonsRef.current = [];
    if (!areas.length) return;

    const isCity = view === "city";

    areas.forEach((area) => {
      const color = spendingColor(area.spending, maxSpend);
      const poly = new api.maps.Polygon({
        paths: area.paths,
        strokeColor: color,
        strokeOpacity: 0.95,
        strokeWeight: isCity ? 3 : 1.25,
        fillColor: color,
        fillOpacity: isCity ? 0.32 : 0.45,
        map: mapRef.current!,
        clickable: true,
        zIndex: isCity ? 1 : 2,
      });

      poly.addListener("mouseover", () => {
        poly.setOptions({
          fillOpacity: isCity ? 0.5 : 0.7,
          strokeWeight: isCity ? 4 : 2.25,
        });
        setHovered(area);
      });
      poly.addListener("mousemove", (e: google.maps.MapMouseEvent) => {
        const dom = (e as unknown as { domEvent?: MouseEvent }).domEvent;
        if (dom && containerRef.current) {
          const rect = containerRef.current.getBoundingClientRect();
          setTooltipPos({ x: dom.clientX - rect.left, y: dom.clientY - rect.top });
        }
      });
      poly.addListener("mouseout", () => {
        poly.setOptions({
          fillOpacity: isCity ? 0.32 : 0.45,
          strokeWeight: isCity ? 3 : 1.25,
        });
        setHovered(null);
        setTooltipPos(null);
      });
      poly.addListener("click", () => {
        setSelected(area);
        if (isCity) {
          setActiveCity(area);
        }
      });

      polygonsRef.current.push(poly);
    });

    return () => {
      polygonsRef.current.forEach((p) => p.setMap(null));
      polygonsRef.current = [];
    };
  }, [api, areas, maxSpend, view]);

  // When entering section view, fit the map to the city bounds
  useEffect(() => {
    if (!api || !mapRef.current) return;
    if (!activeCity) {
      mapRef.current.panTo(SELANGOR_CENTER);
      mapRef.current.setZoom(11);
      return;
    }
    const { sw, ne } = boundsOfArea(activeCity);
    const bounds = new api.maps.LatLngBounds(
      new api.maps.LatLng(sw.lat, sw.lng),
      new api.maps.LatLng(ne.lat, ne.lng),
    );
    mapRef.current.fitBounds(bounds, 48);
  }, [api, activeCity]);

  // Arrow tracking
  useEffect(() => {
    if (!api || !mapRef.current || !containerRef.current || !highest) return;
    const map = mapRef.current;
    let raf = 0;

    const update = () => {
      const bounds = map.getBounds();
      const proj = map.getProjection();
      const container = containerRef.current;
      if (!bounds || !proj || !container) return;

      const targetLL = new api.maps.LatLng(highest.center.lat, highest.center.lng);
      const targetVisible = bounds.contains(targetLL);

      const rect = container.getBoundingClientRect();
      const cx = rect.width / 2;
      const cy = rect.height / 2;

      const centerLL = map.getCenter()!;
      const scale = Math.pow(2, map.getZoom() ?? 12);
      const targetWorld = proj.fromLatLngToPoint(targetLL)!;
      const centerWorld = proj.fromLatLngToPoint(centerLL)!;
      const dxPx = (targetWorld.x - centerWorld.x) * scale;
      const dyPx = (targetWorld.y - centerWorld.y) * scale;
      const angle = (Math.atan2(dxPx, -dyPx) * 180) / Math.PI;

      const dist = Math.hypot(dxPx, dyPx);
      const halfDiag = Math.hypot(cx, cy);
      const proximity = Math.min(1, dist / (halfDiag * 2));

      let x = cx;
      let y = cy;
      if (!targetVisible) {
        const pad = 36;
        const maxX = cx - pad;
        const maxY = cy - pad;
        const tX = dxPx !== 0 ? maxX / Math.abs(dxPx) : Infinity;
        const tY = dyPx !== 0 ? maxY / Math.abs(dyPx) : Infinity;
        const t = Math.min(tX, tY);
        x = cx + dxPx * t;
        y = cy + dyPx * t;
      }

      setArrow({ x, y, angle, visible: !targetVisible, proximity, targetVisible });
      raf = requestAnimationFrame(update);
    };

    const listeners = [
      map.addListener("bounds_changed", () => {
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(update);
      }),
      map.addListener("idle", update),
    ];
    update();

    return () => {
      cancelAnimationFrame(raf);
      listeners.forEach((l) => l.remove());
    };
  }, [api, highest]);

  if (error) {
    return (
      <div className="w-full h-full flex items-center justify-center text-destructive p-8 text-center">
        Failed to load map: {error}
      </div>
    );
  }

  const arrowSize = 36 + (1 - arrow.proximity) * -10;
  const pulseScale = 0.4 + arrow.proximity * 0.8;
  const loading = (loadingCities && !cities.length) || loadingSections;

  const enterCity = (city: Area) => {
    setActiveCity(city);
    setSelected(null);
    setHovered(null);
  };
  const backToCities = () => {
    setActiveCity(null);
    setSelected(null);
    setHovered(null);
  };

  return (
    <div ref={containerRef} className="relative w-full h-full overflow-hidden bg-background">
      <div ref={mapDivRef} className="absolute inset-0" />

      {loading && (
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-20 rounded-2xl bg-card/80 backdrop-blur-xl border border-white/10 shadow-2xl px-5 py-4 flex items-center gap-3">
          <Loader2 className="w-4 h-4 animate-spin text-primary" />
          <div>
            <div className="text-sm font-bold">
              {view === "city" ? "Loading cities…" : `Loading sections of ${activeCity?.name}…`}
            </div>
            <div className="text-[11px] text-muted-foreground">From OpenStreetMap</div>
          </div>
        </div>
      )}
      {loadErr && (
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 z-20 rounded-2xl bg-card/90 backdrop-blur-xl border border-destructive/40 shadow-2xl px-5 py-4 max-w-sm text-center">
          <div className="text-sm font-bold text-destructive mb-1">Could not load boundaries</div>
          <div className="text-[11px] text-muted-foreground">{loadErr}</div>
        </div>
      )}

      {/* Top control panel */}
      <div className="absolute top-4 left-1/2 -translate-x-1/2 z-10 w-[min(680px,calc(100%-2rem))]">
        <div
          className={`transition-all duration-300 ease-out overflow-hidden ${
            panelOpen ? "max-h-[400px] opacity-100" : "max-h-0 opacity-0 pointer-events-none"
          }`}
        >
          <div className="rounded-2xl bg-card/80 backdrop-blur-xl border border-white/10 shadow-2xl p-4 flex flex-wrap items-center gap-4">
            <div className="flex items-center gap-3">
              <Layers className="w-4 h-4 text-primary" />
              <div className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Filter
              </div>
              <div className="flex rounded-full bg-muted/40 p-1">
                <button
                  onClick={backToCities}
                  className={`px-4 py-1.5 text-xs font-bold rounded-full transition-all ${
                    view === "city"
                      ? "bg-primary text-primary-foreground shadow"
                      : "text-foreground/70 hover:text-foreground"
                  }`}
                >
                  City
                </button>
                <button
                  disabled={!activeCity}
                  className={`px-4 py-1.5 text-xs font-bold rounded-full transition-all ${
                    view === "section"
                      ? "bg-primary text-primary-foreground shadow"
                      : "text-foreground/40"
                  }`}
                >
                  Section {activeCity ? `· ${activeCity.name}` : ""}
                </button>
              </div>
            </div>

            <div className="ml-auto flex items-center gap-4">
              <div>
                <div className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold">
                  Total
                </div>
                <div className="text-sm font-extrabold">{fmt(total)}</div>
              </div>
              <div className="h-8 w-px bg-border" />
              <div>
                <div className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold">
                  Areas
                </div>
                <div className="text-sm font-extrabold">{areas.length}</div>
              </div>
              <div className="h-8 w-px bg-border" />
              <div className="flex items-center gap-1.5">
                {[
                  { c: "#22c55e", l: "Low" },
                  { c: "#eab308", l: "Med" },
                  { c: "#f97316", l: "High" },
                  { c: "#ef4444", l: "Top" },
                ].map((s) => (
                  <div key={s.l} className="flex items-center gap-1">
                    <span className="w-2.5 h-2.5 rounded-sm" style={{ background: s.c }} />
                    <span className="text-[10px] font-semibold">{s.l}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="flex justify-center mt-1 gap-2">
          {activeCity && (
            <button
              onClick={backToCities}
              className="pointer-events-auto rounded-full bg-card/85 backdrop-blur-xl border border-white/10 shadow-lg px-3 py-1.5 flex items-center gap-1.5 text-xs font-bold hover:bg-card transition"
            >
              <ArrowLeft className="w-3.5 h-3.5" /> Cities
            </button>
          )}
          <button
            onClick={() => setPanelOpen((v) => !v)}
            className="pointer-events-auto rounded-full bg-card/85 backdrop-blur-xl border border-white/10 shadow-lg px-4 py-1.5 flex items-center gap-1.5 text-xs font-bold hover:bg-card transition"
            aria-label={panelOpen ? "Hide controls" : "Show controls"}
          >
            {panelOpen ? (
              <>
                <ChevronUp className="w-3.5 h-3.5" /> Hide
              </>
            ) : (
              <>
                <ChevronDown className="w-3.5 h-3.5" /> Filters & legend
              </>
            )}
          </button>
        </div>
      </div>

      {/* Hover tooltip */}
      {hovered && tooltipPos && !selected && (
        <div
          className="absolute z-20 pointer-events-none rounded-xl bg-card/90 backdrop-blur-xl border border-white/10 shadow-xl px-3 py-2 text-xs"
          style={{ left: tooltipPos.x + 14, top: tooltipPos.y + 14 }}
        >
          <div className="font-bold">{hovered.name}</div>
          <div className="text-muted-foreground">
            {fmt(hovered.spending)} · {hovered.transactions} tx
          </div>
          {view === "city" && (
            <div className="text-[10px] text-primary mt-0.5">Click to view sections</div>
          )}
        </div>
      )}

      {/* Empty section state */}
      {view === "section" && !loadingSections && !sections.length && !loadErr && (
        <div className="absolute bottom-6 left-1/2 -translate-x-1/2 z-10 rounded-xl bg-card/85 backdrop-blur-xl border border-white/10 shadow-xl px-4 py-3 text-xs text-center max-w-xs">
          <div className="font-bold mb-1">No mapped sections</div>
          <div className="text-muted-foreground text-[11px]">
            OpenStreetMap doesn't have real polygon boundaries for sections inside{" "}
            {activeCity?.name} yet. We don't render synthetic shapes.
          </div>
        </div>
      )}

      {/* Detail panel */}
      {selected && (
        <div className="absolute right-4 top-20 z-10 w-80 rounded-2xl bg-card/85 backdrop-blur-xl border border-white/10 shadow-2xl p-4 pointer-events-auto animate-in fade-in slide-in-from-right-2">
          <div className="flex items-start justify-between mb-3">
            <div>
              <div className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold">
                {selected.level}
              </div>
              <div className="text-lg font-extrabold">{selected.name}</div>
            </div>
            <button
              onClick={() => setSelected(null)}
              className="text-muted-foreground hover:text-foreground text-lg leading-none px-2"
            >
              ×
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3 mb-4">
            <div className="rounded-xl bg-muted/40 p-3">
              <div className="text-[10px] uppercase text-muted-foreground font-semibold">
                Spending
              </div>
              <div className="text-base font-extrabold">{fmt(selected.spending)}</div>
            </div>
            <div className="rounded-xl bg-muted/40 p-3">
              <div className="text-[10px] uppercase text-muted-foreground font-semibold">
                Transactions
              </div>
              <div className="text-base font-extrabold">{selected.transactions}</div>
            </div>
            <div className="rounded-xl bg-muted/40 p-3 col-span-2">
              <div className="text-[10px] uppercase text-muted-foreground font-semibold">
                % of total
              </div>
              <div className="text-base font-extrabold">
                {total > 0 ? ((selected.spending / total) * 100).toFixed(1) : "0"}%
              </div>
            </div>
          </div>
          <div className="text-[10px] uppercase tracking-wider text-muted-foreground font-semibold mb-2">
            By category
          </div>
          <div className="space-y-1.5">
            {Object.entries(selected.categories).map(([cat, val]) => (
              <div key={cat}>
                <div className="flex items-center justify-between text-xs">
                  <span className="font-semibold">{cat}</span>
                  <span className="text-muted-foreground">{fmt(val)}</span>
                </div>
                <div className="h-1.5 rounded-full bg-muted/50 overflow-hidden mt-1">
                  <div
                    className="h-full rounded-full bg-primary"
                    style={{ width: `${(val / selected.spending) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
          {selected.level === "city" && (
            <button
              onClick={() => enterCity(selected)}
              className="mt-4 w-full rounded-xl bg-primary text-primary-foreground text-xs font-bold py-2.5 hover:opacity-90 transition"
            >
              Explore sections of {selected.name} →
            </button>
          )}
        </div>
      )}

      {/* Highest spending indicator */}
      {highest && arrow.targetVisible && (
        <div className="absolute top-20 left-1/2 -translate-x-1/2 z-20 pointer-events-none animate-in fade-in">
          <div className="rounded-full bg-card/85 backdrop-blur-xl border border-white/10 shadow-2xl px-4 py-2 flex items-center gap-2">
            <MapPin className="w-3.5 h-3.5 text-[#ef4444]" />
            <span className="text-xs font-bold">Highest spending: {highest.name}</span>
          </div>
        </div>
      )}
      {highest && !arrow.targetVisible && arrow.visible && (
        <div
          className="absolute z-20 pointer-events-none"
          style={{
            left: arrow.x,
            top: arrow.y,
            transform: "translate(-50%, -50%)",
            transition: "left 120ms ease-out, top 120ms ease-out",
            opacity: 0.4 + arrow.proximity * 0.6,
          }}
        >
          <div className="absolute inset-0 flex items-center justify-center">
            <div
              className="rounded-full border-2 border-[#ef4444]/70 animate-ping-radar"
              style={{
                width: arrowSize * 2.2,
                height: arrowSize * 2.2,
                animationDuration: "2.4s",
                opacity: pulseScale,
              }}
            />
          </div>
          <div
            className="absolute rounded-full blur-xl"
            style={{
              background: "radial-gradient(circle, rgba(239,68,68,0.6), transparent 70%)",
              width: arrowSize * 2.4,
              height: arrowSize * 2.4,
              left: "50%",
              top: "50%",
              transform: "translate(-50%, -50%)",
            }}
          />
          <div
            className="relative rounded-full bg-card/85 backdrop-blur-xl border border-[#ef4444]/60 shadow-[0_0_24px_rgba(239,68,68,0.5)] flex items-center justify-center"
            style={{
              width: arrowSize * 1.4,
              height: arrowSize * 1.4,
              animation: "indicator-pulse 1.8s ease-in-out infinite",
            }}
          >
            <Navigation2
              className="text-[#ef4444]"
              style={{
                width: arrowSize * 0.7,
                height: arrowSize * 0.7,
                transform: `rotate(${arrow.angle}deg)`,
                transition: "transform 120ms ease-out",
                fill: "currentColor",
              }}
            />
          </div>
          <div
            className="absolute left-1/2 -translate-x-1/2 mt-2 whitespace-nowrap rounded-full bg-card/85 backdrop-blur-xl border border-white/10 px-2.5 py-1 text-[10px] font-bold"
            style={{ top: "100%" }}
          >
            Highest spend → {highest.name}
          </div>
        </div>
      )}
    </div>
  );
}

const darkStyles: google.maps.MapTypeStyle[] = [
  { elementType: "geometry", stylers: [{ color: "#0f172a" }] },
  { elementType: "labels.text.stroke", stylers: [{ color: "#0f172a" }] },
  { elementType: "labels.text.fill", stylers: [{ color: "#94a3b8" }] },
  { featureType: "administrative.country", stylers: [{ visibility: "off" }] },
  { featureType: "poi", stylers: [{ visibility: "off" }] },
  { featureType: "transit", stylers: [{ visibility: "off" }] },
  { featureType: "road", elementType: "geometry", stylers: [{ color: "#1e293b" }] },
  { featureType: "road", elementType: "labels", stylers: [{ visibility: "off" }] },
  { featureType: "water", elementType: "geometry", stylers: [{ color: "#0b1220" }] },
  { featureType: "landscape", stylers: [{ color: "#111827" }] },
];
