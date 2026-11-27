export type AssessmentSection = "skills" | "report-cards";

export interface AssessmentPeriod {
  id: string;
  name: string;
  serviceId: string;
  start: Date;
  end: Date;
}

export interface SkillEvaluation {
  id: string;
  subject: string;
  title: string;
  description?: string;
  date: Date;
  teacher?: string;
  skills: { id: string; name: string; domain: string; level: string; abbreviation?: string }[];
}

export interface ReportCard {
  overall: { name: string; value: string }[];
  subjects: { name: string; group?: string; average?: number; classAverage?: number; assessments: string[] }[];
}
