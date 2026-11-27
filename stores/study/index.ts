import AsyncStorage from "@react-native-async-storage/async-storage";
import { create } from "zustand";

import { readLegacyStudyState, syncStudySurface } from "@/modules/cadenza-study";
import { useAccountStore } from "@/stores/account";
import uuid from "@/utils/uuid/uuid";

import {
  changeSessionTimer,
  elapsedSeconds,
  findSubject,
  getActiveSession,
  getWeekDays,
  isPaused,
  newStudyState,
  parseStudyBackup,
  reconcileScheduledStudyWeek,
  setSessionTask,
  studyRange,
  studyTotals,
  type StudyKind,
  type ScheduledStudyCourse,
  type StudySession,
  type StudyState,
  type StudyTask,
} from "./model";

const storageKey = "cadenza.study.state.v1";

type Store = {
  data: StudyState;
  status: "loading" | "ready" | "error";
  error?: string;
};

export const useStudyStore = create<Store>(() => ({ data: newStudyState(), status: "loading" }));

let loading: Promise<void> | undefined;
let writes: Promise<unknown> = Promise.resolve();
let surfaceUpdates: Promise<void> = Promise.resolve();

function publishSurface(state: StudyState) {
  const now = Date.now();
  const profileId = useAccountStore.getState().lastUsedAccount ?? undefined;
  const active = getActiveSession(state);
  const elapsed = active ? Math.floor(elapsedSeconds(active, now)) : 0;
  const today = studyTotals(state, studyRange("day", now), now, profileId);
  const week = studyTotals(state, studyRange("week", now), now, profileId);
  const top = [...week.bySubject].sort(([, first], [, second]) => second - first)[0]?.[0];
  const snapshot = {
    activeSession: active ? {
      id: active.id,
      title: state.subjects.find(subject => subject.id === active.subjectId)?.name ?? active.title,
      kind: active.kind,
      startedAt: active.startedAt,
      elapsedSeconds: elapsed,
      paused: isPaused(active),
      effectiveStartedAt: now - elapsed * 1000,
    } : null,
    todaySeconds: Math.floor(today.courseSeconds + today.revisionSeconds),
    weekSeconds: Math.floor(week.courseSeconds + week.revisionSeconds),
    todayRevisionSeconds: Math.floor(today.revisionSeconds),
    todayMeasuredCourseSeconds: Math.floor(today.measuredCourseSeconds),
    todayScheduledCourseSeconds: Math.floor(today.scheduledCourseSeconds),
    weekRevisionSeconds: Math.floor(week.revisionSeconds),
    weekMeasuredCourseSeconds: Math.floor(week.measuredCourseSeconds),
    weekScheduledCourseSeconds: Math.floor(week.scheduledCourseSeconds),
    sessionCount: week.sessionCount,
    topSubject: state.subjects.find(subject => subject.id === top)?.name,
    weekDays: getWeekDays(now).map(day => {
      const totals = studyTotals(state, day, now, profileId);
      return {
        date: day.start, courseSeconds: Math.floor(totals.courseSeconds), revisionSeconds: Math.floor(totals.revisionSeconds),
        measuredCourseSeconds: Math.floor(totals.measuredCourseSeconds), scheduledCourseSeconds: Math.floor(totals.scheduledCourseSeconds),
      };
    }),
  };
  surfaceUpdates = surfaceUpdates.then(() => syncStudySurface(snapshot)).catch(() => {});
}

export function initializeStudy() {
  loading ??= (async () => {
    try {
      const saved = await AsyncStorage.getItem(storageKey);
      const previous = saved ?? await readLegacyStudyState();
      const data = previous ? parseStudyBackup(previous) : newStudyState();
      if (saved === null && previous) await AsyncStorage.setItem(storageKey, JSON.stringify(data));
      useStudyStore.setState({ data, status: "ready", error: undefined });
      publishSurface(data);
    } catch (error) {
      useStudyStore.setState({
        status: "error",
        error: error instanceof Error ? error.message : "Les séances n’ont pas pu être chargées.",
      });
    }
  })();
  return loading;
}

export function refreshStudySurface() {
  const { status, data } = useStudyStore.getState();
  if (status === "ready") publishSurface(data);
}

export function retryStudyLoad() {
  if (useStudyStore.getState().status === "error") {
    loading = undefined;
    useStudyStore.setState({ status: "loading", error: undefined });
  }
  return initializeStudy();
}

function mutate(edit: (state: StudyState) => StudyState, allowRecovery = false) {
  const operation = writes.then(async () => {
    await initializeStudy();
    const { data, status, error } = useStudyStore.getState();
    if (status !== "ready" && !allowRecovery) throw new Error(error ?? "Le suivi des révisions n’est pas accessible.");
    const updated = edit(data);
    if (updated === data) return;
    await AsyncStorage.setItem(storageKey, JSON.stringify(updated));
    useStudyStore.setState({ data: updated, status: "ready", error: undefined });
    publishSurface(updated);
  });
  writes = operation.catch(() => {});
  return operation;
}

export type SessionInput = { subjectName: string; kind: StudyKind; title?: string; notes?: string; task?: StudyTask; courseId?: string };

export class StudySessionConflict extends Error {
  constructor(readonly sessionId: string) {
    super("Une séance est déjà en cours.");
  }
}

function cleanSubjectName(input: string) {
  const trimmed = input.trim();
  if (!trimmed || trimmed.length > 200) throw new Error("Saisissez un nom de matière de 1 à 200 caractères.");
  return trimmed;
}

function createSession(state: StudyState, request: SessionInput, start: number, end?: number): StudyState {
  const name = cleanSubjectName(request.subjectName);
  const existing = findSubject(state.subjects, name);
  const subject = existing ?? { id: uuid(), name, color: "#2776F8", aliases: [], archived: false };
  const session: StudySession = {
    id: uuid(),
    subjectId: subject.id,
    kind: request.kind,
    title: request.title?.trim() ?? "",
    notes: request.notes?.trim() ?? "",
    startedAt: start,
    endedAt: end,
    segments: [{ start, end }],
    task: request.task,
    taskSegments: request.task ? [{ taskId: request.task.id, start, end }] : [],
    courseId: request.courseId,
  };
  return {
    ...state,
    subjects: existing ? state.subjects : [...state.subjects, subject],
    sessions: [...state.sessions, session],
    tasks: request.task ? { ...state.tasks, [request.task.id]: request.task } : state.tasks,
  };
}

export function startStudy(request: SessionInput, attachTo?: string) {
  return mutate(state => {
    const active = getActiveSession(state);
    if (attachTo && active?.id !== attachTo) {
      throw new Error("La séance a changé. Ouvrez à nouveau le devoir pour l’associer.");
    }
    if (!active) return createSession(state, request, Date.now());
    const task = request.task;
    if ((request.courseId && request.courseId === active.courseId) || (task && task.id === active.task?.id)) return state;
    if (!task || attachTo !== active.id) throw new StudySessionConflict(active.id);
    return {
      ...state,
      sessions: state.sessions.map(session => session.id === active.id ? setSessionTask(session, task) : session),
      tasks: { ...state.tasks, [task.id]: task },
    };
  });
}

export function runTimerAction(action: "pause" | "resume" | "finish") {
  return mutate(state => {
    const active = getActiveSession(state);
    return active ? {
      ...state,
      sessions: state.sessions.map(session => session.id === active.id ? changeSessionTimer(session, action) : session),
    } : state;
  });
}

export function closeStudyTask(completed: boolean) {
  return mutate(state => {
    const active = getActiveSession(state);
    if (!active?.task) return state;
    const task = active.task;
    return {
      ...state,
      sessions: state.sessions.map(session => session.id === active.id ? setSessionTask(session) : session),
      tasks: completed ? { ...state.tasks, [task.id]: { ...task, completed: true } } : state.tasks,
    };
  });
}

export function addPastStudy(request: SessionInput, end: number, minutes: number) {
  return mutate(state => {
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 1440 || !Number.isFinite(end) || end > Date.now()) {
      throw new Error("Indiquez une durée entre 1 et 1 440 minutes et une date passée.");
    }
    return createSession(state, request, end - minutes * 60000, end);
  });
}

export function updateStudySession(id: string, title: string, notes: string) {
  return mutate(state => ({
    ...state,
    sessions: state.sessions.map(session => session.id === id ? { ...session, title: title.trim(), notes: notes.trim() } : session),
  }));
}

export function removeStudySession(id: string) {
  return mutate(state => ({ ...state, sessions: state.sessions.filter(session => session.id !== id || session.endedAt === undefined) }));
}

export function saveStudySubject(id: string | undefined, newName: string, aliases: string, archived: boolean) {
  return mutate(state => {
    const name = cleanSubjectName(newName);
    const previous = state.subjects.find(subject => subject.id === id);
    const matching = findSubject(state.subjects, name);
    if (matching && matching.id !== id) throw new Error("Cette matière existe déjà.");
    const subject = {
      id: previous?.id ?? uuid(),
      color: previous?.color ?? "#2776F8",
      name,
      aliases: aliases.split(",").map(alias => alias.trim()).filter(Boolean),
      archived,
    };
    return { ...state, subjects: previous ? state.subjects.map(item => item.id === id ? subject : item) : [...state.subjects, subject] };
  });
}

export function restoreStudyBackup(raw: string) {
  return mutate(() => {
    if (raw.length > 20 * 1024 * 1024) throw new Error("La sauvegarde dépasse 20 Mo.");
    return parseStudyBackup(raw);
  }, true);
}

export function syncScheduledStudyWeek(profileId: string, weekStart: number, timetable: ScheduledStudyCourse[]) {
  return mutate(state => reconcileScheduledStudyWeek(state, profileId, weekStart, timetable, uuid));
}
