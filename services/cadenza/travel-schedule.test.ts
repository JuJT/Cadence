import { expect, test } from "@jest/globals";
import { selectTravelHome, travelTime, type TravelPreferences } from "./travel-schedule";

const preferences: TravelPreferences = {
  configured: true, enabled: true, arrivalBuffer: 10, weekA: "2026-10-19", cards: [],
  homes: [
    { id: "a", label: "A", week: "A", stop: { id: "stop-a", name: "Arrêt A" }, days: [1, 3, 5] },
    { id: "b", label: "B", week: "B", stop: { id: "stop-b", name: "Arrêt B" }, days: [1, 3, 5] },
  ],
};

test("alternates households at calendar week boundaries and honors a daily override", () => {
  const monday = new Date(2026, 9, 19, 8);
  expect(selectTravelHome(preferences, monday)?.id).toBe("a");
  expect(selectTravelHome(preferences, new Date(2026, 9, 26, 8))?.id).toBe("b");
  expect(selectTravelHome(preferences, new Date(2026, 9, 25, 8))).toBeUndefined();
  expect(selectTravelHome({ ...preferences, override: { date: "2026-10-19", homeId: "b" } }, monday)?.id).toBe("b");
});

test("calculates arrival before class, departure after class, and an independent no-class route", () => {
  const now = new Date(2026, 10, 26, 7);
  const courses = [{ start: +new Date(2026, 10, 26, 9), end: +new Date(2026, 10, 26, 10) },
    { start: +new Date(2026, 10, 26, 15), end: +new Date(2026, 10, 26, 16) }];
  expect(travelTime("outbound", courses, 10, now)).toEqual({ time: new Date(2026, 10, 26, 8, 50), arriveBy: true });
  expect(travelTime("return", courses, 10, now)).toEqual({ time: new Date(2026, 10, 26, 16), arriveBy: false });
  expect(travelTime("outbound", [], 10, now)).toEqual({ time: now, arriveBy: false });
});
