import { ArrowDown, Pause, Play, Square } from "lucide-react-native";
import { useEffect, useRef, useState } from "react";
import {
  AccessibilityInfo, Animated, Easing, Modal, Pressable, ScrollView, StyleSheet, View, useWindowDimensions,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle, Defs, LinearGradient, Stop } from "react-native-svg";

import { StudyClock } from "@/components/StudyEntry";
import { useStudyColors } from "@/hooks/useStudyColors";
import { isPaused, type StudySession } from "@/stores/study/model";
import Typography from "@/ui/new/Typography";

function useReduceMotion() {
  const [reduced, setReduced] = useState(true);
  useEffect(() => {
    let live = true;
    void AccessibilityInfo.isReduceMotionEnabled().then(value => { if (live) setReduced(value); }).catch(() => {});
    const listener = AccessibilityInfo.addEventListener("reduceMotionChanged", setReduced);
    return () => {
      live = false;
      listener.remove();
    };
  }, []);
  return reduced;
}

type Props = {
  session: StudySession;
  subjectName: string;
  visible: boolean;
  onReduce: () => void;
  onTogglePause: () => void;
  onFinish: () => void;
};

export default function StudyFocusModal({ session, subjectName, visible, onReduce, onTogglePause, onFinish }: Props) {
  const colors = useStudyColors();
  const reduced = useReduceMotion();
  const paused = isPaused(session);
  const { width, height, fontScale } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const diameter = Math.min(width - 54, Math.max(226, height * 0.4), 350);
  const orbit = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (reduced || paused || !visible) return;
    const animation = Animated.loop(Animated.timing(orbit, {
      toValue: 1, duration: 20000, easing: Easing.linear, useNativeDriver: true, isInteraction: false,
    }));
    animation.start();
    return () => {
      animation.stop();
      orbit.setValue(0);
    };
  }, [orbit, paused, reduced, visible]);

  return (
    <Modal visible={visible} animationType={reduced ? "none" : "fade"} presentationStyle="fullScreen" onRequestClose={onReduce}>
      <View style={[styles.screen, { backgroundColor: colors.background, paddingTop: insets.top,
        paddingBottom: insets.bottom, paddingLeft: insets.left, paddingRight: insets.right }]} accessibilityViewIsModal>
        <ScrollView contentInsetAdjustmentBehavior="never" showsVerticalScrollIndicator={false} contentContainerStyle={styles.content}>
          <Pressable accessibilityRole="button" accessibilityLabel="Réduire le chronomètre" onPress={onReduce}
            testID="cadenza-study-reduce" style={[styles.control, { alignSelf: "flex-start" }]}>
            <ArrowDown size={19} color={colors.tint} />
            <Typography color="primary" weight="semibold">Réduire</Typography>
          </Pressable>
          <View style={styles.main}>
            <Typography variant="h4" align="center" accessibilityRole="header">{subjectName}</Typography>
            {!!session.title && session.title !== subjectName && (
              <Typography align="center" color="textSecondary">{session.title}</Typography>
            )}
            <View style={{ width: diameter, height: diameter, alignItems: "center", justifyContent: "center", marginVertical: 14 }}>
              <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, {
                transform: [{ rotate: orbit.interpolate({ inputRange: [0, 1], outputRange: ["0deg", "360deg"] }) }],
              }]}>
                <Svg width={diameter} height={diameter} viewBox="0 0 300 300" accessible={false}>
                  <Defs>
                    <LinearGradient id="study-orbit" x1="0%" y1="12%" x2="100%" y2="88%">
                      <Stop offset="0" stopColor="#88CEFF" />
                      <Stop offset="0.53" stopColor={colors.tint} />
                      <Stop offset="1" stopColor="#43CFEA" />
                    </LinearGradient>
                  </Defs>
                  <Circle cx={150} cy={150} r={139} fill={colors.card} stroke={colors.tint} strokeOpacity={0.2} strokeWidth={14} />
                  <Circle cx={150} cy={150} r={139} fill="none" stroke="url(#study-orbit)" strokeWidth={paused ? 7 : 13}
                    opacity={paused ? 0.55 : 1} />
                  <Circle cx={150} cy={150} r={123} fill="none" stroke={colors.tint} strokeOpacity={0.12} strokeWidth={1} />
                </Svg>
              </Animated.View>
              <View style={{ width: "85%", alignItems: "center", gap: 5 }}>
                <Typography align="center" variant="caption" color="primary" weight="semibold">
                  {paused ? "En pause" : session.kind === "course" ? "Cours en cours" : "Révision en cours"}
                </Typography>
                <StudyClock session={session} testID="cadenza-study-fullscreen-clock"
                  style={{ fontSize: Math.min(diameter * 0.18, 58) / Math.max(1, fontScale / 1.4), color: colors.tint }} />
              </View>
            </View>
            <View style={styles.actions}>
              <Pressable accessibilityRole="button" onPress={onTogglePause}
                style={[styles.control, { backgroundColor: colors.tint + "15" }]}>
                {paused ? <Play size={16} color={colors.tint} /> : <Pause size={16} color={colors.tint} />}
                <Typography weight="semibold" color="primary">{paused ? "Reprendre" : "Pause"}</Typography>
              </Pressable>
              <Pressable accessibilityRole="button" onPress={onFinish} style={[styles.control, { backgroundColor: colors.tint }]}>
                <Square size={15} color="#fff" />
                <Typography weight="semibold" color="#fff">Terminer</Typography>
              </Pressable>
            </View>
            {!!session.task && (
              <View style={[styles.task, { backgroundColor: colors.overground, borderColor: colors.border }]}>
                <Typography variant="caption" color="primary" weight="semibold">Devoir associé</Typography>
                <Typography numberOfLines={4}>{session.task.title}</Typography>
              </View>
            )}
          </View>
        </ScrollView>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  content: { flexGrow: 1, width: "100%", maxWidth: 580, alignSelf: "center", padding: 22 },
  main: { paddingVertical: 18, flex: 1, alignItems: "center", justifyContent: "center", gap: 12 },
  actions: { flexDirection: "row", flexWrap: "wrap", justifyContent: "center", gap: 10 },
  control: { flexDirection: "row", alignItems: "center", minHeight: 48, borderRadius: 18, gap: 8, paddingHorizontal: 16, paddingVertical: 10 },
  task: { width: "100%", borderWidth: StyleSheet.hairlineWidth, borderRadius: 18, padding: 13, gap: 4 },
});
