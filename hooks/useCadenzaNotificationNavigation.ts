import * as Notifications from "expo-notifications";
import { useRootNavigationState, useRouter } from "expo-router";
import { useEffect, useRef } from "react";
import { Platform } from "react-native";

export function useCadenzaNotificationNavigation() {
  const router = useRouter();
  const ready = !!useRootNavigationState()?.key;
  const handled = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (Platform.OS !== "ios" || !ready) return;
    const open = (response: Notifications.NotificationResponse | null) => {
      const change = response?.notification.request.content.data?.cadenzaTimetableChange;
      if (typeof change !== "string" || change.length > 220 || change === handled.current) return;
      handled.current = change;
      router.push({ pathname: "/(modals)/timetable-changes", params: { change } });
      void Notifications.clearLastNotificationResponseAsync().catch(() => {});
    };
    const listener = Notifications.addNotificationResponseReceivedListener(open);
    let active = true;
    void Notifications.getLastNotificationResponseAsync().then(response => { if (active) open(response); }).catch(() => {});
    return () => { active = false; listener.remove(); };
  }, [ready, router]);
}
