
import 'react-native-reanimated';
import "@/utils/i18n";

import { Buffer } from 'buffer';
import React, { useEffect } from 'react';

import { AppProviders } from '@/components/AppProviders';
import { RootNavigator } from '@/components/RootNavigator';
import { hideAppSplash, useAppInitialization } from '@/hooks/useAppInitialization';
import { useCadenzaPreview } from '@/hooks/useCadenzaPreview';
import { useAccountStore } from '@/stores/account';
import { useNetworkStore } from '@/stores/logs';
import uuid from '@/utils/uuid/uuid';
import { useCalendarWidgetFeed } from '@/utils/widgets/useCalendarWidgetFeed';
import { usePapillonKitSettingsSync } from '@/utils/widgets/usePapillonKitSettingsSync';
import { LogBox, useColorScheme, View } from 'react-native';

// Polyfill Buffer
Object.assign(globalThis, { Buffer });

LogBox.ignoreLogs([
  "Require cycle:",
  "i18next is made possible by our own product, Locize",
  'Route "./',
  "Linking found multiple possible URI schemes in your Expo config.",
  "[Layout children]: No route named",
  "Found screens with the same name nested inside one another.",
  "Account manager not initialized. Call initializeAccountManager first.",
  "Manager is null, skipping timetable fetch",
  "Installing bindings...",
  "Successfully installed!",
  "The action 'PRELOAD' with payload",
  "DrawerLayoutAndroid is deprecated",
  "cannot calculate shadow efficiently",
]);

// From onLayout, not an effect: hiding earlier shows a blank frame.
const hideSplashIfSignedIn = () => {
  if (useAccountStore.getState().accounts.length > 0) {
    hideAppSplash();
  }
};

export default function RootLayout() {
  const { fontsLoaded } = useAppInitialization();
  const colorScheme = useColorScheme();
  useCadenzaPreview(fontsLoaded);
  useCalendarWidgetFeed();
  usePapillonKitSettingsSync();

  useEffect(() => {
    if (!fontsLoaded) return;
    const fallback = setTimeout(hideAppSplash, 1800);
    return () => clearTimeout(fallback);
  }, [fontsLoaded]);

  useEffect(() => {
    if (!__DEV__) return;
    const originalFetch = window.fetch;

    window.fetch = async (...args) => {
      const id = uuid();
      let request: Request | null = null;
      if (args[0] instanceof Request && args[1] === undefined) {
        request = args[0];
      } else {
        request = new Request(...args);
      }

      try {
        useNetworkStore.getState().addRequest(request, id);
      } catch { }

      const response = await originalFetch(...args);

      try {
        useNetworkStore.getState().addResponse(response.clone(), id);
      } catch { }

      return response;
    }

    return () => {
      window.fetch = originalFetch;
    }
  }, [])

  if (!fontsLoaded) {
    return null;
  }

  return (
    <AppProviders>
      <View
        style={{ flex: 1, backgroundColor: colorScheme === "dark" ? "#06172F" : "#F4F8FF" }}
        onLayout={hideSplashIfSignedIn}
      >
        <RootNavigator />
      </View>
    </AppProviders>
  );
}
