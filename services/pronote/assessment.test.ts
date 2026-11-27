import { beforeEach, describe, expect, it, jest } from "@jest/globals";
import { cadenzaGradebookOverview, evaluations, gradebookPDF, Period, SessionHandle, TabLocation } from "@blockshub/pawnote-lts";

import { fetchAssessmentPeriods, fetchReportCard, fetchReportCardPDF, fetchSkillEvaluations } from "./assessment";

jest.mock("@blockshub/pawnote-lts", () => ({
  ...jest.requireActual<typeof import("@blockshub/pawnote-lts")>("@blockshub/pawnote-lts"),
  cadenzaGradebookOverview: jest.fn(),
  evaluations: jest.fn(),
  gradebookPDF: jest.fn(),
}));

function period(id: string, month: number): Period {
  return { id, name: id, kind: 2, startDate: new Date(2026, month, 1), endDate: new Date(2026, month + 1, 0) };
}
const skills = period("Evaluation trimestrielle", 8);
const report = period("Bulletin trimestriel", 8);
const reportSecond = period("Bulletin 2", 11);
const session = {
  user: { authorizations: { tabs: [TabLocation.Evaluations, TabLocation.Gradebook] } },
  userResource: {
    tabs: new Map([
      [TabLocation.Evaluations, { periods: [skills] }],
      [TabLocation.Gradebook, { periods: [reportSecond, report], defaultPeriod: report }],
    ]),
  },
  information: { url: "https://school.example/pronote" },
} as unknown as SessionHandle;

describe("PRONOTE skills and report cards", () => {
  beforeEach(() => { jest.resetAllMocks(); });

  it("keeps the tab-specific periods and uses the provider's default first", () => {
    expect(fetchAssessmentPeriods(session, "fixture", "skills").map(item => item.id)).toEqual([skills.id]);
    expect(fetchAssessmentPeriods(session, "fixture", "report-cards").map(item => item.id)).toEqual([report.id, reportSecond.id]);
  });

  it("never sends a skills period to the report card API", async () => {
    await expect(fetchReportCard(session, skills.id)).rejects.toThrow("période");
    expect(cadenzaGradebookOverview).not.toHaveBeenCalled();
  });

  it("checks grades and report publication independently", async () => {
    jest.mocked(evaluations).mockResolvedValue([]);
    jest.mocked(cadenzaGradebookOverview).mockResolvedValue(null);
    await expect(fetchSkillEvaluations(session, skills.id)).resolves.toEqual([]);
    await expect(fetchReportCard(session, report.id)).resolves.toBeNull();
    expect(gradebookPDF).not.toHaveBeenCalled();
  });

  it("asks PRONOTE for a PDF only through the explicit PDF action and checks its origin", async () => {
    jest.mocked(gradebookPDF).mockResolvedValueOnce("https://school.example/pronote/fixture.pdf")
      .mockResolvedValueOnce("https://other.example/pronote/fixture.pdf");
    await expect(fetchReportCardPDF(session, report.id)).resolves.toBe("https://school.example/pronote/fixture.pdf");
    await expect(fetchReportCardPDF(session, report.id)).rejects.toThrow("lien");
    expect(gradebookPDF).toHaveBeenCalledWith(session, { ...report, kind: 2 });
  });
});
