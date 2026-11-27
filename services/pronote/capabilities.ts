import { SessionHandle, TabLocation } from "@blockshub/pawnote-lts";

import { Capabilities } from "@/services/shared/types";

export function hasPronoteTab(session: SessionHandle, tab: TabLocation): boolean {
  // The account lists available pages. The active pupil only lists tabs
  // carrying resource-specific data such as grade or attendance periods.
  return session.user?.authorizations?.tabs?.includes(tab) === true ||
    session.userResource?.tabs?.has(tab) === true;
}

export function pronoteCapabilities(session: SessionHandle): Capabilities[] {
  const capabilities = [Capabilities.REFRESH];
  const permissions = session.user?.authorizations;
  const byTab: Partial<Record<TabLocation, Capabilities[]>> = {
    [TabLocation.Assignments]: [Capabilities.HOMEWORK],
    [TabLocation.Grades]: [Capabilities.GRADES],
    [TabLocation.Notebook]: [Capabilities.ATTENDANCE, Capabilities.ATTENDANCE_PERIODS],
    [TabLocation.News]: [Capabilities.NEWS],
    [TabLocation.Menus]: [Capabilities.CANTEEN_MENU],
    [TabLocation.Evaluations]: [Capabilities.SKILLS],
    [TabLocation.Gradebook]: [Capabilities.REPORT_CARDS],
    [TabLocation.Resources]: [Capabilities.COURSE_RESOURCES],
    [TabLocation.Timetable]: [Capabilities.TIMETABLE],
  };
  for (const tab of Object.keys(byTab).map(Number) as TabLocation[]) {
    if (hasPronoteTab(session, tab)) capabilities.push(...(byTab[tab] ?? []));
  }
  if (hasPronoteTab(session, TabLocation.Discussions) && permissions?.canReadDiscussions) {
    capabilities.push(Capabilities.CHAT_READ);
    if (permissions.canDiscuss) {
      capabilities.push(Capabilities.CHAT_REPLY);
      if (permissions.canDiscussWithTeachers || permissions.canDiscussWithStaff) {
        capabilities.push(Capabilities.CHAT_CREATE);
      }
    }
  }
  return capabilities;
}
