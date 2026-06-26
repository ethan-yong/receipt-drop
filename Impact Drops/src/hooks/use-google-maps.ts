/// <reference types="google.maps" />
import { useEffect, useState } from "react";

const TRACKING_ID = import.meta.env.VITE_LOVABLE_CONNECTOR_GOOGLE_MAPS_TRACKING_ID;
const BROWSER_KEY = import.meta.env.VITE_LOVABLE_CONNECTOR_GOOGLE_MAPS_BROWSER_KEY;

declare global {
  interface Window {
    __gmapsPromise?: Promise<typeof google>;
    __gmapsInit?: () => void;
  }
}

function loadGoogleMaps(): Promise<typeof google> {
  if (typeof window === "undefined") return Promise.reject(new Error("SSR"));
  if (window.__gmapsPromise) return window.__gmapsPromise;
  window.__gmapsPromise = new Promise((resolve, reject) => {
    if ((window as any).google?.maps) {
      resolve((window as any).google);
      return;
    }
    if (!BROWSER_KEY) {
      reject(new Error("Missing VITE_LOVABLE_CONNECTOR_GOOGLE_MAPS_BROWSER_KEY"));
      return;
    }
    window.__gmapsInit = () => resolve((window as any).google);
    const s = document.createElement("script");
    const params = new URLSearchParams({
      key: BROWSER_KEY,
      v: "weekly",
      loading: "async",
      callback: "__gmapsInit",
    });
    if (TRACKING_ID) params.set("channel", TRACKING_ID);
    s.src = `https://maps.googleapis.com/maps/api/js?${params.toString()}`;
    s.async = true;
    s.defer = true;
    s.onerror = () => reject(new Error("Failed to load Google Maps"));
    document.head.appendChild(s);
  });
  return window.__gmapsPromise;
}

export function useGoogleMaps() {
  const [api, setApi] = useState<typeof google | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let mounted = true;
    loadGoogleMaps()
      .then((g) => mounted && setApi(g))
      .catch((e) => mounted && setError(e.message));
    return () => {
      mounted = false;
    };
  }, []);
  return { api, error };
}
