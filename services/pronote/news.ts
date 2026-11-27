import {
  cadenzaNewsDetail,
  news as fetchNews,
  NewsInformation,
  newsInformationAcknowledge,
  NewsQuestionKind,
  newsQuestionLocalMutate,
  NewsSurvey,
  newsSurveySend,
  SessionHandle,
  TabLocation,
} from "@blockshub/pawnote-lts";

import { hasPronoteTab } from "@/services/pronote/capabilities";
import { News, SurveyAnswer } from "@/services/shared/news";
import { Attachment } from "@/services/shared/attachment";

type PronoteNews = (NewsInformation | NewsSurvey) & {
  detailsRequired?: boolean;
  acknowledgementAvailable?: boolean;
};

const supportedSurveyKinds = new Set<NewsQuestionKind>([
  NewsQuestionKind.TextInput, NewsQuestionKind.UniqueChoice, NewsQuestionKind.MultipleChoice,
]);

function requireNews(session: SessionHandle) {
  if (!hasPronoteTab(session, TabLocation.News)) {
    throw new Error("Les actualités sont indisponibles pour ce compte.");
  }
}

function mapAttachments(attachments: NewsInformation["attachments"] | undefined, accountId: string): Attachment[] {
  return (attachments ?? []).map(file => ({
    name: file.name, type: file.kind, url: file.url, createdByAccount: accountId,
  }));
}

function mapItem(item: PronoteNews, accountId: string): News {
  const base: News = {
    id: String(item.id),
    title: item.title,
    createdAt: item.creationDate ?? item.startDate ?? new Date(0),
    type: item.is,
    read: item.read === true,
    acknowledged: false,
    content: "",
    attachments: [],
    author: item.author ?? "",
    category: item.category?.name ?? (item.is === "survey" ? "Sondage" : "Information"),
    createdByAccount: accountId,
    detailsRequired: item.detailsRequired === true,
    question: item.is === "survey",
  };
  if (item.detailsRequired) return base;
  if (item.is === "information") {
    return {
      ...base, content: item.content ?? "", attachments: mapAttachments(item.attachments, accountId),
      acknowledged: item.acknowledged === true, needsAcknowledgement: item.needToAcknowledge === true,
    };
  }
  const answerable = (item.questions ?? []).filter(question => question.shouldAnswer);
  const answered = (item.questions ?? []).some(question => question.answered === true);
  const canSubmit = item.detailsRequired === undefined && answerable.length > 0 && !answered &&
    (item.questions ?? []).every(question => question.id && /^\d+$/.test(question.answerID) &&
      Number.isSafeInteger(Number(question.answerID))) &&
    answerable.every(question => supportedSurveyKinds.has(question.kind) &&
      !question.choices.some(choice => choice.isTextInput));
  return {
    ...base,
    survey: {
      isAnonymous: item.isAnonymous === true,
      canSubmit,
      answered,
      questions: (item.questions ?? []).map((question, index) => ({
        id: question.id ?? String(index),
        title: question.title ?? "",
        content: question.content ?? "",
        kind: question.kind,
        required: question.shouldAnswer === true,
        choices: question.choices ?? [],
        attachments: mapAttachments(question.attachments, accountId),
        maximumLength: question.maximumLength || undefined,
        maximumChoices: question.shouldRespectMaximumChoices ? question.maximumChoices : undefined,
      })),
    },
  };
}

export async function fetchPronoteNews(session: SessionHandle, accountId: string): Promise<News[]> {
  requireNews(session);
  const { items } = await fetchNews(session);
  return items.map(item => mapItem(item, accountId));
}

async function findCurrentItem(session: SessionHandle, id: string): Promise<PronoteNews> {
  requireNews(session);
  const { items } = await fetchNews(session);
  const item = items.find(row => String(row.id) === id) as PronoteNews | undefined;
  if (!item) throw new Error("Cette actualité n’est plus disponible.");
  return item.detailsRequired ? cadenzaNewsDetail(session, id) : item;
}

export async function fetchPronoteNewsDetail(session: SessionHandle, accountId: string, id: string): Promise<News> {
  return mapItem(await findCurrentItem(session, id), accountId);
}

export async function setPronoteNewsAsAcknowledged(session: SessionHandle, news: News): Promise<News> {
  const item = await findCurrentItem(session, news.id);
  if (item.is !== "information") throw new Error("Cette actualité ne peut pas être accusée.");
  if (!item.acknowledged) {
    if (item.needToAcknowledge !== true || item.acknowledgementAvailable === false) {
      throw new Error("PRONOTE ne demande pas d’accusé sur cette information.");
    }
    await newsInformationAcknowledge(session, item);
  }
  return { ...mapItem(item, news.createdByAccount), acknowledged: true, needsAcknowledgement: false };
}

export async function submitPronoteSurvey(
  session: SessionHandle, accountId: string, id: string, answers: SurveyAnswer[],
): Promise<News> {
  const item = await findCurrentItem(session, id);
  const mapped = mapItem(item, accountId);
  if (item.is !== "survey" || !mapped.survey?.canSubmit) {
    throw new Error("Ce sondage doit être rempli dans PRONOTE.");
  }
  const updates = new Map(answers.map(answer => [answer.questionId, answer]));
  const questions = item.questions.filter(question => question.shouldAnswer);
  if (updates.size !== answers.length || updates.size !== questions.length) {
    throw new Error("Répondez à toutes les questions demandées.");
  }
  // Validate the complete response before mutating any SDK objects.
  const apply = questions.map(question => {
    const answer = updates.get(question.id);
    if (!answer) throw new Error("Répondez à toutes les questions demandées.");
    if (question.kind === NewsQuestionKind.TextInput) {
      const text = answer.text?.trim();
      if (!text || text.length > (question.maximumLength || 20000)) throw new Error("Vérifiez la longueur de votre réponse.");
      return () => newsQuestionLocalMutate(question, text);
    }
    const choices = answer.choices ?? [];
    const maximum = question.kind === NewsQuestionKind.UniqueChoice ? 1 :
      question.shouldRespectMaximumChoices ? question.maximumChoices : question.choices.length;
    if (!choices.length || choices.length > maximum || new Set(choices).size !== choices.length ||
        !choices.every(position => question.choices.some(choice => choice.position === position))) {
      throw new Error("Vérifiez les choix de votre réponse.");
    }
    return () => newsQuestionLocalMutate(question, choices);
  });
  apply.forEach(update => update());
  await newsSurveySend(session, item);
  return { ...mapped, survey: { ...mapped.survey, canSubmit: false, answered: true } };
}
