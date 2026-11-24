import { CourseStatus, CourseType, type CourseDay } from "@/services/shared/timetable";

export interface AlertLesson {
  id: string;
  subject: string;
  start: number;
  end: number;
  room: string;
  teacher: string;
  status: string;
  cancelled: boolean;
}

interface LessonChange {
  text: string;
  time: number;
}

export function futureLessons(days: CourseDay[], now: number): AlertLesson[] {
  const unique = new Map<string, AlertLesson>();
  for (const course of days.flatMap(day => day.courses)) {
    const start = course.from.getTime();
    const end = course.to.getTime();
    if (course.type !== CourseType.LESSON || !course.id || !Number.isFinite(start) || !Number.isFinite(end) || end <= now || start >= end) continue;
    unique.set(course.id, { id: course.id, subject: course.subject.slice(0, 100), start, end,
      room: (course.room ?? "").slice(0, 160), teacher: (course.teacher ?? "").slice(0, 160),
      status: (course.customStatus ?? "").slice(0, 160), cancelled: course.status === CourseStatus.CANCELED });
  }
  return [...unique.values()].sort((a, b) => a.start - b.start || a.id.localeCompare(b.id));
}

export function changeAlerts(previous: AlertLesson[], current: AlertLesson[], now: number): LessonChange[] {
  const before = new Map(previous.map(lesson => [lesson.id, lesson]));
  const present = new Set(current.map(lesson => lesson.id));
  const changes: LessonChange[] = [];
  for (const lesson of current) {
    const old = before.get(lesson.id);
    if (lesson.end <= now) continue;
    let reason: string | undefined;
    if (lesson.cancelled && (!old?.cancelled || old.status !== lesson.status)) {
      reason = /prof.*absen/i.test(lesson.status) ? "professeur absent" : "cours annulé";
    } else if (!old && !lesson.cancelled) {
      reason = "cours ajouté";
    } else if (old && (lesson.start !== old.start || lesson.end !== old.end)) {
      reason = "horaire modifié";
    } else if (old && (lesson.cancelled !== old.cancelled || lesson.room !== old.room || lesson.teacher !== old.teacher || lesson.subject !== old.subject || lesson.status !== old.status)) {
      reason = "cours modifié";
    }
    if (reason) changes.push({ text: `${lesson.subject} · ${reason}`, time: lesson.start });
  }
  for (const old of previous) {
    if (old.start >= now && !old.cancelled && !present.has(old.id)) {
      changes.push({ text: `${old.subject} · cours retiré`, time: old.start });
    }
  }
  return changes.sort((a, b) => a.time - b.time || a.text.localeCompare(b.text));
}
