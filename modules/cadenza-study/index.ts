import { requireOptionalNativeModule } from "expo-modules-core";

export interface StudySurfaceSnapshot {
  activeSession: {
    id: string;
    title: string;
    kind: "course" | "revision";
    startedAt: number;
    elapsedSeconds: number;
    paused: boolean;
    effectiveStartedAt: number;
  } | null;
  todaySeconds: number;
  weekSeconds: number;
  todayRevisionSeconds?: number;
  todayMeasuredCourseSeconds?: number;
  todayScheduledCourseSeconds?: number;
  weekRevisionSeconds?: number;
  weekMeasuredCourseSeconds?: number;
  weekScheduledCourseSeconds?: number;
  sessionCount: number;
  topSubject?: string;
  weekDays?: {
    date: number;
    courseSeconds: number;
    revisionSeconds: number;
    measuredCourseSeconds?: number;
    scheduledCourseSeconds?: number;
  }[];
}

interface CadenzaStudyNative {
  importTransitPass(): Promise<boolean>;
  previewRoute(): Promise<string | null>;
  readLegacyStudyState(): Promise<string | null>;
  readLegacyNotificationPreference(): Promise<boolean | null>;
  syncStudySurface(serializedSnapshot: string): Promise<void>;
  getStudyDiagnostics(): Promise<{ sharedContainer: boolean; liveActivities: boolean }>;
  verifyUpdateFile(uri: string, expectedSize: number, sha256: string | null): Promise<boolean>;
}

const native = requireOptionalNativeModule<CadenzaStudyNative>("CadenzaStudy");

export async function importTransitPass() {
  if (!native) throw new Error("Cartes est indisponible.");
  return await native.importTransitPass();
}

export async function getCadenzaPreviewRoute() {
  return native ? native.previewRoute() : null;
}

export async function readLegacyStudyState(): Promise<string | null> {
  return native ? native.readLegacyStudyState() : null;
}

export async function readLegacyNotificationPreference(): Promise<boolean | null> {
  return native ? native.readLegacyNotificationPreference() : null;
}

export async function syncStudySurface(snapshot: StudySurfaceSnapshot): Promise<void> {
  await native?.syncStudySurface(JSON.stringify(snapshot));
}

export async function getStudyDiagnostics() {
  return native?.getStudyDiagnostics();
}

export async function verifyUpdateFile(uri: string, expectedSize: number, sha256?: string) {
  return native ? native.verifyUpdateFile(uri, expectedSize, sha256 ?? null) : false;
}
