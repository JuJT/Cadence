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

export interface LessonChange {
  text: string;
  time: number;
  before?: number;
  lessonId: string;
}

function clean(value: string) {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().trim().replace(/[^\p{L}\p{N}]+/gu, " ");
}

function visibleKey(lesson: AlertLesson) {
  return [clean(lesson.subject), lesson.start, lesson.end, clean(lesson.room), clean(lesson.teacher), clean(lesson.status), lesson.cancelled].join("|");
}

export function futureLessons(days: CourseDay[], now: number): AlertLesson[] {
  const unique = new Map<string, AlertLesson>();
  for (const course of days.flatMap(day => day.courses)) {
    const start = course.from.getTime();
    const end = course.to.getTime();
    if (course.type !== CourseType.LESSON || !course.id || !Number.isFinite(start) || !Number.isFinite(end) || end <= now || start >= end) continue;
    const lesson = { id: course.id, subject: course.subject.slice(0, 100), start, end,
      room: (course.room ?? "").slice(0, 160), teacher: (course.teacher ?? "").slice(0, 160),
      status: (course.customStatus ?? "").slice(0, 160), cancelled: course.status === CourseStatus.CANCELED };
    unique.set(visibleKey(lesson), lesson);
  }
  return [...unique.values()].sort((a, b) => a.start - b.start || a.id.localeCompare(b.id));
}

export function changeAlerts(previous: AlertLesson[], current: AlertLesson[], now: number): LessonChange[] {
  const before = new Map(previous.filter(lesson => lesson.end > now).map(lesson => [visibleKey(lesson), lesson]));
  const after = new Map(current.filter(lesson => lesson.end > now).map(lesson => [visibleKey(lesson), lesson]));
  for (const key of after.keys()) {
    if (before.delete(key)) after.delete(key);
  }
  const changes: LessonChange[] = [];
  const pairs: { old?: AlertLesson; lesson: AlertLesson }[] = [];
  const match = (same: (old: AlertLesson, next: AlertLesson) => boolean) => {
    for (const [newKey, lesson] of after) {
      const candidates = [...before].filter(([, old]) => same(old, lesson));
      if (candidates.length !== 1) continue;
      const [oldKey, old] = candidates[0];
      if ([...after.values()].filter(next => same(old, next)).length !== 1) continue;
      pairs.push({ old, lesson });
      before.delete(oldKey);
      after.delete(newKey);
    }
  };
  match((old, next) => old.id === next.id && clean(old.subject) === clean(next.subject));
  match((old, next) => old.start === next.start && clean(old.subject) === clean(next.subject));
  match((old, next) => !old.cancelled && !next.cancelled && !!clean(old.teacher) &&
    clean(old.subject) === clean(next.subject) && clean(old.teacher) === clean(next.teacher) &&
    Math.abs(next.start - old.start) <= 48 * 60 * 60 * 1000);
  for (const lesson of after.values()) pairs.push({ lesson });
  for (const { old, lesson } of pairs) {
    let reason: string | undefined;
    if (lesson.cancelled && (!old?.cancelled || old.status !== lesson.status)) {
      reason = /prof.*absen/i.test(lesson.status) ? "professeur absent" : "cours annulé";
    } else if (!old && !lesson.cancelled) {
      reason = "cours ajouté";
    } else if (old && (lesson.start !== old.start || lesson.end !== old.end)) {
      reason = "horaire modifié";
    } else if (old && visibleKey(old) !== visibleKey(lesson)) {
      reason = "cours modifié";
    }
    if (reason) changes.push({ text: `${lesson.subject} · ${reason}`, time: lesson.start, lessonId: lesson.id,
      before: old && old.start !== lesson.start ? old.start : undefined });
  }
  for (const old of before.values()) {
    if (old.start >= now && !old.cancelled) {
      changes.push({ text: `${old.subject} · cours retiré`, time: old.start, lessonId: old.id });
    }
  }
  return changes.sort((a, b) => a.time - b.time || a.text.localeCompare(b.text));
}
