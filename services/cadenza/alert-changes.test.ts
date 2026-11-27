import { expect, test } from "@jest/globals";

import { changeAlerts, type AlertLesson } from "./alert-changes";

const lesson = (id: string, override: Partial<AlertLesson> = {}): AlertLesson => ({
  id, subject: id, start: 200, end: 300, room: "A", teacher: "T", status: "", cancelled: false, ...override,
});

test("announces a teacher absence and a moved lesson without re-announcing unchanged classes", () => {
  const yesterday = [lesson("Maths"), lesson("Français"), lesson("Anglais")];
  const today = [lesson("Maths", { cancelled: true, status: "Prof. absent" }),
    lesson("Français", { start: 210 }), lesson("Anglais")];
  expect(changeAlerts(yesterday, today, 100).map(change => change.text)).toEqual([
    "Maths · professeur absent", "Français · horaire modifié",
  ]);
  expect(changeAlerts(today, today, 100)).toEqual([]);
});

test("reports future additions and removals and ignores elapsed periods", () => {
  expect(changeAlerts([lesson("SVT"), lesson("Passé", { start: 20, end: 40 })], [lesson("Histoire")], 100)
    .map(change => change.text)).toEqual(["Histoire · cours ajouté", "SVT · cours retiré"]);
});

test("keeps the same visible lesson when PRONOTE changes the identifier and formatting", () => {
  expect(changeAlerts([lesson("old", { subject: "HISTOIRE-GEOGRAPHIE", teacher: "MME MARTIN" })],
    [lesson("new", { subject: "Histoire-géographie", teacher: "Mme. Martin" })], 100)).toEqual([]);
});

test("pairs a uniquely identified move into one dated change", () => {
  expect(changeAlerts([lesson("old", { subject: "Français" })],
    [lesson("new", { subject: "Français", start: 240, end: 340 })], 100)).toEqual([
    { text: "Français · horaire modifié", time: 240, before: 200, lessonId: "new" },
  ]);
});
