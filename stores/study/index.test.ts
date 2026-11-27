import { expect, jest, test } from "@jest/globals";

import { runTimerAction, startStudy, StudySessionConflict, useStudyStore } from "./index";
import { getActiveSession } from "./model";

jest.mock("@react-native-async-storage/async-storage", () => ({
  __esModule: true,
  default: {
    getItem: async () => null,
    setItem: async () => {},
  },
}));

jest.mock("@/modules/cadenza-study", () => ({
  readLegacyStudyState: async () => null,
  syncStudySurface: async () => {},
}));

jest.mock("@/stores/account", () => ({
  useAccountStore: { getState: () => ({ lastUsedAccount: "student" }) },
}));

const active = () => getActiveSession(useStudyStore.getState().data);

test("course and homework starts use the same serialized timer with explicit conflicts", async () => {
  const course = { subjectName: "Mathématiques", kind: "course" as const, courseId: "course-42" };
  const request = { subjectName: "Français", kind: "revision" as const, task: { id: "homework", title: "Lecture" } };

  await Promise.all([startStudy(course), startStudy(course)]);
  const first = active()!;
  expect(first).toMatchObject({ kind: "course", courseId: "course-42" });
  expect(useStudyStore.getState().data.sessions).toHaveLength(1);
  await expect(startStudy({ ...course, courseId: "course-43" })).rejects.toBeInstanceOf(StudySessionConflict);
  await expect(startStudy(request)).rejects.toMatchObject({ sessionId: first.id });
  expect(active()?.task).toBeUndefined();

  await startStudy(request, first.id);
  expect(active()).toMatchObject({ id: first.id, courseId: "course-42", kind: "course", task: request.task });
  expect(active()?.segments).toEqual(first.segments);

  await runTimerAction("finish");
  await expect(startStudy(request, first.id)).rejects.toThrow("La séance a changé");
  expect(active()).toBeUndefined();

  await startStudy(request);
  expect(active()).toMatchObject({ kind: "revision", task: request.task });
  expect(active()?.segments).toHaveLength(1);
});
