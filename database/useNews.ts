import { Model, Q } from "@nozbe/watermelondb";
import { useEffect, useState } from "react";

import { Attachment } from "@/services/shared/attachment";
import { News as SharedNews } from "@/services/shared/news";
import { useAccountStore } from "@/stores/account";
import { generateId } from "@/utils/generateId";
import { info,warn } from "@/utils/logger/logger";

import { getDatabaseInstance, useDatabase } from "./DatabaseProvider";
import News from "./models/News";
import { parseJsonArray } from "./useHomework";
import { safeWrite } from "./utils/safeTransaction";

export function useNews(refresh = 0) {
  const database = useDatabase();
  const accountId = useAccountStore(state => state.lastUsedAccount);
  const serviceIds = useAccountStore(state => state.accounts.find(account => account.id === accountId)?.services);
  const [news, setNews] = useState<SharedNews[]>([]);

  useEffect(() => {

    const query = database.get<News>('news').query();

    const sub = query.observe().subscribe(news =>
      setNews(
        news.map(mapNewsToShared).sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
      )
    );

    return () => sub.unsubscribe();
  }, [refresh, database]);

  return news.filter(item => serviceIds?.some(service => service.id === item.createdByAccount));
}

const pronoteRoutePrefix = "pronote:";

export function getNewsRouteId(item: SharedNews): string {
  return item.type
    ? pronoteRoutePrefix + encodeURIComponent(item.createdByAccount) + ":" + encodeURIComponent(item.id)
    : generateId(item.author + item.title + item.createdByAccount);
}

export async function getNewsById(id: string): Promise<SharedNews | undefined> {
  const database = getDatabaseInstance();
  const records = await database
    .get<News>('news')
    .query(Q.where("newsId", id))
    .fetch();
  const cachedNews = records[0] ? mapNewsToShared(records[0]) : undefined;

  const { getManager } = await import("@/services/shared");
  const manager = getManager();
  const activeAccount = useAccountStore.getState().lastUsedAccount;
  if (!manager || manager.getAccount().id !== activeAccount) return undefined;
  const ownsService = (id: string) => manager.getAccount().services.some(service => service.id === id);
  if (id.startsWith(pronoteRoutePrefix)) {
    const [encodedService, encodedItem] = id.slice(pronoteRoutePrefix.length).split(":");
    if (!encodedService || !encodedItem) return undefined;
    try {
      const service = decodeURIComponent(encodedService);
      const item = decodeURIComponent(encodedItem);
      if (!ownsService(service)) return undefined;
      const row = cachedNews ?? {
        title: undefined, acknowledged: false, author: "", category: "", content: "",
        createdAt: new Date(0), attachments: [], id: item, createdByAccount: service,
      };
      const fresh = await manager.getNewsDetail({ ...row, id: item });
      await addNewsToDatabase([fresh], false).catch(() => undefined);
      return fresh;
    } catch {
      return cachedNews && ownsService(cachedNews.createdByAccount) ? cachedNews : undefined;
    }
  }

  try {
    const freshNews = await manager.getNews();
    return freshNews.find(item => ownsService(item.createdByAccount) && getNewsRouteId(item) === id)
      ?? (cachedNews && ownsService(cachedNews.createdByAccount) ? cachedNews : undefined);
  } catch {
    return cachedNews && ownsService(cachedNews.createdByAccount) ? cachedNews : undefined;
  }
}

export async function addNewsToDatabase(news: SharedNews[], replaceList = true) {
  const db = getDatabaseInstance();

  // PRONOTE IDs are scoped to a service. Keep historical cache keys for other providers.
  const incoming = new Map(news.map(item => [getNewsRouteId(item), item]));
  const refreshedAccounts = new Set(news.map(item => item.createdByAccount));

  // Reading inside the write: concurrent getNews() calls are serialized, so
  // they can't both miss a record and create it twice.
  await safeWrite(
    db,
    async () => {
      const records = await db.get<News>('news').query().fetch();
      const kept = new Map<string, News>();
      const operations: Model[] = [];

      for (const record of records) {
        const isDuplicate = kept.has(record.newsId);
        const isStale = replaceList && refreshedAccounts.has(record.createdByAccount) && !incoming.has(record.newsId);

        if (isDuplicate || isStale) {
          operations.push(record.prepareDestroyPermanently());
        } else {
          kept.set(record.newsId, record);
        }
      }

      for (const [id, item] of incoming) {
        const existing = kept.get(id);
        const apply = (newsModel: News) => {
          newsModel.newsId = id;
          newsModel.title = item.title ?? newsModel.title ?? "";
          newsModel.createdAt = item.createdAt.getTime();
          if (!item.detailsRequired || !existing) {
            newsModel.acknowledged = item.acknowledged;
            newsModel.attachments = JSON.stringify(item.attachments ?? []);
            newsModel.content = item.content ?? newsModel.content ?? "";
          }
          newsModel.author = item.author ?? newsModel.author ?? "";
          newsModel.category = item.category ?? newsModel.category ?? "";
          newsModel.createdByAccount = item.createdByAccount ?? newsModel.createdByAccount ?? "";
          newsModel.question = item.question ?? newsModel.question ?? false;
        };

        operations.push(
          existing
            ? existing.prepareUpdate(model => apply(model as News))
            : db.get<News>('news').prepareCreate(model => apply(model as News))
        );
      }

      if (operations.length > 0) {
        await db.batch(operations);
      } else {
        info(`🍉 No news items to process`);
      }
    },
    10000,
    `add_news_${incoming.size}`
  );
}


export async function getNewsFromCache(): Promise<SharedNews[]> {
  try {
    const database = getDatabaseInstance();

    const news = await database
      .get<News>('news')
      .query()
      .fetch();

    return news
      .map(mapNewsToShared)
      .sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  } catch (e) {
    warn(String(e));
    return [];
  }
}

function mapNewsToShared(news: News): SharedNews {
  return {
    id: news.newsId,
    title: news.title,
    createdAt: new Date(news.createdAt),
    acknowledged: news.acknowledged,
    attachments: parseJsonArray(news.attachments) as Attachment[],
    content: news.content,
    author: news.author,
    category: news.category,
    createdByAccount: news.createdByAccount,
    fromCache: true,
    question: news.question,
    type: news.newsId.startsWith(pronoteRoutePrefix) ? (news.question ? "survey" : "information") : undefined,

  };
}
