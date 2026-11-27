import {
  cadenzaGradebookOverview, evaluations, gradebookPDF, type Period, type SessionHandle, TabLocation,
} from "@blockshub/pawnote-lts";

import { hasPronoteTab } from "@/services/pronote/capabilities";
import type { AssessmentPeriod, AssessmentSection, ReportCard, SkillEvaluation } from "@/services/shared/assessment";

function periodsFor(session: SessionHandle, section: AssessmentSection): Period[] {
  const tab = section === "skills" ? TabLocation.Evaluations : TabLocation.Gradebook;
  if (!hasPronoteTab(session, tab)) throw new Error("Cette rubrique n’est pas disponible pour ce compte PRONOTE.");
  const scoped = session.userResource.tabs.get(tab);
  // Each tab can publish a different set of periods. Keep an explicit empty
  // set empty rather than substituting unrelated notes or calendar periods.
  return scoped?.periods ?? [];
}

function requirePeriod(session: SessionHandle, section: AssessmentSection, id: string): Period {
  const period = periodsFor(session, section).find(value => String(value.id) === id);
  if (!period) throw new Error("Cette période n’est pas disponible dans PRONOTE.");
  return period;
}

export function fetchAssessmentPeriods(
  session: SessionHandle, serviceId: string, section: AssessmentSection,
): AssessmentPeriod[] {
  const periods = periodsFor(session, section);
  const tab = section === "skills" ? TabLocation.Evaluations : TabLocation.Gradebook;
  const current = session.userResource.tabs.get(tab)?.defaultPeriod?.id;
  return [...periods].sort((a, b) => Number(b.id === current) - Number(a.id === current) ||
    b.startDate.getTime() - a.startDate.getTime()).map(period => ({
    id: String(period.id), name: period.name, start: period.startDate, end: period.endDate, serviceId,
  }));
}

export async function fetchSkillEvaluations(session: SessionHandle, id: string): Promise<SkillEvaluation[]> {
  const period = requirePeriod(session, "skills", id);
  return (await evaluations(session, period)).map(evaluation => ({
    id: String(evaluation.id),
    subject: evaluation.subject?.name || "Matière",
    title: evaluation.name,
    description: evaluation.description,
    date: evaluation.date,
    teacher: evaluation.teacher,
    skills: evaluation.skills.map(skill => ({
      id: String(skill.id),
      name: skill.itemName || skill.domainName || skill.pillarName,
      domain: skill.domainName || skill.pillarName,
      level: skill.level,
      abbreviation: skill.abbreviation,
    })),
  })).sort((a, b) => b.date.getTime() - a.date.getTime());
}

export async function fetchReportCard(session: SessionHandle, id: string): Promise<ReportCard | null> {
  const period = requirePeriod(session, "report-cards", id);
  return cadenzaGradebookOverview(session, period);
}

export async function fetchReportCardPDF(session: SessionHandle, id: string): Promise<string> {
  const period = requirePeriod(session, "report-cards", id);
  // Pawnote's PageBulletins expects a report-card period (kind 2).
  const document = new URL(await gradebookPDF(session, { ...period, kind: 2 }));
  const origin = new URL(session.information.url).origin;
  if (document.protocol !== "https:" || document.origin !== origin || document.username || document.password) {
    throw new Error("PRONOTE n’a pas renvoyé de lien de bulletin valide.");
  }
  return document.toString();
}
