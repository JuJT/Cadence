import React, { useMemo } from 'react';
import Stack from './Stack';
import Typography from './Typography';
import { formatHTML } from '@/utils/format/html';
import { useTheme } from "expo-router/react-navigation";
import { useStudyColors } from "@/hooks/useStudyColors";
import adjust from '@/utils/adjustColor';
import { Platform, Pressable, Text } from 'react-native';

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
    <Stack card radius={20} style={{ borderColor: colors.text + "32", borderWidth: Platform.OS === "android" ? 0 : 1, backgroundColor: (Platform.OS === 'android' && !theme.dark) ? "#FFF" : colors.item, elevation: 2, overflow: "hidden" }}>
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

      <Stack padding={[16, 10]} gap={6}>
          {/* Bottom */}
            <Stack inline flex hAlign='start' vAlign='center'>
              {/* Magic */}
              {magic && (
                <Dynamic animated>
                  <Stack
                    animated
                    direction="horizontal"
                    gap={6}
                    hAlign='center'
                    vAlign='center'
                    padding={[12, 6]}
                    radius={12}
                    backgroundColor={tintedColor + "20"}
                  >
                    <Papicons name='sparkles' size={22} color={tintedColor} style={{ marginLeft: -2 }} />
                    <Typography color={tintedColor} variant='body1' weight='semibold'>
                      {magic}
                    </Typography>
                  </Stack>
                </Dynamic>
              )}
            </Stack>
          <Stack animated layout={Animation(LinearTransition, "list")} direction="horizontal" gap={8} hAlign='center' style={{ justifyContent: "space-between", flexWrap: "wrap" }}>
            {studyAction ?? <Stack flex />}
            <Stack animated layout={Animation(LinearTransition, "list")} radius={300} inline hAlign='end' vAlign='center' style={{ overflow: Platform.OS === "android" ? "hidden" : undefined }}>
              <Pressable {...togglePress}
                accessibilityRole="button" accessibilityLabel={completed ? "Remettre à faire" : "Valider le devoir"}
                style={({ pressed }) => ({ opacity: pressed ? 0.6 : 1, minHeight: 44, justifyContent: "center" })}>
                <Stack
                  animated
                  layout={Animation(LinearTransition, "list")}
                  card
                  backgroundColor={completed ? tintedColor : undefined}>
                  <Stack
                    animated
                    layout={Animation(LinearTransition, "list")}
                    padding={[completed ? 12 : 8, 8]}
                    direction='horizontal'
                    gap={6}
                    radius={100}
                    hAlign='center'
                    style={{ overflow: "hidden" }}
                  >
                    <Icon size={24} opacity={completed ? 1 : 0.5} fill={completed ? "#FFF" : undefined}>
                      <Papicons name='check' />
                    </Icon>
                    {completed &&
                      <Dynamic animated>
                        <Typography color='#FFF'>
                          Terminé
                        </Typography>
                      </Dynamic>
                    }
                  </Stack>
                </Stack>
              </Pressable>
            </Stack>
          </Stack>
      </Stack>
    </Stack>
  );
});

Task.displayName = "Task";

export default Task;
