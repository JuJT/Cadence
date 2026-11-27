import { describe, expect, it } from "@jest/globals";
import { SessionHandle, TabLocation, UserAuthorizations } from "@blockshub/pawnote-lts";

import { Capabilities } from "@/services/shared/types";

import { hasPronoteTab, pronoteCapabilities } from "./capabilities";

function session(
  tabs: TabLocation[],
  resourceTabs: TabLocation[],
  permissions: Partial<UserAuthorizations> = {},
): SessionHandle {
  return {
    user: { authorizations: { tabs, ...permissions } },
    userResource: { tabs: new Map(resourceTabs.map(tab => [tab, { location: tab, periods: [] }])) },
  } as SessionHandle;
}

describe("PRONOTE account and resource tabs", () => {
  it("recognizes account-wide pages when resource tabs only enumerate period metadata", () => {
    const demo = session(
      [TabLocation.Timetable, TabLocation.Assignments, TabLocation.Resources, TabLocation.News, TabLocation.Discussions],
      [TabLocation.Grades, TabLocation.Notebook],
      { canReadDiscussions: true, canDiscuss: true, canDiscussWithTeachers: true },
    );
    expect(pronoteCapabilities(demo)).toEqual(expect.arrayContaining([
      Capabilities.TIMETABLE, Capabilities.HOMEWORK, Capabilities.COURSE_RESOURCES, Capabilities.NEWS,
      Capabilities.CHAT_READ, Capabilities.CHAT_REPLY, Capabilities.CHAT_CREATE,
      Capabilities.GRADES, Capabilities.ATTENDANCE,
    ]));
    expect(hasPronoteTab(demo, TabLocation.Menus)).toBe(false);
  });

  it("uses role restrictions even when an account advertises the discussion tab", () => {
    const advertised = [TabLocation.Discussions];
    expect(pronoteCapabilities(session(advertised, []))).toEqual([Capabilities.REFRESH]);
    expect(pronoteCapabilities(session(advertised, [], { canReadDiscussions: true })))
      .toEqual([Capabilities.REFRESH, Capabilities.CHAT_READ]);
    expect(pronoteCapabilities(session(advertised, [], { canReadDiscussions: true, canDiscuss: true })))
      .toEqual([Capabilities.REFRESH, Capabilities.CHAT_READ, Capabilities.CHAT_REPLY]);
    expect(pronoteCapabilities(session([], [], { canReadDiscussions: true, canDiscuss: true, canDiscussWithTeachers: true })))
      .toEqual([Capabilities.REFRESH]);
  });
});
