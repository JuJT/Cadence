
import 'react-native-reanimated';
import "@/utils/i18n";

import { Buffer } from 'buffer';
import React, { useEffect } from 'react';
import * as SplashScreen from 'expo-splash-screen';

import { AppProviders } from '@/components/AppProviders';
import { RootNavigator } from '@/components/RootNavigator';
import { useAppInitialization } from '@/hooks/useAppInitialization';
import { useCadenzaPreview } from '@/hooks/useCadenzaPreview';
import { useAccountStore } from '@/stores/account';
import { useNetworkStore } from '@/stores/logs';
import uuid from '@/utils/uuid/uuid';
import { useCalendarWidgetFeed } from '@/utils/widgets/useCalendarWidgetFeed';
import { usePapillonKitSettingsSync } from '@/utils/widgets/usePapillonKitSettingsSync';
import { LogBox, View } from 'react-native';

// Polyfill Buffer
global.Buffer = Buffer;

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
    SplashScreen.hideAsync();
  }
};

export default function RootLayout() {
  const { fontsLoaded } = useAppInitialization();
  useCadenzaPreview(fontsLoaded);
  useCalendarWidgetFeed();
  usePapillonKitSettingsSync();

  useEffect(() => {
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
      <View style={{ flex: 1 }} onLayout={hideSplashIfSignedIn}>
        <RootNavigator />
      </View>
    </AppProviders>
  );
}
