import React, { useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { getCurrentPeriod } from '@/utils/grades/helper/period';
import { useSchoolManager } from '@/components/pronote/SchoolPage';
import { Capabilities } from '@/services/shared/types';

import HomeHeaderButton, { HomeHeaderButtonItem } from '../components/HomeHeaderButton';
import { useHomeHeaderData } from '../hooks/useHomeHeaderData';

const HomeHeader = () => {
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const { availableCanteenCards, attendancesPeriods, attendances, absencesCount, news } = useHomeHeaderData();
  const { manager } = useSchoolManager();
  const canDiscuss = (manager?.getAvailableClients(Capabilities.CHAT_READ).length ?? 0) > 0;
  const canReadLessons = (manager?.getAvailableClients(Capabilities.COURSE_RESOURCES).length ?? 0) > 0;
  const canReadNews = (manager?.getAvailableClients(Capabilities.NEWS).length ?? 0) > 0;
  const currentAttendancePeriod = attendancesPeriods.length > 0
    ? getCurrentPeriod(attendancesPeriods)
    : undefined;

  const HomeHeaderButtons: HomeHeaderButtonItem[] = useMemo(() => [
    {
      title: t("Home_Cards_Button_Title"),
      image: require("@/assets/shaded_icons/cards.png"),
      icon: "card",
      color: "#c800ad",
      description: availableCanteenCards.length > 0 ?
        (availableCanteenCards.length > 1 ? t("Home_Cards_Button_Description_Number", { number: availableCanteenCards.length }) :
          t("Home_Cards_Button_Description_Singular")) : t("Home_Cards_Button_Description_None"),
      route: "/(features)/(cards)/cards"
    },
    {
      title: t("Home_Menu_Button_Title"),
      image: require("@/assets/shaded_icons/menu.png"),
      icon: "cutlery",
      color: "#46c700",
      description: t("Home_Menu_Button_Description"),
      route: "/(features)/canteen-menu"
    },
    {
      title: t("Home_Attendance_Title"),
      image: require("@/assets/shaded_icons/homework.png"),
      icon: "chair",
      color: "#ffae00",
      description: absencesCount > 0 ?
        (absencesCount > 1 ? t("Home_Attendance_Button_Description_Number", { number: absencesCount }) : t("Home_Attendance_Button_Description_Singular"))
        : t("Home_Attendance_Button_Description_None"),
      route: "/(features)/attendance",
      params: {
        periods: JSON.stringify(attendancesPeriods),
        currentPeriod: JSON.stringify(currentAttendancePeriod),
        attendances: JSON.stringify(attendances),
      },
    },
    ...(canReadNews || news.length > 0 ? [{
      title: "Informations et sondages",
      image: require("@/assets/shaded_icons/actu.png"),
      icon: "newspaper",
      color: "#0080ff",
      description: news.reduce<(typeof news)[number] | undefined>((latest, item) => !latest || item.createdAt > latest.createdAt ? item : latest, undefined)?.title ?? t("News_Empty_Title"),
      route: "/(features)/(news)/news"
    }] : []),
    ...(canDiscuss ? [{ title: "Discussions", icon: "TextBubble", color: "#3979df", description: "Messages PRONOTE", route: "/(features)/pronote/discussions" }] : []),
    ...(canReadLessons ? [{ title: "Cahier de textes", icon: "Paper", color: "#248985", description: "Contenus des cours", route: "/(features)/pronote/lessons" }] : []),
  ], [availableCanteenCards, absencesCount, news, currentAttendancePeriod, attendancesPeriods, attendances, canDiscuss, canReadLessons, canReadNews, t]);

  return (
    <View style={{ paddingHorizontal: 0, width: "100%", flex: 1, overflow: "visible" }}>
      <View style={{ height: insets.top + 56 + (insets.right > 10 ? 10 : 0) }} />
      <View style={{ width: '100%', gap: 6, overflow: 'visible' }}>
        {Array.from({ length: Math.ceil(HomeHeaderButtons.length / 2) }, (_, i) => {
          const row = HomeHeaderButtons.slice(i * 2, i * 2 + 2);
          return (
            <View key={i} style={{ flexDirection: 'row', gap: 6, width: '100%' }}>
              {row.map(item => <HomeHeaderButton key={item.title} item={item} />)}
              {row.length === 1 && <View style={{ flex: 1 }} />}
            </View>
          );
        })}
      </View>
    </View>
  );
};

export default HomeHeader;
