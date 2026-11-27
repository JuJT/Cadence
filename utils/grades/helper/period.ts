import { gradePeriodKey, type Period } from "@/services/shared/grade";

function normalizePeriodName(name: string): string {
  return name.normalize("NFD").replace(/\p{Diacritic}/gu, "").trim().toLowerCase();
}

const usualPeriod = /^(?:(?:1er|[2-9](?:e|eme))\s+)?(?:trimestre|semestre|periode|term|quarter)(?:\s|$)/;
const specialPeriod = /\b(annee|hors periode|(?:bac|brevet) blanc|dnl|epreuves? ponctuelles?|controle en cours|mi[- ]semestre)\b/;

export function sortGradePeriods(periods: Period[]): Period[] {
  const priority = (period: Period) => usualPeriod.test(normalizePeriodName(period.name)) ? 0 : 1;
  return [...periods].sort((a, b) => priority(a) - priority(b) || a.start.getTime() - b.start.getTime());
}

export function getCurrentPeriod(periods: Period[], now = new Date()): Period | undefined {
  const dated = periods.filter(period =>
    Number.isFinite(period.start.getTime()) &&
    Number.isFinite(period.end.getTime()) &&
    period.end >= period.start &&
    !specialPeriod.test(normalizePeriodName(period.name))
  );
  const usual = dated.filter(period => usualPeriod.test(normalizePeriodName(period.name)));
  const candidates = (usual.length > 0 ? usual : dated).sort((a, b) => b.start.getTime() - a.start.getTime());
  const containsToday = (period: Period) => {
    const end = new Date(period.end);
    end.setHours(23, 59, 59, 999);
    return period.start <= now && now <= end;
  };
  return candidates.find(containsToday) ??
    candidates.find(period => period.start <= now) ??
    candidates.at(-1) ??
    sortGradePeriods(periods)[0];
}

export function findGradePeriod(periods: Period[], key: string): Period | undefined {
  const exact = periods.find(period => gradePeriodKey(period) === key);
  if (exact) return exact;
  const legacy = periods.filter(period => period.id === key);
  return legacy.length === 1 ? legacy[0] : undefined;
}
