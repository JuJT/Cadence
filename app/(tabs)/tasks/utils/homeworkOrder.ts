type HomeworkDeadline = { dueDate: Date; isDone: boolean };

export function homeworkDayPriority(homework: HomeworkDeadline, startOfToday: number) {
  if (homework.isDone) return 2;
  return new Date(homework.dueDate).getTime() < startOfToday ? 1 : 0;
}

export function compareHomeworkDeadlines(a: HomeworkDeadline, b: HomeworkDeadline, startOfToday: number) {
  const aPriority = homeworkDayPriority(a, startOfToday);
  const bPriority = homeworkDayPriority(b, startOfToday);
  const difference = new Date(a.dueDate).getTime() - new Date(b.dueDate).getTime();
  return aPriority - bPriority || (aPriority === 0 ? difference : -difference);
}
