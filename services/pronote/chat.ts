import {
  discussionMessages,
  discussionRecipients,
  discussions,
  DiscussionSendAction,
  discussionSendMessage,
  EntityKind,
  newDiscussion,
  newDiscussionRecipients,
  SessionHandle,
  TabLocation,
} from "@blockshub/pawnote-lts";

import { Chat, Message, Recipient } from "@/services/shared/chat";

function requireChatPermission(session: SessionHandle, write = false) {
  const permissions = session.user.authorizations;
  if (!session.userResource.tabs.has(TabLocation.Discussions) || !permissions.canReadDiscussions ||
      (write && !permissions.canDiscuss)) {
    throw new Error("Cette action est indisponible pour ce compte PRONOTE.");
  }
  return permissions;
}

async function findDiscussion(session: SessionHandle, id: string) {
  requireChatPermission(session);
  const { items } = await discussions(session);
  const item = items.find(thread => thread.participantsMessageID === id);
  if (!item) throw new Error("Cette discussion n’est plus disponible.");
  return item;
}

function cleanMessage(session: SessionHandle, raw: string): string {
  const text = raw.trim();
  if (!text || text.length > 20000) throw new Error("Saisissez un message de 1 à 20 000 caractères.");
  if (!session.user.authorizations.hasAdvancedDiscussionEditor) return text;
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\r?\n/g, "<br>");
}

export async function fetchPronoteChats(session: SessionHandle, accountId: string): Promise<Chat[]> {
  requireChatPermission(session);
  const { items } = await discussions(session);
  return items.map(chat => ({
    id: chat.participantsMessageID,
    subject: chat.subject,
    provider: "pronote",
    creator: chat.creator,
    recipient: chat.recipientName,
    date: chat.date,
    createdByAccount: accountId,
  }));
}

export async function fetchPronoteChatRecipients(session: SessionHandle, chat: Chat): Promise<Recipient[]> {
  const item = await findDiscussion(session, chat.id);
  const recipients = await discussionRecipients(session, item);
  return recipients.map(recipient => ({ id: recipient.id, name: recipient.name }));
}

export async function fetchPronoteChatMessages(
  session: SessionHandle, accountId: string, chat: Chat,
): Promise<Message[]> {
  const item = await findDiscussion(session, chat.id);
  const messages = await discussionMessages(session, item, false);
  return messages.sents.map(message => ({
    id: message.id,
    subject: "",
    content: message.content,
    author: message.author?.name ?? session.userResource.name,
    date: message.creationDate,
    attachments: message.files.map(file => ({
      type: file.kind,
      name: file.name,
      url: file.url,
      createdByAccount: accountId,
    })),
  }));
}

async function getReplyableDiscussion(session: SessionHandle, chat: Chat) {
  if (!requireChatPermission(session).canDiscuss) return undefined;
  const thread = await findDiscussion(session, chat.id);
  if (thread.closed) return undefined;
  const { sendAction } = await discussionMessages(session, thread, false);
  return sendAction == null || sendAction === DiscussionSendAction.Close ? undefined : thread;
}

export async function canReplyToPronoteChat(session: SessionHandle, chat: Chat): Promise<boolean> {
  return Boolean(await getReplyableDiscussion(session, chat));
}

export async function sendPronoteMessageInChat(session: SessionHandle, chat: Chat, content: string): Promise<void> {
  const text = cleanMessage(session, content);
  const thread = await getReplyableDiscussion(session, chat);
  if (!thread) throw new Error("PRONOTE n’autorise plus les réponses dans ce fil.");
  await discussionSendMessage(session, thread, text);
}

async function getNewRecipients(session: SessionHandle) {
  const permissions = requireChatPermission(session, true);
  const kinds: Array<typeof EntityKind.Teacher | typeof EntityKind.Personal> = [];
  if (permissions.canDiscussWithTeachers) kinds.push(EntityKind.Teacher);
  if (permissions.canDiscussWithStaff) kinds.push(EntityKind.Personal);
  const groups = await Promise.all(kinds.map(kind => newDiscussionRecipients(session, kind)));
  return new Map(groups.flat().map(recipient => [recipient.kind + ":" + recipient.id, recipient]));
}

export async function fetchPronoteRecipients(session: SessionHandle): Promise<Recipient[]> {
  return [...await getNewRecipients(session)].map(([id, recipient]) => ({ id, name: recipient.name }));
}

export async function createPronoteMail(
  session: SessionHandle, accountId: string, subject: string, content: string, recipients: Recipient[],
): Promise<Chat> {
  const title = subject.trim();
  const text = cleanMessage(session, content);
  const ids = recipients.map(recipient => recipient.id);
  if (!title || title.length > 200 || !ids.length || ids.length > 20 || new Set(ids).size !== ids.length) {
    throw new Error("Vérifiez l’objet et les destinataires avant l’envoi.");
  }
  const available = await getNewRecipients(session);
  const selected = ids.map(id => {
    const recipient = available.get(id);
    if (!recipient) throw new Error("Un destinataire n’est plus disponible. Vérifiez votre sélection.");
    return recipient;
  });

  await newDiscussion(session, title, text, selected);
  return {
    id: "",
    subject: title,
    recipient: selected.map(recipient => recipient.name).join(", "),
    creator: session.user.name,
    date: new Date(),
    createdByAccount: accountId,
  };
}
