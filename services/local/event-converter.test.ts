import { expect, test } from "@jest/globals";

import { CourseStatus, CourseType } from "@/services/shared/timetable";
import { convertICalEventToSharedCourse } from "./event-converter";
import { parseICalString } from "./parsers/ical-event-parser";

const base = {
  icalId: "calendar", icalTitle: "Calendrier", isADE: false, isHyperplanning: false,
  intelligentParsing: false, isSchool: false,
};
const event = {
  uid: "course", summary: "Mathématiques",
  dtstart: new Date("2026-11-24T08:00:00Z"), dtend: new Date("2026-11-24T09:00:00Z"),
};

test("only timed events from known educational sources are course credit candidates", () => {
  expect(convertICalEventToSharedCourse(event, base).studyCandidate).toBe(false);
  expect(convertICalEventToSharedCourse(event, { ...base, provider: "https://example.net/pronote.ics" }).studyCandidate).toBe(false);
  expect(convertICalEventToSharedCourse(event, { ...base, provider: "-//Index Education//PRONOTE//FR" })).toMatchObject({
    type: CourseType.ACTIVITY, studyCandidate: true,
  });
  expect(convertICalEventToSharedCourse(event, { ...base, isADE: true }).studyCandidate).toBe(true);
  expect(convertICalEventToSharedCourse({ ...event, allday: true }, { ...base, isSchool: true }).studyCandidate).toBe(false);
  expect(convertICalEventToSharedCourse({ ...event, dtend: undefined }, { ...base, isHyperplanning: true }).studyCandidate).toBe(false);
});

test("status CANCELLED survives parsing and educational calendar conversion", () => {
  const ics = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Index Education//PRONOTE//FR",
    "BEGIN:VEVENT", "UID:course", "DTSTART:20261124T080000Z", "DTEND:20261124T090000Z",
    "SUMMARY:Mathématiques", "STATUS:CANCELLED", "END:VEVENT", "END:VCALENDAR", "",
  ].join("\r\n");
  const { events, metadata } = parseICalString(ics);
  expect(convertICalEventToSharedCourse(events[0], { ...base, provider: metadata.prodId })).toMatchObject({
    status: CourseStatus.CANCELED, studyCandidate: true,
  });
});
