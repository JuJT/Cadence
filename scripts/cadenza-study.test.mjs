import assert from "node:assert/strict";
import test from "node:test";

import {
  changeSessionTimer,
  elapsedSeconds,
  getActiveSession,
  isPaused,
  newStudyState,
  parseStudyBackup,
  reconcileScheduledStudyCourses,
  setSessionTask,
  studyTotals,
} from "../stores/study/model.ts";

const start = Date.parse("2026-11-19T10:00:00Z");
const revision = {
  id: "session-1", subjectId: "math", kind: "revision", title: "Suites",
  notes: "Réviser le chapitre 2", startedAt: start, segments: [{ start }], taskSegments: [],
};

test("a timer advances from dates, excludes pauses and survives a cold restore", () => {
  const time = offset => start + offset * 1000;
  const linked = setSessionTask(revision, { id: "task-1", title: "Suites" }, time(2));
  assert.equal(elapsedSeconds(linked, time(10)), 10);
  const paused = changeSessionTimer(linked, "pause", time(10));
  assert.equal(elapsedSeconds(paused, time(100)), 10);
  assert.equal(isPaused(paused), true);
  const data = parseStudyBackup(JSON.stringify({ ...newStudyState(), sessions: [paused] }));
  const resumed = changeSessionTimer(getActiveSession(data), "resume", time(100));
  assert.equal(elapsedSeconds(resumed, time(111)), 21);
  const finished = changeSessionTimer(resumed, "finish", time(111));
  assert.deepEqual(finished.taskSegments.map(segment => (segment.end - segment.start) / 1000), [8, 11]);
  assert.equal(elapsedSeconds(finished, time(898)), 21);
});

test("a homework switch neither pauses nor resets an existing timer", () => {
  const first = setSessionTask(revision, { id: "task-1", title: "Suites" }, start + 2000);
  const second = setSessionTask(first, { id: "task-2", title: "Dissertation" }, start + 5000);
  assert.equal(elapsedSeconds(second, start + 10000), 10);
  assert.equal(second.subjectId, "math");
  assert.deepEqual(second.taskSegments, [
    { taskId: "task-1", start: start + 2000, end: start + 5000 },
    { taskId: "task-2", start: start + 5000 },
  ]);
});

test("imports old schema 3 homework, notes, pauses and course credits without double counting", () => {
  const legacy = {
    schemaVersion: 3,
    subjects: [{ id: "math", name: "Mathématiques", colorHex: "#2776F8", aliases: ["Maths"], position: 0 }],
    sessions: [{
      id: "revision-old", subjectID: "math", kind: "revision", startedAt: new Date(start).toISOString(),
      activeSegments: [{ start: new Date(start).toISOString(), end: new Date(start + 5000).toISOString() }],
      activeHomeworkID: "homework-id", topic: "Suites", notes: "À relire",
    }],
    homework: [{ localID: "homework-id", localCompletionOverride: true, source: { uid: "pronote-1", description: "<p>Exercices</p>" } }],
    occurrences: [{
      id: "course-old", subjectID: "math", status: "confirmed", confirmedSeconds: 1200,
      start: new Date(start - 3600000).toISOString(), end: new Date(start).toISOString(),
    }],
  };
  const imported = parseStudyBackup(JSON.stringify(legacy), start + 6500);
  assert.equal(isPaused(getActiveSession(imported)), true);
  assert.equal(imported.sessions[0].notes, "À relire");
  assert.deepEqual(imported.sessions[0].task, { id: "homework-id", title: "Exercices", completed: true });
  const synced = reconcileScheduledStudyCourses(imported, [{
    id: "papillon-course", subjectName: "MATHS", start: start - 3600000, end: start, canceled: false,
  }], () => "unexpected");
  assert.equal(synced.courses.length, 1);
  const totals = studyTotals(synced, { start: start - 3600000, end: start + 10000 }, start + 6500);
  assert.equal(totals.courseSeconds, 1200);
  assert.equal(totals.revisionSeconds, 5);
  const measured = { ...synced, sessions: [...synced.sessions, {
    id: "course-new", subjectId: "math", kind: "course", title: "", notes: "", startedAt: start - 600000,
    endedAt: start, segments: [{ start: start - 600000, end: start }], taskSegments: [], courseId: "papillon-course",
  }] };
  assert.equal(studyTotals(measured, { start: start - 3600000, end: start + 10000 }, start + 6500).courseSeconds, 600);
});

test("imports schema 1 active session with an open segment", () => {
  const input = {
    schemaVersion: 1, subjects: [{ id: "math", name: "Mathématiques" }], sessions: [],
    activeSession: {
      id: "old", subjectId: "math", kind: "revision", startedAt: new Date(start).toISOString(),
      isPaused: false, completedSegments: [], currentSegmentStart: new Date(start).toISOString(),
    },
  };
  assert.equal(elapsedSeconds(getActiveSession(parseStudyBackup(JSON.stringify(input))), start + 50000), 50);
});

test("rejects a missing subject, overlapping intervals and unknown schema", () => {
  const data = newStudyState();
  const orphan = { ...revision, subjectId: "lost" };
  const overlap = { ...revision, segments: [{ start, end: start + 2000 }, { start: start + 1000 }] };
  assert.throws(() => parseStudyBackup(JSON.stringify({ ...data, sessions: [orphan] })));
  assert.throws(() => parseStudyBackup(JSON.stringify({ ...data, sessions: [overlap] })));
  assert.throws(() => parseStudyBackup(JSON.stringify({ schemaVersion: 100, subjects: [], sessions: [] })));
});

test("scheduled lessons earn credit after completion and canceled lessons earn none", () => {
  const timetable = [{
    id: "math-plan", subjectName: "Maths", start, end: start + 3600000, canceled: false,
  }];
  const data = reconcileScheduledStudyCourses(newStudyState(), timetable, () => "unneeded");
  assert.equal(reconcileScheduledStudyCourses(data, timetable, () => "unneeded"), data);
  const range = { start, end: start + 100000000 };
  assert.equal(studyTotals(data, range, start + 35).courseSeconds, 0);
  assert.equal(studyTotals(data, range, start + 4000000).courseSeconds, 3600);
  const canceled = reconcileScheduledStudyCourses(data, [{ ...timetable[0], canceled: true }], () => "unneeded");
  assert.equal(studyTotals(canceled, range, start + 4000000).courseSeconds, 0);
});
