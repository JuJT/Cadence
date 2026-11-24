import { useIsFocused } from "expo-router/react-navigation";
import { router } from "expo-router";
import { BarChart3, ChevronRight, Timer } from "lucide-react-native";
import { useEffect, useState } from "react";
import { AppState, Pressable, Text, View, type TextStyle } from "react-native";

import { useStudyColors } from "@/hooks/useStudyColors";
import { useStudyStore } from "@/stores/study";
import { clockText, elapsedSeconds, getActiveSession, isPaused, type StudySession } from "@/stores/study/model";
import Typography from "@/ui/new/Typography";

export function StudyClock({ session, style }: { session: StudySession; style?: TextStyle }) {
  const colors = useStudyColors();
  const focused = useIsFocused();
  const [now, setNow] = useState(Date.now);
  const running = !isPaused(session) && session.endedAt === undefined;
  useEffect(() => {
    if (!running || !focused) return;
    let tick: ReturnType<typeof setInterval> | undefined;
    const stop = () => {
      if (tick !== undefined) clearInterval(tick);
      tick = undefined;
    };
    const sync = (phase: string | null | undefined) => {
      stop();
      if (phase == null || phase === "active") {
        setNow(Date.now());
        tick = setInterval(() => setNow(Date.now()), 1000);
      }
    };
    const subscription = AppState.addEventListener("change", sync);
    sync(AppState.currentState);
    return () => {
      stop();
      subscription.remove();
    };
  }, [session.id, running, focused]);
  const display = clockText(elapsedSeconds(session, now));
  return (
    <Text
      accessibilityLabel={"Temps écoulé " + display}
      testID="cadenza-study-clock"
      style={[{ color: colors.text, fontWeight: "700", fontVariant: ["tabular-nums"] }, style]}
    >
      {display}
    </Text>
  );
}

export function StudyEntry({ statistics = false, accessory = false }: { statistics?: boolean; accessory?: boolean }) {
  const colors = useStudyColors();
  const active = useStudyStore(state => getActiveSession(state.data));
  const subject = useStudyStore(state => state.data.subjects.find(item => item.id === active?.subjectId));
  const title = statistics ? "Statistiques" : accessory ? subject?.name ?? "Révision" : active ? "Séance en cours" : "Révision";
  const subtitle = statistics ? "Par matière et par période" : active
    ? (isPaused(active) ? "En pause" : active.kind === "course" ? "Cours en cours" : "Révision en cours")
    : "Chronomètre et historique";
  const Glyph = statistics ? BarChart3 : Timer;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={title + ", " + subtitle}
      onPress={() => router.navigate({ pathname: "/(tabs)/study", params: { section: statistics ? "stats" : "timer", open: String(Date.now()) } })}
      style={({ pressed }) => ({
        backgroundColor: accessory ? "transparent" : colors.card,
        borderColor: colors.border, borderWidth: accessory ? 0 : 1, borderRadius: 18,
        flexDirection: "row", alignItems: "center", gap: 10,
        paddingHorizontal: 13, paddingVertical: accessory ? 4 : 12, minHeight: accessory ? 40 : 48,
        opacity: pressed ? 0.7 : 1, flex: accessory ? 1 : undefined,
      })}
    >
      <Glyph size={20} color={colors.tint} />
      <View style={{ flex: 1 }}>
        <Typography variant="title" numberOfLines={accessory ? 1 : undefined}>{title}</Typography>
        <Typography variant="caption" color="textSecondary" numberOfLines={accessory ? 1 : undefined}>{subtitle}</Typography>
      </View>
      {accessory && active ? <StudyClock session={active} style={{ fontSize: 15 }} /> : <ChevronRight size={16} color={colors.tint} />}
    </Pressable>
  );
}
