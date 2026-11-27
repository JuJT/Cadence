const api = "https://api.transitous.org/api/v1/";
const contact = "Cadenza/0.9.0 (https://github.com/JuJT/Cadence)";

export type TransitStop = { id: string; name: string; area?: string; tz?: string };
export type TransitDeparture = { id: string; line: string; mode: string; headsign: string; time: string; scheduled?: string; live: boolean; cancelled: boolean };
export type TransitLeg = { mode: string; line: string; from: string; to: string; departure: string; arrival: string; direction?: string; live: boolean; cancelled: boolean };
export type TransitJourney = { id: string; departure: string; arrival: string; transfers: number; legs: TransitLeg[] };
export type TransitNetwork = { id: string; name: string; area: string; url: string; realtimePublished: boolean };

type RawStop = { id?: string; type?: string; name?: string; country?: string; tz?: string; areas?: { name: string; default?: boolean; adminLevel?: number }[] };
type RawDeparture = {
  tripId?: string; mode?: string; headsign?: string; routeShortName?: string; displayName?: string; realTime?: boolean;
  cancelled?: boolean; tripCancelled?: boolean;
  place?: { departure?: string; scheduledDeparture?: string; cancelled?: boolean; departureTimestampReason?: string };
};
type RawLeg = {
  mode: string; routeShortName?: string; headsign?: string; from?: { name?: string; departureTimestampReason?: string };
  to?: { name?: string }; startTime: string; endTime: string; realTime?: boolean; cancelled?: boolean;
};
type RawJourney = { id?: string; startTime: string; endTime: string; transfers?: number; legs: RawLeg[] };
type RawNetwork = { id: string | number; title: string; type: string; page_url: string; covered_area?: { nom: string }[]; resources?: { format: string; is_available?: boolean }[] };

type CacheEntry = { expires: number; request: Promise<unknown> };
const cache = new Map<string, CacheEntry>();

async function request<T>(url: string, validFor: number): Promise<T> {
  const now = Date.now();
  const existing = cache.get(url);
  if (existing && existing.expires > now) return existing.request as Promise<T>;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  const pending = (async () => {
    const response = await fetch(url, { signal: controller.signal, headers: { "User-Agent": contact, Accept: "application/json" } });
    if (!response.ok) throw new Error(response.status === 429 ? "Le service est très sollicité. Réessaie dans un instant." : "Les données de transport sont indisponibles.");
    return await response.json() as T;
  })().catch(error => {
    if (cache.get(url)?.request === pending) cache.delete(url);
    throw error;
  }).finally(() => clearTimeout(timeout));
  for (const [key, item] of cache) if (item.expires <= now) cache.delete(key);
  if (cache.size >= 64) cache.delete(cache.keys().next().value!);
  cache.set(url, { expires: now + validFor, request: pending });
  return pending;
}

function endpoint(path: string, parameters: Record<string, string>) {
  return api + path + "?" + new URLSearchParams(parameters).toString();
}

const frenchRegions = new Set(["FR", "GP", "MQ", "GF", "RE", "YT", "PM", "BL", "MF", "WF", "PF", "NC", "TF"]);

export async function findTransitStops(text: string, near?: { latitude: number; longitude: number }): Promise<TransitStop[]> {
  const query = text.trim().slice(0, 110);
  if (!near && query.length < 2) return [];
  const hits = near
    ? await request<RawStop[]>(endpoint("reverse-geocode", { place: `${near.latitude.toFixed(3)},${near.longitude.toFixed(3)}`, type: "STOP", language: "fr" }), 180_000)
    : await request<RawStop[]>(endpoint("geocode", { text: query, type: "STOP", language: "fr" }), 180_000);
  return hits.filter(stop => stop.type === "STOP" && stop.id && stop.name && (!stop.country || frenchRegions.has(stop.country)))
    .slice(0, 16).map(stop => ({ id: stop.id!, name: stop.name!, tz: stop.tz,
      area: stop.areas?.find(area => area.default)?.name ?? stop.areas?.find(area => area.adminLevel === 8)?.name }));
}

export async function nextTransitDepartures(stop: TransitStop): Promise<TransitDeparture[]> {
  const data = await request<{ stopTimes?: RawDeparture[] }>(endpoint("stoptimes", { stopId: stop.id, n: "8" }), 60_000);
  return (data.stopTimes ?? []).flatMap((item, index) => {
    const time = item.place?.departure ?? item.place?.scheduledDeparture;
    if (!time || !Number.isFinite(Date.parse(time))) return [];
    return [{ id: `${item.tripId ?? index}/${time}`, line: item.routeShortName || item.displayName || "Transport",
      mode: item.mode ?? "TRANSIT", headsign: item.headsign ?? "", time, scheduled: item.place?.scheduledDeparture,
      live: item.realTime === true && item.place?.departureTimestampReason !== "NO_RT_DATA",
      cancelled: !!(item.cancelled || item.tripCancelled || item.place?.cancelled) }];
  });
}

export async function planTransitJourney(from: TransitStop, to: TransitStop, time: Date, arriveBy: boolean): Promise<TransitJourney[]> {
  const rounded = new Date(Math.floor(time.getTime() / 60_000) * 60_000);
  const data = await request<{ itineraries?: RawJourney[] }>(endpoint("plan", {
    fromPlace: from.id, toPlace: to.id, time: rounded.toISOString(), arriveBy: String(arriveBy), numItineraries: "3",
  }), 300_000);
  return (data.itineraries ?? []).flatMap((item, index) => {
    if (!Number.isFinite(Date.parse(item.startTime)) || !Number.isFinite(Date.parse(item.endTime)) || !item.legs?.length) return [];
    return [{ id: item.id ?? `${item.startTime}/${index}`, departure: item.startTime, arrival: item.endTime, transfers: item.transfers ?? 0,
      legs: item.legs.map(leg => ({ mode: leg.mode, line: leg.routeShortName ?? "", from: leg.from?.name ?? from.name,
        to: leg.to?.name ?? to.name, departure: leg.startTime, arrival: leg.endTime, direction: leg.headsign,
        live: leg.realTime === true && leg.from?.departureTimestampReason !== "NO_RT_DATA", cancelled: !!leg.cancelled })) }];
  });
}

export async function getFrenchTransitNetworks(): Promise<TransitNetwork[]> {
  const data = await request<RawNetwork[]>("https://transport.data.gouv.fr/api/datasets", 12 * 60 * 60 * 1000);
  return data.filter(item => item.type === "public-transit" && item.resources?.some(feed =>
    feed.is_available !== false && /^(GTFS|NETEX)$/i.test(feed.format)))
    .map(item => ({ id: String(item.id), name: item.title, area: item.covered_area?.map(area => area.nom).join(", ") ?? "France",
      url: item.page_url, realtimePublished: item.resources?.some(feed => feed.is_available !== false && /GTFS.?RT|SIRI/i.test(feed.format)) ?? false }))
    .sort((a, b) => a.name.localeCompare(b.name, "fr"));
}
