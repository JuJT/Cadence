import { Model, Q } from "@nozbe/watermelondb";
import { addDays } from "date-fns";
import { useEffect, useState } from "react";

import { getICalCourseById, getICalEventsForWeek } from "@/services/local/ical";
import { Course as SharedCourse,CourseDay as SharedCourseDay } from "@/services/shared/timetable"
import { generateId } from "@/utils/generateId";
import { warn } from "@/utils/logger/logger";

import { getDatabaseInstance, useDatabase } from "./DatabaseProvider"
import { mapCourseToShared } from "./mappers/course";
import Course from "./models/Timetable";
import { getDateRangeOfWeek } from "./useHomework";
import { safeWrite } from "./utils/safeTransaction";

export function getCourseRouteId(course: SharedCourse): string {
  if (course.createdByAccount.startsWith('ical_')) return course.id;
  return generateId(
    course.from.toISOString() +
      course.to.toISOString() +
      course.subject +
      course.teacher +
      course.createdByAccount
  );
}

export async function getCourseById(id: string): Promise<SharedCourse | undefined> {
  try {
    const courses = await getDatabaseInstance()
      .get<Course>('courses')
      .query(Q.where('courseId', id))
      .fetch();
    return courses[0] ? mapCourseToShared(courses[0]) : await getICalCourseById(id);
  } catch {
    return getICalCourseById(id);
  }
}

export function useTimetable(refresh = 0, weekNumber: number | number[] = 0, date: Date = new Date()) {
  const database = useDatabase();
  const [timetable, setTimetable] = useState<SharedCourseDay[]>([]);

  const weeks = Array.isArray(weekNumber) ? weekNumber : [weekNumber];
  // Create a stable key for the weeks array to use in dependency arrays
  const weeksKey = weeks.join(',');

  useEffect(() => {
    let cancelled = false;
    let requestId = 0;
    const year = date.getFullYear();

    const fetchTimetable = async () => {
      const currentRequest = ++requestId;
      const timetableFetched = await getCoursesFromCache(weeks, year);
      if (!cancelled && currentRequest === requestId) {
        setTimetable(timetableFetched);
      }
    };

    // Courses written by a sync (e.g. right after adding an account) must show up
    // without the caller having to bump `refresh`.
    const { start, end } = getWeeksRange(weeks, year);
    const courseSubscription = database
      .get('courses')
      .query(Q.where('from', Q.between(start.getTime(), end.getTime())))
      .observe()
      .subscribe(fetchTimetable);
    const icalSubscription = database.get('icals').query().observe().subscribe(fetchTimetable);

    return () => {
      cancelled = true;
      courseSubscription.unsubscribe();
      icalSubscription.unsubscribe();
    };
  }, [refresh, database, weeksKey, date.getFullYear()]);

  return timetable;
}

export async function addCourseDayToDatabase(courses: SharedCourseDay[], authoritative?: { weekStart: Date; serviceIds: string[] }) {
  const db = getDatabaseInstance();
  await safeWrite(
    db,
    async () => {
      const collection = db.get<Course>('courses');
      const operations: Model[] = [];
      const byDay = new Map<number, SharedCourse[]>();
      if (authoritative) {
        for (let offset = 0; offset < 7; offset++) byDay.set(addDays(authoritative.weekStart, offset).getTime(), []);
      }
      for (const day of courses) {
        for (const course of day.courses) {
          const timestamp = startOfLocalDay(course.from);
          const existing = byDay.get(timestamp) ?? [];
          existing.push(course);
          byDay.set(timestamp, existing);
        }
      }
      for (const [timestamp, dayCourses] of byDay) {
        const nextDay = addDays(new Date(timestamp), 1).getTime();
        const dbCourses = await collection
          .query(
            Q.where('from', Q.gte(timestamp)), Q.where('from', Q.lt(nextDay)),
          )
          .fetch();
        const incoming = new Map(dayCourses.map(item => [getCourseRouteId(item), item]));
        const refreshed = new Set([...(authoritative?.serviceIds ?? []), ...dayCourses.map(item => item.createdByAccount)]);
        const existing = new Map<string, Course>();
        for (const record of dbCourses) {
          if (!refreshed.has(record.createdByAccount)) continue;
          if (existing.has(record.courseId) || !incoming.has(record.courseId)) operations.push(record.prepareMarkAsDeleted());
          else existing.set(record.courseId, record);
        }
        for (const [id, item] of incoming) {
          const record = existing.get(id);
          if (!record) {
            operations.push(collection.prepareCreate(course => {
              Object.assign(course, {
                createdByAccount: item.createdByAccount,
                courseId: id,
                subject: item.subject,
                type: item.type,
                from: item.from.getTime(),
                to: item.to.getTime(),
                additionalInfo: item.additionalInfo,
                room: item.room,
                teacher: item.teacher,
                group: item.group,
                backgroundColor: item.backgroundColor,
                status: item.status,
                customStatus: item.customStatus,
                url: item.url,
                kidName: item.kidName,
              });
            }));
          } else {
            operations.push(record.prepareUpdate(course => {
              Object.assign(course, {
                subject: item.subject ?? course.subject,
                type: item.type ?? course.type,
                from: item.from.getTime(),
                to: item.to.getTime(),
                additionalInfo: item.additionalInfo ?? course.additionalInfo,
                room: item.room ?? course.room,
                teacher: item.teacher ?? course.teacher,
                group: item.group ?? course.group,
                backgroundColor: item.backgroundColor ?? course.backgroundColor,
                // A fresh status always wins: a course that is no longer
                // cancelled comes back without one.
                status: item.status,
                customStatus: item.customStatus,
                url: item.url ?? course.url,
                kidName: item.kidName ?? course.kidName,
              });
            }));
          }
        }
      }
      if (operations.length) await db.batch(operations);
    },
    15000,
    `add_timetable_${courses.length}_days`
  );
}

// Courses are grouped on the day they fall on in the device's timezone: grouping
// on the UTC date would file evening courses under the previous day west of UTC.
function startOfLocalDay(date: Date): number {
  const day = new Date(date);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

function getWeeksRange(weeks: number[], year: number): { start: Date; end: Date } {
  let start = new Date(8640000000000000);
  let end = new Date(-8640000000000000);

  for (const w of weeks) {
    const range = getDateRangeOfWeek(w, year);
    if (range.start < start) {start = range.start;}
    if (range.end > end) {end = range.end;}
  }

  return { start, end };
}

// Every useTimetable instance's observer fires at once on mount and on each sync write;
// concurrent calls for the same range share one query instead of each re-reading the DB.
const inFlightCourses = new Map<string, Promise<SharedCourseDay[]>>();

export function getCoursesFromCache(weeks: number[], year: number): Promise<SharedCourseDay[]> {
  const key = `${year}:${weeks.join(',')}`;
  let pending = inFlightCourses.get(key);
  if (!pending) {
    pending = readCoursesFromCache(weeks, year).finally(() => inFlightCourses.delete(key));
    inFlightCourses.set(key, pending);
  }
  return pending;
}

async function readCoursesFromCache(weeks: number[], year: number): Promise<SharedCourseDay[]> {
  try {
    const database = getDatabaseInstance();
    const { start: minStart, end: maxEnd } = getWeeksRange(weeks, year);

    const courses = await database
      .get<Course>('courses')
      .query(Q.where('from', Q.between(minStart.getTime(), maxEnd.getTime())))
      .fetch();

    const dayMap: Record<number, SharedCourse[]> = {};
    for (const course of courses) {
      const dayKey = startOfLocalDay(new Date(course.from));
      dayMap[dayKey] = dayMap[dayKey] || [];
      dayMap[dayKey].push(mapCourseToShared(course));
    }

    try {
      const icalEvents = await getICalEventsForWeek(minStart, maxEnd);
      for (const event of icalEvents) {
        const dayKey = startOfLocalDay(event.from);
        dayMap[dayKey] = dayMap[dayKey] || [];
        dayMap[dayKey].push(event);
      }
    } catch (icalError) {
      console.warn('Error loading iCal events:', icalError);
    }

    for (const day in dayMap) {
      dayMap[day].sort((a, b) => a.from.getTime() - b.from.getTime());
    }

    return Object.entries(dayMap).map(([day, courses]) => ({
      date: new Date(Number(day)),
      courses
    }));
  } catch (e) {
    warn(String(e));
    return [];
  }
}
