export type StudyKind = "course" | "revision";

export type StudySubject = {
  id: string;
  name: string;
  color: string;
  aliases: string[];
  archived: boolean;
};

export type StudyTask = {
  id: string;
  title: string;
  routeId?: string;
  completed?: boolean;
};

export type StudySegment = { start: number; end?: number };
type StudyTaskSegment = StudySegment & { taskId: string };

export type StudySession = {
  id: string;
  subjectId: string;
  kind: StudyKind;
  title: string;
  notes: string;
  startedAt: number;
  endedAt?: number;
  segments: StudySegment[];
  task?: StudyTask;
  taskSegments: StudyTaskSegment[];
  courseId?: string;
};

type CourseCredit = StudySegment & {
  id: string; subjectId: string; end: number; seconds: number;
  timetableId?: string; source?: "papillon";
  timetableIds?: string[];
  profileId?: string;
  weekStart?: number;
  manuallyAdjusted?: boolean;
};

export type ScheduledStudyCourse = {
  id: string; subjectName: string; start: number; end: number; canceled: boolean;
  source?: "school" | "ical";
};

export type StudyState = {
  version: 1;
  subjects: StudySubject[];
  sessions: StudySession[];
  courses: CourseCredit[];
  tasks: Record<string, StudyTask>;
};

export const newStudyState = (): StudyState => ({
  version: 1,
  subjects: [
    { id: "math", name: "Mathématiques", color: "#258BFF", aliases: ["Maths", "Math"], archived: false },
    { id: "physics", name: "Physique-Chimie", color: "#7668F6", aliases: ["Physique", "PC"], archived: false },
    { id: "biology", name: "SVT", color: "#27835D", aliases: ["Sciences de la vie"], archived: false },
    { id: "history", name: "Histoire-Géographie", color: "#B46B26", aliases: ["Histoire", "Géographie"], archived: false },
    { id: "french", name: "Français", color: "#BC426C", aliases: ["FR"], archived: false },
    { id: "english", name: "Anglais", color: "#347D93", aliases: ["ANG", "English"], archived: false },
  ],
  sessions: [],
  courses: [],
  tasks: {},
});

function normalize(value: string) {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

export function findSubject(subjects: StudySubject[], name: string, includeArchived = false) {
  const key = normalize(name);
  return subjects.find(subject => (includeArchived || !subject.archived) && [subject.name, ...subject.aliases].some(alias => normalize(alias) === key));
}

export function getActiveSession(state: StudyState) {
  return state.sessions.find(session => session.endedAt === undefined);
}

export function reconcileScheduledStudyWeek(
  state: StudyState, profileId: string, weekStart: number,
  timetable: ScheduledStudyCourse[], newId: () => string,
): StudyState {
  if (!profileId || !Number.isFinite(weekStart)) return state;
  const week = studyRange("week", weekStart);
  const subjects = [...state.subjects];
  const slots = new Map<string, CourseCredit>();
  const legacySlots = new Map(state.courses.filter(credit => !credit.source)
    .map(credit => [courseKey(credit.subjectId, credit.start, credit.end), credit]));
  const ordered = [...timetable].sort((first, second) => Number(first.source === "ical") - Number(second.source === "ical"));
  for (const course of ordered) {
    if (!course.id || !course.subjectName.trim() || !Number.isFinite(course.start) ||
        !Number.isFinite(course.end) || course.end <= course.start ||
        course.start < week.start || course.start >= week.end) continue;
    const previousSubject = findSubject(subjects, course.subjectName, true);
    const subject = previousSubject ?? { id: newId(), name: course.subjectName.trim(), color: "#2776F8", aliases: [], archived: false };
    if (!previousSubject) subjects.push(subject);
    const key = courseKey(subject.id, course.start, course.end);
    const sameSlot = slots.get(key);
    if (sameSlot) {
      if (!sameSlot.timetableIds?.includes(course.id)) sameSlot.timetableIds?.push(course.id);
      continue;
    }
    const legacy = legacySlots.get(key);
    const plannedSeconds = (course.end - course.start) / 1000;
    const hasManualDuration = legacy && (legacy.manuallyAdjusted || (legacy.seconds > 0 && legacy.seconds !== plannedSeconds));
    slots.set(key, {
      id: course.id, subjectId: subject.id, start: course.start, end: course.end,
      seconds: course.canceled ? 0 : hasManualDuration ? legacy.seconds : plannedSeconds,
      timetableIds: [...new Set([course.id, ...(legacy ? [legacy.id] : [])])], source: "papillon", profileId, weekStart: week.start,
    });
  }
  const previous = state.courses.filter(course => course.profileId === profileId && course.weekStart === week.start);
  const replacement = [...slots.values()].sort((first, second) => first.start - second.start || first.id.localeCompare(second.id));
  if (JSON.stringify(previous) === JSON.stringify(replacement)) return state;
  const remaining = state.courses.filter(course => course.profileId !== profileId || course.weekStart !== week.start);
  return { ...state, subjects, courses: [...remaining, ...replacement] };
}

function courseKey(subjectId: string, start: number, end: number) {
  return subjectId + ":" + start + ":" + end;
}

export function isPaused(session: StudySession) {
  return session.endedAt === undefined && session.segments.at(-1)?.end !== undefined;
}

export function elapsedSeconds(session: StudySession, now = Date.now()) {
  return session.segments.reduce((sum, part) => sum + Math.max(0, (part.end ?? now) - part.start), 0) / 1000;
}

export function clockText(seconds: number) {
  const value = Math.floor(Math.max(0, seconds));
  return [Math.floor(value / 3600), Math.floor(value / 60) % 60, value % 60]
    .map(part => String(part).padStart(2, "0")).join(":");
}

export function durationText(seconds: number) {
  const minutes = Math.floor(Math.max(0, seconds) / 60);
  if (minutes < 1 && seconds > 0) return "< 1 min";
  if (minutes < 60) return minutes + " min";
  return Math.floor(minutes / 60) + " h " + String(minutes % 60).padStart(2, "0");
}

type Range = { start: number; end: number };

export function studyRange(period: "day" | "week" | "month", now = Date.now()): Range {
  const local = new Date(now);
  local.setHours(0, 0, 0, 0);
  if (period === "week") local.setDate(local.getDate() - ((local.getDay() + 6) % 7));
  if (period === "month") local.setDate(1);
  const start = local.getTime();
  if (period === "month") local.setMonth(local.getMonth() + 1);
  else local.setDate(local.getDate() + (period === "week" ? 7 : 1));
  return { start, end: local.getTime() };
}

export function getWeekDays(now = Date.now()): Range[] {
  const date = new Date(studyRange("week", now).start);
  return Array.from({ length: 7 }, () => {
    const start = date.getTime();
    date.setDate(date.getDate() + 1);
    return { start, end: date.getTime() };
  });
}

function overlap({ start, end }: StudySegment, range: Range, now: number) {
  return Math.max(0, Math.min(end ?? now, range.end, now) - Math.max(start, range.start));
}

export function studyTotals(state: StudyState, range: Range, now = Date.now(), profileId?: string) {
  let measuredCourseSeconds = 0;
  let scheduledCourseSeconds = 0;
  let revisionSeconds = 0;
  let sessionCount = 0;
  const bySubject = new Map<string, number>();
  const track = (subjectId: string, kind: StudyKind | "scheduled", seconds: number) => {
    if (seconds <= 0) return;
    if (kind === "course") measuredCourseSeconds += seconds;
    else if (kind === "scheduled") scheduledCourseSeconds += seconds;
    else revisionSeconds += seconds;
    bySubject.set(subjectId, (bySubject.get(subjectId) ?? 0) + seconds);
  };
  for (const session of state.sessions) {
    const seconds = session.segments.reduce((sum, part) => sum + overlap(part, range, now), 0) / 1000;
    if (seconds > 0) sessionCount += 1;
    track(session.subjectId, session.kind, seconds);
  }
  const measuredCourses = new Set(state.sessions.flatMap(session => session.courseId ? [session.courseId] : []));
  const currentSlots = new Set(state.courses
    .filter(credit => credit.profileId !== undefined && credit.profileId === profileId)
    .map(credit => courseKey(credit.subjectId, credit.start, credit.end)));
  for (const credit of state.courses) {
    if (credit.end > now || (credit.profileId && credit.profileId !== profileId) ||
        (!credit.source && currentSlots.has(courseKey(credit.subjectId, credit.start, credit.end))) ||
        measuredCourses.has(credit.id) || (credit.timetableId && measuredCourses.has(credit.timetableId)) ||
        credit.timetableIds?.some(id => measuredCourses.has(id))) continue;
    track(credit.subjectId, "scheduled", credit.seconds * overlap(credit, range, now) / (credit.end - credit.start));
  }
  return { courseSeconds: measuredCourseSeconds + scheduledCourseSeconds, measuredCourseSeconds, scheduledCourseSeconds,
    revisionSeconds, sessionCount, bySubject };
}

function stopLastSegment<T extends StudySegment>(segments: T[], now: number) {
  const last = segments.at(-1);
  return !last || last.end !== undefined ? segments : [
    ...segments.slice(0, -1), { ...last, end: Math.max(now, last.start) },
  ];
}

export function changeSessionTimer(session: StudySession, action: "pause" | "resume" | "finish", now = Date.now()): StudySession {
  if (session.endedAt !== undefined) return session;
  const last = session.segments.at(-1);
  const time = Math.max(now, last?.end ?? last?.start ?? session.startedAt);
  if (action === "resume") {
    if (!isPaused(session)) return session;
    return {
      ...session,
      segments: [...session.segments, { start: time }],
      taskSegments: session.task ? [...session.taskSegments, { taskId: session.task.id, start: time }] : session.taskSegments,
    };
  }
  return {
    ...session,
    segments: stopLastSegment(session.segments, time),
    taskSegments: stopLastSegment(session.taskSegments, time),
    endedAt: action === "finish" ? time : undefined,
  };
}

export function setSessionTask(session: StudySession, task?: StudyTask, now = Date.now()): StudySession {
  if (session.endedAt !== undefined) return session;
  if (session.task?.id === task?.id) return { ...session, task };
  const lastTask = session.taskSegments.at(-1);
  const time = Math.max(now, lastTask?.end ?? lastTask?.start ?? session.segments.at(-1)?.start ?? session.startedAt);
  const taskSegments = stopLastSegment(session.taskSegments, time);
  return {
    ...session,
    task,
    taskSegments: task && !isPaused(session) ? [...taskSegments, { taskId: task.id, start: time }] : taskSegments,
  };
}

type Properties = Record<string, unknown>;

function object(value: unknown): Properties {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Properties : {};
}

function objects(value: unknown): Properties[] {
  return Array.isArray(value) ? value.map(object) : [];
}

function string(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function optionalDate(value: unknown): number | undefined {
  if (value === undefined || value === null) return undefined;
  const date = typeof value === "number" ? value : Date.parse(string(value));
  if (!Number.isFinite(date)) throw new Error("La sauvegarde contient une date invalide.");
  return date;
}

function requiredDate(value: unknown): number {
  const date = optionalDate(value);
  if (date === undefined) throw new Error("Une date manque dans la sauvegarde.");
  return date;
}

function segment(source: Properties): StudySegment {
  return { start: requiredDate(source.start), end: optionalDate(source.end) };
}

function verifyStudyState(state: StudyState) {
  const subjects = new Set(state.subjects.map(subject => subject.id));
  const ids = new Set(state.sessions.map(session => session.id));
  if (subjects.size !== state.subjects.length || ids.size !== state.sessions.length ||
      !state.subjects.every(subject => typeof subject.id === "string" && subject.id && typeof subject.name === "string" &&
        subject.name.trim() && Array.isArray(subject.aliases) && subject.aliases.every(alias => typeof alias === "string")) ||
      state.sessions.filter(session => session.endedAt === undefined).length > 1) {
    throw new Error("Les matières ou séances de la sauvegarde sont incohérentes.");
  }
  for (const session of state.sessions) {
    if (!session.id || !subjects.has(session.subjectId) || (session.kind !== "revision" && session.kind !== "course") ||
        !Number.isFinite(session.startedAt) || !Array.isArray(session.segments) || !session.segments.length ||
        !Array.isArray(session.taskSegments) || typeof session.title !== "string" || typeof session.notes !== "string" ||
        (session.endedAt !== undefined && !Number.isFinite(session.endedAt))) {
      throw new Error("Une séance de la sauvegarde est incomplète.");
    }
    let previousEnd = session.startedAt;
    for (const [index, part] of session.segments.entries()) {
      if (!Number.isFinite(part.start) || part.start < previousEnd ||
        (part.end === undefined
          ? index !== session.segments.length - 1 || session.endedAt !== undefined
          : !Number.isFinite(part.end) || part.end < part.start || (session.endedAt !== undefined && part.end > session.endedAt))) {
        throw new Error("Les périodes d’une séance se chevauchent ou sont invalides.");
      }
      previousEnd = part.end ?? part.start;
    }
  }
  if (!state.courses.every(credit => credit.id && subjects.has(credit.subjectId) && Number.isFinite(credit.start) &&
      Number.isFinite(credit.end) && credit.end > credit.start && Number.isFinite(credit.seconds) && credit.seconds >= 0)) {
    throw new Error("Des heures de cours sont invalides dans la sauvegarde.");
  }
  return state;
}

export function parseStudyBackup(json: string, now = Date.now()): StudyState {
  const input = object(JSON.parse(json));
  if (!Array.isArray(input.subjects) || !Array.isArray(input.sessions)) {
    throw new Error("Ce fichier ne contient pas de sauvegarde Cadenza.");
  }
  if (input.version === 1 && Array.isArray(input.courses) && input.tasks) {
    const state = verifyStudyState(input as StudyState);
    // Build 10 saved derived timetable rows without a profile. They cannot be
    // trusted after a profile change and are recomputed from complete weeks.
    return { ...state, courses: state.courses.filter(credit => !credit.source || (credit.profileId && Number.isFinite(credit.weekStart))) };
  }
  if (input.schemaVersion !== 1 && input.schemaVersion !== 2 && input.schemaVersion !== 3) {
    throw new Error("Cette version de sauvegarde Cadenza est inconnue.");
  }

  const tasks = Object.fromEntries(objects(input.homework).flatMap(item => {
    const source = object(item.source);
    const id = string(item.localID) || string(source.uid);
    if (!id) return [];
    return [[id, {
      id,
      title: string(source.description).replace(/<[^>]*>/g, " ").trim() || string(source.subject, "Devoir"),
      completed: typeof item.localCompletionOverride === "boolean" ? item.localCompletionOverride : source.done === true,
    } satisfies StudyTask]];
  }));

  const backupSessions = objects(input.sessions);
  if (input.schemaVersion === 1 && input.activeSession) {
    const active = object(input.activeSession);
    const segments = objects(active.completedSegments);
    if (active.currentSegmentStart && active.isPaused !== true) segments.push({ start: active.currentSegmentStart });
    if (segments.length === 0) {
      segments.push({ start: active.startedAt, end: active.isPaused === true ? active.startedAt : undefined });
    }
    backupSessions.push({ ...active, activeSegments: segments });
  }

  const sessions = backupSessions.map((source): StudySession => {
    const taskId = string(source.activeHomeworkID);
    return {
      id: string(source.id),
      subjectId: string(source.subjectID) || string(source.subjectId),
      kind: string(source.kind) as StudyKind,
      title: string(source.topic),
      notes: string(source.notes),
      startedAt: requiredDate(source.startedAt),
      endedAt: optionalDate(source.endedAt),
      segments: objects(source.activeSegments).map(segment),
      task: taskId ? tasks[taskId] ?? { id: taskId, title: "Devoir" } : undefined,
      taskSegments: objects(source.homeworkWorkSegments).map(part => ({ ...segment(part), taskId: string(part.homeworkID) })),
      courseId: string(source.linkedOccurrenceID) || undefined,
    };
  });

  const subjectValues = objects(input.subjects)
    .sort((first, second) => Number(first.position ?? 0) - Number(second.position ?? 0));
  const subjects = subjectValues.map((source): StudySubject => ({
    id: string(source.id), name: string(source.name), color: string(source.colorHex, "#2776F8"),
    aliases: Array.isArray(source.aliases) ? source.aliases.filter((alias): alias is string => typeof alias === "string") : [],
    archived: source.isArchived === true,
  }));
  const subjectIds = new Set(subjects.map(subject => subject.id));
  const sessionIds = new Set(sessions.map(session => session.id));
  const settings = object(input.settings);
  const courses: CourseCredit[] = objects(input.occurrences).flatMap(course => {
    const subjectId = string(course.subjectID);
    const school = object(course.school);
    const status = string(course.localStatusOverride) || (course.status === "needsReview" ? string(course.previousStatus) : string(course.status));
    if (!subjectIds.has(subjectId) || course.supersededByOccurrenceID) return [];
    const start = requiredDate(course.start);
    const end = requiredDate(course.end);
    const autoCredit = course.sourceMissing !== true && (course.school || settings.autoCreditCourses !== false) &&
      (status === "scheduled" || status === "inProgressScheduled");
    if (end <= start || end > now) return [];
    const excluded = sessionIds.has(string(course.linkedSessionID)) ||
      ((school.canceled || school.exempted) && status !== "confirmed") ||
      (status !== "estimated" && status !== "confirmed" && !autoCredit);
    const confirmed = course.confirmedSeconds;
    const seconds = status === "confirmed" && typeof confirmed === "number" && Number.isFinite(confirmed)
      ? Math.max(0, confirmed) : (end - start) / 1000;
    return [{ id: string(course.id), subjectId, start, end, seconds: excluded ? 0 : seconds,
      manuallyAdjusted: status === "confirmed" && !excluded }];
  });

  return verifyStudyState({ version: 1, subjects, sessions, courses, tasks });
}
