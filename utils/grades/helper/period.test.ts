import { gradePeriodKey, type Period } from "@/services/shared/grade";
import { findGradePeriod, getCurrentPeriod } from "./period";

function period(name: string, start: Date, end: Date): Period {
  return { name, id: "identifiant-réutilisé", start, end, createdByAccount: "service" };
}

describe("périodes de notes", () => {
  const first = period("Trimestre 1", new Date(2026, 8, 1), new Date(2026, 10, 26));
  const second = period("Trimestre 2", new Date(2026, 10, 28), new Date(2027, 1, 26));
  const wholeYear = period("ANNÉE", new Date(2026, 8, 1), new Date(2027, 5, 30));
  const mockExam = period("Bac blanc", new Date(2026, 9, 1), new Date(2026, 11, 20));

  it("choisit le trimestre ordinaire, y compris aux dernières heures du dernier jour", () => {
    expect(getCurrentPeriod([wholeYear, mockExam, second, first], new Date(2026, 10, 26, 22))).toBe(first);
  });

  it("sélectionne la période commencée la plus récente entre deux dates", () => {
    expect(getCurrentPeriod([wholeYear, mockExam, second, first], new Date(2026, 10, 27))).toBe(first);
    expect(getCurrentPeriod([wholeYear, mockExam, second, first], new Date(2027, 2, 10))).toBe(second);
  });

  it("distingue les années, services et enfants malgré le même nom et identifiant", () => {
    const previous = period(first.name, new Date(2025, 8, 1), new Date(2025, 10, 26));
    expect(gradePeriodKey(first)).not.toBe(gradePeriodKey(previous));
    expect(gradePeriodKey(first)).not.toBe(gradePeriodKey({ ...first, createdByAccount: "autre" }));
    expect(gradePeriodKey(first, "élève-a")).not.toBe(gradePeriodKey(first, "élève-b"));
    expect(findGradePeriod([first, previous], gradePeriodKey(previous))).toBe(previous);
    expect(findGradePeriod([first, previous], first.id!)).toBeUndefined();
    expect(findGradePeriod([first], first.id!)).toBe(first);
  });
});
