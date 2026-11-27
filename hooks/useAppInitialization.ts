import { useEffect, useState, useRef } from 'react';
import { AppState } from 'react-native';
import * as SplashScreen from 'expo-splash-screen';
import { useFonts } from 'expo-font';

import { initializeDatabaseOnStartup } from '@/database/utils/initialization';
import { configureTips, resetTipsDatastore, showAllTips } from '@/modules/papillon-tips';
import { initializeAccountManager } from '@/services/shared';
import { useSettingsStore } from '@/stores/settings';
import { useTipsStore } from '@/stores/tips';
import i18n from '@/utils/i18n';
import { warn } from '@/utils/logger/logger';
import ModelManager from '@/utils/magic/ModelManager';
import { MAGIC_AVAILABLE } from '@/utils/magic/tflite';
import { FONT_CONFIG } from '@/constants/LayoutScreenOptions';

// Prevent the splash screen from auto-hiding before asset loading is complete.
void SplashScreen.preventAutoHideAsync().catch(e => warn(String(e), "SplashScreen"));
SplashScreen.setOptions({ duration: 200, fade: true });

export function hideAppSplash() {
  void SplashScreen.hideAsync().catch(e => warn(String(e), "SplashScreen"));
}

export function useAppInitialization() {
  const [fontsLoaded, fontsError] = useFonts(FONT_CONFIG);
  const [fontsTimedOut, setFontsTimedOut] = useState(false);

  // Settings
  const customLanguage = useSettingsStore(state => state.personalization.language);
  const magicEnabled = useSettingsStore(state => state.personalization.magicEnabled);
  const selectedTheme = useSettingsStore(state => state.personalization.theme);
  const mutateProperty = useSettingsStore(state => state.mutateProperty);

  useEffect(() => {
    if (!selectedTheme) {
      mutateProperty('personalization', {
        theme: "auto"
      });
    }
  }, [mutateProperty, selectedTheme]);

  // Language Initialization
  useEffect(() => {
    if (customLanguage && i18n.language !== customLanguage) {
      i18n.changeLanguage(customLanguage).catch((error) => {
        console.error("Error changing language:", error);
      });
    }
  }, [customLanguage]);

  // TipKit Initialization
  // Has to happen before any tip is asked whether it should show, and exactly
  // once per process. `immediate` because our tips point at something on screen
  // right now — holding one back for an hour would point at nothing.
  //
  // A reset asked for from the debug menu is carried out here rather than
  // there: TipKit only lets its datastore be wiped before it is configured, so
  // this launch is the first chance to honour it.
  useEffect(() => {
    const setUpTips = async () => {
      const { pendingDatastoreReset, clearPendingDatastoreReset, forceAll } =
        useTipsStore.getState();

      if (pendingDatastoreReset) {
        await resetTipsDatastore();
        clearPendingDatastoreReset();
      }

      await configureTips('immediate');

      if (forceAll) {
        await showAllTips();
      }
    };

    setUpTips().catch(err => {
      warn(`TipKit configuration failed: ${err}`);
    });
  }, []);

  // Database Initialization
  // The WatermelonDB adapter is constructed synchronously at module load
  // (see database/index.ts), so it's already usable before this effect runs.
  // initializeDatabaseOnStartup() only runs diagnostic health checks, so it
  // does not need to gate app readiness / the splash screen.
  useEffect(() => {
    initializeDatabaseOnStartup().catch(err => {
      warn(`Database initialization failed: ${err}`);
    });
  }, []);

  // AppState Monitoring
  const appState = useRef(AppState.currentState);
  const lastBackgroundRef = useRef<number | null>(null);

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (nextAppState) => {
      if (appState.current?.match(/inactive|background/) && nextAppState === "active") {
        if (lastBackgroundRef.current) {
          const now = Date.now();
          const durationMs = now - lastBackgroundRef.current;

          if (durationMs > 5 * 60 * 1000) {
            initializeAccountManager().catch(e => warn(`Background account refresh failed: ${e}`));
          }
        }
      }

      if (nextAppState === "background") {
        lastBackgroundRef.current = Date.now();
      }

      appState.current = nextAppState;
    });

    return () => {
      subscription.remove();
    };
  }, []);

  // Magic/ModelManager Initialization
  useEffect(() => {
    if (MAGIC_AVAILABLE && magicEnabled) {
      ModelManager.safeInit();
    }
  }, [magicEnabled]);

  useEffect(() => {
    if (fontsError) {
      warn(String(fontsError), "Fonts");
      return;
    }
    if (fontsLoaded) return;
    const fallback = setTimeout(() => setFontsTimedOut(true), 4000);
    return () => clearTimeout(fallback);
  }, [fontsError, fontsLoaded]);

  return {
    fontsLoaded: fontsLoaded || Boolean(fontsError) || fontsTimedOut,
    fontsError
  };
}
