import AsyncStorage from "@react-native-async-storage/async-storage";
import { startOfWeek } from "date-fns";
import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import { dayKey, type TravelPreferences } from "@/services/cadenza/travel-schedule";

type TravelStore = {
  profiles: Record<string, TravelPreferences>;
  update: (profile: string, changes: Partial<TravelPreferences> | ((old: TravelPreferences) => Partial<TravelPreferences>)) => void;
};

export const defaultTravelPreferences: TravelPreferences = {
  configured: false,
  enabled: false,
  homes: [],
  cards: [],
  weekA: dayKey(startOfWeek(new Date(), { weekStartsOn: 1 })),
  arrivalBuffer: 10,
};

export const useTravelStore = create<TravelStore>()(persist((set) => ({
  profiles: {},
  update: (profile, changes) => {
    if (!profile) return;
    set(state => {
      const old = state.profiles[profile] ?? defaultTravelPreferences;
      return { profiles: { ...state.profiles, [profile]: { ...old, ...(typeof changes === "function" ? changes(old) : changes) } } };
    });
  },
}), { name: "cadenza.travel.v1", storage: createJSONStorage(() => AsyncStorage), partialize: state => ({ profiles: state.profiles }) }));
