import type { NewsInformation, NewsSurvey, SessionHandle } from "@blockshub/pawnote-lts";

declare module "@blockshub/pawnote-lts" {
  export function cadenzaNewsDetail(session: SessionHandle, id: string): Promise<NewsInformation | NewsSurvey>;
}
