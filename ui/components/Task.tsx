import React, { useMemo } from 'react';
import Stack from './Stack';
import Typography from './Typography';
import { formatHTML } from '@/utils/format/html';
import { useTheme } from "expo-router/react-navigation";
import { useStudyColors } from "@/hooks/useStudyColors";
import adjust from '@/utils/adjustColor';
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native';

import { formatDistanceStrict, startOfDay } from 'date-fns';
import * as DateLocale from 'date-fns/locale';
import i18n from '@/utils/i18n';
import { LinearGradient } from 'expo-linear-gradient';
import { Papicons } from '@getpapillon/papicons';
import Icon from './Icon';
import { Dynamic } from './Dynamic';
import { Animation } from '../utils/Animation';
import { LinearTransition } from 'react-native-reanimated';
import { useDragSafePress } from "../utils/useDragSafePress";

interface TaskProps {
  subject: string;
  emoji: string;
  title: string;
  color: string;
  description: string;
  date: Date;
  completed: boolean;
  hasAttachments: boolean;
  isCustom?: boolean;
  magic?: string;
  studyAction?: React.ReactNode;
  onToggle: () => void;
  onPress?: () => void;
}

export function formatDistanceDay(date: Date): string {
  // if yesterday, today or tomorrow
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);

  if (date.toDateString() === yesterday.toDateString()) {
    return i18n.t("Yesterday").toLowerCase();
  } else if (date.toDateString() === today.toDateString()) {
    return i18n.t("Today").toLowerCase();
  } else if (date.toDateString() === tomorrow.toDateString()) {
    return i18n.t("Tomorrow").toLowerCase();
  }

  return formatDistanceStrict(startOfDay(date), startOfDay(new Date()), { addSuffix: true, unit: "day", locale: DateLocale[i18n.language as keyof typeof DateLocale] || DateLocale.enUS })
}

const Task: React.FC<TaskProps> = React.memo(({
  subject,
  emoji,
  title,
  color,
  description,
  date,
  completed,
  hasAttachments,
  isCustom = false,
  magic,
  studyAction,
  onToggle,
  onPress
}) => {
  const theme = useTheme();
  const colors = useStudyColors();
  const openPress = useDragSafePress(onPress);
  const togglePress = useDragSafePress(onToggle);
  const tintedColor = useMemo(() => adjust(color, theme.dark ? 0.3 : -0.3), [color, theme.dark]);
  const formattedDescription = useMemo(() => formatHTML(description), [description]);

  return (
    <View style={[styles.card, { borderColor: colors.text + "32", borderWidth: Platform.OS === "android" ? 0 : 1,
      backgroundColor: (Platform.OS === 'android' && !theme.dark) ? "#FFF" : colors.item }]}>
      <Pressable {...openPress} accessibilityRole={onPress ? "link" : undefined} disabled={!onPress}>
        {/* The card above already clips to its corners: a second rounded clip
            here would cost another offscreen pass per row, on every row the
            week pager moves across the screen. */}
        <Stack padding={[16, 14]} gap={12}>
          {Platform.OS !== "android" && (
            <LinearGradient
              colors={[color, colors.card]}
              style={{
                position: "absolute",
                top: 0,
                left: 0,
              right: 0,
              height: 100,
              zIndex: -1,
              opacity: 0.1
            }}
          /> )}

          {/* Subejct */}
          <Stack direction="horizontal" gap={8} hAlign='center'>
            {/* Emoji container */}
            <Text style={{ fontSize: 22 }}>
              {emoji}
            </Text>
            {/* Name */}
            <Stack inline flex direction="horizontal" gap={4} hAlign='center'>
              <Typography nowrap variant='body1' weight='semibold' color={tintedColor} style={{ flexShrink: 1 }}>
                {subject}
              </Typography>

              {/* Attachments */}
              {hasAttachments && (
                <Icon size={18} fill={tintedColor}>
                  <Papicons name="link" />
                </Icon>
              )}

              {isCustom && (
                <Icon size={18} fill={tintedColor}>
                  <Papicons name="PenAlt" />
                </Icon>
              )}
            </Stack>
            {/* Date */}
            <Typography nowrap variant='body2' weight='medium' color={"secondary"}>
              {formatDistanceDay(date)}
            </Typography>
          </Stack>

          {/* Content */}
          <Stack animated layout={Animation(LinearTransition, "list")}>
            <Typography numberOfLines={3} variant='title' weight='medium'>
              {formattedDescription}
            </Typography>
          </Stack>
        </Stack>
      </Pressable>

      <View style={styles.footer}>
        {magic && (
          <Dynamic animated>
            <View style={[styles.magic, { backgroundColor: tintedColor + "20" }]}>
              <Papicons name='sparkles' size={22} color={tintedColor} />
              <Typography color={tintedColor} variant='body1' weight='semibold'>{magic}</Typography>
            </View>
          </Dynamic>
        )}
        <View style={styles.actions}>
          {studyAction}
          <Pressable {...togglePress} accessibilityRole="button"
            accessibilityLabel={completed ? "Remettre à faire" : "Valider le devoir"}
            style={({ pressed }) => [styles.toggle, {
              paddingHorizontal: completed ? 12 : 9,
              backgroundColor: completed ? tintedColor : colors.item,
              borderColor: completed ? 'transparent' : colors.border,
              opacity: pressed ? 0.6 : 1,
            }]}>
            <Icon size={24} opacity={completed ? 1 : 0.5} fill={completed ? "#FFF" : undefined}>
              <Papicons name='check' />
            </Icon>
            {completed && <Typography color='#FFF'>Terminé</Typography>}
          </Pressable>
        </View>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  card: { width: '100%', borderRadius: 20, borderCurve: 'continuous', elevation: 2, overflow: 'hidden' },
  footer: { paddingHorizontal: 16, paddingBottom: 10, gap: 6 },
  actions: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
  toggle: { marginLeft: 'auto', flexDirection: 'row', alignItems: 'center', gap: 6, minHeight: 44,
    borderWidth: StyleSheet.hairlineWidth, borderRadius: 22 },
  magic: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 12, paddingVertical: 6, borderRadius: 12 },
});

Task.displayName = "Task";

export default Task;
