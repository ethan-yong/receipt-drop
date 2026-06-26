// Real-world boundary data for Selangor fetched from OpenStreetMap (Overpass API).
// Two granularity levels only:
//   - city     : admin_level=8 municipalities in Selangor (Petaling Jaya, Shah Alam, ...)
//   - section  : place=suburb/neighbourhood/quarter polygons (or admin_level 9/10)
//                inside a specific city. ONLY rendered when real polygon geometry exists.
//
// No synthesized geometry — if OSM has no polygon for a place, we simply skip it.

export type LatLng = { lat: number; lng: number };

export type Category = "Food" | "Shopping" | "Transport" | "Bills" | "Entertainment";

export type Level = "city" | "section";

export type Area = {
  id: string;
  name: string;
  level: Level;
  parentCityId?: string;
  center: LatLng;
  paths: LatLng[][];
  spending: number;
  transactions: number;
  categories: Record<Category, number>;
};

export const SELANGOR_CENTER: LatLng = { lat: 3.08, lng: 101.6 };

// Cities we want to surface (real OSM boundaries only).
export const CITY_NAMES = [
  "Petaling Jaya",
  "Subang Jaya",
  "Shah Alam",
  "Klang",
  "Puchong",
  "Kajang",
  "Ampang Jaya",
  "Sepang",
  "Selayang",
  "Gombak",
] as const;

// ---------- deterministic mock spending ----------
function hashString(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
function seededRand(seed: number) {
  let s = seed || 1;
  return () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}
function spendFor(name: string, base: number, txBase: number) {
  const r = seededRand(hashString(name));
  const spending = Math.round(base * (0.4 + r() * 1.6));
  const transactions = Math.round(txBase * (0.5 + r() * 1.5));
  const weights = [r(), r(), r(), r(), r()];
  const sum = weights.reduce((a, b) => a + b, 0);
  const cats: Category[] = ["Food", "Shopping", "Transport", "Bills", "Entertainment"];
  const categories = {} as Record<Category, number>;
  cats.forEach((c, i) => (categories[c] = Math.round((weights[i] / sum) * spending)));
  return { spending, transactions, categories };
}

// ---------- Overpass ----------
const OVERPASS_ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.openstreetmap.fr/api/interpreter",
];

async function overpass(query: string): Promise<any> {
  let lastErr: any;
  for (const url of OVERPASS_ENDPOINTS) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "data=" + encodeURIComponent(query),
      });
      if (!res.ok) throw new Error(`Overpass ${res.status}`);
      return await res.json();
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? new Error("Overpass failed");
}

const keyOf = (p: LatLng) => `${p.lat.toFixed(6)},${p.lng.toFixed(6)}`;

function ringsFromRelation(rel: any): LatLng[][] {
  if (!rel.members) return [];
  const segs: LatLng[][] = [];
  for (const m of rel.members) {
    if (m.type !== "way" || !m.geometry) continue;
    if (m.role !== "outer" && m.role !== "") continue;
    segs.push(m.geometry.map((p: any) => ({ lat: p.lat, lng: p.lon })));
  }
  const rings: LatLng[][] = [];
  while (segs.length) {
    let ring = segs.shift()!;
    let extended = true;
    while (extended && keyOf(ring[0]) !== keyOf(ring[ring.length - 1])) {
      extended = false;
      const tail = keyOf(ring[ring.length - 1]);
      for (let i = 0; i < segs.length; i++) {
        const s = segs[i];
        if (keyOf(s[0]) === tail) {
          ring = ring.concat(s.slice(1));
          segs.splice(i, 1);
          extended = true;
          break;
        }
        if (keyOf(s[s.length - 1]) === tail) {
          ring = ring.concat(s.slice().reverse().slice(1));
          segs.splice(i, 1);
          extended = true;
          break;
        }
      }
    }
    if (ring.length >= 4 && keyOf(ring[0]) === keyOf(ring[ring.length - 1])) {
      rings.push(ring);
    }
  }
  return rings;
}

function ringFromClosedWay(way: any): LatLng[][] {
  const g = way.geometry;
  if (!g || g.length < 4) return [];
  const first = g[0];
  const last = g[g.length - 1];
  if (first.lat !== last.lat || first.lon !== last.lon) return [];
  return [g.map((p: any) => ({ lat: p.lat, lng: p.lon }))];
}

function centroidOf(rings: LatLng[][]): LatLng {
  const ring = rings[0] ?? [];
  if (!ring.length) return SELANGOR_CENTER;
  let lat = 0,
    lng = 0;
  for (const p of ring) {
    lat += p.lat;
    lng += p.lng;
  }
  return { lat: lat / ring.length, lng: lng / ring.length };
}

// ---------- Cities ----------
type RawCity = { osmId: number; name: string; paths: LatLng[][]; center: LatLng };

const CITY_CACHE_KEY = "selangor-cities-v1";
const sectionCacheKey = (cityId: string) => `selangor-sections-${cityId}-v1`;

function readCache<T>(key: string): T | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}
function writeCache(key: string, data: unknown) {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(key, JSON.stringify(data));
  } catch {
    /* quota — ignore */
  }
}

async function fetchCitiesRaw(): Promise<RawCity[]> {
  const names = CITY_NAMES.map((n) => `"${n}"`).join("|");
  // admin_level 6 covers districts (Petaling, Hulu Langat...), 8 covers
  // city/municipality. Some Selangor cities are tagged at level 7. Match all
  // three within Selangor and filter by name.
  const q = `
    [out:json][timeout:60];
    area["name"="Selangor"]["admin_level"="4"]->.sel;
    (
      relation["boundary"="administrative"]["admin_level"~"6|7|8"]["name"~"^(${names.replace(/"/g, "")})$"](area.sel);
    );
    out geom;
  `;
  const data = await overpass(q);
  const byName = new Map<string, RawCity>();
  for (const el of data.elements ?? []) {
    if (el.type !== "relation") continue;
    const name = el.tags?.["name:en"] || el.tags?.name;
    if (!name || !CITY_NAMES.includes(name)) continue;
    const paths = ringsFromRelation(el);
    if (!paths.length) continue;
    // Prefer larger polygon when duplicates exist.
    const prev = byName.get(name);
    if (prev && prev.paths[0].length >= paths[0].length) continue;
    byName.set(name, {
      osmId: el.id,
      name,
      paths,
      center: centroidOf(paths),
    });
  }
  return Array.from(byName.values());
}

export async function loadCities(): Promise<Area[]> {
  const cached = readCache<RawCity[]>(CITY_CACHE_KEY);
  let raw = cached;
  if (!raw) {
    raw = await fetchCitiesRaw();
    writeCache(CITY_CACHE_KEY, raw);
  }
  return raw.map((c) => ({
    id: `city-${c.osmId}`,
    name: c.name,
    level: "city" as const,
    paths: c.paths,
    center: c.center,
    ...spendFor(c.name, 40000, 600),
  }));
}

// ---------- Sections (sub-city) ----------
type RawSection = {
  osmType: "relation" | "way";
  osmId: number;
  name: string;
  paths: LatLng[][];
  center: LatLng;
};

async function fetchSectionsRaw(cityOsmId: number): Promise<RawSection[]> {
  // Look only for entities that actually carry polygon geometry in OSM:
  //   - relations tagged place=suburb/neighbourhood/quarter/village
  //   - closed ways with the same place tags
  //   - admin_level 9/10 boundaries
  // Inside the given city's area.
  const q = `
    [out:json][timeout:60];
    rel(${cityOsmId});map_to_area->.c;
    (
      relation["place"~"^(suburb|neighbourhood|quarter|village)$"](area.c);
      way["place"~"^(suburb|neighbourhood|quarter|village)$"](area.c);
      relation["boundary"="administrative"]["admin_level"~"^(9|10)$"](area.c);
    );
    out geom;
  `;
  const data = await overpass(q);
  const out: RawSection[] = [];
  const seen = new Set<string>();
  for (const el of data.elements ?? []) {
    const name = el.tags?.["name:en"] || el.tags?.name;
    if (!name) continue;
    let paths: LatLng[][] = [];
    if (el.type === "relation") paths = ringsFromRelation(el);
    else if (el.type === "way") paths = ringFromClosedWay(el);
    if (!paths.length) continue; // skip anything without real polygon geometry
    const key = `${el.type}-${el.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      osmType: el.type,
      osmId: el.id,
      name,
      paths,
      center: centroidOf(paths),
    });
  }
  return out;
}

export async function loadSectionsForCity(city: Area): Promise<Area[]> {
  const cityOsmId = Number(city.id.replace("city-", ""));
  if (!Number.isFinite(cityOsmId)) return [];
  const cacheKey = sectionCacheKey(city.id);
  let raw = readCache<RawSection[]>(cacheKey);
  if (!raw) {
    raw = await fetchSectionsRaw(cityOsmId);
    writeCache(cacheKey, raw);
  }
  return raw.map((s) => ({
    id: `section-${s.osmType}-${s.osmId}`,
    name: s.name,
    level: "section" as const,
    parentCityId: city.id,
    paths: s.paths,
    center: s.center,
    ...spendFor(`${city.name}/${s.name}`, 6000, 80),
  }));
}

// ---------- helpers for the UI ----------
export function spendingColor(value: number, max: number): string {
  const t = max > 0 ? Math.min(1, value / max) : 0;
  if (t < 0.33) return "#22c55e";
  if (t < 0.6) return "#eab308";
  if (t < 0.85) return "#f97316";
  return "#ef4444";
}

export function totalSpending(areas: Area[]): number {
  return areas.reduce((a, b) => a + b.spending, 0);
}

export function boundsOfArea(area: Area): { sw: LatLng; ne: LatLng } {
  let minLat = Infinity,
    minLng = Infinity,
    maxLat = -Infinity,
    maxLng = -Infinity;
  for (const ring of area.paths) {
    for (const p of ring) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
  }
  return { sw: { lat: minLat, lng: minLng }, ne: { lat: maxLat, lng: maxLng } };
}
