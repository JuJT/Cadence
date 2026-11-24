import AsyncStorage from "@react-native-async-storage/async-storage";
import { addWeeks, format, startOfWeek } from "date-fns";
import * as Notifications from "expo-notifications";
import { Platform } from "react-native";

import { readLegacyNotificationPreference } from "@/modules/cadenza-study";
import type { CourseDay } from "@/services/shared/timetable";
import { changeAlerts, futureLessons, type AlertLesson } from "./alert-changes";

const choiceKey = "@cadenza/timetable-alerts/choice";
const historyPrefix = "@cadenza/timetable-alerts/history/";
const historyQueue = new Map<string, Promise<void>>();

if (Platform.OS === "ios") {
  Notifications.setNotificationHandler({
    handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: true, shouldSetBadge: false }),
  });
}

async function readChoice(): Promise<"enabled" | "disabled" | null> {
  const stored = await AsyncStorage.getItem(choiceKey);
  if (stored === "enabled" || stored === "disabled") return stored;
  const legacy = await readLegacyNotificationPreference().catch(() => null);
  return legacy === true ? "enabled" : null;
}

function permitted(permission: Notifications.NotificationPermissionsStatus) {
  return permission.granted || permission.ios?.status === Notifications.IosAuthorizationStatus.PROVISIONAL;
}

export async function getTimetableAlertSettings() {
  if (Platform.OS !== "ios") return { enabled: false, blockedByOS: false };
  const [choice, permission] = await Promise.all([readChoice(), Notifications.getPermissionsAsync()]);
  return { enabled: choice === "enabled" && permitted(permission), blockedByOS: !permission.canAskAgain && !permitted(permission) };
}

export async function shouldOfferTimetableAlerts(): Promise<boolean> {
  return Platform.OS === "ios" && await readChoice() === null;
}

export async function setTimetableAlerts(enabled: boolean) {
  if (Platform.OS !== "ios") return;
  if (!enabled) {
    await AsyncStorage.setItem(choiceKey, "disabled");
    return;
  }
  const current = await Notifications.getPermissionsAsync();
  const next = permitted(current) || !current.canAskAgain ? current : await Notifications.requestPermissionsAsync();
  await AsyncStorage.setItem(choiceKey, permitted(next) ? "enabled" : "disabled");
}

function readWeek(value: string | null): AlertLesson[] | null {
  if (!value) return null;
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

export function observePronoteWeek(accountId: string, date: Date, days: CourseDay[]): void {
  if (Platform.OS !== "ios") return;
  const thisWeek = startOfWeek(new Date(), { weekStartsOn: 1 });
  const viewedWeek = startOfWeek(date, { weekStartsOn: 1 });
  if (viewedWeek < thisWeek || viewedWeek >= addWeeks(thisWeek, 5)) return;
  const accountPrefix = historyPrefix + encodeURIComponent(accountId) + "/";
  const key = accountPrefix + format(viewedWeek, "yyyy-MM-dd");
  const pending = (historyQueue.get(accountId) ?? Promise.resolve()).then(async () => {
    const now = Date.now();
    const lessons = futureLessons(days, now);
    const prior = readWeek(await AsyncStorage.getItem(key));
    if (prior && (await getTimetableAlertSettings()).enabled) {
      const changes = changeAlerts(prior, lessons, now);
      if (changes.length) {
        await Notifications.scheduleNotificationAsync({
          content: { title: "Emploi du temps modifié", body: changes.slice(0, 3).map(change => change.text).join("\n"), sound: true },
          trigger: null,
        });
      }
    }
    await AsyncStorage.setItem(key, JSON.stringify(lessons));
    const oldest = format(thisWeek, "yyyy-MM-dd");
    const keys = (await AsyncStorage.getAllKeys()).filter(candidate => candidate.startsWith(accountPrefix) && candidate.slice(accountPrefix.length) < oldest);
    if (keys.length) await AsyncStorage.multiRemove(keys);
  }).catch(() => {});
  historyQueue.set(accountId, pending);
  void pending.finally(() => { if (historyQueue.get(accountId) === pending) historyQueue.delete(accountId); });
}
