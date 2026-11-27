import { useState, useCallback } from 'react';
import { Homework } from "@/services/shared/homework";
import { getSubjectName } from "@/utils/subjects/name";
import { compareHomeworkDeadlines, homeworkDayPriority } from "../utils/homeworkOrder";

export type SortMethod = 'date' | 'subject' | 'done';

const normalize = (value: string) =>
  value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");

const formatDateHeader = (date: Date): string => {
  return date.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
};

export interface HomeworkSection {
  id: string;
  title: string;
  date?: Date;
  data: Homework[];
}

export interface TaskFilterOptions {
  searchTerm: string;
  sortMethod: SortMethod;
  showUndoneOnly?: boolean;
}

// Pure, so every week rendered by the pager can build its own sections from the
// filters shared by the screen without duplicating hook state per page.
export const buildHomeworkSections = (
  homeworks: Homework[],
  { searchTerm, sortMethod, showUndoneOnly = false }: TaskFilterOptions
): HomeworkSection[] => {
  const uniqueIds = new Set<string>();
  let data = homeworks.filter(hw => {
    if (hw.id) {
      const id = JSON.stringify([hw.createdByAccount, hw.id]);
      if (!uniqueIds.has(id)) {
        uniqueIds.add(id);
        return true;
      }
      return false;
    }
    return true;
  });

  if (showUndoneOnly) {
    data = data.filter(h => !h.isDone);
  }

  if (searchTerm.trim().length > 0) {
    const term = normalize(searchTerm);
    data = data.filter(h => {
      const cleanContent = h.content.replace(/<[^>]*>/g, "");
      const normalizedContent = normalize(cleanContent);
      const normalizedSubject = normalize(h.subject);
      const normalizedSubjectName = normalize(getSubjectName(h.subject));
      return (
        normalizedContent.includes(term) ||
        normalizedSubject.includes(term) ||
        normalizedSubjectName.includes(term)
      );
    });
  }

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const startOfToday = today.getTime();
  const byDeadline = (a: Homework, b: Homework) => compareHomeworkDeadlines(a, b, startOfToday);
  if (sortMethod === 'date' || sortMethod === 'done') {
    data.sort(byDeadline);
  } else if (sortMethod === 'subject') {
    data.sort((a, b) => a.subject.localeCompare(b.subject) || byDeadline(a, b));
  }

  const isSearching = searchTerm.trim().length > 0;

  if (sortMethod === 'date' && !isSearching) {
    const sectionMap = new Map<string, HomeworkSection>();

    data.forEach((hw) => {
      const hwDate = new Date(hw.dueDate);
      const priority = homeworkDayPriority(hw, startOfToday);
      const dateKey = priority + "-" + hwDate.toDateString();
      const headerId = `header-${dateKey}`;

      if (!sectionMap.has(dateKey)) {
        sectionMap.set(dateKey, {
          id: headerId,
          title: priority === 2 ? "Terminés · " + formatDateHeader(hwDate)
            : priority === 1 ? "En retard · " + formatDateHeader(hwDate)
            : formatDateHeader(hwDate),
          date: hwDate,
          data: []
        });
      }

      sectionMap.get(dateKey)!.data.push(hw);
    });

    return Array.from(sectionMap.values());
  }

  return [
    {
      id: 'all',
      title: '',
      data
    }
  ];
};

export const useTaskFilters = () => {
  const [searchTerm, setSearchTerm] = useState("");
  const [showUndoneOnly, setShowUndoneOnly] = useState(false);
  const [sortMethod, setSortMethod] = useState<SortMethod>("date");
  const [collapsedGroups, setCollapsedGroups] = useState<string[]>([]);

  const toggleGroup = useCallback((headerId: string) => {
    setCollapsedGroups(prev => {
      if (prev.includes(headerId)) {
        return prev.filter(id => id !== headerId);
      }
      return [...prev, headerId];
    });
  }, []);

  return {
    searchTerm,
    setSearchTerm,
    showUndoneOnly,
    setShowUndoneOnly,
    sortMethod,
    setSortMethod,
    collapsedGroups,
    toggleGroup,
  };
};
