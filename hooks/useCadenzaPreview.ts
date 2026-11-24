import { router, useRootNavigationState, type Href } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { useEffect, useRef } from "react";

import { getCadenzaPreviewRoute } from "@/modules/cadenza-study";
import { createMockProfile } from "@/services/mock/account";
import { useSettingsStore } from "@/stores/settings";
import { addPastStudy, initializeStudy, startStudy, useStudyStore } from "@/stores/study";

const routes: Record<string, Href> = {
  home: "/(tabs)",
  courses: "/(tabs)/calendar",
  grades: "/(tabs)/grades",
  study: "/(tabs)/study",
};

async function preparePreview() {
  // The native method only accepts this launch argument in an iOS simulator.
  const screen = await getCadenzaPreviewRoute();
  if (!screen || !Object.hasOwn(routes, screen)) return;

  // Account creation clears the welcome flag synchronously before loading services.
  const profile = createMockProfile(false);
  useSettingsStore.getState().mutateProperty("personalization", {
    welcomeModalSeen: true,
    calendarViewMode: "week",
  });
  await profile;

  if (screen === "study") {
    await initializeStudy();
    if (useStudyStore.getState().data.sessions.length === 0) {
      await addPastStudy({ subjectName: "Physique-Chimie", kind: "revision" }, Date.now() - 3600000, 35);
      await startStudy({
        subjectName: "Mathématiques",
        kind: "revision",
        title: "Suites numériques",
        task: { id: "preview-homework", title: "Exercices 26 et 27, page 297" },
      });
    }
  }

  router.replace(routes[screen]);
  await SplashScreen.hideAsync();
  console.info(`Cadenza simulator preview: ${screen}`);
}

export function useCadenzaPreview(fontsLoaded: boolean) {
  const navigationKey = useRootNavigationState()?.key;
  const started = useRef(false);
  useEffect(() => {
    if (!fontsLoaded || !navigationKey || started.current) return;
    started.current = true;
    void preparePreview().catch(error => console.error("Cadenza simulator preview failed", error));
  }, [fontsLoaded, navigationKey]);
}
