import { useEffect, useMemo, useState } from "react";
import { AppState } from "react-native";

import { getWeekNumberFromDate } from "@/database/useHomework";
import { getCourseRouteId, useTimetable } from "@/database/useTimetable";
import { CourseStatus, CourseType } from "@/services/shared/timetable";
import { useAccountStore } from "@/stores/account";
import { refreshStudySurface, syncScheduledStudyCourses } from "@/stores/study";
import { cleanSubjectName, getSubjectFormat } from "@/utils/subjects/utils";

const YEAR_END_WEEKS = [47, 48, 49, 50, 51, 52, 53, 54];
const LAST_WEEK = [54];

export function useStudyTimetableSync() {
  const [today, setToday] = useState(() => new Date());
  const currentYear = today.getFullYear();
  const week = getWeekNumberFromDate(today);
  const weeks = useMemo(() => {
    const first = Math.max(1, week - 6);
    return Array.from({ length: week - first + 2 }, (_, index) => first + index);
  }, [week]);
  const previousYear = useMemo(() => new Date(currentYear - 1, 11, 31), [currentYear]);
  const currentTimetable = useTimetable(0, weeks, today);
  const previousTimetable = useTimetable(0, week <= 6 ? YEAR_END_WEEKS : LAST_WEEK, previousYear);
  const activeProfile = useAccountStore(state => state.accounts.find(account => account.id === state.lastUsedAccount));

  useEffect(() => {
    const subscription = AppState.addEventListener("change", phase => {
      if (phase === "active") {
        setToday(new Date());
        refreshStudySurface();
      }
    });
    return () => subscription.remove();
  }, []);

  useEffect(() => {
    if (!activeProfile) return;
    const services = new Set(activeProfile.services?.map(service => service.id));
    const days = week <= 6 ? [...previousTimetable, ...currentTimetable] : currentTimetable;
    const timetable = days.flatMap(day => day.courses)
      .filter(course => course.type === CourseType.LESSON &&
        (services.has(course.createdByAccount) || course.createdByAccount.startsWith("ical_")))
      .map(course => {
        const customName = activeProfile.customisation?.subjects?.[cleanSubjectName(course.subject)]?.name;
        return {
          id: getCourseRouteId(course),
          subjectName: customName || getSubjectFormat(course.subject)?.pretty || course.subject,
          start: course.from.getTime(),
          end: course.to.getTime(),
          canceled: course.status === CourseStatus.CANCELED,
        };
      });
    if (timetable.length > 0) void syncScheduledStudyCourses(timetable).catch(() => {});
  }, [activeProfile, currentTimetable, previousTimetable, week]);
}
