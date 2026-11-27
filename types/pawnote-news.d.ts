import type { NewsInformation, NewsSurvey, Period, SessionHandle } from "@blockshub/pawnote-lts";

import type { ReportCard } from "@/services/shared/assessment";

declare module "@blockshub/pawnote-lts" {
  export function cadenzaGradebookOverview(
    session: SessionHandle, period: Period,
  ): Promise<ReportCard | null>;
  export function cadenzaNewsDetail(session: SessionHandle, id: string): Promise<NewsInformation | NewsSurvey>;
}
