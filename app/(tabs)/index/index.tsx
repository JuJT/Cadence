import { Papicons } from '@getpapillon/papicons';
import { useIsFocused } from "expo-router/react-navigation";
import { useRouter } from 'expo-router';
import { t } from 'i18next';
import React from 'react';
import { FlatList, Platform, RefreshControl, StatusBar, View } from 'react-native';
import Reanimated, { LinearTransition } from 'react-native-reanimated';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { useAccountStore } from '@/stores/account';
import { useSettingsStore } from '@/stores/settings';
import { Animation } from '@/ui/utils/Animation';

import HomeHeader from './atoms/HomeHeader';
import HomeTopBar from './atoms/HomeTopBar';
import Wallpaper from './atoms/Wallpaper';
import HomeWidget, { HomeWidgetItem } from './components/HomeWidget';
import { useHomeData } from './hooks/useHomeData';
import { useTimetableWidgetData } from './hooks/useTimetableWidgetData';
import { useTimetableWidgetTitle } from './hooks/useTimetableWidgetTitle';
import HomeTimeTableWidget from './widgets/timetable';
import GradesWidget from './widgets/Grades';
import { usePeriodsData } from '../grades/hooks/usePeriodsData';
import { useGradesData } from '../grades/hooks/useGradesData';
import MainTabErrorBoundary from '@/ui/components/MainTabErrorBoundary';
import { Dynamic } from '@/ui/components/Dynamic';
import Stack from '@/ui/components/Stack';
import Typography from '@/ui/components/Typography';
import Icon from '@/ui/components/Icon';
import { StudyEntry } from '@/components/StudyEntry';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { CADENZA_RELEASE_KEY } from '@/constants/Cadenza';
import { TravelHomeEntry } from '@/components/TravelHomeEntry';

const HomeScreen = () => {
  const insets = useSafeAreaInsets();
  const bottomTabBarHeight = insets.bottom + 16;
  const topBarHeight = insets.top + 56 + (insets.right > 10 ? 10 : 0);
  const focused = useIsFocused();

  // Account
  const accounts = useAccountStore((state) => state.accounts);
  const lastUsedAccount = useAccountStore((state) => state.lastUsedAccount);
  const account = accounts.find(a => a.id === lastUsedAccount);
  const router = useRouter();
  const welcomeModalSeen = useSettingsStore(state => state.personalization.welcomeModalSeen);
  const mutateSettings = useSettingsStore(state => state.mutateProperty);
  const attemptedIntro = React.useRef(false);

  React.useEffect(() => {
    if (accounts.length === 0) {
      router.replace("/(onboarding)/welcome");
      return;
    }

  }, [accounts.length, router]);

  React.useEffect(() => {
    if (!focused || !account || attemptedIntro.current) return;
    let cancelled = false;
    const transition = setTimeout(() => {
      if (attemptedIntro.current || cancelled) return;
      attemptedIntro.current = true;
      if (!welcomeModalSeen) {
        mutateSettings("personalization", { welcomeModalSeen: true });
        void AsyncStorage.setItem(CADENZA_RELEASE_KEY, '1').catch(() => {});
        router.navigate("/(modals)/welcome");
        return;
      }
      void AsyncStorage.getItem(CADENZA_RELEASE_KEY).then(seen => {
        if (cancelled) attemptedIntro.current = false;
        else if (!seen) router.push({ pathname: '/changelog', params: { automatic: '1' } });
      }).catch(() => {});
    }, 350);
    return () => { cancelled = true; clearTimeout(transition); };
  }, [focused, account, welcomeModalSeen, mutateSettings, router]);

  const { syncing, refresh } = useHomeData();
  const { courses } = useTimetableWidgetData();
  const timetableTitle = useTimetableWidgetTitle(courses);

  const { currentPeriod } = usePeriodsData();
  const { grades, history, averages, refresh: refreshGrades } = useGradesData(currentPeriod);

  const [refreshing, setRefreshing] = React.useState(false);
  const handleRefresh = React.useCallback(async () => {
    setRefreshing(true);
    try {
      await refresh();
      // The grades widget keeps its own cache, the timetable reads the database.
      await refreshGrades();
    } finally {
      setRefreshing(false);
    }
  }, [refresh, refreshGrades]);
  const gradesWidgetHidden = grades.length === 0;

  const renderTimeTable = React.useCallback(() => <HomeTimeTableWidget courses={courses} />, [courses]);
  const renderGrades = React.useCallback(
    () => <GradesWidget history={history} averages={averages} />,
    [history, averages]
  );
  const data: HomeWidgetItem[] = React.useMemo(() => [
    {
      icon: <Papicons name={"Calendar"} />,
      title: timetableTitle,
      redirect: "/(tabs)/calendar",
      hidden: courses.length === 0,
      render: renderTimeTable
    },
    {
      icon: <Papicons name={"Grades"} />,
      title: t("Home_Widget_Grades_Average"),
      redirect: "/(tabs)/grades",
      hidden: gradesWidgetHidden,
      render: renderGrades
    }
  ], [courses.length, gradesWidgetHidden, renderGrades, renderTimeTable, timetableTitle]);

  const visibleWidgets = React.useMemo(
    () => data.filter(item => !item.hidden && (!item.dev || __DEV__)),
    [data]
  );
  const allWidgetsHidden = visibleWidgets.length === 0;

  return (
    <>
      <Wallpaper />
      <HomeTopBar loading={syncing} />
      {focused && <StatusBar animated barStyle={'light-content'} />}
      <HomeViewContainer key={"home"}>
        <FlatList
          renderItem={({ item }) => (
            <Reanimated.View layout={Animation(LinearTransition, "list")}>
              <HomeWidget item={item} />
            </Reanimated.View>
          )}
          keyExtractor={(item) => item.title}
          ListHeaderComponent={
            <View style={{ gap: 8 }}>
              <HomeHeader />
              <TravelHomeEntry />
              <StudyEntry />
              <StudyEntry statistics />
            </View>
          }
          style={{ flex: 1 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor="#fff" progressViewOffset={topBarHeight} />}
          contentContainerStyle={{
            paddingBottom: Platform.OS === 'ios' ? bottomTabBarHeight : 16,
            flexGrow: 1,
            gap: 12,
            marginTop: 6,
            width: '100%',
            maxWidth: 700,
            marginHorizontal: 'auto',
            paddingHorizontal: 16,
          }}
          data={visibleWidgets}
          ListFooterComponent={
            <View style={{ gap: 12 }}>
              {allWidgetsHidden && <HomeEmptyState />}
            </View>
          }
        />
      </HomeViewContainer>
    </>
  );
};

const HomeEmptyState = React.memo(() => (
  <Dynamic animated key="home-widgets:empty" style={{ width: "100%" }}>
    <Stack hAlign="center" vAlign="center" flex padding={[22, 16]} gap={2} style={{ width: "100%" }}>
      <Icon papicon opacity={0.5} size={32} style={{ marginBottom: 3 }}>
        <Papicons name={"Ghost"} />
      </Icon>
      <Typography variant="h4" color="text" align="center">
        {t("Home_Widgets_Empty_Title")}
      </Typography>
      <Typography variant="body2" color="secondary" align="center">
        {t("Home_Widgets_Empty_Description")}
      </Typography>
    </Stack>
  </Dynamic>
));
HomeEmptyState.displayName = "HomeEmptyState";

const HomeViewContainer = ({ children }: { children: React.ReactNode }) => (
  <SafeAreaView style={{ flex: 1 }} edges={["left", "right"]}>{children}</SafeAreaView>
);

const HomeScreenWithBoundary = () => (
  <MainTabErrorBoundary>
    <HomeScreen />
  </MainTabErrorBoundary>
);

export default HomeScreenWithBoundary;
