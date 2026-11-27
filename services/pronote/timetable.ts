import {
  parseTimetable,
  resource,
  resourcesFromIntervals,
  SessionHandle,
  TabLocation,
  TimetableClassActivity,
  TimetableClassDetention,
  TimetableClassLesson,
  timetableFromWeek,
  translateToWeekNumber,
} from "@blockshub/pawnote-lts";

import { Course, CourseDay, CourseResource, CourseStatus, CourseType, LessonSummary } from "@/services/shared/timetable";
import { error } from "@/utils/logger/logger";

export async function fetchPronoteWeekTimetable(
  session: SessionHandle,
  accountId: string,
  weekNumberRaw: number,
  date: Date
): Promise<CourseDay[]> {
  if (!session) {
    error("Session is undefined", "fetchPronoteTimetable");
  }

  const weekNumber = translateToWeekNumber(date, session.instance.firstMonday);
  const timetable = await timetableFromWeek(session, weekNumber);

  parseTimetable(session, timetable, {
    withSuperposedCanceledClasses: false,
    withCanceledClasses: true,
    withPlannedClasses: true,
  });

  const mappedCourses = mapCourses(accountId, timetable.classes);
  const dayMap: Record<number, Course[]> = {};

  for (const course of mappedCourses) {
    const localDay = new Date(course.from);
    localDay.setHours(0, 0, 0, 0);
    const dayKey = localDay.getTime();
    dayMap[dayKey] = dayMap[dayKey] || [];
    dayMap[dayKey].push(course);
  }

  for (const day in dayMap) {
    dayMap[day].sort((a, b) => a.from.getTime() - b.from.getTime());
  }

  const result = Object.entries(dayMap).map(([day, courses]) => ({
    date: new Date(Number(day)),
    courses
  }));
  return result;
}

const mapCourses = (
  accountId: string,
  courses: (
    | TimetableClassLesson
    | TimetableClassDetention
    | TimetableClassActivity
  )[]
): Course[] => {
  const courseList: Course[] = [];

  for (const c of courses) {
    const baseCourse = {
      from: c.startDate,
      to: c.endDate,
      backgroundColor: c.backgroundColor,
      additionalInfo: c.notes,
      createdByAccount: accountId
    }
    if (c.is === "lesson") {
      courseList.push({
        subject: c.subject!.name,
        id: c.id,
        type: CourseType.LESSON,
        room: c.classrooms.join(", "),
        teacher: c.teacherNames.join(", "),
        group: c.groupNames.join(", "),
        status: mapCourseStatus(c),
        customStatus: c.status,
        resourceId: c.lessonResourceID,
        ...baseCourse
      });
    } else if (c.is === "detention") {
      courseList.push({
        id: c.id,
        type: CourseType.DETENTION,
        subject: c.title ?? "Detention",
        room: c.classrooms.join(", "),
        ...baseCourse
      });
    } else if (c.is === "activity") {
      courseList.push({
        id: c.id,
        type: CourseType.ACTIVITY,
        subject: c.title,
        ...baseCourse
      });
    }
  }

  return courseList;
};

export async function fetchPronoteLessons(session: SessionHandle, accountId: string): Promise<LessonSummary[]> {
  if (!session.userResource?.tabs.has(TabLocation.Resources)) {
    throw new Error("Le cahier de textes est indisponible pour ce compte.");
  }

  const first = session.instance.firstDate ?? session.instance.firstMonday;
  const from = new Date(first);
  from.setHours(0, 0, 0, 0);
  const today = new Date();
  const last = session.instance.lastDate;
  const through = new Date(last instanceof Date && last < today ? last : today);
  through.setHours(23, 59, 59, 999);
  if (!Number.isFinite(from.getTime()) || through.getTime() - from.getTime() > 370 * 86400000) {
    throw new Error("Le calendrier scolaire fourni par PRONOTE est invalide.");
  }

  const lessons = new Map<string, LessonSummary>();
  while (from <= through) {
    const next = new Date(from);
    next.setDate(next.getDate() + 28);
    const end = new Date(Math.min(next.getTime() - 1, through.getTime()));
    for (const item of await resourcesFromIntervals(session, from, end)) {
      if (!item.id || !item.subject?.name) continue;
      lessons.set(item.id, {
        id: item.id,
        subject: item.subject.name,
        date: item.startDate,
        title: item.contents?.find(content => content.title)?.title,
        teachers: item.teachers ?? [],
        hasHomework: item.haveAssignment,
        createdByAccount: accountId,
      });
    }
    from.setTime(next.getTime());
  }

  return [...lessons.values()].sort((left, right) => right.date.getTime() - left.date.getTime());
}

export async function fetchPronoteCourseResources(
  session: SessionHandle, accountId: string, course: Course
): Promise<CourseResource[]> {
  if (!course.resourceId) return [];
  return fetchPronoteLesson(session, accountId, course.resourceId);
}

export async function fetchPronoteLesson(
  session: SessionHandle, accountId: string, id: string,
): Promise<CourseResource[]> {
  const tabs = session.userResource?.tabs;
  if (!id || (!tabs?.has(TabLocation.Resources) && !tabs?.has(TabLocation.Timetable))) {
    throw new Error("Cette leçon est indisponible pour ce compte.");
  }
  const { contents } = await resource(session, id);
  return contents.map(content => ({
    title: content.title,
    description: content.description,
    category: content.category,
    attachments: content.files.map(file => ({
      type: file.kind,
      name: file.name,
      url: file.url,
      createdByAccount: accountId,
    })),
  }));
}

const mapCourseStatus = (course: TimetableClassLesson): CourseStatus | undefined => {
  // eslint-disable-next-line default-case
  switch (course.status) {
  case "Cours annulé":
  case "Prof. absent":
  case "Classe absente":
  case "Prof./pers. absent":
  case "Sortie pédagogique":
    return CourseStatus.CANCELED;
  }

  if (course.test) {
    return CourseStatus.EVALUATED;
  }

  return undefined
};
