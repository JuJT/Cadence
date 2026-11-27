import { differenceInCalendarWeeks, format } from "date-fns";

import type { TransitStop } from "./transit";

export type TransitHome = {
  id: string;
  label: string;
  stop: TransitStop;
  days: number[];
  week: "all" | "A" | "B";
};

export type TransitCard = { id: string; name: string; image: string };
export type TravelPreferences = {
  configured: boolean;
  enabled: boolean;
  school?: TransitStop;
  homes: TransitHome[];
  cards: TransitCard[];
  weekA: string;
  arrivalBuffer: number;
  override?: { date: string; homeId: string };
};

export function dayKey(date: Date) {
  return format(date, "yyyy-MM-dd");
}

export function selectTravelHome(config: TravelPreferences, date: Date): TransitHome | undefined {
  if (config.override?.date === dayKey(date)) {
    const selected = config.homes.find(home => home.id === config.override?.homeId);
    if (selected) return selected;
  }
  const week = differenceInCalendarWeeks(date, new Date(`${config.weekA}T12:00:00`), { weekStartsOn: 1 }) % 2 === 0 ? "A" : "B";
  const available = config.homes.filter(home => home.days.includes(date.getDay()));
  return available.find(home => home.week === week) ?? available.find(home => home.week === "all");
}

export function travelTime(
  direction: "outbound" | "return",
  courses: { start: number; end: number }[],
  bufferMinutes: number,
  now: Date,
): { time: Date; arriveBy: boolean } {
  const sorted = courses.filter(course => Number.isFinite(course.start) && course.end > course.start)
    .sort((a, b) => a.start - b.start);
  if (!sorted.length) return { time: now, arriveBy: false };
  if (direction === "return") {
    return { time: new Date(Math.max(now.getTime(), ...sorted.map(course => course.end))), arriveBy: false };
  }
  const first = sorted.find(course => course.start - bufferMinutes * 60_000 > now.getTime());
  return first ? { time: new Date(first.start - bufferMinutes * 60_000), arriveBy: true } : { time: now, arriveBy: false };
}
