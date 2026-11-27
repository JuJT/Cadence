import { beforeEach, describe, expect, it, jest } from "@jest/globals";
import {
  SessionHandle, TabLocation, discussionMessages, discussionSendMessage, discussions, newDiscussion, newDiscussionRecipients,
} from "@blockshub/pawnote-lts";

import { createPronoteMail, fetchPronoteChatMessages, sendPronoteMessageInChat } from "./chat";

jest.mock("@blockshub/pawnote-lts", () => ({
  TabLocation: { Discussions: 131 },
  EntityKind: { Teacher: 3, Personal: 4 },
  DiscussionSendAction: { Close: 5 },
  discussionMessages: jest.fn(),
  discussionSendMessage: jest.fn(),
  discussions: jest.fn(),
  newDiscussion: jest.fn(),
  newDiscussionRecipients: jest.fn(),
}));

const session = {
  user: { authorizations: { tabs: [TabLocation.Discussions], canReadDiscussions: true, canDiscuss: true, canDiscussWithTeachers: true } },
  userResource: { tabs: new Map() },
} as unknown as SessionHandle;
const chat = { id: "thread", subject: "Cours", date: new Date(), createdByAccount: "test" };
const thread = { participantsMessageID: chat.id } as Awaited<ReturnType<typeof discussions>>["items"][number];

describe("PRONOTE discussions", () => {
  beforeEach(() => { jest.resetAllMocks(); });

  it("opens a thread without marking it read", async () => {
    jest.mocked(discussions).mockResolvedValue({ folders: [], items: [thread] });
    jest.mocked(discussionMessages).mockResolvedValue({ sents: [], drafts: [], defaultReplyMessageID: "", canIncludeStudentsAndParents: false });
    await fetchPronoteChatMessages(session, "test", chat);
    expect(discussionMessages).toHaveBeenCalledWith(session, thread, false);
  });

  it("does not send if the current thread no longer accepts replies", async () => {
    jest.mocked(discussions).mockResolvedValue({ folders: [], items: [{ ...thread, closed: true }] });
    await expect(sendPronoteMessageInChat(session, chat, "Bonjour")).rejects.toThrow();
    expect(discussionSendMessage).not.toHaveBeenCalled();
  });

  it("does not send to a reduced subset after recipients change", async () => {
    const allowed = { kind: 3, id: "a", name: "A" } as Awaited<ReturnType<typeof newDiscussionRecipients>>[number];
    jest.mocked(newDiscussionRecipients).mockResolvedValue([allowed]);
    const recipients = [{ id: "3:a", name: "A" }, { id: "3:b", name: "B" }];
    await expect(createPronoteMail(session, "test", "Cours", "Bonjour", recipients)).rejects.toThrow();
    expect(newDiscussion).not.toHaveBeenCalled();
  });
});
