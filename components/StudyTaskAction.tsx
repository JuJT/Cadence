import { router } from "expo-router";
import { Timer } from "lucide-react-native";
import { Pressable } from "react-native";

import { getHomeworkRouteId } from "@/database/useHomework";
import { useStudyColors } from "@/hooks/useStudyColors";
import { studyTimerHref, useStudyLaunch } from "@/hooks/useStudyLaunch";
import type { Homework } from "@/services/shared/homework";
import { useStudyStore } from "@/stores/study";
import { getActiveSession } from "@/stores/study/model";
import Typography from "@/ui/new/Typography";
import { useDragSafePress } from "@/ui/utils/useDragSafePress";
import { formatHTML } from "@/utils/format/html";
import { getSubjectName } from "@/utils/subjects/name";

export default function StudyTaskAction({ homework }: { homework: Homework }) {
  const colors = useStudyColors();
  const active = useStudyStore(state => getActiveSession(state.data));
  const id = getHomeworkRouteId(homework);
  const status = active?.task?.id === id ? "Ouvrir la séance" : "Faire le devoir";
  const { launch, launching } = useStudyLaunch(() => router.navigate(studyTimerHref("tasks")));
  const press = useDragSafePress(() => { void launch({
    subjectName: getSubjectName(homework.subject) || "Devoir",
    kind: "revision",
    task: { id, routeId: id, title: formatHTML(homework.content).trim() || homework.subject, completed: homework.isDone },
  }); });
  return (
    <Pressable
      accessibilityRole="button"
      testID="cadenza-homework-start-timer"
      accessibilityState={{ disabled: launching }}
      disabled={launching}
      {...press}
      style={({ pressed }) => ({
        flexDirection: "row", alignItems: "center", gap: 7, alignSelf: "flex-start",
        minHeight: 44, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 15,
        backgroundColor: colors.tint + "14", opacity: launching ? 0.5 : pressed ? 0.75 : 1,
      })}
    >
      <Timer size={16} color={colors.tint} />
      <Typography variant="body2" weight="semibold" color="primary">{status}</Typography>
    </Pressable>
  );
}
