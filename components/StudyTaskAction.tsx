import { router } from "expo-router";
import { Timer } from "lucide-react-native";
import { Alert, Pressable } from "react-native";

import { getHomeworkRouteId } from "@/database/useHomework";
import { useStudyColors } from "@/hooks/useStudyColors";
import type { Homework } from "@/services/shared/homework";
import { startStudy, useStudyStore } from "@/stores/study";
import { getActiveSession } from "@/stores/study/model";
import Typography from "@/ui/new/Typography";
import { formatHTML } from "@/utils/format/html";
import { getSubjectName } from "@/utils/subjects/name";

export default function StudyTaskAction({ homework }: { homework: Homework }) {
  const colors = useStudyColors();
  const active = useStudyStore(state => getActiveSession(state.data));
  const id = getHomeworkRouteId(homework);
  const status = active?.task?.id === id ? "Ouvrir la séance" : active ? "Associer à la séance" : "Réviser ce devoir";
  const open = async () => {
    try {
      await startStudy({
        subjectName: getSubjectName(homework.subject) || "Devoir",
        kind: "revision",
        task: { id, routeId: id, title: formatHTML(homework.content).trim() || homework.subject, completed: homework.isDone },
      });
      router.navigate({ pathname: "/(tabs)/study", params: { section: "timer", open: String(Date.now()) } });
    } catch (error) {
      Alert.alert("Révision", error instanceof Error ? error.message : "Impossible de démarrer la séance.");
    }
  };
  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => { void open(); }}
      style={({ pressed }) => ({
        flexDirection: "row", alignItems: "center", gap: 7, alignSelf: "flex-start",
        minHeight: 44, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 15,
        backgroundColor: colors.tint + "14", opacity: pressed ? 0.75 : 1,
      })}
    >
      <Timer size={16} color={colors.tint} />
      <Typography variant="body2" weight="semibold" color="primary">{status}</Typography>
    </Pressable>
  );
}
